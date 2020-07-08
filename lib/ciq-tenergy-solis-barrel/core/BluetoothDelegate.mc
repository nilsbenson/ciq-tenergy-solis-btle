using Toybox.System;
using Toybox.BluetoothLowEnergy;

module TenergySolis {

	/*
	
		- The CIQ bluetooth stack doesn't understand "standard" 16-bit UUIDs so we have to use the full formal UUID to get things working.
		- CIQ bluetooth stack truncates at 20 bytes meaning local name in advertising data (scanresult) is missing
		- CIQ requires us to register at least one profile (currently max 3) that defines all of the services / characteristics / descriptors we will be using
		- CIQ has no way of "subscribing" to characteristics so we have to set the notify flag to true/on on the descriptor. most stacks have a way of handling this for us
		- 
	*/
	
	//UUID of the tenergy "generic" service we communicate with
	const TENERGY_SERVICE = BluetoothLowEnergy.stringToUuid("0000FFF0-0000-1000-8000-00805F9B34FB");
	
	//this characteristic supports NOTIFY and it is what actually provides the temperature data
	const TENERGY_TEMP_CHARACTERISTIC = BluetoothLowEnergy.stringToUuid("0000FFF4-0000-1000-8000-00805F9B34FB");
	
	//this is char that we write the pairing key to to complete the connection process
	const TENERGY_PAIRING_CHARACTERISTIC = BluetoothLowEnergy.stringToUuid("0000FFF2-0000-1000-8000-00805F9B34FB");
	
	//this char is the "command" channel that we use to enable auto-updates for temp, change units, set predefined temps, etc.
	const TENERGY_COMMAND_CHARACTERISTIC = BluetoothLowEnergy.stringToUuid("0000FFF5-0000-1000-8000-00805F9B34FB");
	
	//UUID of the descriptor on the TEMP_CHARACTERISTIC so we can twiddle the notify flag to "on" so it continuously publishes temperatures to us
	const TENERGY_TEMP_NOTIFY_DESCRIPTOR = BluetoothLowEnergy.stringToUuid("00002902-0000-1000-8000-00805F9B34FB");
	
	//the default auto-pairing key as cribbed from cloudbbq / verified with wireshark & the nordic DK with sniffer
	const TENERGY_AUTO_PAIR_KEY = [ 33, 7, 6, 5, 4, 3, 2, 1, -72, 34, 0, 0, 0, 0, 0 ]b;
	
	
	class BluetoothDelegate extends BluetoothLowEnergy.BleDelegate {
	
		hidden var _device = null;			//the device we're connected to
		hidden var _service = null;			//the service we're communicating with
		hidden var _tempChar;				//ref to the characteristic that provides temperature data
		hidden var _state = PAIRING;		//state of the delegate - PAIRING -> INIT -> READ -> PAIRING
		hidden var _onTempChanged = null;		//callback method to allow notifying the UI that temperature has changed
		hidden var _onScanResult = null;	//callback to handle notifications from the BTLE delegate that there's a scan result
		hidden var _pairedDevices = null; 	//list of devices we've already paired with so if we find a matching scanresult we can just connect to it
		
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
			
			_onTempChanged = interface.method(:tempChanged);
			_onScanResult = interface.method(:onScanResult);
			_pairedDevices = BluetoothLowEnergy.getPairedDevices();
			
			//bluetooth API on garmin REQUIRES us to register which services, characteristics, and descriptors we will be using
			//otherwise they will not be available to use when we call getService()/getCharacteristic()/getDescriptor()
			//basically we have to register up-front what we intend to use
			
			//so in this case we will use the FFF0 service, and on that service we're interested in the characteristics exposed for TEMP/COMMAND/PAIRING
			//for each of these characteristics we will want access to the characteristic control descriptor (cccdUuid)
			 
			 var profile = {
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
					str = Lang.format("PROBE $1$: $2$ degC $3$ degF", [i, temp, BluetoothDevice.degCtoF(temp)] );
				}
				
				System.println(str);
				output += (str + "\n");
			}
			
			if(null != _onTempChanged) {
				_onTempChanged.invoke(output);
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
				System.println(Lang.format("enabling notifications for characteristic on device $1$", [characteristic.getService().getDevice().getName()]));
				var desc = _tempChar.getDescriptor(BluetoothLowEnergy.cccdUuid());
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
				
				System.println(Lang.format("onConnectedStateChanged (device param) device: $1$", [device.getName()]));
				
				//make sure the device has the service we're looking for
				if(null == _service) {
					return;
				}
				
				System.println(Lang.format("onConnectedStateChanged (service.getDevice()) device: $1$", [_service.getDevice().getName()]));
				
				//get the pairing characteristic of the service
				var pairingChar = _service.getCharacteristic(TENERGY_PAIRING_CHARACTERISTIC);
				
				//get the temp characteristic for the service - will need this to enable notifications
				_tempChar = _service.getCharacteristic(TENERGY_TEMP_CHARACTERISTIC);
				
				//send the pairing key
				if(null != pairingChar) {
					System.println(Lang.format("onConnectedStateChanged (char.getService().getDevice().getName()) device: $1$", [pairingChar.getService().getDevice().getName()]));
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
		//we have to do this because there is what I consider a bug in CIQ BLE that won't return the entire advertiser info
		//if it's over 20 bytes which means the "iBBQ" local name doesn't make it to our app so we have to guess at it
		function onScanResults(results) {

			var result = results.next();
			
			if(null != _device) {
				return;
			}
			
			while(null != result) {
			
				System.println("========");
				System.println(Lang.format("FOUND Device name: $1$ Appearance: $2$", [result.getDeviceName(), result.getAppearance()]));

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
							if(!self.hasDevice(result)) {
								_device = BluetoothLowEnergy.pairDevice(result);
							}
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
		
		function hasDevice(device) {
		
			for(var paired = _pairedDevices.next(); paired != null; paired = _pairedDevices.next()) {
				if(paired.isSameDevice(device)) {
					return true;
				}
			}
		
			return false;
		}
	}

}