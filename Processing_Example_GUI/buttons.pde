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

//When you hit the button, this runs
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
  screamer_begin_download();
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

  //First we try the Uno/Optiboot/115200bps bootload
  int response = 0;
  response = stk500_board_guessing(115200);
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
  if (response == -1) response = stk500_board_guessing(19200);
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
  property_ICID = screamer_query_target(ICRQ);
  println("IC code: " + property_ICID);

  property_FREQ = screamer_query_target(FRQ);
  println("Board frequency code: " + property_FREQ);

  property_ACS = screamer_query_target(ACSRQ);
  println("Available code space: " + property_ACS);

  property_PS = screamer_query_target(PSRQ);
  println("Page size: " + property_PS);
  property_PS_int = Integer.parseInt(property_PS); //Convert this property to a usable int

  //The following are optional items
  //Good for the user to know but not necessarily needed for compiling code

  property_VOLT = screamer_query_target(VRQ);
  println("Board voltage: " + property_VOLT);

  property_TAG = screamer_query_target(TRQ);
  println("Board Tag: " + property_TAG);

  property_TUG = screamer_query_target(TUGRQ);
  println("Time until giveup: " + property_TUG);

  property_BLT = "Screamer";

  //Once we're done identifying things, tell the target to resume normal operation
  myPort.write(Integer.toString(SSRQ) + ","); //Start sketch
  myPort.stop(); //Clean up

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
