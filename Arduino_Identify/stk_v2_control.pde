/*
 10/4/2011
 Nathan Seidle
 Spark Fun Electronics 2011
 
 These functions are all the low level stuff for bootloading:
 
 parse_file: reads a HEX file into a binary array
 
 stk500_board_guessing
 stk500_bootload
 stk500_check_testchar
 
 */

int frameNumber = 1; //Starts at 1

//This function assumes the correct port is already open at the correct speed
//This function receives a HEXarray that is normally filled by the parse function
//Assumes you have correctly loaded global variable property_PS_int.
//This fuction will send the correct commands to a target to load the firmware in the hex array
//It will bail with a -1 if anything goes wrong
public int stk500_v2_bootload(int pageSize, int lastByte, byte[] HEXarray) {

  byte[] comm_output = new byte[20]; //When reading, no more than a dozen bytes + some control bytes.
  int[] comm_input = new int[300]; //When reading, we will see 256 + some control bytes.
  int x; //Spare variable used a lot

  int currentMemoryAddress = 0;

  //For regular bootloading we are going to assume we will start at 0x0000 for all cases.
  //Convert 32-bit startingLocation into four bytes
  //The memory locations for the STKv2 are four bytes. 
  int[] MemoryAddress = new int[4]; 
  MemoryAddress[0] = 0x80; //Set the high bit for ICs that have more than 64kb flash space. Both 1280 and 2560 are this way.
  MemoryAddress[1] = 0x00;
  MemoryAddress[2] = 0x00;
  MemoryAddress[3] = 0x00;

  //Load address to start the write from
  int cmd_load_address = 0x06; 
  int[] command_str = {
    cmd_load_address, MemoryAddress[0], MemoryAddress[1], MemoryAddress[2], MemoryAddress[3]
  };
  comm_output = stk500_v2_form_frame(command_str, 5);
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(8, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
  for (x = 0 ; x < 8 ; x++) comm_input[x] = (byte)myPort.readChar();

  //Check two bytes to see if they are what we expect
  //byte[5] = 0x60 and byte[6] = 0x00 means the board responded OK!
  if (comm_input[5] != cmd_load_address || comm_input[6] != 0x00) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  while (currentMemoryAddress < lastByte) {

    int blockLength = pageSize; //Set block length to page size
    if (currentMemoryAddress + blockLength > lastByte) //Check to see if we're towards the end of the array
      blockLength = lastByte - currentMemoryAddress; //Trim the blockLength to grab the final less-than-pagesize block 

    //Now tell the board to record some bytes!
    int cmd_read_flash_isp = 0x14;
    int blockLengthHigh = blockLength / 256;
    int blockLengthLow = blockLength % 256;

    //For a program flash type frame, there's a lot:
    //5 bytes of header
    //1 byte of CMD_PROGRAM_FLASH (0x13)
    //2 bytes of number of bytes (0x0100)
    //1 Mode
    //1 Delay
    //1 CMD1
    //1 CMD2
    //1 CMD3
    //1 Poll1
    //1 Poll2
    //256 bytes of data
    //1 CRC
    //16 command bytes + 256 data bytes = 272 bytes total

    byte[] dataBytes = new byte[16 + pageSize]; 


    dataBytes[0] = 0x1B; //Every frame begins with 0x1B
    dataBytes[1] = (byte)frameNumber++; //This is the frame number. Rolls over at 255
    int length_of_command = pageSize + 10;
    dataBytes[2] = (byte)(length_of_command / 256);
    dataBytes[3] = (byte)(length_of_command % 256);
    dataBytes[4] = 0x0E; //This is to indicate the beginning of actual data
    dataBytes[5] = 0x13; //CMD_PROGRAM_FLASH
    dataBytes[6] = (byte)(blockLength / 256);
    dataBytes[7] = (byte)(blockLength % 256);
    dataBytes[8] = (byte)0xC1;
    dataBytes[9] = (byte)0x0A;
    dataBytes[10] = (byte)0x40;
    dataBytes[11] = (byte)0x4C;
    dataBytes[12] = (byte)0x20;
    dataBytes[13] = (byte)0x00;
    dataBytes[14] = (byte)0x00;

    //Splice in the next block of data from the compressed HEX array
    for (int i = 0 ; i < blockLength ; i++)
      dataBytes[15 + i] = HEXarray[currentMemoryAddress + i];

    //Calculate the CRC for this frame  
    int CRC = 0;
    for (x = 0 ; x < (15 + pageSize) ; x++)
      CRC ^= dataBytes[x]; //Calculate the CRC for this frame. It is the XOR of ALL the bytes in the frame
    dataBytes[15 + pageSize] = (byte)CRC; //Attach CRC to the very end of the frame

    myPort.write(dataBytes); //Send the frame
    myPort.clear();

    //Get the response and check it
    if (waitForResponse(8, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
    for (x = 0 ; x < 8 ; x++) comm_input[x] = (byte)myPort.readChar();

    //Check two bytes to see if they are what we expect
    //byte[5] = 0x13 and byte[6] = 0x00 means the board responded OK!
    if (comm_input[5] != 0x13 || comm_input[6] != 0x00) {
      //Invalid response! Eject! Eject!
      myPort.stop(); //Clean up
      return(-1); //Fail
    }

    //Move the marker forward
    //println("currentMemoryAddress: " + currentMemoryAddress); //Debug
    currentMemoryAddress += blockLength;
  }

  //Rest the board so that it is in a clean/happy state
  myPort.setDTR(true);
  delay(1); //Don't wait too long here, the 0.1uF capacitor's rise time is quick
  myPort.setDTR(false);

  //Clean up
  myPort.stop();

  //println("Bootload finished");

  return(0); //Success!
}

//This function reads a certain number of bytes from a starting location into an array of chars
//It assumes the port is already open and the STK500 v2 bootloader is sitting waiting for commands
//This was originally designed to pull down the first 256 bytes of a boards firmware so that we could
//Overwrite it with the frequency test app, then replace the original firmware
public int stk500_v2_read(int numberOfBytes, int startingLocation, int pageSize, byte[] HEXarray) {

  byte[] comm_output = new byte[20]; //When reading, no more than a dozen bytes + some control bytes.
  int[] comm_input = new int[300]; //When reading, we will see 256 + some control bytes.
  int x; //Spare variable used a lot

  int currentMemoryAddress = startingLocation;
  int lastByte = startingLocation + numberOfBytes;

  //startingLocation /= 2; //Memory locations are by 16-bit word, not byte location.

  //Convert 32-bit startingLocation into four bytes
  //The memory locations for the STKv2 are four bytes. 
  int[] MemoryAddress = new int[4]; 
  for (x = 0 ; x < 4 ; x++) {
    MemoryAddress[3 - x] = startingLocation % 256;
    startingLocation /= 256;
  }

  MemoryAddress[0] |= 0x80; //Set the high bit for ICs that have more than 64kb flash space. Both 1280 and 2560 are this way.

  //Load address to start the read from
  int cmd_load_address = 0x06; 
  int[] command_str = {
    cmd_load_address, MemoryAddress[0], MemoryAddress[1], MemoryAddress[2], MemoryAddress[3]
  };
  comm_output = stk500_v2_form_frame(command_str, 5);
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(8, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
  for (x = 0 ; x < 8 ; x++) comm_input[x] = (byte)myPort.readChar();

  //Check two bytes to see if they are what we expect
  //byte[5] = 0x60 and byte[6] = 0x00 means the board responded OK!
  if (comm_input[5] != cmd_load_address || comm_input[6] != 0x00) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  while (currentMemoryAddress < lastByte) {

    int blockLength = pageSize; //Set block length to page size
    if (currentMemoryAddress + blockLength > lastByte) //Check to see if we're towards the end of the array
      blockLength = lastByte - currentMemoryAddress; //Trim the blockLength to grab the final less-than-pagesize block 

    //Now tell the board to report some bytes!
    int cmd_read_flash_isp = 0x14;
    int blockLengthHigh = blockLength / 256;
    int blockLengthLow = blockLength % 256;

    int[] command_read = {
      cmd_read_flash_isp, blockLengthHigh, blockLengthLow, 0x20
    };
    comm_output = stk500_v2_form_frame(command_read, 4);
    myPort.write(comm_output); //Send the frame
    myPort.clear();

    //myPort.available() seems to overflow at 137 characters so we split it into multiple reads
    //265 bytes total:
    //5 bytes of header
    //1 byte of ANSWER ID (0x14)
    //1 byte of CMD OK
    //256 bytes of data = 0xC1 00 …
    //1 byte of CMD OK
    //1 byte of CRC

    //Get first 7 header characters
    if (waitForResponse(7, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
    for (x = 0 ; x < 7 ; x++) myPort.readChar(); //Just throw out these 7 bytes

    //Get block of 256
    for (int i = 0 ; i < blockLength ; i++) {
      waitForResponse(1, 500);
      HEXarray[currentMemoryAddress + i] = (byte)myPort.readChar();
    }

    //Get last two ending characters (CMD OK and CRC)
    if (waitForResponse(2, 1000) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
    for (x = 0 ; x < 2 ; x++) myPort.readChar(); //Just throw out these 2 bytes

    //Move the marker forward
    //println("currentMemoryAddress: " + currentMemoryAddress); //Debug
    currentMemoryAddress += blockLength;
  }

  return(0); //Success!
}

//This function talks to bootloaders based on the STK v2 protocol
//This is specifically for the v2 protocol found on Mega boards (ATmega1280 and ATmega2560 based boards)
//It will try to communicate at portSpeed. It will give up after 500ms.
public int stk500_v2_board_guessing(int portSpeed) {
  int response;

  IC_type = "Unknown"; //Reset the IC type until we find a good one.

  //This is the initial reset and ping of the target, let's see if STK500v2 is lurking out there
  response = stk500_v2_initial_handshake(portSpeed);
  if (response == -1) return(-1); //This is not STK500v2!
  println("Board answered to STK v2!");

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //Now we ping the IC for its signature

  byte[] comm_output = new byte[300]; //Can be 256 byte data frames
  int[] comm_input = new int[300];

  //bytes in java are signed? WTF?
  //http://www.faludi.com/2006/03/21/signed-and-unsigned-bytes-in-processing/
  //Thanks Rob!
  int sign1, sign2, sign3;

  //Tell the board to give up its first signature byte
  int[] stkv2_signature_req1 = {
    0x1D, 0x04, 0x04, 0x00, 0x30, 0x00, 0x00, 0x00
  };  
  comm_output = stk500_v2_form_frame(stkv2_signature_req1, 8); //Take this command and add the frame bits around it
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(13, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
  for (int x = 0 ; x < 13 ; x++) comm_input[x] = (byte)myPort.readChar();
  sign1 = comm_input[10] & 0xFF;

  //Tell the board to give up its 2nd signature byte
  int[] stkv2_signature_req2 = {
    0x1D, 0x04, 0x04, 0x00, 0x30, 0x00, 0x01, 0x00
  };  
  comm_output = stk500_v2_form_frame(stkv2_signature_req2, 8); //Take this command and add the frame bits around it
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(13, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
  for (int x = 0 ; x < 13 ; x++) comm_input[x] = (byte)myPort.readChar();
  sign2 = comm_input[10] & 0xFF;

  //Tell the board to give up its 3rd signature byte
  int[] stkv2_signature_req3 = {
    0x1D, 0x04, 0x04, 0x00, 0x30, 0x00, 0x02, 0x00
  };  
  comm_output = stk500_v2_form_frame(stkv2_signature_req3, 8); //Take this command and add the frame bits around it
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(13, 500) == -1) return(-1); //Wait for characters to come back. Return fail if we time out.
  for (int x = 0 ; x < 13 ; x++) comm_input[x] = (byte)myPort.readChar();
  sign3 = comm_input[10] & 0xFF;

  if (sign1 == 0x1E && sign2 == 0x98 && sign3 == 0x01) { 
    IC_type = "ATmega2560"; 
    property_PS = "256"; 
    property_PS_int = 256;
  }
  if (sign1 == 0x1E && sign2 == 0x97 && sign3 == 0x03) { 
    IC_type = "ATmega1280"; 
    property_PS = "256"; 
    property_PS_int = 256;
  }
  //Maybe add ATmega644? MakerBot folks?

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //We now have the IC type, but can we get the frequency identified?
  println("Begin frequency testing:");

  //Before we muck with the firmware on the target, read in its first 512 bytes of firmware and store it locally, temporarily
  byte[] tempHEX = new byte[512];
  println("Read firmware start");
  response = stk500_v2_read(512, 0, property_PS_int, tempHEX);
  if (response == -1) {
    println("Read firmware fail.");
    property_FREQ = "Failed test";
    return(0);
  }

  println("512 bytes read from target's firmware");

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //Parse the test HEX

  //We're going to keep the port open while we parse the files.
  //There's a timeout issue here but I think we can beat it.
  //Close down port operations so that we can load new firmware
  //myPort.stop();


  byte[] compressedHEX = new byte[100000]; //Assume most firmware should be smaller than 100,000 bytes

  //Parse frequency file
  int lastMemoryAddress = 0;
  if (IC_type == "ATmega2560")
    lastMemoryAddress = parse_file("Frequency_Test-ATmega2560.hex", compressedHEX);
  else if (IC_type == "ATmega1280")
    lastMemoryAddress = parse_file("Frequency_Test-ATmega1280.hex", compressedHEX);
  else {
    println("No test HEX available to identify the freq of this IC");
    property_FREQ = "Unknown";
    return(0); //Maybe success?
  }

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //Now push this hex file to the target
  response = stk500_v2_bootload(property_PS_int, lastMemoryAddress, compressedHEX);
  if (response == -1) {
    myPort.stop(); //Clean up
    println("Freq test loading HEX failed");
    return(-1);
  }
  else
    println("Test HEX successfully loaded!");

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //Now we wiggle the serial port at different baud rates looking for the X
  property_FREQ = "Unknown";

  if (property_FREQ == "Unknown") {
    response = stk500_v2_check_testchar(19200); //See if we can see the 'X' at 16MHz
    if (response == 1) {
      myPort.stop(); //Clean up
      println("Frequency confirmed at 16MHz");
      property_FREQ = "16MHz";
    }
  }

  if (property_FREQ == "Unknown") {
    response = stk500_v2_check_testchar(9600); //See if we can see the 'X' at 8MHz
    if (response == 1) {
      myPort.stop(); //Clean up
      println("Frequency confirmed at 8MHz");
      property_FREQ = "8MHz";
    }
  }

  if (property_FREQ == "Unknown") {
    response = stk500_v2_check_testchar(1200); //See if we can see the 'X' at 1MHz
    if (response == 1) {
      myPort.stop(); //Clean up
      println("Frequency confirmed at 1MHz");
      property_FREQ = "1MHz";
    }
  }

  if (property_FREQ == "Unknown") {
    response = stk500_v2_check_testchar(24000); //See if we can see the 'X' at 20MHz
    if (response == 1) {
      myPort.stop(); //Clean up
      println("Frequency confirmed at 20MHz");
      property_FREQ = "20MHz";
    }
  }

  if (property_FREQ == "Unknown") {
    println("Failed to identify frequency");
    property_FREQ = "Tested but unknown";
  }

  //Now return the first 512 bytes to the target's firmware
  //We have to reset and re-init the STK500v2 protocol
  response = stk500_v2_initial_handshake(portSpeed);
  if (response == -1) {
    gracefulExit("Failed restore on original firmware.");
    return(0); //Mild success
  }

  response = stk500_v2_bootload(property_PS_int, 512, tempHEX);
  if (response == -1) {
    gracefulExit("Failed restore on original firmware.");
    return(0); //Mild success
  }

  println("Original firmware restored.");
  
  myPort.stop(); //Clean up

  return(0); //Success!
}

//This function opens up a given port, resets the target board, then sends the initial two commands to start STK500v2 communications
public int stk500_v2_initial_handshake(int portSpeed) {

  //Open the port at a given speed
  String portName = Serial.list()[serialPortNumber];
  myPort = new Serial(this, portName, portSpeed);
  myPort.clear();

  //Reset the target board to begin bootloading
  myPort.setDTR(true);
  delay(1); //Don't wait too long here, the 0.1uF capacitor's rise time is quick
  myPort.setDTR(false);

  //Whenever we reset the board, so must we reset the STk500v2 frameNumber
  frameNumber = 1;

  delay(100); //Testing with optiboot, 50ms is too short. We have to wait a significant amount of time before sending commands to the target.

  myPort.clear();

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //For the STK v2 based bootloaders, the host transmits frames that are not small or simple.
  //See Datasheet, AVR068: http://www.atmel.com/dyn/resources/prod_documents/doc2591.pdf

  byte[] comm_output = new byte[30]; //Can be 512 bytes+, but in this initial handshake function, it's limited to ~10 bytes
  int[] comm_input = new int[30];

  int[] init_comm = {
    0x01
  };
  comm_output = stk500_v2_form_frame(init_comm, 1); //Take this command and add the frame bits around it
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(8, 500) == -1) return(-1); //Wait for 8 characters to come back. Return fail if we time out.
  for (int x = 0 ; x < 8 ; x++) comm_input[x] = (byte)myPort.readChar(); //We got a response! Is it what we expected?

  //Check two bytes to see if they are what we expect
  if (comm_input[0] != 0x1B || comm_input[1] != 0x01) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  //println("Board answered to STK v2!");

  //-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
  //Otherwise, yay! We have a valid response!
  //First we have to tell the board to enter CMD_ENTER_PROGMODE_ISP

  int[] stkv2_enter_prog = {
    0x10, 0xC8, 0x64, 0x19, 0x20, 0x00, 0x53, 0x03, 0xAC, 0x53, 0x01, 0x00
  };  
  comm_output = stk500_v2_form_frame(stkv2_enter_prog, 12); //Take this command and add the frame bits around it
  myPort.write(comm_output); //Send the frame
  myPort.clear();
  if (waitForResponse(8, 500) == -1) return(-1); //Wait for 8 characters to come back. Return fail if we time out.

  //We got a response! Is it what we expected?
  for (int x = 0 ; x < 8 ; x++)
    comm_input[x] = (byte)myPort.readChar();

  //Check two bytes to see if they are what we expect
  //byte[5] = 0x10 and byte[6] = 0x00 means the board responded OK!
  if (comm_input[5] != 0x10 || comm_input[6] != 0x00) {
    //Invalid response! Eject! Eject!
    myPort.stop(); //Clean up
    return(-1); //Fail
  }

  return(0); //Yay! Success
}


//This function takes a command string, adds the precursory 0x1B, frame #, frame size, 0x0E delimiter, and ending CRC byte
public byte[] stk500_v2_form_frame(int[] command_string, int length_of_command) {

  byte[] final_string = new byte[length_of_command + 6]; //There is 6 frame bytes (5 in the header, 1 CRC)

  final_string[0] = 0x1B; //Every frame begins with 0x1B

    final_string[1] = (byte)frameNumber++; //This is the frame number. Rolls over at 255

  final_string[2] = (byte)(length_of_command / 256);
  final_string[3] = (byte)(length_of_command % 256);

  final_string[4] = 0x0E; //This is to indicate the beginning of actual data

  for (int x = 0 ; x < length_of_command ; x++)
    final_string[5 + x] = (byte)command_string[x]; //Splice in the command_string

  int CRC = 0;
  for (int x = 0 ; x < (5 + length_of_command) ; x++)
    CRC ^= final_string[x]; //Calculate the CRC for this frame. It is the XOR of ALL the bytes in the frame
  final_string[5 + length_of_command] = (byte)CRC; //Attach CRC to the very end of the frame

  //For debug
  /*print("Cmd str: ");
   for(int x = 0 ; x < 5 + length_of_command + 1 ; x++) {
   print((int)final_string[x]);
   print(" ");
   }
   println();*/

  return(final_string);
}

//This function opens up the comm port at a given port speed and looks for the character 'X'
//It assumes you've already loaded the test HEX onto the target board
//It returns 1 if it see's 'X' and -1 if it fails
public int stk500_v2_check_testchar(int portSpeed) {
  //println("Serial test at " + portSpeed);

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

