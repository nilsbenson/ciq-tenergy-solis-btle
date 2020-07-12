using Toybox;
using Toybox.BluetoothLowEnergy;

(:btle)
module TenergySolis {

	enum {
		TEMP_DEG_C = 0,
		TEMP_DEG_F = 1
	}

	class BluetoothDevice {
		hidden var _scanResult;
		hidden var _device;
		hidden var _temps;
		hidden var _delegate;
		
		var tempChanged = new SimpleCallbackEvent("tempChanged");
		function initialize(scanResult, delegate) {
			_scanResult = scanResult;
			_delegate = delegate;
		}
		
		function getScanResult() {
			return _scanResult;
		}
		
		function pairAndConnect() {
			System.println("pairing / connecting to BTLE device");
			_device = BluetoothLowEnergy.pairDevice(_scanResult);
			_delegate.setConnectedDevice(self);
		}
		
		function disconnect() {
			if(null != _device) {
				BluetoothLowEnergy.unpairDevice(_device);
				_device = null;
			}
		}
		
		function setTemp(temps) {
			_temps = temps;
			tempChanged.emit(self);
		}
		
		function getTemps(tempType) {
			if(tempType == TEMP_DEG_C) {
				return _temps;
			}
				
			var newTemps = new [6];
			for(var i = 0; i < _temps.size(); i++) {
				if(-1 == _temps[i]) {
					newTemps[i] = -1;
				}
				else {
					newTemps[i] = BluetoothDevice.degCtoF(_temps[i]);
				}
			} 
			
			return newTemps;
		}
		
		//convert C to F - device sends degrees as C over bluetooth, regardless of the display setting on the device
		static function degCtoF(degC) {
			return (degC * 1.8) + 32;
		}
		
		function isSameDevice(other) {
			if(null == self._scanResult || null == other || null == other.getScanResult()) {
				return false;
			}
			
			return self._scanResult.isSameDevice(other.getScanResult()); 
		}
		
	}

}