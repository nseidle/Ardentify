//This function receives a HEXarray that is normally filled by the parse function
//Assumes you have correctly loaded global variable property_PS_int.
//This fuction will send the correct commands to a target to load the firmware in the hex array
//It will bail with a -1 if anything goes wrong

public int stk500_bootload(int portSpeed, int pageSize, int lastByte, byte[] HEXarray) {

  //Open the port at a given speed
  String portName = Serial.list()[serialPortNumber];
  myPort = new Serial(this, portName, portSpeed);
  myPort.clear();

  //Reset the target board to begin bootloading
  myPort.setDTR(true);
  delay(1); //Don't wait too long here, the 0.1uF capacitor's rise time is quick
  myPort.setDTR(false);

  delay(100); //Testing with optiboot, 50ms is too short. We have to wait a significant amount of time before sending commands to the target.

  myPort.clear();

  //For the STK based bootloaders, the host transmits two bytes after reset. The target should respond with 0x14 + 0x10.
  //myPort.write(char(0x30));
  //myPort.write(char(0x20));
  byte[] buff1 = {0x30, 0x20};
  myPort.write(buff1);

  if (waitForResponse(2, 500) == -1) return(-1); //Wait for 2 characters to come back. Return fail if we time out.

  //We got a response! Is it what we expected?
  int incomingChar1 = myPort.readChar();
  int incomingChar2 = myPort.readChar();

  if (incomingChar1 != 0x14 || incomingChar2 != 0x10) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  //Otherwise, yay! We have a valid response!

  //Begin testing the board to see if it supports extended commands or not
  byte GENERIC_RESPONSE = 0x03;
  byte CRC_EOP = 0x20; //The STK protocol uses a lot of 0x20s (Space)
  byte STK_GET_PARAMETER = 0x41;
  byte Parameter_CID = (byte)0xA0;
  byte Parameter_UBR = (byte)0xA3;
  int CID = 0;

  //myPort.write(char(STK_GET_PARAMETER)); //Tell the board we are messing with parameters
  //myPort.write(char(Parameter_CID)); //Request the company ID
  //myPort.write(char(CRC_EOP)); //Send end of Parameter character (space)
  byte[] buff2 = {STK_GET_PARAMETER, Parameter_CID, CRC_EOP};
  myPort.write(buff2);

  //Board will now respond with STK_INSYNC (0x14) and then the results of the paramter request
  if (waitForResponse(2, 500) == 0) { //This is an extended command, may not be supported
    incomingChar1 = myPort.readChar(); //Read insyc character and throw it away
    CID = myPort.readChar();
    if (CID != GENERIC_RESPONSE && CID != 0x00) {
      //Generic response is 0x03 on Optiboot
      //Some boards respond with 0x00
      println("Extended commands supported!");
      extendedCommandSupport = true;
    }
    else
      //Board responded with generic 0x03 which means it does not support this command
      extendedCommandSupport = false;
  }

  if (extendedCommandSupport == true) {
    //Let's see if we can force it into a higher baud rate
    println("Sending UART setting");
    //myPort.write(char(STK_GET_PARAMETER)); //Tell the board we are messing with parameters
    //myPort.write(char(Parameter_UBR)); //Set baud rate
    //myPort.write(char(CRC_EOP)); //Send end of Parameter character (space)
    byte[] buff3 = {STK_GET_PARAMETER, Parameter_UBR, CRC_EOP};
    myPort.write(buff3);
    if (waitForResponse(1, 500) == 0) {
      incomingChar1 = myPort.readChar(); //Read insyc character and throw it away
    }
    myPort.write((char)ubr_setting); //Push the IC to 2Mbps
    //Board should now be at new speed

    delay(10); //This small delay reduces the number of NullPointerExceptions. Maybe java needs time before we stop port?

    //Close and re-open port at new speed
    myPort.stop();
    myPort = new Serial(this, portName, max_port_speed);
    //It can take the computer up to 1300ms to switch port speeds (ya, bad)
    //Transmit a ! to let the board know we're ready to continue
    myPort.write('!'); //Tell the board we are now at this new speed
    delay(10); //This delay is needed to clear out any residual characters
    //while(myPort.available () > 0) myPort.readChar(); //Clear out any stray characters in the RX buffer
  }


  //Begin actual bootloading here:

  //Start at beginning of large intel array
  int currentMemoryAddress = 0;
  int inChar1, inChar2;

  while (true) {

    //Here's our escape!
    if (currentMemoryAddress >= lastByte) {
      //We shouldn't have to do anything. The Arduino bootloader should time out.
      break;
    }

    //Convert 16-bit current_memory_address into two 8-bit characters
    //STK500 is weird. It loads the word location, not the actual memory location
    int MemoryAddressHigh = (currentMemoryAddress / 2) / 256;
    int MemoryAddressLow = (currentMemoryAddress / 2) % 256;

    myPort.clear();
    while (myPort.available () > 0) myPort.readChar();

    //Send the memory address to the target
    //startBytes[0] = (byte)0x55; //STK command for load address
    //startBytes[1] = (byte)MemoryAddressLow; 
    //startBytes[2] = (byte)MemoryAddressHigh;
    //startBytes[3] = (byte)0x20; //STK character for the termination of a command
    byte[] startBytes = {0x55, (byte)MemoryAddressLow, (byte)MemoryAddressHigh, 0x20};
    myPort.write(startBytes);

    //myPort.clear();

    //Wait for target to verify with 0x14 0x10
    if (waitForResponse(2, 500) == -1) {
      gracefulExit("The target IC did not finish loading. You will likely experience unexpected program execution.");
      return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }
    inChar1 = myPort.read();
    inChar2 = myPort.read();

    if (inChar1 != 0x14 || inChar2 != 0x10) {
      //Bad response!
      println("Error: STK500 bootloader did not respond to PAGE ADDRESS command.");
      myPort.stop(); //Clean up
      return(-1); //Bail!
    }

    //Send the next block length (property_PS_int) of bytes
    int block_length = pageSize; //Set block length to page size
    if (currentMemoryAddress + block_length > lastByte) //Check to see if we're towards the end of the array
      block_length = lastByte - currentMemoryAddress;

    //Each myPort.write takes 1ms of overhead
    //By combining all the control and data into one array, we can do one system/serial.write instead of many. 
    byte[] dataBytes = new byte[block_length + 5];

    //Send the start character
    dataBytes[0] = (byte)0x64; //STK command for program page

    dataBytes[1] = (byte)0x00; //Thrown out by the STK/Arduino bootload. This may be the high byte for page sizes greater than 255.

    //Send the record length
    dataBytes[2] = (byte)block_length; //The size of this block. May be less than 128 or 64 bytes

    //Send the record length
    dataBytes[3] = (byte)0x46; //Thrown out by the STK/Arduino bootload. It's just a random character as far as I'm concerned.

    //Send the next block of data from the compressed HEX array
    for (int i = 0 ; i < block_length ; i++)
      dataBytes[i + 4] = HEXarray[currentMemoryAddress + i];

    //Send the record length
    dataBytes[block_length + 4] = (byte)0x20; //STK's termination character.

    //Push this block of control and data out to the serial port
    //while(myPort.available() > 0) myPort.readChar();
    myPort.write(dataBytes);


    //Wait for target to verify with 0x14 0x10
    if (waitForResponse(2, 500) == -1) {
      gracefulExit("The target IC did not finish loading. You will likely experience unexpected program execution.");
      return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }
    inChar1 = myPort.read();
    inChar2 = myPort.read();

    if (inChar1 != 0x14 || inChar2 != 0x10) {
      //Bad response!
      println("Error: STK500 bootloader did not respond to PAGE LOAD command.");
      myPort.stop(); //Clean up
      return(-1); //Bail!
    }

    currentMemoryAddress += block_length; //Advance the marker and go do it again
  }

  //Clean up
  myPort.stop();

  //println("Bootload finished");

  return(0); //Success!
}

//This function reads a certain number of bytes from a starting location into an array of chars
//It assumes the port is already open and the STK500 bootloader is sitting waiting for commands
//This was originally designed to pull down the first 256 bytes of a boards firmware so that we could
//Overwrite it with the frequency test app, then replace the original firmware
public int stk500_read(int numberOfBytes, int startingLocation, int pageSize, byte[] HEXarray) {

  //Start at beginning of large intel array
  int currentMemoryAddress = startingLocation;

  int lastByte = startingLocation + numberOfBytes;

  while (true) {

    //Here's our escape!
    if (currentMemoryAddress >= lastByte) break;

    int blockLength = pageSize; //Set block length to page size
    if (currentMemoryAddress + blockLength > lastByte) //Check to see if we're towards the end of the array
      blockLength = lastByte - currentMemoryAddress; //Trim the blockLength to grab the final less-than-pagesize block 

    //Convert 16-bit current_memory_address into two 8-bit characters
    //STK500 is weird. It loads the word location, not the actual memory location, so we divide by 2
    int MemoryAddressHigh = (currentMemoryAddress / 2) / 256;
    int MemoryAddressLow = (currentMemoryAddress / 2) % 256;

    //myPort.clear();
    while (myPort.available () > 0) myPort.readChar(); //Clear out any stray characters in the in buffer

      //Send the memory address to the target
    //myPort.write((char)0x55); //STK command for load address
    //myPort.write((char)MemoryAddressLow);
    //myPort.write((char)MemoryAddressHigh);
    //myPort.write((char)0x20); //STK character for the termination of a command
    byte[] buff1 = {0x55, (byte)MemoryAddressLow, (byte)MemoryAddressHigh, 0x20};
    myPort.write(buff1);

    //myPort.clear(); //This may mess up at faster speeds

    //Wait for target to verify with 0x14 0x10
    if (waitForResponse(2, 500) == -1) {
      gracefulExit("STK500 bootloader did not respond to ADDRESS WRITE command.");
      return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }

    int inChar1 = (byte)myPort.read();
    int inChar2 = (byte)myPort.read();

    if (inChar1 != 0x14 || inChar2 != 0x10) {
      //Bad response!
      println("Char1: " + (int)inChar1);
      println("Char2: " + (int)inChar2);
      gracefulExit("STK500 bootloader failed response to ADDRESS WRITE command");
      return(-1); //Bail!
    }

    //Send the request for page read to the target
    //myPort.write((char)0x74); //STK command for load address
    //myPort.write((char)(blockLength / 256)); //High byte of page size?
    //myPort.write((char)(blockLength % 256)); //Low byte of page size
    //myPort.write((char)0x46); //Unknown - but was in the page_write series as well
    //myPort.write((char)0x20); //STK character for the termination of a command
    byte[] buff2 = {0x74, (byte)(blockLength / 256), (byte)(blockLength % 256), 0x46, 0x20};
    myPort.write(buff2);

    myPort.clear();

    //Now the target is going to respond with 0x14 and pagesize worth of bytes + 0x10
    if (waitForResponse(1, 500) == -1) {
      gracefulExit("STK500 bootloader did not respond to PAGE READ command.");
      return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }
    myPort.read(); //Read the 0x14 character from the port

    //Read in the 128? bytes of the page
    for (int i = 0 ; i < blockLength ; i++) {
      waitForResponse(1, 500);
      HEXarray[currentMemoryAddress + i] = (byte)myPort.read();
    }

    //Read the 0x10 termination character
    if (waitForResponse(1, 500) == -1) {
      gracefulExit("STK500 bootloader did not terminate the PAGE READ command.");
      return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }
    myPort.read(); //Read the 0x10 character from the port

    //Move the marker forward
    currentMemoryAddress += blockLength;
  }

  return(0); //Success!
}

//This function talks to bootloaders based on the STK protocol
//It will try to communicate at portSpeed. It will give up after 500ms.
public int stk500_board_guessing(int portSpeed) {

  IC_type = "Unknown"; //Reset the IC type until we find a good one.

  //Open the port at a given speed
  String portName = Serial.list()[serialPortNumber];
  myPort = new Serial(this, portName, portSpeed);
  myPort.clear();

  //Reset the target board to begin bootloading
  myPort.setDTR(true);
  delay(1); //Don't wait too long here, the 0.1uF capacitor's rise time is quick
  myPort.setDTR(false);

  delay(100); //Testing with optiboot, 50ms is too short. We have to wait a significant amount of time before sending commands to the target.

  myPort.clear();

  //For the STK based bootloaders, the host transmits two bytes after reset. The target should respond with 0x14 + 0x10.
  byte[] comm_output = {0x30, 0x20};
  myPort.write(comm_output);

  if (waitForResponse(2, 500) == -1) return(-1); //Wait for 2 characters to come back. Return fail if we time out.

  //We got a response! Is it what we expected?
  int incomingChar1 = myPort.readChar();
  int incomingChar2 = myPort.readChar();

  if (incomingChar1 != 0x14 || incomingChar2 != 0x10) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  //Otherwise, yay! We have a valid response!
  println("Responded at: " + portSpeed);

  //Begin testing the board to see if it supports extended commands or not
  byte GENERIC_RESPONSE = 0x03;
  byte CRC_EOP = 0x20; //The STK protocol uses a lot of 0x20s (Space)
  byte STK_GET_PARAMETER = 0x41;
  byte Parameter_CID = (byte)0xA0;
  byte Parameter_BID = (byte)0xA1;
  byte Parameter_XTAL = (byte)0xA2;
  byte Parameter_UBR = (byte)0xA3;
  int CID = 0;
  int BID = 0;
  int OSC = 0;

  //myPort.write(char(STK_GET_PARAMETER)); //Tell the board we are messing with parameters
  //myPort.write(char(Parameter_CID)); //Request the company ID
  //myPort.write(char(CRC_EOP)); //Send end of Parameter character (space)
  byte[] buff1 = {STK_GET_PARAMETER, Parameter_CID, CRC_EOP};
  myPort.write(buff1);

  //Board will now respond with STK_INSYNC (0x14) and then the results of the paramter request
  if (waitForResponse(2, 500) == 0) { //This is an extended command, may not be supported
    incomingChar1 = myPort.readChar(); //Read insyc (0x14) character and throw it away
    CID = myPort.readChar();
    if (CID != GENERIC_RESPONSE && CID != 0x00) {
      //Generic response is 0x03 on Optiboot
      //Some boards respond with 0x00
      println("Extended commands supported!");
      extendedCommandSupport = true;
    }
    else
      //Board responded with generic 0x03 which means it does not support this command
      extendedCommandSupport = false;
  }

  if (extendedCommandSupport == true) {
    //myPort.write(char(STK_GET_PARAMETER)); //Tell the board we are messing with parameters
    //myPort.write(char(Parameter_BID)); //Request the board ID
    //myPort.write(char(CRC_EOP)); //Send end of Parameter character (space)
    byte[] buff2 = {STK_GET_PARAMETER, Parameter_BID, CRC_EOP};
    myPort.write(buff2);
    if (waitForResponse(2, 500) == 0) {
      incomingChar1 = myPort.readChar(); //Read insyc character and throw it away
      BID = myPort.readChar();
    }

    //myPort.write(char(STK_GET_PARAMETER)); //Tell the board we are messing with parameters
    //myPort.write(char(Parameter_XTAL)); //Request the crystal frequency
    //myPort.write(char(CRC_EOP)); //Send end of Parameter character (space)
    byte[] buff3 = {STK_GET_PARAMETER, Parameter_XTAL, CRC_EOP};
    myPort.write(buff3);
    if (waitForResponse(2, 500) == 0) {
      incomingChar1 = myPort.readChar(); //Read insyc character and throw it away
      OSC = myPort.readChar();
    }

    //Print this boards CID/BID/XTAL
    println("CID:" + CID + " BID:" + BID + " OSC:" + OSC + "MHz");

    //Let's see if we can force it into a higher baud rate
    println("Sending UART setting");
    //myPort.write(char(STK_GET_PARAMETER)); //Tell the board we are messing with parameters
    //myPort.write(char(Parameter_UBR)); //Set baud rate
    //myPort.write(char(CRC_EOP)); //Send end of Parameter character (space)
    byte[] buff4 = {STK_GET_PARAMETER, Parameter_UBR, CRC_EOP};
    myPort.write(buff4);
    if (waitForResponse(1, 500) == 0) {
      incomingChar1 = myPort.readChar(); //Read insyc character and throw it away
    }
    myPort.write((char)ubr_setting); //Push the IC to 2Mbps
    //Board should now be at new speed

    delay(10); //This small delay reduces the number of NullPointerExceptions. Maybe java needs time before we stop port?

    //Close and re-open port at new speed
    myPort.stop();
    myPort = new Serial(this, portName, max_port_speed);
    //It can take the computer up to 1300ms to switch port speeds (ya, bad)
    //Transmit a ! to let the board know we're ready to continue
    myPort.write('!'); //Tell the board we are now at this new speed
    //incomingChar1 = myPort.readChar(); //Read insyc character and throw it away
  }

  delay(10);
  while (myPort.available () > 0) myPort.readChar(); //Clear out any stray characters in the RX buffer

  //Let's go get the IC signature
  //This code takes 31.817ms
  //myPort.write(char(0x75)); //This is the STK command to get IC signature
  //myPort.write(char(0x20)); //Target should respond with 5 bytes. For example 0x14 1E 95 0F 10
  //This code takes 25.23ms
  byte[] buff5 = {0x75, 0x20};
  myPort.write(buff5);

  if (waitForResponse(5, 500) == -1) return(-1); //Wait for 5 characters to come back. Return fail if we time out.

  //The thing identified itself!
  char sign1, sign2, sign3;
  incomingChar1 = myPort.readChar(); //Read, but ignore this byte. It's just the 0x14 header byte
  sign1 = myPort.readChar();
  sign2 = myPort.readChar();
  sign3 = myPort.readChar();

  println("sign1: " + (int)sign1);
  println("sign2: " + (int)sign2);
  println("sign3: " + (int)sign3);

  if (sign1 == 0x1E && sign2 == 0x95 && sign3 == 0x0F) { 
    IC_type = "ATmega328"; 
    property_PS = "128"; 
    property_PS_int = 128;
  }
  if (sign1 == 0x1E && sign2 == 0x98 && sign3 == 0x01) { 
    IC_type = "ATmega2560"; 
    property_PS = "256"; 
    property_PS_int = 256;
  }
  if (sign1 == 0x1E && sign2 == 0x94 && sign3 == 0x06) { 
    IC_type = "ATmega168"; 
    property_PS = "128"; 
    property_PS_int = 128;
  }
  if (sign1 == 0x1E && sign2 == 0x93 && sign3 == 0x07) { 
    IC_type = "ATmega8"; 
    property_PS = "64"; 
    property_PS_int = 64;
  }
  if (sign1 == 0x1E && sign2 == 0x97 && sign3 == 0x03) { 
    IC_type = "ATmega1280"; 
    property_PS = "256"; 
    property_PS_int = 256;
  }
  //Maybe add ATmega644? MakerBot folks?

  println("IC: " + IC_type);

  //Before we muck with the firmware on the target, read in it's first 256 bytes of firmware and store it locally, temporarily
  byte[] tempHEX = new byte[256];
  int response = stk500_read(256, 0, property_PS_int, tempHEX);
  if (response == -1) {
    println("Read firmware fail.");
    property_FREQ = "Failed test";
    return(0);
  }
  else
    println("256 bytes read from target's firmware");

  //Close down port operations so that we can load new firmware
  myPort.stop();

  //We now have the IC type, but can we get the frequency identified?
  println("Begin frequency testing:");

  byte[] compressedHEX = new byte[100000]; //Assume most firmware should be smaller than 100,000 bytes

  //Parse frequency file
  int lastMemoryAddress = 0;
  if (IC_type == "ATmega328")
    lastMemoryAddress = parse_file("Frequency_Test-ATmega328.hex", compressedHEX);
  else if (IC_type == "ATmega168")
    lastMemoryAddress = parse_file("Frequency_Test-ATmega168.hex", compressedHEX);
  else {
    println("No test HEX available to identify the freq of this IC");
    property_FREQ = "Unknown";
    return(0); //Maybe success?
  }

  //Now push this hex file to the target
  response = stk500_bootload(portSpeed, property_PS_int, lastMemoryAddress, compressedHEX);
  if (response == -1) {
    myPort.stop(); //Clean up
    println("Freq test loading HEX failed");
    return(-1);
  }
  else
    println("Test HEX successfully loaded!");

  response = stk500_check_testchar(19200); //See if we can see the 'X' at 16MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 16MHz");
    property_FREQ = "16MHz";

    //Now return the first 256 bytes to the target's firmware
    response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
    if (response == -1) {
      gracefulExit("Failed restore on original firmware.");
      return(0); //Mild success
    }
    else {
      println("Original firmware restored.");
      myPort.stop(); //Clean up
      return(0); //Success!
    }
  }

  response = stk500_check_testchar(9600); //See if we can see the 'X' at 8MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 8MHz");
    property_FREQ = "8MHz";

    //Now return the first 256 bytes to the target's firmware
    response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
    if (response == -1) {
      gracefulExit("Failed restore on original firmware.");
      return(0); //Mild success
    }
    else {
      println("Original firmware restored.");
      myPort.stop(); //Clean up
      return(0); //Success!
    }
  }

  response = stk500_check_testchar(1200); //See if we can see the 'X' at 1MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 1MHz");
    property_FREQ = "1MHz";

    //Now return the first 256 bytes to the target's firmware
    response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
    if (response == -1) {
      gracefulExit("Failed restore on original firmware.");
      return(0); //Mild success
    }
    else {
      println("Original firmware restored.");
      myPort.stop(); //Clean up
      return(0); //Success!
    }
  }

  response = stk500_check_testchar(24000); //See if we can see the 'X' at 20MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 20MHz");
    property_FREQ = "20MHz";

    //Now return the first 256 bytes to the target's firmware
    response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
    if (response == -1) {
      gracefulExit("Failed restore on original firmware.");
      return(0); //Mild success
    }
    else {
      println("Original firmware restored.");
      myPort.stop(); //Clean up
      return(0); //Success!
    }
  }

  println("Failed to identify frequency");
  property_FREQ = "Tested but unknown";

  //Now return the first 256 bytes to the target's firmware
  response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
  if (response == -1) {
    gracefulExit("Failed restore on original firmware.");
    return(0); //Mild success
  }
  else {
    println("Original firmware restored.");
    myPort.stop(); //Clean up
    return(0); //Success!
  }

  //return(0); //Maybe success?
}

//This function opens up the comm port at a given port speed and looks for the character 'X'
//It assumes you've already loaded the test HEX onto the target board
//It returns 1 if it see's 'X' and -1 if it fails
public int stk500_check_testchar(int portSpeed) {
  println("Serial test at " + portSpeed);

  //Bootloading closes the port when done so open the port back up at 19200, the assumed baud rate of our test hex
  String portName = Serial.list()[serialPortNumber];
  myPort = new Serial(this, portName, portSpeed);
  myPort.clear();

  //Reset the target board to begin bootloading
  myPort.setDTR(true);
  delay(1); //Don't wait too long here, the 0.1uF capacitor's rise time is quick
  myPort.setDTR(false);

  int testChar = 0;

  //This is a bad hack. Sometimes processing sees a serial response character here that is
  //254. This for loop allows us to ignore any 254 responses
  for (int x = 0 ; x < 2 ; x++) {
    //Wait for our new test app to output the letter 'X'
    if (waitForResponse(1, 2500) == -1) return(-1); //Wait for 1 character to come back. Return fail if we time out.

    testChar = myPort.read();
    //  println("Test char seen: " + testChar);
    if (testChar != 254) break;
    println("Bad test character seen. Ignoring.");
  }

  myPort.stop(); //Clean up

    if (testChar == 'X') //We are golden! We see the X.
    return(1); //Yay!
  else
    return(-1); //Boo.
}

//This function resets the target board and then downloads 
//the new firmware onto the board
public void stk500_begin_download() {

  loadTime1 = millis(); //We use load time variable as a timer. Start the timer.

  println();
  println("Begin boot loading");

  byte[] compressedHEX = new byte[100000]; //Assume this firmware is not larger than 100,000 bytes

  println("Parsing file");
  int lastMemoryAddress = parse_file(fullFilePath, compressedHEX);

  //public int stk500_bootload(int portSpeed, int pageSize, int lastByte, byte[] HEXarray)
  stk500_bootload(115200, 128, lastMemoryAddress, compressedHEX);

  loadTime2 = millis(); //We use load time variable as a timer. Start the timer.

  println("Download complete!");
}

