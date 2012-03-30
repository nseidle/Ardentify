/*
 10/4/2011
 Nathan Seidle
 Spark Fun Electronics 2011
 
 These functions that handle when you hit a button.

 */

public void EmergencyStop(int theValue) {
  println("Emergency stop");
  emergency_stop = true;
}

//When you click on the open file button, this runs
public void OpenFile(int theValue) {
  println("Open File!");

  String loadPath = selectInput();  // Opens file chooser
  if (loadPath == null) {
    WeHaveAFile = false;
    println("No file was selected...");
  } 
  else {
    fullFilePath = loadPath;
    println(fullFilePath);

    //We now have the full path to the file, now let's try to strip out just the file name
    
    int findSpot = fullFilePath.lastIndexOf((char)92); //Char 92 is the '\'. Works with Windows
    if(findSpot == -1) findSpot = fullFilePath.lastIndexOf((char)47); //Char 47 is the '/'. Should work with linux/mac
    //println(findSpot);
    fileName = fullFilePath.substring(findSpot + 1);
    println(fileName);

    WeHaveAFile = true;
    
    byte[] tempArray = new byte[100000]; //Assume firmware will not be bigger than 100,000 bytes
    
    fileSize = parse_file(fileName, tempArray); //Push this file's contents into the big HEX binary array
  }
  return;
}

//Push the most recently opened file to a given serial port
public void Download(int theValue) {
  if(portSelected == false){
    fileName = "Please select a port!";
    return;
  }

  if (WeHaveAFile == false){
    fileName = "Please click FILE!";
    return;
  }
  
  //Go!
  stk500_begin_download();
}

//When you hit the button, this runs
public void Identify(int theValue) {

  if(portSelected == false) {
    println("Please select a COM port!");
    board_guess = "Select a COM port";
    return;    
  }
  
  identTime1 = millis();

  println("Identify Board:");

  int response = -1;

  //Is it the STKv2 and the Mega line of boards?
  if (response == -1) response = stk500_v2_board_guessing(115200);
  if (response != -1) {
    println("This is a 115200bps STK v2 bootloader, probably an Arduino Mega or Mega Pro.");
    println("IC is: " + IC_type);

    board_guess = "I dunno";
    if (IC_type == "ATmega2560") board_guess = "Mega 2560";
    if (IC_type == "ATmega2560" && property_FREQ == "8MHz") board_guess = "Mega Pro 2560";
    if (IC_type == "ATmega1280") board_guess = "Mega 1280";

    identTime2 = millis();
    property_ICID = IC_type;
    property_COMM = "115200";
    //property_PS = "Unknown";
    property_TAG = "Unknown";
    //property_FREQ = "Unknown";
    property_ACS = "Unknown";
    property_VOLT = "Unknown";
    property_TUG = "Unknown";
    property_BLT = "STK500v2";
    return; //We're done
  }
  else
    println("This is not a 115200bps STK v2 bootloader");

  //Next we try the Uno/Optiboot/115200bps bootload
  if (response == -1) response = stk500_board_guessing(115200);
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
  if (response == -1) response = stk500_board_guessing(57600);
  if (response != -1) {
    println("This is a 57600bps bootloader found on a Duemilanove, Pro, Fio, or LilyPad.");
    println("IC is: " + IC_type);

    board_guess = "I dunno";
    if (property_FREQ == "16MHz") board_guess = "Duemilanove or Pro 16MHz";
    if (property_FREQ == "8MHz") board_guess = "LilyPad, Fio or Pro 8MHz";

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
  if (response == -1) response = stk500_board_guessing(19200);
  if (response != -1) {
    println("This is a 19200bps bootloader, probably a Diecimila, NG, or older boards.");
    println("IC is: " + IC_type);

    board_guess = "I dunno";
    if (property_FREQ == "16MHz") board_guess = "Diecimila";
    if (property_FREQ == "8MHz") board_guess = "Pre-2010 LilyPad";
    if (IC_type == "ATmega8") board_guess = "NG";

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

  board_guess = property_TAG;

  println("Identify complete");

  identTime2 = millis();
}

//When you hit the button, this runs
public void Restart(int theValue) {
  WeHaveAFile = false;
  fileSize = 0;

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
