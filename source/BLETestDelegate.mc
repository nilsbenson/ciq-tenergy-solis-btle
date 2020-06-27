using Toybox.WatchUi;
using Toybox.BluetoothLowEnergy;
using Toybox.System;

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

