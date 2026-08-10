pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    property bool ready: false
    property bool charging: isChargingState(UPower.displayDevice.state)
    property real percentage: UPower.displayDevice.percentage

    signal chargingStateChanged(bool charging, real percentage)

    function isChargingState(state) {
        return state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged
    }

    onChargingChanged: {
        if (!root.ready) return
        root.chargingStateChanged(root.charging, root.percentage)
    }

    Component.onCompleted: {
        Qt.callLater(() => root.ready = true)
    }
}
