pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string profile: "balanced" // performance | balanced | power-saver
    readonly property string currentProfile: profile
    readonly property bool saverEnabled: profile === "power-saver"

    function refresh() {
        if (!getProc.running) getProc.running = true
    }

    function setProfile(name) {
        if (!name) return
        root.profile = name
        setProc.command = ["powerprofilesctl", "set", name]
        setProc.running = true
    }

    function toggleSaver() {
        setProfile(root.saverEnabled ? "balanced" : "power-saver")
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: getProc
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim()
                if (p.length > 0) root.profile = p
            }
        }
    }

    Process { id: setProc; onExited: root.refresh() }
}
