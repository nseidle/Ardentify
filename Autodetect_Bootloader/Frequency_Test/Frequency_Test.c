/*
 10-3-2011
 Nathan Seidle
 Spark Fun Electronics 2011
  
 This code is public domain but you buy me a beer if you find this code useful and we meet someday (Beerware license).
 
 This is a very small, very simple C program to make a microcontroller communicate at 19200bps. We assume 16MHz.
 If the microcontroller is not running at 16MHz, that's ok. We can identify baud rate errors from the computer side.
 
 If the board is running at 16MHz, the 'X' will be sent at 19200bps correctly.
 If the board is running at 8MHz, the 'X' will be sent at 9600bps.
 If the board is running at 1MHz, the 'X' will be sent at 2400bps.
 
 This code has to be separately compiled for:
 ATmega328
 ATmega168
 ATmega8
 ATmega1280
 
 */

#include <avr/io.h> //For general pin definitions

#define FREQ 16000000
#define BAUD_19200 19200

//#define MYUBRR_19200 (((((FREQ * 10) / (16L * BAUD_19200)) + 5) / 10) - 1) //Assumes normal UART speed
#define MYUBRR_19200 ((FREQ / (8L * BAUD_19200)) - 1) //Assumes double UART speed

int main(void) {

    //Setup USART to 19200
    UBRR0H = MYUBRR_19200 >> 8;
    UBRR0L = MYUBRR_19200;
    UCSR0B = (1<<RXEN0)|(1<<TXEN0);
	UCSR0A = (1<<U2X0); //Double the UART speed

	//Print the letter X so that the computer can see what speed this board is running at
	UDR0 = 'X';
}