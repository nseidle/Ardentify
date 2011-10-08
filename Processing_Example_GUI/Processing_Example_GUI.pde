/*
 9-21-2011
 Nathan Seidle
 Spark Fun Electronics 2011
 
 This is an example GUI written in processing to auto-detect what type of Arduino you have attached. Start the 
 program, select a valid com port and press 'Identify'. You should then see what board is attached to your computer.
 
 The goal is to eventually get this autodetect method implemented into the Arduino IDE so that beginners don't have to worry 
 about what board to select from some list. They should just hit the 'Play' button and the system should take care of the 
 rest (identify board IC, identify board freq, then compile code using these bits of information, then load code onto 
 target board).
 
 You may need to download Control5P:
 http://www.sojamo.de/libraries/controlP5/
 And then install this library by sticking it to the correct processing library directory. This can be tricky. For Windows 7, it's:
 C:\Users\NetBook2\Documents\Processing\libraries\controlP5\(all the files in the zip folder)

 How it works:
 The app will first try to use the stk500 bootloader at various speeds to get a valid response. If an STK500
 response is found, then we bootload a very small test firmware onto the target. This test firmware sends
 the letter 'X' at 19200bps. The processing app then tries to find the X at various baud rates. Depending 
 on what is found we can establish what frequency is being used on the board.
 
 There is also a new bootloader created called Screamer. This new bootloader is much faster and more light weight
 on the serial port than STK500 or Optiboot. It allows for more board identification and board information (such as
 board voltage, board name (string), available code space, etc).
 
 */

import java.io.*;

//These are all for the serial port testing
import gnu.io.SerialPort;
import gnu.io.CommPortIdentifier;
import gnu.io.NoSuchPortException;
import gnu.io.PortInUseException;
import gnu.io.UnsupportedCommOperationException;

//import javax.swing.JFileChooser; //For file open goodness

int serialPortNumber = 0;
boolean portSelected = false;

import controlP5.*;
ControlP5 controlP5;
Button button1, button2, button3, button4, button5;
DropdownList COMList;

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

//byte[] compressedHEX; //This is the large array that contains all the program binary data

int myColor_black = color(0, 0, 0);
PFont myFont;

long loadTime1, loadTime2; //Timers for bootload timing
long identTime1, identTime2; //Timers for identification timing

boolean WeHaveAFile; //This helps us prevent bootloading without a firmware file selected
String fileName;
int fileSize;
String fullFilePath;

void setup() {
  size(600, 340);
  smooth();
  frameRate(30);

  myFont = createFont("Arial", 16, true);

  controlP5 = new ControlP5(this);

  button1 = controlP5.addButton("Identify", 255, 30, 50, 80, 19);
  button2 = controlP5.addButton("EmergencyStop", 128, 30, 70, 80, 19);
  button2.captionLabel().set("Emergency Stop");
  //controlP5.addButton("Restart", 128, 30, 90, 80, 19);

  COMList = controlP5.addDropdownList("myList-COMs", 30, 111, 80, 100);
  COMList.setBackgroundColor(color(190));
  COMList.setItemHeight(20);
  COMList.setBarHeight(20);
  COMList.captionLabel().set("Com Port");
  COMList.captionLabel().style().marginTop = 5;
  COMList.captionLabel().style().marginLeft = 3;
  COMList.valueLabel().style().marginTop = 3;
  COMList.setColorActive(color(255, 128));

  //Identify the available COM ports
  Enumeration ports = CommPortIdentifier.getPortIdentifiers();
  int x = 0;
  while (ports.hasMoreElements ()) {
    CommPortIdentifier cpi = (CommPortIdentifier) ports.nextElement();
    COMList.addItem(cpi.getName(), x++);
  }
  if (x == 1) { //We only have one com port! Let's assume it's the one we need.
    serialPortNumber = 0;
    portSelected = true;
  }

  button3 = controlP5.addButton("OpenFile", 0, 30, 230, 80, 19);
  button3.captionLabel().set("Open File");
  button4 = controlP5.addButton("Download", 255, 30, 250, 80, 19);

  //compressedHEX = new byte[65000]; //Allocates memory for 65000 integers
  //Instead of pre-assigning this, we should be allocating this array based on the firmware file we open

  textFont(myFont);

  loadTime1 = 0;
  loadTime2 = 0;
  identTime1 = 0;
  identTime2 = 0;

  WeHaveAFile = false;
  fileName = "Click FILE";

  board_guess = "Select a port";
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

  text("File size: " + fileSize + "(bytes)", width/2, 220);

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

public void controlEvent(ControlEvent theEvent) {
  //println(theEvent.controller().name());

  // PulldownMenu is if type ControlGroup.
  // A controlEvent will be triggered from within the ControlGroup.
  // therefore you need to check the originator of the Event with
  // if (theEvent.isGroup())
  // to avoid an error message from controlP5.

  if (theEvent.isGroup()) {
    // check if the Event was triggered from a ControlGroup
    if (theEvent.name() == "myList-COMs") {
      serialPortNumber = int(theEvent.group().value()); //The user has selected a com port!
      println("Port Number: " + serialPortNumber);
      portSelected = true;
    }
    //println(theEvent.group().value() + " from " + theEvent.group());
  } 
  else if (theEvent.isController()) {
    //println(theEvent.controller().value() + " from " + theEvent.controller());
    println(theEvent.controller().name());
  }
}

public void serialTesting() throws NoSuchPortException, PortInUseException, UnsupportedCommOperationException, IOException, TooManyListenersException {

  //  String portName = Serial.list()[0];
  String portName = Serial.list()[serialPortNumber];

  final SerialPort serialPort;
  CommPortIdentifier portId = CommPortIdentifier.getPortIdentifier(portName);
  serialPort = (SerialPort) portId.open(this.getClass().getName(), 2000);
}

