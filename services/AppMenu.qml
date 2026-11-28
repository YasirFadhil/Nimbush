pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    property var model: []
    property int pid: 0
    property string source: ""
    property bool loading: false
    property bool available: false
    property string lastError: ""
    property var menuCache: ({})

    readonly property string helperPath: {
        var p = Qt.resolvedUrl("../tools/atspi/run_menu.sh").toString()
        if (p.startsWith("file://")) p = p.substring(7)
        return (p && p.length > 0) ? p : (Quickshell.env("HOME") + "/.config/quickshell/tools/atspi/run_menu.sh")
    }

    function request(targetPid) {
        if (!targetPid || targetPid <= 0) {
            root.pid = 0
            root.model = []
            root.source = ""
            root.available = false
            root.loading = false
            return
        }

        root.pid = targetPid
        root.loading = true

        if (!helperProc.running) {
            helperProc.running = true
        }

        const appClass = (Services.ActiveApp && Services.ActiveApp.windowClass) ? Services.ActiveApp.windowClass : ""
        const winTitle = (Services.ActiveApp && Services.ActiveApp.windowTitle) ? Services.ActiveApp.windowTitle : ""
        const msg = JSON.stringify({ cmd: "menu", pid: targetPid, app_class: appClass, title: winTitle })
        try {
            helperProc.write(msg + "\n")
        } catch (e) {
            root.loading = false
            root.lastError = String(e)
            console.warn("[AppMenu] write error:", e)
        }
    }

    function refresh() {
        if (Services.ActiveApp && Services.ActiveApp.pid > 0) {
            request(Services.ActiveApp.pid)
        } else if (root.pid > 0) {
            request(root.pid)
        }
    }

    function trigger(itemOrPath) {
        if (!root.pid || !itemOrPath) return
        const appClass = (Services.ActiveApp && Services.ActiveApp.windowClass) ? Services.ActiveApp.windowClass : ""
        const winTitle = (Services.ActiveApp && Services.ActiveApp.windowTitle) ? Services.ActiveApp.windowTitle : ""
        let payload = { cmd: "trigger", pid: root.pid, app_class: appClass, title: winTitle }
        if (Array.isArray(itemOrPath)) {
            if (itemOrPath.length === 0) return
            payload.path = itemOrPath
        } else if (typeof itemOrPath === "object") {
            if (itemOrPath.action) payload.action = itemOrPath.action
            if (itemOrPath.path) payload.path = itemOrPath.path
            if (!payload.action && (!payload.path || payload.path.length === 0)) return
        } else {
            return
        }

        try {
            helperProc.write(JSON.stringify(payload) + "\n")
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
                        const items = res.items || []
                        const src = res.source || ""
                        const avail = Boolean(res.available && items.length > 0)
                        root.menuCache[res.pid] = { items: items, source: src, available: avail }
                        if (res.pid === root.pid) {
                            root.model = items
                            root.source = src
                            root.available = avail
                            root.loading = false
                            console.log("[AppMenu] Loaded menu for PID", res.pid, "source:", root.source, "items:", root.model.length)
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
        interval: 25
        repeat: false
        onTriggered: {
            if (Services.ActiveApp) {
                root.request(Services.ActiveApp.pid)
            }
        }
    }

    Timer {
        id: titleRefreshDebounce
        interval: 350
        repeat: false
        onTriggered: {
            if (Services.ActiveApp && Services.ActiveApp.pid > 0 && !root.loading) {
                root.request(Services.ActiveApp.pid)
            }
        }
    }

    Connections {
        target: Services.ActiveApp || null
        function onPidChanged() {
            const nextPid = Services.ActiveApp ? Services.ActiveApp.pid : 0
            root.pid = nextPid
            if (nextPid > 0 && root.menuCache[nextPid]) {
                const cached = root.menuCache[nextPid]
                root.model = cached.items
                root.source = cached.source
                root.available = cached.available
            } else {
                root.model = []
                root.source = ""
                root.available = false
            }
            activeAppDebounce.restart()
        }
        function onWindowTitleChanged() {
            if (!root.available) {
                titleRefreshDebounce.restart()
            }
        }
    }

    Component.onCompleted: {
        if (Services.ActiveApp && Services.ActiveApp.pid > 0) {
            root.request(Services.ActiveApp.pid)
        }
    }
}
