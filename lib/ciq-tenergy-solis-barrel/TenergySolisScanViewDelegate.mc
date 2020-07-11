using Toybox;
using Toybox.WatchUi;

module TenergySolis {

	class TenergySolisScanViewDelegate extends WatchUi.View {
	
		hidden var _btDelegate;
		hidden var _scanResults;
		
		//takes a TenergySolis::BluetoothDelegate
		function initialize(btDelegate) {
			View.initialize();
			_scanResults = [];
		}
		
		function onScanResult(scanResult) {
			
		}
	}
}