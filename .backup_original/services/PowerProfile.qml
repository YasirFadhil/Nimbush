pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string profile: "balanced" // performance | balanced | power-saver
    readonly property bool saverEnabled: profile === "power-saver"

    function refresh() {
        getProc.running = true
    }

    function toggleSaver() {
        setProc.command = ["powerprofilesctl", "set", root.saverEnabled ? "balanced" : "power-saver"]
        setProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: getProc
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            onRead: data => root.profile = data.trim()
        }
    }

    Process { id: setProc; onExited: root.refresh() }
}
