pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: false
    property var devices: []
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

    function checkNextStatus() {
        if (root.statusIndex >= root.devices.length) {
            root.refreshing = false
            return
        }
        infoProc.command = ["bluetoothctl", "info", root.devices[root.statusIndex].mac]
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
            root.devices = pairedProc.buffer
            root.statusIndex = 0
            root.checkNextStatus()
        }
    }

    Process {
        id: infoProc
        property bool foundConnected: false
        stdout: SplitParser {
            onRead: data => {
                if (data.trim().startsWith("Connected: yes")) infoProc.foundConnected = true
            }
        }
        onRunningChanged: { if (running) foundConnected = false }
        onExited: {
            const arr = root.devices.slice()
            if (arr[root.statusIndex]) arr[root.statusIndex].connected = infoProc.foundConnected
            root.devices = arr
            root.statusIndex++
            root.checkNextStatus()
        }
    }

    Process { id: connectProc; onExited: root.listDevices() }
    Process { id: disconnectProc; onExited: root.listDevices() }
    Process { id: toggleProc; onExited: root.refresh() }
}
