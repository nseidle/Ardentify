/*
  9-21-2011
 Nathan Seidle
 
 */
import java.io.*;

//These are all for the serial port testing
import gnu.io.SerialPort;
import gnu.io.CommPortIdentifier;
import gnu.io.NoSuchPortException;
import gnu.io.PortInUseException;
import gnu.io.UnsupportedCommOperationException;

import javax.swing.JFileChooser; //For file open goodness

int serialPortNumber = 1;

import controlP5.*;
ControlP5 controlP5;

import processing.serial.*;
Serial myPort;  // Create object from Serial class

boolean emergency_stop = false;

//These are the various things that the host or target can request of each other
static int SSVQ = 10; //Serial speed verification request
static int ICRQ = 11; //IC request
static int FRQ = 12; //Frequency request
static int ACSRQ  = 13; //Available code space request
static int PSRQ = 14; //Page size space request
static int VRQ = 15; //Voltage request (optional)
static int TRQ = 16; //Tag request (optional)
static int TUGRQ = 17; //Time until giveup request (optional)
static int BLRQ = 18; //Boot load request
static int SSRQ = 19; //Start sketch request

//Global variables are used for the various properties we find out
String property_COMM;
String property_ICID; 
String property_FREQ;
String property_ACS; 
String property_PS; 
int property_PS_int;
String property_VOLT; 
String property_TAG; 
String property_TUG; 
String property_BLT; //Boot loader type
String board_guess;

String IC_type; //Used during board identification. Contains a string like "ATmega328"

byte[] compressedHEX; //This is the large array that contains all the program binary data
int lastMemoryAddress; //The last known byte location from the HEX file

int myColor_black = color(0, 0, 0);
PFont myFont;

long loadTime1, loadTime2; //Timers for bootload timing
long identTime1, identTime2; //Timers for identification timing

boolean WeHaveAFile; //This helps us prevent bootloading without a firmware file selected
String fileName;
String fullFilePath;

void setup() {
  size(600, 340);
  smooth();
  frameRate(30);

  myFont = createFont("Arial", 16, true);

  controlP5 = new ControlP5(this);
  controlP5.addButton("Identify", 255, 30, 50, 80, 19);
  controlP5.addButton("Stop", 128, 30, 70, 80, 19);
  controlP5.addButton("Restart", 128, 30, 90, 80, 19);

  controlP5.addButton("File", 0, 30, 230, 80, 19);
  controlP5.addButton("Download", 255, 30, 250, 80, 19);

  compressedHEX = new byte[65000]; //Allocates memory for 65000 integers
  //Instead of pre-assigning this, we should be allocating this array based on the firmware file we open

  lastMemoryAddress = 0;

  textFont(myFont);

  loadTime1 = 0;
  loadTime2 = 0;
  identTime1 = 0;
  identTime2 = 0;

  WeHaveAFile = false;
  //WeHaveAFile = true; //For demoing
  fileName = "Click FILE";

  board_guess = "Hit identify";
}

void draw() {
  background(myColor_black);

  fill(255);
  textAlign(CENTER);

  text("My board guess: " + board_guess, width/2, 40);

  //Display board type
  text("IC Code: " + property_ICID, width/2, 60);

  //Display board crystal
  text("Crystal Freq: " + property_FREQ, width/2, 80);

  //Display communication speed
  text("Bootloader Communication speed(bps): " + property_COMM, width/2, 100);

  text("Boot loader type: " + property_BLT, width/2, 120);

  //Display page size
  text("Chip page size: " + property_PS, width/2, 140);

  //Display identification time
  long identTime = identTime2 - identTime1;
  text("Identification time: " + identTime/1000 + "." + identTime%1000, width/2, 160);

  text("Firmware file: " + fileName, width/2, 200);

  text("File size: " + lastMemoryAddress + "(bytes)", width/2, 220);

  //Display load time
  long totalTime = loadTime2 - loadTime1;
  text("Total load time: " + totalTime/1000 + "." + totalTime%1000, width/2, 240);


  //Display board name
  text("Board tag: " + property_TAG, width/2, 260);

  //Display code space
  text("Available code space: " + property_ACS, width/2, 280);

  //Display board voltage
  text("Board voltage: " + property_VOLT, width/2, 300);

  //Display TUG
  text("Time until giveup: " + property_TUG, width/2, 320);
}

//Parses the HEX file into snippets the size of the IC's allowed page size
public void parse_file(int property_pageSize, String fileName) {

  //Read in the HEX file

    String[] lines = loadStrings(fileName);

  //This may be a weird windows thing, but the fing backslashes (\) throw errors
  //String[] lines = loadStrings("C:/Users\Main\Documents\My Dropbox\Code\BigHEX\BigHEX-30414.hex");

  //String[] lines = loadStrings("blink.hex");
  //String[] lines = loadStrings("BigHEX-30414.hex");
  //String[] lines = loadStrings("BlinkDifferently.hex");

  //Remove empty lines + lines not starting with a ":"

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
      compressedHEX[memoryAddress + x] = (byte)Integer.parseInt(tempText.substring(0, 2), 16);
      //print(compressedHEX[memoryAddress + x] + " ");
      tempText = tempText.substring(2, tempText.length()); //These two bytes are now processed, so remove them
    }
  }

  //println("Last memory address: " + lastMemoryAddress);

  //The binary form of the HEX file is now in the compressed HEX array
  println("HEX file parsed");
}

public int screamer_bootload() {

  //Start at beginning of large intel array
  int currentMemoryAddress = 0;

  while (true) {

    //Wait for IC to tell us he's ready
    while (myPort.available () < 1) {
      //See if user has aborted - most likely freeze error
      if (emergency_stop == true) {
        println("Error: The target IC did not finish loading. You will likely experience unexpected program execution.");
        myPort.stop();
        return(-1);
      }
    } 

    int incomingChar = myPort.readChar();

    if (incomingChar == 'T') { //All is well
    }
    else if (incomingChar == 'X') { //Resend last line
      currentMemoryAddress -= property_PS_int; //Move the marker back one (page size)
    }
    else {
      println("Error: Incorrect response from target IC. Programming is incomplete and will now halt.");
      myPort.stop();
      return(-1);
    }

    //Here's our escape!
    if (currentMemoryAddress >= lastMemoryAddress) {
      //Tell the target IC we are done transmitting data, go start your program
      myPort.write(":S");
      break;
    }

    //=============================================
    //Convert 16-bit current_memory_address into two 8-bit characters
    int MemoryAddressHigh = currentMemoryAddress / 256;
    int MemoryAddressLow = currentMemoryAddress % 256;

    //println("Address: " + currentMemoryAddress + ", " + MemoryAddressHigh + ", " + MemoryAddressLow);

    int block_length = property_PS_int; //Set block length to page size
    if (currentMemoryAddress + block_length > lastMemoryAddress) //Check to see if we're towards the end of the array
      block_length = lastMemoryAddress - currentMemoryAddress;

    //println("Block length: " + block_length);
    //=============================================
    //Calculate current check_sum
    int CheckSum = 0;
    CheckSum += block_length;
    CheckSum += MemoryAddressHigh;
    CheckSum += MemoryAddressLow;

    for (int j = 0 ; j < block_length ; j++)
      CheckSum += compressedHEX[currentMemoryAddress + j]; //We should be calculating this during preprocessing to save time

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

    for (int i = 0 ; i < block_length ; i++)
      dataBytes[i + 5] = (byte)compressedHEX[currentMemoryAddress + i];

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

//This function assumes the correct port is already open at the correct speed
//This function assumes the intel hex array has already been loaded by the parse function
//Assumes you have correctly loaded global variable property_PS_int.
//This fuction will send the correct commands to a target to load the firmware in the hex array
//It will bail with a -1 if anything goes wrong
public int stk500_bootload() {

  //Start at beginning of large intel array
  int currentMemoryAddress = 0;

  while (true) {

    //Here's our escape!
    if (currentMemoryAddress >= lastMemoryAddress) {
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

    //Wait for target to verify with 0x14 0x10
    while (myPort.available () < 2) {
      //See if user has aborted - most likely freeze error
      if (emergency_stop == true) {
        println("Error: The target IC did not finish loading. You will likely experience unexpected program execution.");
        myPort.stop(); //Clean up
        return(-1); //Bail!
      }
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
    int block_length = property_PS_int; //Set block length to page size
    if (currentMemoryAddress + block_length > lastMemoryAddress) //Check to see if we're towards the end of the array
      block_length = lastMemoryAddress - currentMemoryAddress;


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
      dataBytes[i + 4] = (byte)compressedHEX[currentMemoryAddress + i];

    //Send the record length
    dataBytes[block_length + 4] = (byte)0x20; //STK's termination character.

    //Push this block of control and data out to the serial port
    myPort.write(dataBytes);


    //Wait for IC to tell us he's ready
    //Wait for target to verify with 0x14 0x10
    while (myPort.available () < 2) {
      //See if user has aborted - most likely freeze error
      if (emergency_stop == true) {
        println("Error: The target IC did not finish loading. You will likely experience unexpected program execution.");
        myPort.stop(); //Clean up
        return(-1); //Bail!
      }
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

public void controlEvent(ControlEvent theEvent) {
  println(theEvent.controller().name());
}

public void serialTesting() throws NoSuchPortException, PortInUseException, UnsupportedCommOperationException, IOException, TooManyListenersException {

  //  String portName = Serial.list()[0];
  String portName = Serial.list()[serialPortNumber];

  final SerialPort serialPort;
  CommPortIdentifier portId = CommPortIdentifier.getPortIdentifier(portName);
  serialPort = (SerialPort) portId.open(this.getClass().getName(), 2000);
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

  int tries = 0;
  int tries_before_giveup = 100;
  while (myPort.available () < 1) {
    tries++;
    delay(1);
    if (tries > tries_before_giveup) {
      myPort.stop();
      return(-1);
    }

    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return(-1);
    }
  } 
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
  property_PS = query_target(PSRQ);
  println("Page size: " + property_PS);
  property_PS_int = Integer.parseInt(property_PS); //Convert this property to a usable int

  println("Parsing file");
  parse_file(property_PS_int, fullFilePath);

  myPort.write(BLRQ + ","); //Send the target the boot load request
  screamer_bootload();

  loadTime2 = millis(); //We use load time variable as a timer. Start the timer.
}

public void Stop(int theValue) {
  println("Emergency stop");
  emergency_stop = true;
}

public void File(int theValue) {
  println("Open File!");

  String loadPath = selectInput();  // Opens file chooser
  if (loadPath == null) {
    WeHaveAFile = false;
    println("No file was selected...");
  } 
  else {
    // If a file was selected, print path to file
    fullFilePath = loadPath;
    println(fullFilePath);
    int findSpot = fullFilePath.lastIndexOf((char)92); //Char 92 is the '\'. Works with Windows
    if(findSpot == -1) findSpot = fullFilePath.lastIndexOf((char)47); //Char 47 is the '/'. Should work with linux/mac
    //println(findSpot);
    fileName = fullFilePath.substring(findSpot + 1);
    println(fileName);
    WeHaveAFile = true;
  }
  return;
}

//When you hit the button, this runs
public void Download(int theValue) {
  if (WeHaveAFile == true) 
    screamer_begin_download();
  else
    fileName = "Please click FILE!";
}

//This function talks to bootloaders based on the STK protocol
//It will try to communicate at portSpeed. It will give up after 500ms.
public int stk_board_guessing(int portSpeed) {
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

  int tries = 0;
  int tries_before_giveup = 500;
  while (myPort.available () < 2) {
    tries++;
    delay(1);
    if (tries > tries_before_giveup) {
      myPort.stop();
      return(-1);
    }
    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return(-1);
    }
  }

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

    tries = 0;
  tries_before_giveup = 500;
  while (myPort.available () < 5) {
    tries++;
    delay(1);
    if (tries > tries_before_giveup) {
      myPort.stop(); //Clean up
      return(-1); //Bail out. The target didn't respond to our sign request
    }
    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return(-1);
    }
  }

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

  //We now have the IC type, but can we get the frequency identified?
  println("Begin frequency testing.");

  //Parse frequency file
  if (IC_type == "ATmega328")
    parse_file(property_PS_int, "Frequency_Test-ATmega328.hex");
  else if (IC_type == "ATmega168")
    parse_file(property_PS_int, "Frequency_Test-ATmega168.hex");
  else {
    println("No test HEX available to identify the freq of this IC");
    property_FREQ = "Unknown";
    return(0); //Maybe success?
  }

  //Now push this hex file to the target
  int response = stk500_bootload();
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
    return(0); //Success!
  }

  response = stk500_check_testchar(9600); //See if we can see the 'X' at 8MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 8MHz");
    property_FREQ = "8MHz";
    return(0); //Success!
  }

  response = stk500_check_testchar(2400); //See if we can see the 'X' at 1MHz
  if (response == 1) {
    myPort.stop(); //Clean up
    println("Frequency confirmed at 1MHz");
    property_FREQ = "1MHz";
    return(0); //Success!
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
  int tries = 0;
  int tries_before_giveup = 1500; //Duemilanove and Diecimila can take up to 1.5 seconds
  while (myPort.available () < 1) {
    tries++;
    delay(1);
    if (tries > tries_before_giveup) {
      myPort.stop(); //Clean up
      return(-1); //Bail out. The target didn't respond to our sign request
    }
    //Here we have an emergency break
    if (emergency_stop == true) {
      println("Error: User break");
      myPort.stop();
      return(-1);
    }
  }

  int testChar = myPort.read();
  myPort.stop(); //Clean up

    if (testChar == 'X') //We are golden! We see the X.
    return(1); //Yay!
  else
    return(-1); //Boo.
}

//When you hit the button, this runs
public void Identify(int theValue) {
  identTime1 = millis();

  println("Identify Board:");

  //First we try the Uno/Optiboot/115200bps bootload
  int response = 0;
  response = stk_board_guessing(115200);
  if (response != -1) {
    println("This is a 115200bps bootloader, probably Optiboot");
    println("IC is: " + IC_type);

    board_guess = "I dunno";
    if (property_FREQ == "16MHz") board_guess = "Uno";

    identTime2 = millis();
    property_ICID = IC_type;
    property_COMM = "115200";
    //property_PS = "Unknown";
    property_TAG = "Unknown";
    //property_FREQ = "Unknown";
    property_ACS = "Unknown";
    property_VOLT = "Unknown";
    property_TUG = "Unknown";
    property_BLT = "STK500";
    return; //We're done
  }
  else
    println("This is not a 115200bps bootloader");

  //Next, let's try the older Duemilanove/57600 type boards
  if (response == -1) response = stk_board_guessing(57600);
  if (response != -1) {
    println("This is a 57600bps bootloader found on a Duemilanove, Pro, or LilyPad.");
    println("IC is: " + IC_type);

    board_guess = "I dunno";
    if (property_FREQ == "16MHz") board_guess = "Duemilanove or Pro 16MHz";
    if (property_FREQ == "8MHz") board_guess = "LilyPad or Pro 8MHz";

    identTime2 = millis();
    property_ICID = IC_type;
    property_COMM = "57600";
    //property_PS = "Unknown";
    property_TAG = "Unknown";
    //property_FREQ = "Unknown";
    property_ACS = "Unknown";
    property_VOLT = "Unknown";
    property_TUG = "Unknown";
    property_BLT = "STK500";
    return; //We're done
  }
  else
    println("This is not a 57600bps bootloader");

  //Next, let's try the really old boards
  if (response == -1) response = stk_board_guessing(19200);
  if (response != -1) {
    println("This is a 19200bps bootloader, probably a Diecimila or older boards.");
    println("IC is: " + IC_type);

    board_guess = "I dunno";
    if (property_FREQ == "16MHz") board_guess = "Diecimila";
    if (property_FREQ == "8MHz") board_guess = "Pre-2010 LilyPad";

    identTime2 = millis();
    property_ICID = IC_type;
    property_COMM = "19200";
    //property_PS = "Unknown";
    property_TAG = "Unknown";
    //property_FREQ = "Unknown";
    property_ACS = "Unknown";
    property_VOLT = "Unknown";
    property_TUG = "Unknown";
    property_BLT = "STK500";
    return; //We're done
  }
  else
    println("This is not a 19200bps bootloader");

  //If none of the above work, then try the new auto-detect bootloader
  //Reset the target IC and go through enumeration steps
  response = screamer_secret_handshake();
  if (response == -1) {
    println("This is not a Screamer bootloader.");
    println("Identify failed. Are you sure you've got the right COM port selected?");

    identTime2 = millis();
    board_guess = "No board. Wrong COM port?";
    property_ICID = "Unknown";
    property_COMM = "Unknown";
    property_PS = "Unknown";
    property_TAG = "Unknown";
    property_FREQ = "Unknown";
    property_ACS = "Unknown";
    property_VOLT = "Unknown";
    property_TUG = "Unknown";
    property_BLT = "Unknown";
    return; //We're done
  }  
  //We need a fail state here

  //Now let's start pinging the target for all its info

  //Send the target the (IC request) then wait for the target to respond with the IC type ID
  property_ICID = query_target(ICRQ);
  println("IC code: " + property_ICID);

  property_FREQ = query_target(FRQ);
  println("Board frequency code: " + property_FREQ);

  property_ACS = query_target(ACSRQ);
  println("Available code space: " + property_ACS);

  property_PS = query_target(PSRQ);
  println("Page size: " + property_PS);
  property_PS_int = Integer.parseInt(property_PS); //Convert this property to a usable int

  //The following are optional items
  //Good for the user to know but not necessarily needed for compiling code

  property_VOLT = query_target(VRQ);
  println("Board voltage: " + property_VOLT);

  property_TAG = query_target(TRQ);
  println("Board Tag: " + property_TAG);

  property_TUG = query_target(TUGRQ);
  println("Time until giveup: " + property_TUG);

  property_BLT = "Screamer";

  //Once we're done identifying things, tell the target to resume normal operation
  myPort.write(Integer.toString(SSRQ) + ","); //Start sketch
  myPort.stop(); //Clean up

    board_guess = property_TAG;

  println("Identify complete");

  identTime2 = millis();
}

//This function takes in a command (no comma needed) and returns what the target responded with
//Returns -1 if the user hits the break button
public String query_target(int cmdQuery) {
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
//When you hit the button, this runs
public void Restart(int theValue) {
  //WeHaveAFile = false;
  lastMemoryAddress = 0;

  loadTime2 = 0;
  loadTime1 = 0;

  property_BLT = "";
  property_COMM = "";
  property_PS = "";
  identTime2 = 0;
  identTime1 = 0;
  property_TAG = "";
  property_ICID = "";
  property_FREQ = "";
  property_ACS = "";
  property_VOLT = "";
  property_TUG = "";
}

