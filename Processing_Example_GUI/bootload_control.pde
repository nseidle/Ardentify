/*
 10/4/2011
 Nathan Seidle
 Spark Fun Electronics 2011
 
 These functions are all the low level stuff for bootloading:
 
 parse_file: reads a HEX file into a binary array
 
 screamer_begin_download
 screamer_bootloading
 screamer_query_target
 screamer_secret handshake
 
 stk500_board_guessing
 stk500_bootload
 stk500_check_testchar
 
 */

//This function waits for a certain number of characters, before giving up
//Each giveup is 1 ms long. 500 milliseconds is common.
public int waitForResponse(int numberOfChars, int triesBeforeGiveup) {

  int tries = 0;
  while (myPort.available() < numberOfChars) {
    tries++;
    delay(1);
    if (tries > triesBeforeGiveup) {
      myPort.stop();
      return(-1);
    }
    //Here we have an emergency break
    if (emergency_stop == true) {
      gracefulExit("User break");
      return(-1);
    }
  }
  
  return(0); //Success!
}

//Gracefully closes the COM port and takes care of any other problems
public void gracefulExit(String theError) {
  if(theError != "") println("Error: " + theError);
  myPort.stop(); //Close the COM port
}

//Given a file name, and an array, the function parses the HEX file into a large binary array
//Returns the last memory address in this HEX file
public int parse_file(String fileName, byte[] theArray) {
  int lastMemoryAddress = 0;

  //Read in the HEX file

  String[] lines = loadStrings(fileName);

  //Remove empty lines + lines not starting with a ":"
  //Not yet implemented

  //Step through file and contents into large array
  //Also convert from ASCII to binary
  for (int i = 0 ; i < lines.length ; i++) {

    //Get the next line from the hex file
    String tempText = lines[i];

    //Peel off ':' from this line
    tempText = tempText.substring(1, tempText.length());
    //println("Peel " + i + ": " + tempText);

    //Peel off record length
    //http://www.roseindia.net/java/java-conversion/HexadecimalToDecima.shtml
    int recordLength = Integer.parseInt(tempText.substring(0, 2), 16); //The 16 on the end converts from hex to decimal
    tempText = tempText.substring(2, tempText.length()); //These two bytes are now processed, so remove them
    //println("record length " + i + ": " + recordLength);

    //Get the memory address of this line
    int memoryAddress = Integer.parseInt(tempText.substring(0, 4), 16);
    tempText = tempText.substring(4, tempText.length()); //These four bytes are now processed, so remove them
    //println("memory address " + i + ": " + memoryAddress);

    if ((lastMemoryAddress + recordLength) > lastMemoryAddress)
      lastMemoryAddress = memoryAddress + recordLength; //Increase the last memory address as we go

    //Check for end of file tag
    int endOfFile = Integer.parseInt(tempText.substring(0, 2), 16);
    tempText = tempText.substring(2, tempText.length()); //These two bytes are now processed, so remove them
    //println("endOfFile " + i + ": " + endOfFile);
    if (endOfFile == 1) break; //We're done processing the file!

    //Push the contents of this line to the larger array
    for (int x = 0 ; x < recordLength ; x++) {
      theArray[memoryAddress + x] = (byte)Integer.parseInt(tempText.substring(0, 2), 16);
      //print(compressedHEX[memoryAddress + x] + " ");
      tempText = tempText.substring(2, tempText.length()); //These two bytes are now processed, so remove them
    }
  }

  //println("Last memory address: " + lastMemoryAddress);

  //The binary form of the HEX file is now in the compressed HEX array
  println("HEX file parsed");
  
  return(lastMemoryAddress);
}

//This function assumes the correct port is already open at the correct speed
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
  myPort.write(char(0x30));
  myPort.write(char(0x20));

  if(waitForResponse(2, 500) == -1) return(-1); //Wait for 2 characters to come back. Return fail if we time out.

  //We got a response! Is it what we expected?
  int incomingChar1 = myPort.readChar();
  int incomingChar2 = myPort.readChar();

  if (incomingChar1 != 0x14 || incomingChar2 != 0x10) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  //Start at beginning of large intel array
  int currentMemoryAddress = 0;

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

    //Send the memory address to the target
    myPort.write((char)0x55); //STK command for load address
    myPort.write((char)MemoryAddressLow);
    myPort.write((char)MemoryAddressHigh);
    myPort.write((char)0x20); //STK character for the termination of a command

    myPort.clear();

    //Wait for target to verify with 0x14 0x10
    if(waitForResponse(2, 500) == -1){
       gracefulExit("The target IC did not finish loading. You will likely experience unexpected program execution.");
       return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }

    int inChar1 = myPort.read();
    int inChar2 = myPort.read();

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
    myPort.write(dataBytes);


    //Wait for IC to tell us he's ready
    //Wait for target to verify with 0x14 0x10
    if(waitForResponse(2, 500) == -1){
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

  println("Bootload finished");

  return(0); //Success!
}

//This function reads a certain number of bytes from a starting location into an array of chars
//It assumes the port is already open and the STK500 bootloader is sitting waiting for commands
//This was originally designed to pull down the first 256 bytes of a boards firmware so that we could
//Overwrite it with the frequency test app, the replace the original firmware
public int stk500_read(int numberOfBytes, int startingLocation, int pageSize, byte[] HEXarray) {

  //Start at beginning of large intel array
  int currentMemoryAddress = startingLocation;
  
  int lastByte = startingLocation + numberOfBytes;

  while (true) {

    //Here's our escape!
    if (currentMemoryAddress >= lastByte) {
      //We shouldn't have to do anything. The Arduino bootloader should time out.
      break;
    }

    int blockLength = pageSize; //Set block length to page size
    if (currentMemoryAddress + blockLength > lastByte) //Check to see if we're towards the end of the array
      blockLength = lastByte - currentMemoryAddress; //Trim the blockLength to grab the final less-than-pagesize block 

    //Convert 16-bit current_memory_address into two 8-bit characters
    //STK500 is weird. It loads the word location, not the actual memory location, so we divide by 2
    int MemoryAddressHigh = (currentMemoryAddress / 2) / 256;
    int MemoryAddressLow = (currentMemoryAddress / 2) % 256;

    myPort.clear();

    //Send the memory address to the target
    myPort.write((char)0x55); //STK command for load address
    myPort.write((char)MemoryAddressLow);
    myPort.write((char)MemoryAddressHigh);
    myPort.write((char)0x20); //STK character for the termination of a command

    myPort.clear();

    //Wait for target to verify with 0x14 0x10
    if(waitForResponse(2, 500) == -1){
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
    myPort.write((char)0x74); //STK command for load address
    myPort.write((char)(blockLength / 256)); //High byte of page size?
    myPort.write((char)(blockLength % 256)); //Low byte of page size
    myPort.write((char)0x46); //Unknown - but was in the page_write series as well
    myPort.write((char)0x20); //STK character for the termination of a command

    myPort.clear();
    
    //Now the target is going to respond with 0x14 and pagesize worth of bytes + 0x10
    if(waitForResponse(1, 500) == -1){
       gracefulExit("STK500 bootloader did not respond to PAGE READ command.");
       return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }
    myPort.read(); //Read the 0x14 character from the port
    
    //Read in the 128? bytes of the page
    for(int i = 0 ; i < blockLength ; i++) {
      waitForResponse(1, 500);
      HEXarray[currentMemoryAddress + i] = (byte)myPort.read();
    }
    
    //Read the 0x10 termination character
    if(waitForResponse(1, 500) == -1){
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
  myPort.write(char(0x30));
  myPort.write(char(0x20));

  if(waitForResponse(2, 500) == -1) return(-1); //Wait for 2 characters to come back. Return fail if we time out.

  //We got a response! Is it what we expected?
  int incomingChar1 = myPort.readChar();
  int incomingChar2 = myPort.readChar();

  if (incomingChar1 != 0x14 || incomingChar2 != 0x10) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  //Otherwise, yay! We have a valid response!
  //Let's go get the IC signature
  myPort.write(char(0x75)); //This is the STK command to get IC signature
  myPort.write(char(0x20)); //Target should respond with 5 bytes. For example 0x14 1E 95 0F 10

  if(waitForResponse(5, 500) == -1) return(-1); //Wait for 2 characters to come back. Return fail if we time out.

  //The thing identified itself!
  char sign1, sign2, sign3;
  incomingChar1 = myPort.readChar(); //Read, but ignore this byte. It's just the 0x14 header byte
  sign1 = myPort.readChar();
  sign2 = myPort.readChar();
  sign3 = myPort.readChar();

  if (sign1 == 0x1E && sign2 == 0x95 && sign3 == 0x0F) { 
    IC_type = "ATmega328"; 
    property_PS = "128"; 
    property_PS_int = 128;
  }
  if (sign1 == 0x1E && sign2 == 0x98 && sign3 == 0x01) { 
    IC_type = "ATmega2560"; 
    property_PS = "128"; 
    property_PS_int = 128;
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
    property_PS = "128"; 
    property_PS_int = 128;
  }

  //Before we muck with the firmware on the target, read in it's first 256 bytes of firmware and store it locally, temporarily
  byte[] tempHEX = new byte[256];
  int response = stk500_read(256, 0, property_PS_int, tempHEX);
  if(response == -1) {
    println("Read firmware fail.");
    property_FREQ = "Failed test";
    return(0);
  }
  else
    println("256 bytes read from target's firmware");
    
  for(int i = 0 ; i < 64 ; i++)
    print(tempHEX[i] + " ");
  println();

  //Close down port operations so that we can load new firmware
  myPort.stop();

  //We now have the IC type, but can we get the frequency identified?
  println("Begin frequency testing.");
  
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
    if(response == -1) {
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
  if (response == -1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 8MHz");
    property_FREQ = "8MHz";

    //Now return the first 256 bytes to the target's firmware
    response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
    if(response == -1) {
      gracefulExit("Failed restore on original firmware.");
      return(0); //Mild success
    }
    else {
      println("Original firmware restored.");
      myPort.stop(); //Clean up
      return(0); //Success!
    }
  }

  response = stk500_check_testchar(2400); //See if we can see the 'X' at 1MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 1MHz");
    property_FREQ = "1MHz";

    //Now return the first 256 bytes to the target's firmware
    response = stk500_bootload(portSpeed, property_PS_int, 256, tempHEX);
    if(response == -1) {
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
  return(0); //Maybe success?
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

  //Wait for our new test app to output the letter 'X'
  if(waitForResponse(1, 1500) == -1) return(-1); //Wait for 2 characters to come back. Return fail if we time out.

  int testChar = myPort.read();
  myPort.stop(); //Clean up

  if (testChar == 'X') //We are golden! We see the X.
    return(1); //Yay!
  else
    return(-1); //Boo.
}

//Give the ICs page size, the last byte of the array, and a binary array of firmware
//This function pushes all the data out to the target as fast as possible
//Uses basic 8 bit CRC
//Returns -1 for fail, !(-1) for success
public int screamer_bootload(int pageSize, int lastByte, byte[] HEXarray) {

  //Start at beginning of large intel array
  int currentMemoryAddress = 0;

  while (true) {

    //Wait for IC to tell us he's ready
    if(waitForResponse(1, 500) == -1){
       gracefulExit("The target IC did not finish loading. You will likely experience unexpected program execution.");
       return(-1); //Wait for 2 characters to come back. Return fail if we time out.
    }

    int incomingChar = myPort.readChar();

    if (incomingChar == 'T') { //All is well
    }
    else if (incomingChar == 'X') { //Resend last line
      currentMemoryAddress -= pageSize; //Move the marker back one page
    }
    else {
      println("Error: Incorrect response from target IC. Programming is incomplete and will now halt.");
      myPort.stop();
      return(-1);
    }

    //Here's our escape!
    if (currentMemoryAddress >= lastByte) {
      //Tell the target IC we are done transmitting data, go start your program
      myPort.write(":S");
      break;
    }

    //=============================================
    //Convert 16-bit current_memory_address into two 8-bit characters
    int MemoryAddressHigh = currentMemoryAddress / 256;
    int MemoryAddressLow = currentMemoryAddress % 256;

    //println("Address: " + currentMemoryAddress + ", " + MemoryAddressHigh + ", " + MemoryAddressLow);

    int block_length = pageSize; //Set block length to page size
    if (currentMemoryAddress + block_length > lastByte) //Check to see if we're towards the end of the array
      block_length = lastByte - currentMemoryAddress;

    //println("Block length: " + block_length);
    //=============================================
    //Calculate current check_sum
    int CheckSum = 0;
    CheckSum += block_length;
    CheckSum += MemoryAddressHigh;
    CheckSum += MemoryAddressLow;

    for (int j = 0 ; j < block_length ; j++)
      CheckSum += HEXarray[currentMemoryAddress + j]; //We should be calculating this during preprocessing to save time

    //Now reduce check_sum to 8 bits
    while (CheckSum > 256)
      CheckSum -= 256;

    //Now take 2's compliment
    CheckSum = 256 - CheckSum;

    //println("CheckSum: " + CheckSum);
    //=============================================

    //Each myPort.write takes 1ms of overhead
    //By combining all the control and data into one array, we can do one system/serial.write instead of many. 
    byte[] dataBytes = new byte[block_length + 5];

    //Send the start character
    dataBytes[0] = ':'; //myPort.write((char)':');

    //Send the record length
    dataBytes[1] = (byte)block_length; //myPort.write((char)block_length);

    //Send this block's address
    dataBytes[2] = (byte)MemoryAddressLow; //myPort.write((char)MemoryAddressLow);
    dataBytes[3] = (byte)MemoryAddressHigh; //myPort.write((char)MemoryAddressHigh);

    //Send this block's check sum
    dataBytes[4] = (byte)CheckSum; //myPort.write((char)CheckSum);

    //Send the next block of data from the compressed HEX array

    //This is too slow. 1ms per byte.
    //for(int j = 0 ; j < block_length ; j++) {
    //  myPort.write((char)compressedHEX[currentMemoryAddress + j]); //Processing takes ~0.8ms to run this line. Bad!
    //}

    //This didn't work. A REALLY weird single byte error shows up in the stream.
    //myPort.write(compressedHEXlines[lineNumber++]);
    //Aha! From: http://msdn.microsoft.com/en-us/library/1050fs1h%28v=vs.80%29.aspx
    //By default, SerialPort uses ASCIIEncoding to encode the characters. ASCIIEncoding encodes all characters greater then 127 as (char)63 or '?'.

    for (int i = 0 ; i < block_length ; i++)
      dataBytes[i + 5] = HEXarray[currentMemoryAddress + i];

    //Push this block of control and data out to the serial port
    myPort.write(dataBytes);
    //=============================================

    currentMemoryAddress += block_length;
  }

  //Clean up
  myPort.stop();

  println("Bootload finished");

  return(0); //Success!
}

//This function gets the IC through the basics of comm speed negotiations and to the state
//where the target is waiting for further instructions
public int screamer_secret_handshake() {
  emergency_stop = false;

  //Initially host opens port at 19200 and waits for ASCII(5)
  //Opening the port should cause a board reset
  String portName = Serial.list()[serialPortNumber];
  myPort = new Serial(this, portName, 19200);
  myPort.clear();

  //Reset the target board to begin bootloading
  myPort.setDTR(true);
  delay(1); //Don't wait too long here, the 0.1uF capacitor's rise time is quick
  myPort.setDTR(false);

  myPort.clear();

  if(waitForResponse(1, 500) == -1) return(-1); //Wait for 1 character to come back. Return fail if we time out.
  int incomingChar = myPort.readChar();

  //Target should say hello with ASCII(5)
  if (incomingChar != char(5)) {
    println("Error: Wrong response from target" + (int)incomingChar);
    myPort.stop(); //Close port before we leave
    return(-1);
  }

  //Send the target ASCII(6) to cause the target IC to go into load mode
  myPort.write(char(6));
  myPort.clear();

  //Wait for the target to tell us what serial speed to talk at
  int targetResponse = 0;
  while (true) {
    if (myPort.available() > 0) {
      incomingChar = myPort.readChar();
      if (incomingChar == ',') break;
      if (incomingChar >= '0' && incomingChar <= '9') {
        incomingChar -= '0'; //Convert alpha to number
        targetResponse = (targetResponse * 10) + incomingChar;
      }
    }

    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return(-1);
    }
  } 

  myPort.write(targetResponse + ",");

  property_COMM = Integer.toString(targetResponse); //Store the download speed

  //From testing, this println takes about 11ms so be careful when printing
  println("New comm speed requested: " + targetResponse); //Respond back to the target to confirm we agree on the new speed

  //Unfortunately java doesn't seem to be able to close and reopen the port very quickly.
  myPort.stop(); //Close the port and go to the new commSpeed
  myPort = new Serial(this, portName, targetResponse);
  //Rough testing shows that this takes my computer ~150ms. So the bootloader on the arduino has to spin
  //its thumbs for 250ms. Boo.

  //Wait for the target to send us the SSVQ (serial speed verification request)
  targetResponse = 0;
  while (true) {
    if (myPort.available() > 0) {
      incomingChar = myPort.readChar();
      if (incomingChar == ',') break;
      if (incomingChar >= '0' && incomingChar <= '9') {
        incomingChar -= '0'; //Convert alpha to number
        targetResponse = (targetResponse * 10) + incomingChar;
      }
    }

    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return(-1);
    }
  }
  if (targetResponse == SSVQ) {
    myPort.write(SSVQ + ","); //Respond that we are a-ok at this new speed
    println("New comm speed achieved");
  }
  else {
    println("Error: Target failed SSVQ - " + (int)targetResponse);
    myPort.stop();
    return(-1);
  }

  return(1);

  //Now the target IC should be sitting waiting for further commands
}

//Screamer, Higher speed bootloader
//This function resets the target board, identifies the requested baud rate and 
//begins identifying the board and then downloads code onto the board
public void screamer_begin_download() {

  loadTime1 = millis(); //We use load time variable as a timer. Start the timer.

  println();
  println("Begin boot loading");

  //Reset the target IC and go through enumeration steps
  screamer_secret_handshake();

  //Before we can bootload, we must know the page size
  property_PS = screamer_query_target(PSRQ);
  println("Page size: " + property_PS);
  property_PS_int = Integer.parseInt(property_PS); //Convert this property to a usable int

  byte[] compressedHEX = new byte[100000]; //Assume this firmware is not larger than 100,000 bytes

  println("Parsing file");
  int lastMemoryAddress = parse_file(fullFilePath, compressedHEX);

  myPort.write(BLRQ + ","); //Send the target the boot load request
  screamer_bootload(property_PS_int, lastMemoryAddress, compressedHEX);

  loadTime2 = millis(); //We use load time variable as a timer. Start the timer.
}

//This function takes in a command (no comma needed) and returns what the target responded with
//Returns -1 if the user hits the break button
public String screamer_query_target(int cmdQuery) {
  myPort.write(cmdQuery + ","); //Send the target a command

  String targetResponse = "";
  while (true) {
    if (myPort.available() > 0) {
      char incomingChar = myPort.readChar();
      //print(incomingChar);
      if (incomingChar == ',') break;
      targetResponse += incomingChar;
    }

    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return("-1");
    }
  }

  return(targetResponse);
}

