// Accelerometer library
#require "LIS3DH.class.nut:1.3.0"
// Temperature Humidity sensor library
#require "HTS221.class.nut:1.0.0"
// Air Pressure sensor library
#require "LPS22HB.class.nut:1.0.0"

/***
 * This is the second part of the SmartFridge device code. In this part, we
 * package up our sensors into an ExplorerKit class. A class is used to neatly
 * package together methods and data into a single object. We can create an
 * instance of a class and then call its methods to, in this case, get
 * sensor readings and log them to the server.
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
    /***
     * Constructor
     *      Assumes that all sensors are being used
     ***/
    constructor() {
        _configureSensors();
    }
    
    /***
     * This method will create a local i2c instance in order to configure
     * the sensors.
     * 
     ***/
    function _configureSensors() {
    	local i2c = hardware.i2c89;
    	i2c.configure(CLOCK_SPEED_400_KHZ);
    	
    	_tempHumid = HTS221(i2c);
    	_tempHumid.setMode(HTS221_MODE.CONTINUOUS, 7);
    	
    	_press = LPS22HB(i2c);
    	
    	_accel = LIS3DH(i2c, LIS3DH_ADDR);
    	_accel.init();
    	_accel.setDataRate(100);
    	_accel.enable(true);
    }
    
    /***
     *  This function will communicate with the sensors over
     *  i2c in order to get readings which will be stored in the
     *  reading array (readingAr)
     ***/
    function getReadings() {
    	_readingAr[LIGHT] = hardware.lightlevel();
    	_readingAr[TEMP_HUMID] = _tempHumid.read();
    	_readingAr[ACCELEROMETER] = _magnitudeAcceleration();
    	_readingAr[AIR_PRESSURE] = _press.read();
    }

    /***
     *  This function will calculate the magnitude of the total acceleration
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
    
    /***************************************************************************************
     * enableAccelerometerClickInterrupt
     * Returns: this
     * Parameters:
                cb (optional) : optional interrupt callback function (passed to the wake pin configure)
     **************************************************************************************/
    function enableAccelerometerClickInterrupt(cb = null) {
        // Configure Alert Pin
        alertPin = hardware.pin1;
        if (cb == null) {
            alertPin.configure(DIGITAL_IN_WAKEUP);
        } else {
            alertPin.configure(DIGITAL_IN_WAKEUP, function() {
                if (alertPin.read() == 0) return;
                cb();
            }.bindenv(this));
        }


        // enable and latch interrupt
        accel.configureInterruptLatching(true);
        accel.configureClickInterrupt(true, LIS3DH.SINGLE_CLICK, ACCEL_THRESHOLD, ACCEL_DURATION);

        return this;
    }

    /***************************************************************************************
     * disableInterrupt
     * Returns: this
     * Parameters:
     **************************************************************************************/
    function disableInterrupt() {
        accel.configureClickInterrupt(false);
        return this;
    }

    /***************************************************************************************
     * checkAccelInterrupt, checks and clears the interrupt
     * Returns: boolean, if single click event detected
     * Parameters: none
     **************************************************************************************/
    function checkAccelInterrupt() {
        local event = accel.getInterruptTable();
        return (event.singleClick) ? true : false;
    }
    
    /***
     *  This function will access the curent readings stored in the reading array
     *  and log them to the server. They can be seen in the log at the bottom of the IDE
     * 
     ***/
    function logData() {
    	server.log(format("Current Light: %f", _readingAr[LIGHT]));
    	server.log(format("Current Temp: %f", _readingAr[TEMP_HUMID].temperature));
    	server.log(format("Current Acceleration: %f", _readingAr[ACCELEROMETER]));
    	server.log(format("Current Pressure: %f", _readingAr[AIR_PRESSURE].pressure));
    }
    
}
// create an instance of the ExplorerKit
ek <- ExplorerKit();

// every second, get new readings and log data
while(true) {
    ek.getReadings();
    ek.logData();
    imp.sleep(1);
}