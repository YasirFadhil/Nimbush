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
    property var tempDevices: []
    property bool refreshing: false
    property bool scanning: false
    property string pairingMac: ""
    property int statusIndex: 0

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
        if (refreshing || pairedProc.running) return
        refreshing = true
        pairedProc.running = true
    }

    function startScan() {
        if (!enabled) {
            toggleProc.command = ["bluetoothctl", "power", "on"]
            toggleProc.running = true
        }
        scanning = true
        scanProc.command = ["bluetoothctl", "--timeout", "15", "scan", "on"]
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
        pairProc.command = ["sh", "-c", "bluetoothctl pair \"$1\" && bluetoothctl trust \"$1\" && bluetoothctl connect \"$1\"", "sh", mac]
        pairProc.running = true
    }

    function connectDevice(mac) {
        connectProc.command = ["bluetoothctl", "connect", mac]
        connectProc.running = true
    }

    function disconnectDevice(mac) {
        disconnectProc.command = ["bluetoothctl", "disconnect", mac]
        disconnectProc.running = true
    }

    function removeDevice(mac) {
        removeProc.command = ["bluetoothctl", "remove", mac]
        removeProc.running = true
    }

    function unpairDevice(mac) {
        removeDevice(mac)
    }

    function checkNextStatus() {
        if (root.statusIndex >= root.tempDevices.length) {
            root.devices = root.tempDevices
            root.refreshing = false
            allDevicesProc.running = true
            return
        }
        infoProc.command = ["bluetoothctl", "info", root.tempDevices[root.statusIndex].mac]
        infoProc.running = true
    }

    // Fallback sync timer (15s interval) - live events are already handled instantly by D-Bus monitor below
    Timer {
        interval: 15000
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
            if (Services.OverlayManager.btPanelVisible) {
                root.refresh()
                root.listDevices()
            }
        }
    }

    Process {
        id: powerProc
        command: ["sh", "-c", "bluetoothctl show | grep Powered"]
        stdout: SplitParser {
            onRead: data => root.enabled = data.trim().endsWith("yes")
        }
    }

    // Live monitor: detect connect/disconnect events instantly via BlueZ D-Bus signals
    Process {
        id: btEventMonitor
        command: ["sh", "-c",
            "dbus-monitor --system \"type='signal',interface='org.freedesktop.DBus.Properties'," +
            "member='PropertiesChanged',path_namespace='/org/bluez'\" 2>/dev/null" +
            " | stdbuf -oL grep -o '\"Connected\"'"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.listDevices()
            }
        }
    }

    Process {
        id: pairedProc
        command: ["bluetoothctl", "devices", "Paired"]
        property var buffer: []
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                const m = line.match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.*)$/)
                if (m) pairedProc.buffer.push({ mac: m[1], name: m[2], connected: false, paired: true })
            }
        }
        onRunningChanged: { if (running) buffer = [] }
        onExited: {
            root.tempDevices = pairedProc.buffer
            root.statusIndex = 0
            root.checkNextStatus()
        }
    }

    Process {
        id: allDevicesProc
        command: ["bluetoothctl", "devices"]
        property var buffer: []
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                const m = line.match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.*)$/)
                if (m) {
                    const mac = m[1]
                    const name = m[2]
                    const isPaired = root.devices.some(d => d.mac.toLowerCase() === mac.toLowerCase())
                    if (!isPaired) {
                        allDevicesProc.buffer.push({ mac: mac, name: name, connected: false, paired: false })
                    }
                }
            }
        }
        onRunningChanged: { if (running) buffer = [] }
        onExited: {
            root.unpairedDevices = allDevicesProc.buffer
        }
    }

    Process {
        id: infoProc
        property bool foundConnected: false
        property int foundBattery: -1
        property string foundIcon: ""
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.startsWith("Connected: yes")) infoProc.foundConnected = true

                const batMatch = line.match(/Battery Percentage:\s*(?:0x[0-9a-fA-F]+\s*\()?(\d+)\)?%?/)
                if (batMatch) {
                    infoProc.foundBattery = parseInt(batMatch[1])
                }

                const iconMatch = line.match(/^Icon:\s*(.+)$/)
                if (iconMatch) {
                    infoProc.foundIcon = iconMatch[1].trim()
                }
            }
        }
        onRunningChanged: {
            if (running) {
                foundConnected = false
                foundBattery = -1
                foundIcon = ""
            }
        }
        onExited: {
            if (root.tempDevices[root.statusIndex]) {
                root.tempDevices[root.statusIndex].connected = infoProc.foundConnected
                root.tempDevices[root.statusIndex].battery = infoProc.foundBattery
                root.tempDevices[root.statusIndex].icon = infoProc.foundIcon
            }
            root.statusIndex++
            root.checkNextStatus()
        }
    }

    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "15", "scan", "on"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                const m = line.match(/(?:\[NEW\]\s+)?Device\s+([0-9A-Fa-f:]{17})\s+(.*)$/)
                if (m) {
                    const mac = m[1]
                    const name = m[2]
                    const isPaired = root.devices.some(d => d.mac.toLowerCase() === mac.toLowerCase())
                    if (!isPaired) {
                        const exists = root.unpairedDevices.some(d => d.mac.toLowerCase() === mac.toLowerCase())
                        if (!exists) {
                            const updated = root.unpairedDevices.slice()
                            updated.push({ mac: mac, name: name, connected: false, paired: false })
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
