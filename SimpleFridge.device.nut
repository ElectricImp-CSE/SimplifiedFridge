#require "MessageManager.lib.nut:2.0.0"
// Accelerometer library
#require "LIS3DH.class.nut:1.3.0"
// Temperature Humidity sensor library
#require "HTS221.class.nut:1.0.0"
// Air Pressure sensor library
#require "LPS22HB.class.nut:1.0.0"

/***
 * This is the third part of the SmartFridge code. In this part, in the device code we 
 * format the data that we collected with the ExplorerKit class in order
 * to send it to the agent. The agent code is also provided in order to handle
 * the data and provide it to Watson
 ***/
class ExplorerKit {
    static LIS3DH_ADDR = 0x32;
    
    // Accel i2c Address
    static LIS3DH_ADDR = 0x32;
    
    // Sensor Indices
    static TEMP_HUMID = 0x00;
    static AIR_PRESSURE = 0x01;
    static ACCELEROMETER = 0x02;
    static LIGHT = 0x03;
    
    // Array to hold the readings. Indexed by the constants above
    _readingAr = array(4);
    
    // Sensor objects
    _tempHumid = null;
    _press = null;
    _accel = null;
    
    _readPressure = false;
    
    /***
     * Constructor
     *      Takes an optional parameter that allows the pressure sensor
     *      to be configured and used
     ***/
     
    constructor(readPressure=false) {
        this._readPressure = readPressure;
        _configureSensors();
    }
    
    /***
     * This method will use a local i2c instance in order to configure
     * the sensors.
     * 
     ***/
    function _configureSensors() {
    	local i2c = hardware.i2c89;
    	i2c.configure(CLOCK_SPEED_400_KHZ);
    	
    	_tempHumid = HTS221(i2c);
    	_tempHumid.setMode(HTS221_MODE.CONTINUOUS, 7);
    	
    	if(_readPressure) {
    	   _press = LPS22HB(i2c); 
    	}
    	
    	_accel = LIS3DH(i2c, LIS3DH_ADDR);
    	_accel.init();
    	_accel.setDataRate(100);
    	_accel.enable(true);
    }
    
    /***
     *  This method will communicate with the sensors over
     *  i2c in order to get readings which will be stored in the
     *  reading array (readingAr)
     ***/
    function getReadings() {
    	_readingAr[LIGHT] = hardware.lightlevel();
    	_readingAr[TEMP_HUMID] = _tempHumid.read();
    	_readingAr[ACCELEROMETER] = _magnitudeAcceleration();
    	if(_readPressure) {
    	    _readingAr[AIR_PRESSURE] = _press.read();
    	}
    }

    /***
     *  This method will calculate the magnitude of the total acceleration
     *  experienced by the LIS3DH sensors. It uses the formula that a
     *  vector's magnitude is the square root of the sum of the squares of its components
     * 
     ***/
    function _magnitudeAcceleration() {
    	local data = _accel.getAccel();
    	local tot = 0;
    	foreach(axis in data) {
    		tot += math.pow(axis, 2);
    	}
    	tot = math.pow(tot, 0.5);
    	return tot;
    }
    
    /***
     *  This method will access the curent readings stored in the reading array
     *  and log them to the server. They can be seen in the log at the bottom of the IDE
     * 
     ***/
    function logData() {
    	server.log(format("Current Light: %f", _readingAr[LIGHT]));
    	server.log(format("Current Temp: %f", _readingAr[TEMP_HUMID].temperature));
    	server.log(format("Current Acceleration: %f", _readingAr[ACCELEROMETER]));
    	if(_readPressure) {
    	    server.log(format("Current Pressure: %f", _readingAr[AIR_PRESSURE].pressure));
    	}
    }
    
    // This method returns the amount of light seen by the board
    function getLight() {
        return _readingAr[LIGHT];
    }
    
    // This method returns the temperature in degrees celsius
    function getTemp() {
        return _readingAr[TEMP_HUMID].temperature;
    }
    
    // This method returns the magnitude of the total acceleration experienced
    // by the acceleration sensor
    function getAcceleration() {
        return _readingAr[ACCELEROMETER];
    }
    
    // This method returns the relative humidity
    function getHumidity() {
        return _readingAr[TEMP_HUMID].humidity;
    }
    
}

/***
 * This class manages the data from the sensors, acquiring it from the 
 * ExplorerKit class and then converting it into the format required
 * to be transmitted to the agent. This class transmits using an instance of
 * the bullwinkle class
 ***/
class Data {
    
    static LIGHT_THRESHOLD = 20000;
    
    // Door status strings
    static DOOR_OPEN = "open";
    static DOOR_CLOSED = "closed";
    
    // 
    _ek = null;
    _bull = null;
    _data = {};
    
    /***
     * Constructor
     *      This constructor creates instances of the ExplorerKit class and
     *      the MessageManager class
     ***/
    constructor() {
        _ek = ExplorerKit();
        _bull = MessageManager();
        _storeInNV();
    }
    
    /***
     * This method creates a table containing information about the status of
     * the door. It is returned to be used as an entry into the _data table
     * which is sent to the agent
     ***/
    function _doorStatus() {
        local doorStatus = ( LIGHT_THRESHOLD < _ek.getLight() ) ?  DOOR_OPEN : DOOR_CLOSED;
        local doorTable = {};
        doorTable.currentStatus <- doorStatus;
        doorTable.openAlertSent <- !(nv.lastDoor == DOOR_CLOSED && doorStatus == DOOR_OPEN);
        nv.doorAlertSent = doorTable.openAlertSent;
        nv.lastDoor = doorStatus;
        doorTable.ts <- time();
        return doorTable;
    }
    
    /***
     * This method constructs clears and then fills the _data table to be
     * sent to the agent
     * 
     ***/
    function constructData() {
        _data.clear();
        _ek.getReadings();
        _data.doorStatus <- _doorStatus();
        _data.readings <- _constructReadings();
        //_data.events <- _constructEvents();
        // Because this simpler code was adapted from other code, we still
        // need _data to have an 'events' key for the device code to remain
        // compatible with the agent code
        _data.events <- "";
    }
    
    /***
     * This method sends data to the agent using an instance of the Bullwinkle
     * class
     ***/
    function sendData() {
        _bull.send("update", _data);
    }
    
    /***
     *  This method creates an array which contains a table holding sensor data
     * 
     ***/
    function _constructReadings() {
        local ar = [];
        local data = {"ts" : time()};
        data["lxlevel"] <- _ek.getLight();
        data["temperature"] <- _ek.getTemp();
        data["humidity"] <- _ek.getHumidity();
        ar.push(data);
        return ar;
    }
    
    function _constructEvents() {
        local ar = [];
        local events = { "type" : "test",
        "ts" : time(),
        "description": "something above threshold",
        "latestReading": "500" };
        ar.push(events);
        return ar;
    }
    
    function _storeInNV() {
        local root = getroottable();
        if(!("nv" in root)) {
            root.nv <- { "doorAlertSent" : false,
                        "lastDoor" : "closed"
            };
        }
    }
}

// Create a data instance
d <- Data();
while(true) {
    // Loop that constructs the data, sends it, then sleeps for 5 seconds before
    // repeating
    d.constructData();
    d.sendData();
    imp.sleep(5);
}