pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: false
    property var devices: []
    property var tempDevices: []
    property bool refreshing: false
    property int statusIndex: 0

    function refresh() {
        powerProc.running = true
    }

    function toggle() {
        toggleProc.command = ["bluetoothctl", "power", root.enabled ? "off" : "on"]
        toggleProc.running = true
    }

    function listDevices() {
        refreshing = true
        pairedProc.running = true
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

    function checkNextStatus() {
        if (root.statusIndex >= root.tempDevices.length) {
            root.devices = root.tempDevices
            root.refreshing = false
            return
        }
        infoProc.command = ["bluetoothctl", "info", root.tempDevices[root.statusIndex].mac]
        infoProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: powerProc
        command: ["sh", "-c", "bluetoothctl show | grep Powered"]
        stdout: SplitParser {
            onRead: data => root.enabled = data.trim().endsWith("yes")
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
                if (m) pairedProc.buffer.push({ mac: m[1], name: m[2], connected: false })
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

    Process { id: connectProc; onExited: root.listDevices() }
    Process { id: disconnectProc; onExited: root.listDevices() }
    Process { id: toggleProc; onExited: root.refresh() }
    Process { id: removeProc; onExited: root.listDevices() }
}
