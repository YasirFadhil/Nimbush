pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

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

    function refresh() {
        radioProc.running = true
        savedProc.running = true
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
        scanning = true
        lastError = ""
        rescanProc.running = true
    }

    function connectNetwork(targetSsid, password) {
        lastError = ""
        if (password && password.length > 0) {
            connectProc.command = ["nmcli", "dev", "wifi", "connect", targetSsid, "password", password]
        } else {
            connectProc.command = ["nmcli", "dev", "wifi", "connect", targetSsid]
        }
        connectProc.running = true
    }

    function disconnectNetwork() {
        if (root.ssid.length === 0) return
        disconnectProc.command = ["nmcli", "con", "down", "id", root.ssid]
        disconnectProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
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

    // Current active connection
    Process {
        id: connProc
        command: ["sh", "-c", "nmcli -t -f active,ssid,signal dev wifi list --rescan no | grep '^yes'"]
        property bool foundAny: false
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0) return
                const parts = line.split(":")
                root.connected = true
                root.ssid = parts[1] || ""
                root.signalStrength = parseInt(parts[2]) || 0
                connProc.foundAny = true
            }
        }
        onRunningChanged: { if (running) foundAny = false }
        onExited: {
            if (!foundAny) {
                root.connected = false
                root.ssid = ""
                root.signalStrength = 0
            }
        }
    }

    // Manual rescan (dipicu tombol refresh)
    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        onExited: listProc.running = true
    }

    // List semua network yang kelihatan
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
        }
    }

    Process {
        id: connectProc
        stderr: SplitParser {
            onRead: data => { if (data.trim().length > 0) root.lastError = data.trim() }
        }
        onExited: (exitCode) => {
            root.refresh()
            if (exitCode === 0) root.scan()
        }
    }

    Process { id: disconnectProc; onExited: root.refresh() }
    Process { id: toggleProc; onExited: root.refresh() }

    // Daftar profil WiFi yang udah pernah disave (buat badge "Saved" + fitur forget)
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
