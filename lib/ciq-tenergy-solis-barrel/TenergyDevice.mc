using Toybox;
using Toybox.BluetoothLowEnergy;

module TenergySolis {

	class TenergyDevice extends TenergySolis.BluetoothDevice {
	
		function initialize(scanResult) {
			BluetoothDevice.initialize(scanResult);
		}
	
	}

}