/*
 9-21-2011
 Nathan Seidle
 Spark Fun Electronics 2011
  
 This code is public domain but you buy me a beer if you find this code useful and we meet someday (Beerware license).
 
 This bootloader is styled after an old PIC bootloader I designed years ago:
 http://www.sparkfun.com/tutorials/69
 
 There are two main features to this bootloader. 
 1) Baked-in board identification: IC type, crystal freq, page size, available code space, download speed, 
 board voltage, and board name.
 2) Fastest possible bootload speeds.
 
 The benefit of this bootloader is that it no longer relies on 'industry standard' baud rates. If the microcontroller
 can communicate best at 194,233bps, then we will bootload at 194,233bps. This removes a bunch of limitations and errors 
 when a board has a weird crystal frequency and board voltage.

 We do this by starting communication first at 19200bps (any micro should be able to communicate reasonably at this baud).
 The host queries the target for the baud rate they would like to jump to. A speed is stablished, both parties then
 hang up the phone, go to the new faster baud rate, then communication and bootloading proceeds.

 This bootloader squeezes out every efficiency to bootload as quickly as possible. It is currently about 1500bytes and should
 fit into most any microcontroller's boot load space. It also uses a simple CRC to verify the incoming data bytes are not corrupt. 
 It does not do a page read/verification step.
 
 Most all of the bootload communication is done in visible ASCII so that it is easier to debug.
 
 If you don't already have one, I highly recommend getting yourself a Logic Analyzer from Saleae:
 http://www.sparkfun.com/products/8938
 This thing continues to save my life and my sanity.
 
 This code has to be separately compiled for:
 ATmega328
 ATmega168
 ATmega8
 ATmega1280
 
 */

#include <avr/boot.h> //Needed for onboard flash writing
#include <avr/wdt.h> //Needed to disable the watch dog timer
#include <util/delay.h> //Needed for _delay_ms()

#define FREQ	16000000
#define BAUD_19200	19200

//#define MYUBRR_19200 (((((FREQ * 10) / (16L * BAUD_19200)) + 5) / 10) - 1) //Assumes normal UART speed
#define MYUBRR_19200 ((FREQ / (8L * BAUD_19200)) - 1) //Assumes double UART speed

//Here we calculate the wait period inside getch(). Too few cycles and the host may 
//not be able to send the character in time. Too long and your sketch will a long
//time to start
#define MAX_WAIT_TIME_IN_MS	100
#define MAX_WAIT_IN_CYCLES (FREQ / 20000L * MAX_WAIT_TIME_IN_MS)

#define FALSE	0
#define TRUE	1

#define SSVQ 10 //Serial speed verification request
#define ICRQ 11 //IC request
#define FRQ 12 //Frequency request
#define ACSRQ 13 //Available code space request
#define PSRQ 14 //Page size space request
#define VRQ 15 //Voltage request (optional)
#define TRQ 16 //Tag request (optional)
#define TUGRQ 17 //Time until giveup request (optional)
#define BLRQ 18 //Boot load request
#define SSRQ 19 //Start sketch

//These specific bits should maybe be in a header some day
//These are all the specific settings to this chip and board
#define PROP_MAXBOOTLOAD  "2000000" //Maximum bootload speed achievable by this board
#define PROP_MAXBOOTLOAD_INT  2000000 //Integer for of maximum bootload speed
#define PROP_IC  "ATmega328" //1 //1 = ATmega328
#define PROP_FREQ  "16MHz" //1 //1 = 16MHz
#define PROP_ACS  "30000" //The regular Arduino has 30k of free code space
#define PROP_PS  "128" //The page size of the ATmega328 is 128 bytes
#define PROP_PS_INT  128 //The page size of the ATmega328 is 128 bytes
#define PROP_VOLT "5V" //The optional board voltage
#define PROP_TAG "Pro Mini 5V@16MHz" //The optional board tag - limit to 32 bytes
#define PROP_TUG  "50" //The number of milliseconds before the bootloader gives up

//#define MYUBRR_MAX (((((FREQ * 10) / (16L * PROP_MAXBOOTLOAD_INT)) + 5) / 10) - 1) //Assumes normal UART speed
#define MYUBRR_MAX ((FREQ / (8L * PROP_MAXBOOTLOAD_INT)) - 1) //Assumes double UART speed

//From testing, 111111 seems to be perfect from the IC, works great 9us, 144ms to push a 128byte block
//200,000 works perfectly, 5us. 143ms to push a 128 byte block
//1000,000 works prefectly

//Pin definitions
//-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//Status LED
#define LED_DDR  DDRB
#define LED_PORT PORTB
#define LED_PIN  PINB
#define LED      PINB5
//-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

//Global variables
//-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
char retransmit_flag = FALSE;
//-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

//Function prototypes
//-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
void (*start_sketch)(void) = 0x0000;

void putch(char);
void putstr(char *str);
char getch(void);
void flash_LED(uint8_t);
void bootLoad(void);
void onboard_program_write(uint32_t page, uint8_t *buf);
//-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

int main(void) {

//  wdt_disable(); //We don't what the user has done before this so let's disable the WDT to be safe

    //Setup USART baud rate
	//Initially, all boards talk at 19200bps
    UBRR0H = MYUBRR_19200 >> 8;
    UBRR0L = MYUBRR_19200;
    UCSR0B = (1<<RXEN0)|(1<<TXEN0);
	UCSR0A = (1<<U2X0); //Double the UART speed

    //1 = output, 0 = input 
    LED_DDR |= (1<<LED); //Set LED pin as output

	//Blink LED to indicate we're alive
	LED_PORT |= (1<<LED);
	_delay_ms(25);
	LED_PORT &= ~(1<<LED);
	_delay_ms(25);

	//Start bootloading process
	putch(5); //Tell the world we can be bootloaded

	//Check to see if the computer responded
	//From testing, the processing app takes about 3ms to respond
	uint32_t count = 0;
	while(!(UCSR0A & (1<<RXC0)))
		if (count++ > MAX_WAIT_IN_CYCLES) start_sketch();
	if(getch() != 6) start_sketch(); //If the computer did not respond correctly with a ACK, we jump to user's program

	//Now send the baud rate we would like to bootload at
	//From testing, the uC takes 37.7us to respond with bootload speed
	putstr(PROP_MAXBOOTLOAD);
	putch(',');

	//Host will respond with the rate we just sent, if they do, hang up the phone and go to that comm speed
	//From testing, the processing app takes 5.17ms to respond
	long hostResponse = 0;
	while(1) {
		if(UCSR0A & (1<<RXC0)) {
			char incomingChar = getch();
			if(incomingChar == ',') break;
			if(incomingChar >= '0' && incomingChar <= '9') {
				incomingChar -= '0'; //Convert alpha to number
				hostResponse = (hostResponse * 10) + incomingChar;
			}
		}
		//It is possible to get stuck in this loop. Reset will get you out.
	}
	if(hostResponse != PROP_MAXBOOTLOAD_INT) start_sketch();

	//Now hang up the phone and go to this new comm speed
	while (!(UCSR0A & (1<<UDRE0))); //Wait for all transmissions to complete
    UBRR0H = MYUBRR_MAX >> 8;
    UBRR0L = MYUBRR_MAX;
    UCSR0B = (1<<RXEN0)|(1<<TXEN0);
	
	while(1) {
		//Tell the host that we are a-ok with the SSVQ (serial speed verification) command
		putstr("10,"); //This is the SSVQ in string printable form

		//The host can take a bit of time to shift gears to the new baud rate (silly slow computers!)
		//During testing, the target sent '10,' twice for a total of about 200ms before the computer
		//Could answer correctly

		//Wait for response from host
		hostResponse = 0;
		count = 0;
		while(count++ < MAX_WAIT_IN_CYCLES) {
			//If the host doesn't respond in time, break and re-send the SSVQ

			if(UCSR0A & (1<<RXC0)) {
				char incomingChar = getch();
				if(incomingChar == ',') break;
				if(incomingChar >= '0' && incomingChar <= '9') {
					incomingChar -= '0'; //Convert alpha to number
					hostResponse = (hostResponse * 10) + incomingChar;
				}
			}
		}
		if(hostResponse == SSVQ) break; //We've got confirmation!
		//It is possible to get stuck in this loop. Reset will get you out.
	}

	//Now we hang out in host control mode
	//The host can query for information about this target board
	//The host can also initiate bootloading

	while(1) {

		//Wait for a command from the host
		int hostCommand = 0;
		while(1) {
			if(UCSR0A & (1<<RXC0)) {
				char incomingChar = getch();
				if(incomingChar == ',') break;
				if(incomingChar >= '0' && incomingChar <= '9') {
					incomingChar -= '0'; //Convert alpha to number
					hostCommand = (hostCommand * 10) + incomingChar;
				}
			}
			//It is possible to get stuck in this loop. Reset will get you out.
		}

		switch(hostCommand) {
			case(ICRQ): //IC identify request
				putstr(PROP_IC);
				putch(',');
				break;
			case(FRQ): //Frequency request
				putstr(PROP_FREQ);
				putch(',');
				break;
			case(ACSRQ): //Available code space request
				putstr(PROP_ACS);
				putch(',');
				break;
			case(PSRQ): //Page size request
				putstr(PROP_PS);
				putch(',');
				break;
			case(VRQ): //Board voltage request
				putstr(PROP_VOLT);
				putch(',');
				break;
			case(TRQ): //Board tag (name) request
				putstr(PROP_TAG);
				putch(',');
				break;
			case(TUGRQ): //Time until giveup request
				putstr(PROP_TUG);
				putch(',');
				break;
			case(BLRQ): //Boot load request - zomg!
				bootLoad();
				start_sketch();
				break;
			case(SSRQ): //Do nothing, start the sketch (mostly used for board ID)
				start_sketch();
				break;

			default: //Unknown command
				putstr("-1,");
		}
	}

}

//This is the core of the bootloader. It takes in specially stripped down binary values
//and stores them in various locations in memory
void bootLoad(void) {

union page_address_union {
	uint16_t word;
	uint8_t  byte[2];
} 
page_address;
 
	uint8_t check_sum = 0; //Init check_sum as good
	uint8_t incoming_page_data[PROP_PS_INT * 2]; //Limited to 256. This might be a problem for larger chips someday.
	uint8_t block_length; //This will vary between 1 and 128 for the ATmega328. 

	while(1) { //Loop until the host sends us the 'S' page length (stop) command

		//Determine if the last received data was good or bad
		if (check_sum != 0) //If the check sum does not compute, tell computer to resend same line
	RESTART:
			putch('X'); //Something is wrong. Tell the computer to retransmit!
		else            
			putch('T'); //Tell the computer that we are ready for the next line

		while(1) { //Wait for the computer to initiate transfer
			if (getch() == ':') break; //This is the "gimme the next chunk" command
			if (retransmit_flag == TRUE) goto RESTART;
		}

		block_length = getch(); //Get the length of this block
		if (retransmit_flag == TRUE)  goto RESTART;

		if (block_length == 'S') { //Check to see if we are done - this is the "all done" command
			//There is the posibility for a bug here: if the host sends a block_length of ASCII 'S' (dec 83) that is not the
			//end of the file. Rare, but it may happen.
			boot_rww_enable(); //Wait for any flash writes to complete?
			start_sketch(); 
		}

		//Get the memory address at which to store this block of data
		page_address.byte[0] = getch(); 
		if (retransmit_flag == TRUE) goto RESTART;
		page_address.byte[1] = getch(); 
		if (retransmit_flag == TRUE) goto RESTART;

		boot_page_erase(page_address.word); //Start the page erasing
		//This can take as much as 4-5ms, do it in the background

		check_sum = getch(); //Pick up the check sum for error dectection
		if (retransmit_flag == TRUE) goto RESTART;

		uint16_t i;
		for(i = 0 ; i < block_length ; i++) { //Read the program data
			incoming_page_data[i] = getch();
			if (retransmit_flag == TRUE) goto RESTART;
			

			//1522
			//1568

			//Calculate the checksum as we go
			check_sum += incoming_page_data[i];
		}
		
		//There is a case here where i < page_size and so we don't get a full page write. Bad?

		//Calculate the checksum
		check_sum += block_length;
		check_sum += page_address.byte[0];
		check_sum += page_address.byte[1];


		if(check_sum == 0) { //If we have a good transmission, put it in ink
			
			boot_spm_busy_wait(); //There may be stuff still going on from the previous time around
			for(i = 0 ; i < block_length ; i += 2) { 
				uint16_t databyte = incoming_page_data[i];
				databyte += (incoming_page_data[i+1] << 8);
				boot_page_fill(page_address.word + i, databyte);
			}

			boot_page_write(page_address.word); //Record the new bytes to flash
			boot_spm_busy_wait(); //Wait for record to complete - we can't do anything else!
		}
	}  
}

char getch(void) {
  retransmit_flag = FALSE;

  //Optional flow control
  //cbi(PORTD, RTS); //Tell Host it is now okay to send us serial characters

	uint32_t count = 0;
	while(!(UCSR0A & (1<<RXC0))) {
		if (count++ > MAX_WAIT_IN_CYCLES) {
			retransmit_flag = TRUE;
			return(0);
		}
	}

  //Optional flow control
  //sbi(PORTD, RTS); //Tell Host to hold serial characters, we are busy doing other things

  return(UDR0); //Return the character we see
}

void putch(char ch) {
	//Optional flow contro
	//while( (PIND & (1<<CTS)) != 0); //Wait for the Host to tell us it's ok to send

	while (!(UCSR0A & (1<<UDRE0)));
	UDR0 = ch;
}

void putstr(char *str) {
	for(uint8_t x = 0 ; str[x] != '\0' ; x++)
		putch(str[x]);
}
