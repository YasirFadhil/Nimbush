pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

import "." as Services

Singleton {
    id: root

    property bool enabled: false
    property bool connected: false
    property string ssid: ""
    property int signalStrength: 0

    property var networks: []
    property var savedNetworks: []
    property bool scanning: false
    property string lastError: ""
    property string connectingSsid: ""
    property string statusMessage: ""

    function refresh() {
        if (!radioProc.running) radioProc.running = true
    }

    function refreshAll() {
        refresh()
        if (!savedProc.running) savedProc.running = true
        if (root.enabled) {
            listNetworks()
            scan()
        }
    }

    function listNetworks() {
        if (!listProc.running) listProc.running = true
    }

    function isSaved(targetSsid) {
        return root.savedNetworks.indexOf(targetSsid) !== -1
    }

    function forgetNetwork(targetSsid) {
        forgetProc.command = ["nmcli", "con", "delete", "id", targetSsid]
        forgetProc.running = true
    }

    function toggle() {
        toggleProc.command = ["nmcli", "radio", "wifi", root.enabled ? "off" : "on"]
        toggleProc.running = true
    }

    function scan() {
        if (scanning || rescanProc.running) return
        scanning = true
        lastError = ""
        statusMessage = "Scanning for networks..."
        rescanProc.running = true
    }

    function connectNetwork(targetSsid, password) {
        lastError = ""
        statusMessage = "Connecting to " + targetSsid + "..."
        connectingSsid = targetSsid
        if (password && password.length > 0) {
            connectProc.command = ["nmcli", "dev", "wifi", "connect", targetSsid, "password", password]
        } else {
            connectProc.command = ["nmcli", "dev", "wifi", "connect", targetSsid]
        }
        connectProc.running = true
    }

    function disconnectNetwork() {
        if (root.ssid.length === 0) return
        statusMessage = "Disconnecting from " + root.ssid + "..."
        connectingSsid = root.ssid
        disconnectProc.command = ["nmcli", "con", "down", "id", root.ssid]
        disconnectProc.running = true
    }

    // Background connection status check (7s interval, passive - no hardware scan)
    Timer {
        interval: 7000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Periodic active rescan ONLY when the user is actively viewing the WiFi panel in Control Center
    Timer {
        id: autoRescanTimer
        interval: 15000
        running: Services.OverlayManager ? Services.OverlayManager.wifiPanelVisible : false
        repeat: true
        onTriggered: root.scan()
    }

    Timer {
        id: delayedScanTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (Services.OverlayManager && Services.OverlayManager.wifiPanelVisible) {
                root.refreshAll()
            }
        }
    }

    Connections {
        target: Services.OverlayManager
        function onWifiPanelVisibleChanged() {
            if (Services.OverlayManager.wifiPanelVisible) {
                root.refresh()
                root.listNetworks()
                delayedScanTimer.restart()
            } else {
                delayedScanTimer.stop()
            }
        }
    }

    // Radio on/off
    Process {
        id: radioProc
        command: ["nmcli", "-t", "-f", "WIFI", "radio"]
        stdout: SplitParser {
            onRead: data => {
                const state = data.trim()
                root.enabled = (state === "enabled")
                if (root.enabled) {
                    connProc.running = true
                } else {
                    root.connected = false
                    root.ssid = ""
                    root.signalStrength = 0
                }
            }
        }
    }

    property bool ready: false

    // Current active connection
    Process {
        id: connProc
        command: ["sh", "-c", "dev=$(nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null | awk -F: '$1==\"wifi\" && $2==\"connected\"{print $3; exit}'); if [ -n \"$dev\" ]; then sig=$(nmcli -t -f in-use,signal dev wifi list --rescan no 2>/dev/null | awk -F: '$1==\"*\"{print $2; exit}'); echo \"CONNECTED:$dev:${sig:-0}\"; else echo \"DISCONNECTED\"; fi"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.startsWith("CONNECTED:")) {
                    const parts = line.split(":")
                    root.connected = true
                    root.ssid = parts[1] || ""
                    const sig = parseInt(parts[2])
                    if (!isNaN(sig) && sig > 0) root.signalStrength = sig
                } else if (line === "DISCONNECTED") {
                    root.connected = false
                    root.ssid = ""
                    root.signalStrength = 0
                }
                root.ready = true
            }
        }
    }

    // Manual rescan (triggered by refresh button)
    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: listProc.running = true
    }

    // List all visible networks
    Process {
        id: listProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SECURITY,SIGNAL", "dev", "wifi", "list", "--rescan", "no"]
        property var buffer: []
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0) return
                const parts = line.split(":")
                const inUse = parts[0] === "*"
                const ssid = parts[1] || ""
                const security = parts[2] || ""
                const signal = parseInt(parts[3]) || 0
                if (ssid.length === 0) return
                listProc.buffer.push({ ssid, security, signal, inUse })
            }
        }
        onRunningChanged: { if (running) buffer = [] }
        onExited: {
            const bySsid = {}
            for (const n of listProc.buffer) {
                if (!bySsid[n.ssid] || n.signal > bySsid[n.ssid].signal) bySsid[n.ssid] = n
            }
            root.networks = Object.values(bySsid).sort((a, b) => b.signal - a.signal)
            root.scanning = false
            if (root.statusMessage === "Scanning for networks...") root.statusMessage = ""
        }
    }

    Process {
        id: connectProc
        stderr: SplitParser {
            onRead: data => { if (data.trim().length > 0) root.lastError = data.trim() }
        }
        onExited: (exitCode) => {
            if (root.connectingSsid.length > 0) {
                if (exitCode === 0) {
                    root.statusMessage = "Connected to " + root.connectingSsid
                    root.lastError = ""
                } else if (root.lastError.length === 0) {
                    root.lastError = "Could not connect to " + root.connectingSsid
                    root.statusMessage = ""
                }
                root.connectingSsid = ""
            }
            root.refresh()
            if (exitCode === 0) root.scan()
        }
    }

    Process {
        id: disconnectProc
        onExited: {
            if (root.connectingSsid.length > 0) {
                if (exitCode === 0) root.statusMessage = "Disconnected"
                else if (root.lastError.length === 0) root.lastError = "Could not disconnect"
                root.connectingSsid = ""
            }
            root.refresh()
        }
    }
    Process { id: toggleProc; onExited: root.refresh() }

    // Saved WiFi connection profiles (for "Saved" badge + forget connection feature)
    Process {
        id: savedProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        property var buffer: []
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0) return
                const parts = line.split(":")
                if (parts[1] === "802-11-wireless") savedProc.buffer.push(parts[0])
            }
        }
        onRunningChanged: { if (running) buffer = [] }
        onExited: root.savedNetworks = savedProc.buffer
    }

    Process {
        id: forgetProc
        stderr: SplitParser {
            onRead: data => { if (data.trim().length > 0) root.lastError = data.trim() }
        }
        onExited: {
            root.refresh()
            root.scan()
        }
    }
}
