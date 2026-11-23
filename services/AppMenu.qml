pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    property var model: []
    property int pid: 0
    property bool loading: false
    property bool available: false
    property string lastError: ""

    readonly property string helperPath: {
        var p = Qt.resolvedUrl("../tools/atspi/run_menu.sh").toString()
        if (p.startsWith("file://")) p = p.substring(7)
        return (p && p.length > 0) ? p : (Quickshell.env("HOME") + "/.config/quickshell/tools/atspi/run_menu.sh")
    }

    function request(targetPid) {
        if (!targetPid || targetPid <= 0) {
            root.pid = 0
            root.model = []
            root.available = false
            root.loading = false
            return
        }

        root.pid = targetPid
        root.loading = true

        if (!helperProc.running) {
            helperProc.running = true
        }

        const msg = JSON.stringify({ cmd: "menu", pid: targetPid })
        try {
            helperProc.write(msg + "\n")
        } catch (e) {
            root.loading = false
            root.lastError = String(e)
            console.warn("[AppMenu] write error:", e)
        }
    }

    function trigger(path) {
        if (!root.pid || !path || path.length === 0) return
        const msg = JSON.stringify({ cmd: "trigger", pid: root.pid, path: path })
        try {
            helperProc.write(msg + "\n")
        } catch (e) {
            root.lastError = String(e)
            console.warn("[AppMenu] trigger write error:", e)
        }
    }

    Process {
        id: helperProc
        command: ["bash", root.helperPath, "--daemon"]
        stdinEnabled: true
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = data.trim()
                if (!line) return
                try {
                    const res = JSON.parse(line)
                    if (res.type === "menu") {
                        if (res.pid === root.pid) {
                            root.model = res.items || []
                            root.available = Boolean(res.available && root.model.length > 0)
                            root.loading = false
                            console.log("[AppMenu] Loaded menu for PID", res.pid, "items:", root.model.length)
                        }
                    } else if (res.type === "trigger") {
                        // Action executed
                    } else if (res.type === "error") {
                        root.lastError = res.msg || ""
                        root.loading = false
                    }
                } catch (e) {
                    // Ignore non-JSON lines (e.g. nix-shell evaluation messages)
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                // Ignore harmless warning
                if (!data.includes("GetApplicationBusAddress")) {
                    console.warn("[AppMenu] helper stderr:", data)
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.loading = false
            console.warn("[AppMenu] helper process exited with code", exitCode, "status", exitStatus)
            // Auto-restart with backoff delay
            restartTimer.restart()
        }
    }

    Timer {
        id: restartTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!helperProc.running) {
                helperProc.running = true
                if (root.pid > 0) {
                    root.request(root.pid)
                }
            }
        }
    }

    Timer {
        id: activeAppDebounce
        interval: 120
        repeat: false
        onTriggered: {
            if (Services.ActiveApp) {
                root.request(Services.ActiveApp.pid)
            }
        }
    }

    Connections {
        target: Services.ActiveApp || null
        function onPidChanged() {
            activeAppDebounce.restart()
        }
    }

    Component.onCompleted: {
        if (Services.ActiveApp && Services.ActiveApp.pid > 0) {
            root.request(Services.ActiveApp.pid)
        }
    }
}
