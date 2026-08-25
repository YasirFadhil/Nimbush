pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

import "." as Services

Singleton {
    id: root

    property bool enabled: false
    property var devices: []
    property var unpairedDevices: []
    property bool refreshing: false
    property bool scanning: false
    property string pairingMac: ""

    readonly property string helperScript: Quickshell.env("HOME") 
        ? (Quickshell.env("HOME") + "/.config/quickshell/scripts/bluetooth-helper.py") 
        : "/home/yasirfadhil/.config/quickshell/scripts/bluetooth-helper.py"

    // Computed properties for connected devices & battery
    readonly property bool hasConnectedDevice: {
        for (let i = 0; i < devices.length; i++) {
            if (devices[i] && devices[i].connected) return true
        }
        return false
    }

    readonly property var connectedDevices: {
        const list = []
        for (let i = 0; i < devices.length; i++) {
            if (devices[i] && devices[i].connected) list.push(devices[i])
        }
        return list
    }

    readonly property var primaryConnectedDevice: (connectedDevices.length > 0) ? connectedDevices[0] : null
    readonly property string connectedDeviceName: primaryConnectedDevice ? (primaryConnectedDevice.name || primaryConnectedDevice.mac || "") : ""
    readonly property int connectedDeviceBattery: (primaryConnectedDevice && primaryConnectedDevice.battery !== undefined) ? primaryConnectedDevice.battery : -1
    readonly property string connectedDeviceIcon: primaryConnectedDevice ? (primaryConnectedDevice.icon || "") : ""

    function refresh() {
        if (!powerProc.running) powerProc.running = true
    }

    function toggle() {
        toggleProc.command = ["bluetoothctl", "power", root.enabled ? "off" : "on"]
        toggleProc.running = true
    }

    function listDevices() {
        if (!enabled) {
            devices = []
            unpairedDevices = []
            refreshing = false
            return
        }
        if (refreshing || listProc.running) return
        refreshing = true
        listProc.command = ["python3", root.helperScript, "list"]
        listProc.running = true
    }

    function startScan() {
        if (!enabled) {
            toggleProc.command = ["bluetoothctl", "power", "on"]
            toggleProc.running = true
        }
        scanning = true
        scanProc.command = ["bluetoothctl", "--timeout", "20", "scan", "on"]
        scanProc.running = true
    }

    function stopScan() {
        scanProc.running = false
        scanning = false
    }

    function toggleScan() {
        if (scanning) stopScan()
        else startScan()
    }

    function pairAndConnect(mac) {
        pairingMac = mac
        pairProc.command = ["python3", root.helperScript, "pair", mac]
        pairProc.running = true
    }

    function connectDevice(mac) {
        connectProc.command = ["python3", root.helperScript, "connect", mac]
        connectProc.running = true
    }

    function disconnectDevice(mac) {
        disconnectProc.command = ["python3", root.helperScript, "disconnect", mac]
        disconnectProc.running = true
    }

    function removeDevice(mac) {
        removeProc.command = ["python3", root.helperScript, "remove", mac]
        removeProc.running = true
    }

    function unpairDevice(mac) {
        removeDevice(mac)
    }

    // Debounce timer for D-Bus live sync events
    Timer {
        id: debounceListTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (root.enabled) root.listDevices()
        }
    }

    // Fallback sync timer (12s interval)
    Timer {
        interval: 12000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refresh()
            if (root.enabled) {
                root.listDevices()
            }
        }
    }

    Connections {
        target: Services.OverlayManager
        function onBtPanelVisibleChanged() {
            if (Services.OverlayManager && Services.OverlayManager.btPanelVisible) {
                root.refresh()
                root.listDevices()
            }
        }
    }

    Process {
        id: powerProc
        command: ["sh", "-c", "bluetoothctl show | grep Powered"]
        stdout: SplitParser {
            onRead: data => {
                const isPowered = data.trim().endsWith("yes")
                root.enabled = isPowered
                if (isPowered) {
                    root.listDevices()
                } else {
                    root.devices = []
                    root.unpairedDevices = []
                }
            }
        }
    }

    // Live monitor: detect connect/disconnect/battery/pairing events instantly via BlueZ D-Bus signals
    Process {
        id: btEventMonitor
        command: ["sh", "-c",
            "dbus-monitor --system \"type='signal',interface='org.freedesktop.DBus.Properties'," +
            "member='PropertiesChanged',path_namespace='/org/bluez'\" 2>/dev/null" +
            " | stdbuf -oL grep -E '\"(Connected|BatteryPercentage|Paired|ServicesResolved|Value|Connected:)\"'"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                debounceListTimer.restart()
            }
        }
    }

    Process {
        id: listProc
        property string rawOutput: ""
        stdout: SplitParser {
            onRead: data => {
                listProc.rawOutput += data
            }
        }
        onRunningChanged: {
            if (running) rawOutput = ""
        }
        onExited: {
            root.refreshing = false
            try {
                const parsed = JSON.parse(listProc.rawOutput.trim())
                if (parsed && Array.isArray(parsed.devices)) {
                    root.devices = parsed.devices
                }
                if (parsed && Array.isArray(parsed.unpaired)) {
                    const existingUnpaired = root.unpairedDevices.slice()
                    const map = {}
                    parsed.unpaired.forEach(d => { map[d.mac.toLowerCase()] = d })
                    existingUnpaired.forEach(d => {
                        const mac = d.mac.toLowerCase()
                        if (!root.devices.some(dev => dev.mac.toLowerCase() === mac)) {
                            if (!map[mac]) map[mac] = d
                        }
                    })
                    root.unpairedDevices = Object.values(map)
                }
            } catch (e) {
                // Ignore parse errors on empty output
            }
        }
    }

    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "20", "scan", "on"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                const m = line.match(/(?:\[NEW\]\s+)?Device\s+([0-9A-Fa-f:]{17})\s+(.*)$/)
                if (m) {
                    const mac = m[1]
                    const name = m[2]
                    const isPaired = root.devices.some(d => d.mac.toLowerCase() === mac.toLowerCase())
                    if (!isPaired) {
                        const existingIdx = root.unpairedDevices.findIndex(d => d.mac.toLowerCase() === mac.toLowerCase())
                        if (existingIdx === -1) {
                            const updated = root.unpairedDevices.slice()
                            updated.push({ mac: mac, name: name, connected: false, paired: false, battery: -1, icon: "" })
                            root.unpairedDevices = updated
                        } else if (name && name !== mac && root.unpairedDevices[existingIdx].name !== name) {
                            const updated = root.unpairedDevices.slice()
                            updated[existingIdx].name = name
                            root.unpairedDevices = updated
                        }
                    }
                } else {
                    const chgMatch = line.match(/\[CHG\]\s+Device\s+([0-9A-Fa-f:]{17})\s+(?:Name|Alias):\s+(.*)$/)
                    if (chgMatch) {
                        const mac = chgMatch[1]
                        const name = chgMatch[2]
                        const existingIdx = root.unpairedDevices.findIndex(d => d.mac.toLowerCase() === mac.toLowerCase())
                        if (existingIdx !== -1 && name) {
                            const updated = root.unpairedDevices.slice()
                            updated[existingIdx].name = name
                            root.unpairedDevices = updated
                        }
                    }
                }
            }
        }
        onExited: {
            root.scanning = false
            root.listDevices()
        }
    }

    Process {
        id: pairProc
        onExited: {
            root.pairingMac = ""
            root.listDevices()
        }
    }

    Process { id: connectProc; onExited: root.listDevices() }
    Process { id: disconnectProc; onExited: root.listDevices() }
    Process { id: toggleProc; onExited: root.refresh() }
    Process { id: removeProc; onExited: root.listDevices() }
}
