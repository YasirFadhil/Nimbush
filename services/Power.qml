pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "." as Services

Singleton {
    id: root

    property bool ready: false
    property bool charging: isChargingState(UPower.displayDevice.state)
    property real percentage: UPower.displayDevice.percentage
    readonly property bool hasBattery: UPower.displayDevice.isPresent && !isNaN(percentage)
    readonly property string stateString: {
        const st = UPower.displayDevice.state
        if (st === UPowerDeviceState.Charging) return "Charging"
        if (st === UPowerDeviceState.FullyCharged) return "Fully Charged"
        if (st === UPowerDeviceState.Discharging) return "Discharging"
        if (st === UPowerDeviceState.Empty) return "Empty"
        return "AC Power / Unknown"
    }
    readonly property bool isWarning: !charging && ready && !isNaN(percentage) && (percentage * 100 <= (Services.Config ? Services.Config.batteryLowThreshold : 20))
    readonly property bool isLow: !charging && ready && !isNaN(percentage) && (percentage * 100 <= 10)

    property bool warn20Sent: false
    property bool warn10Sent: false
    property bool warn5Sent: false

    signal chargingStateChanged(bool charging, real percentage)
    signal batteryWarning(int level, string title, string message)

    function isChargingState(state) {
        return state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged
    }

    function sendNotification(title, message, urgencyStr, icon) {
        let u = 1
        if (urgencyStr === "critical") u = 2
        else if (urgencyStr === "low") u = 0

        Notifications.addSystemNotification({
            appName: "System Warning",
            appIcon: icon || "battery-caution",
            summary: title,
            body: message,
            urgency: u
        })
    }

    function checkBatteryWarnings() {
        if (Services.Config && !Services.Config.batteryShowWarnings) return
        if (!ready || isNaN(percentage)) return
        const pct = Math.round(percentage * 100)

        if (charging) {
            if (pct > 20) warn20Sent = false
            if (pct > 10) warn10Sent = false
            if (pct > 5) warn5Sent = false
            return
        }

        if (pct > 20) {
            warn20Sent = false
            warn10Sent = false
            warn5Sent = false
        } else if (pct > 10) {
            warn10Sent = false
            warn5Sent = false
        } else if (pct > 5) {
            warn5Sent = false
        }

        if (pct <= 5 && !warn5Sent) {
            warn5Sent = true
            warn10Sent = true
            warn20Sent = true
            sendNotification("Battery Critical (5%)", "Battery remaining: 5%! Device will shut down soon.", "critical", "battery-empty")
            root.batteryWarning(5, "Battery Critical (5%)", "Battery remaining: 5%! Device will shut down soon.")
        } else if (pct <= 10 && pct > 5 && !warn10Sent) {
            warn10Sent = true
            warn20Sent = true
            sendNotification("Battery Low (10%)", "Battery remaining: 10%! Please connect your charger.", "critical", "battery-caution")
            root.batteryWarning(10, "Battery Low (10%)", "Battery remaining: 10%! Please connect your charger.")
        } else if (pct <= 20 && pct > 10 && !warn20Sent) {
            warn20Sent = true
            sendNotification("Battery Warning (20%)", "Battery remaining: 20%. Consider connecting charger.", "critical", "battery-low")
            root.batteryWarning(20, "Battery Warning (20%)", "Battery remaining: 20%. Consider connecting charger.")
        }
    }

    onPercentageChanged: checkBatteryWarnings()

    onChargingChanged: {
        if (!root.ready) return
        root.chargingStateChanged(root.charging, root.percentage)
        if (charging) {
            warn20Sent = false
            warn10Sent = false
            warn5Sent = false
        } else {
            checkBatteryWarnings()
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            root.ready = true
            if (!isNaN(root.percentage)) {
                const initialPct = Math.round(root.percentage * 100)
                if (initialPct <= 20) root.warn20Sent = true
                if (initialPct <= 10) root.warn10Sent = true
                if (initialPct <= 5)  root.warn5Sent = true
            }
        })
    }
}
