using Toybox;
using Toybox.BluetoothLowEnergy;

module TenergySolis {

	class BluetoothDevice {
		hidden var _scanResult;
		
		function initialize(scanResult) {
			_scanResult = scanResult;
		}
		
		function getScanResult() {
			return _scanResult;
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