using Toybox.WatchUi;
using Toybox.BluetoothLowEnergy;
using Toybox.System;

//UUID of the tenergy "generic" service we communicate with
const TENERGY_SERVICE = BluetoothLowEnergy.stringToUuid("0000FFF0-0000-1000-8000-00805F9B34FB");

const TENERGY_TEMP_CHARACTERISTIC = BluetoothLowEnergy.stringToUuid("0000FFF4-0000-1000-8000-00805F9B34FB");
const TENERGY_PAIRING_CHARACTERISTIC = BluetoothLowEnergy.stringToUuid("0000FFF2-0000-1000-8000-00805F9B34FB");
const TENERGY_COMMAND_CHARACTERISTIC = BluetoothLowEnergy.stringToUuid("0000FFF5-0000-1000-8000-00805F9B34FB");

//UUID of the descriptor on the TEMP_CHARACTERISTIC so we can twiddle the notify flag to "on" so it continuously publishes temperatures to us
const TENERGY_TEMP_NOTIFY_DESCRIPTOR = BluetoothLowEnergy.stringToUuid("00002902-0000-1000-8000-00805F9B34FB");

//the default auto-pairing key as cribbed from cloudbbq / verified with wireshark & the nordic DK with sniffer
const TENERGY_AUTO_PAIR_KEY = [33,7,6,5,4,3,2,1,-72,34,0,0,0,0,0]b;

class BLETestDelegate extends WatchUi.BehaviorDelegate {

	private var _foundDevice = false;
	
    function initialize() {
        BehaviorDelegate.initialize();
        BluetoothLowEnergy.setDelegate(new BluetoothDelegate(self));
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function onMenu() {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new BLETestMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
    
    function tempChanged(output) {
    	//System.println(output);
    	BLETestView.output = output;
    	WatchUi.requestUpdate();
    }

}

class BluetoothDelegate extends BluetoothLowEnergy.BleDelegate {

	hidden var _device = null;
	hidden var _service = null;
	hidden var _foundService = null;
	hidden var _char;
	hidden var _state = PAIRING;
	hidden var _tempChanged = null;
	
	//we start in the pairing state, and write the auto-pair key to the pairing characteristic
	//once that's done, we transition to the INIT state and tell the temp characteristic to enable notification
	//then finally it transitions to the READ state and we tell the command characteristic to start sending auto-updates
	//after that, onCharacteristicChanged starts recieving updates from the device
	enum {
		PAIRING,
		INIT,
		READ
	}
	
	function initialize(interface) {
		BleDelegate.initialize();
		
		_tempChanged = interface.method(:tempChanged);
		
		//bluetooth API on garmin REQUIRES us to register which services, characteristics, and descriptors we will be using
		//otherwise they will not be available to use when we call getService()/getCharacteristic()/getDescriptor()
		//basically we have to register up-front what we intend to use
		
		//so in this case we will use the FFF0 service, and on that service we're interested in the characteristics exposed for TEMP/COMMAND/PAIRING
		//for each of these characteristics we will want access to the characteristic control descriptor (cccdUuid)
		 var profile = {                                                  // Set the Profile
           :uuid => TENERGY_SERVICE,
           :characteristics => [ 
				{
                   :uuid => TENERGY_TEMP_CHARACTERISTIC,     // UUID of the characteristic that provides temperatures
                   :descriptors => [ BluetoothLowEnergy.cccdUuid()] 
                },
				{
                   :uuid => TENERGY_COMMAND_CHARACTERISTIC,     // UUID of the characteristic that acts as the "control" or "command" channel
                   :descriptors => [ BluetoothLowEnergy.cccdUuid()] 
                },
				{
                   :uuid => TENERGY_PAIRING_CHARACTERISTIC,     // UUID of the pairing characteristic - required so we can write the pairing key to it
                   :descriptors => [ BluetoothLowEnergy.cccdUuid()] 
                },
           ]
       };

       // Make the registerProfile call
       BluetoothLowEnergy.registerProfile( profile );
	}
	
	
	//convert C to F - device sends degrees as C over bluetooth, regardless of the display setting on the device
	function degCtoF(degC) {
		return (degC * 1.8) + 32; 	
	}
	
	//handles incoming data from characteristics on the tenergy service via the NOTIFY bluetooth option
	function onCharacteristicChanged(characteristic, value) {
		System.println(Lang.format("char changed $1$", [value]));
		
		var output = "";
		
		for(var i = 0; i < 6; i++) {
			var temp = (value.decodeNumber(Lang.NUMBER_FORMAT_SINT16, { :offset => i * 2 }) / 10);
			var str = "";
			if(temp <= 0) {
				str = Lang.format("PROBE $1$: not connected", [i]);
			}
			else {
				str = Lang.format("PROBE $1$: $2$ degC $3$ degF", [i, temp, self.degCtoF(temp)] );
			}
			
			System.println(str);
			output += (str + "\n");
		}
		
		if(null != _tempChanged) {
			_tempChanged.invoke(output);
		}
	}
	
	//we don't have to actually perform a direct read on any characteristics - we enable NOTIFY and they get pushed to us
	function onCharacteristicRead(characteristic, status, value) {
		System.println(Lang.format("char read: $1$ $2$", [status, value]));
	}
	
	//the code is ugly and everything is changed together with these callbacks and a simple _state variable.
	//in this case, after we have a successful WRITE to the pairing characteristic we transition to INIT and write the "enable notification" 
	//data to the temperature characteristic's control descriptor. The notify stuff is all standard bluetooth LE and every characteristic on all services everywhere has 
	//a descriptor matching the cccdUuid
	function onCharacteristicWrite(characteristic, status) {
		System.println(Lang.format("char write: $1$", [status]));

		if(_state == PAIRING && STATUS_SUCCESS == status) {
			
			_state = INIT;
			var desc = _char.getDescriptor(BluetoothLowEnergy.cccdUuid());
			desc.requestWrite([0x1, 0x0]b);
		}

	}
	
	//handle connect/disconnect of the device
	//when connected, we get references to the services we want to use and the temperature characteristic
	//we write the auto-pairing key to complete the pairing operation and that kicks off the rest
	//on disconnect, we transition back to the PAIRING state so the whole process will restart itself every time the device disconnects/reconnects itself
	function onConnectedStateChanged(device, state) {
		System.println("connected changed");
	
		if(state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
			System.println("connected");
			
			_service = device.getService(TENERGY_SERVICE);
			
			//make sure the device has the service we're looking for
			if(null == _service) {
				return;
			}
			
			//get the pairing characteristic of the service
			var pairingChar = _service.getCharacteristic(TENERGY_PAIRING_CHARACTERISTIC);
			
			//get the temp characteristic for the service - will need this to enable notifications
			_char = _service.getCharacteristic(TENERGY_TEMP_CHARACTERISTIC);
			
			//send the pairing key
			if(null != pairingChar) {
				//the rest of the operation is chained off the callbacks started by this write operation
				pairingChar.requestWrite(TENERGY_AUTO_PAIR_KEY, {});
			}
		}
		else {
		
			//on disconnect start over
			_state = PAIRING;
			System.println("disconnected");
		}
	
	}
	
	//currently not used
	function onDescriptorRead(descriptor, status, value) {
		System.println(Lang.format("desc read $1$: $2$ : $3$", [descriptor.getUuid().toString(), status, value]));
	}
	
	//called after a write to a characteristic descriptor.
	//in this case, it gets called after the auto-pairing key has been written
	//if it was successful, transition to the INIT state and enable auto-updates on the temperature characteristic
	function onDescriptorWrite(descriptor, status) {
		System.println(Lang.format("desc write $1$: $2$", [descriptor.getUuid().toString(), status]));
		
		if(_state == INIT && STATUS_SUCCESS == status) {
			_state = READ;
			var control = _service.getCharacteristic(TENERGY_COMMAND_CHARACTERISTIC);
			control.requestWrite([11, 1, 0, 0, 0, 0]b, {:writeType => BluetoothLowEnergy.WRITE_TYPE_WITH_RESPONSE});
		}
	}
	
	function onProfileRegister(uuid, status) {
		System.println("onprofileregister()");
	}
	
	//results from scanning for devices. We use a terrible "hueristic" to find device(s) we're interested in
	function onScanResults(results) {
		var result = results.next();
		
		if(null != _device) {
			return;
		}
		
		while(null != result) {
		
			System.println("========");
			System.println(Lang.format("FOUND Device name: $1$ Appearance: $2$", [result.getDeviceName(), result.getAppearance()]));
			
			var infos = result.getManufacturerSpecificDataIterator();
			var info = infos.next();
			while(null != info) {
				System.println(info);
				System.println(Lang.format("Manuf. Data: $1$", [info]));
				info = infos.next();
			}
			
			var services = result.getServiceUuids();
			var service = services.next();
			
			System.println("Services:");
			while(null != service) {
				
				//this is the UUID of the service
				System.println(service.toString());
				
				//does it look like the service we're interested in?
				if(service.equals(TENERGY_SERVICE) ) {
					//we found it - maybe
					System.println("maybe a tenergy");
					
					//wrap a try/catch around it since once we've successfully paired this will throw an exception
					//this whole method (onScanResults) is garbage so don't read too much into it
					try {
						_device = BluetoothLowEnergy.pairDevice(result);
					}
					catch(DevicePairException) {
						System.println("device probably already paired");
					} 
					
					System.println(Lang.format("service: $1$ TENERGY_SERVICE: $2$", [service.toString(), TENERGY_SERVICE.toString()]));
					System.println(_device.getName());	
				}
				
				service = services.next();
			}
			
			result = results.next();
		}
	}
	
	function onScanStateChange(state, status) {
		System.println(Lang.format("Scan state changed: $1$ - $2$", [state, status])); 	
	}
}