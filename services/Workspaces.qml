pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

// Tracks active workspace, full workspace list, and active window title.
// Supports both Niri and Hyprland compositors automatically.
Singleton {
    id: root

    property int activeWorkspaceId: 1
    property string activeWorkspaceName: "1"
    property var workspaceIds: []       // sorted array of int workspace ids currently open
    property string activeWindowTitle: ""
    property bool isFullscreen: false

    readonly property string detectedCompositor: {
        if (Services.Compositor && Services.Compositor.activeCompositor)
            return Services.Compositor.activeCompositor
        const niriSock = Quickshell.env("NIRI_SOCKET") || ""
        const hyprSig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        const desktop = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
        if (niriSock !== "" || desktop.includes("niri")) return "niri"
        if (hyprSig !== "" || desktop.includes("hyprland")) return "hyprland"
        return "niri"
    }

    function isNiri() {
        return root.detectedCompositor === "niri"
    }

    // ── Sync from Niri (via native QML NiriService or CLI fallback) ───────────
    function syncFromNiri() {
        const service = Services.NiriService
        if (service && service.connected) {
            const workspaces = service.workspaces || []
            const indexes = []
            for (let i = 0; i < workspaces.length; i++) {
                const index = Number(workspaces[i].index)
                if (Number.isFinite(index) && index > 0 && !indexes.includes(index)) indexes.push(index)
            }
            indexes.sort((a, b) => a - b)
            root.workspaceIds = indexes

            const focused = workspaces.find(ws => ws.isFocused) || workspaces.find(ws => ws.isActive)
            if (focused) {
                root.activeWorkspaceId = Number(focused.index) || 1
                root.activeWorkspaceName = focused.name || String(root.activeWorkspaceId)
            }

            const window = service.focusedWindow
            root.activeWindowTitle = window ? String(window.title || "") : ""
            return
        }

        // Fallback to CLI queries if NiriService is not yet connected
        if (isNiri()) {
            refreshWorkspaceList()
            refreshActiveWindow()
        }
    }

    function refreshWorkspaceList() {
        if (isNiri()) {
            if (Services.NiriService && Services.NiriService.connected) {
                Services.NiriService.refreshWorkspaces()
            } else if (!niriListProc.running) {
                niriListProc.output = ""
                niriListProc.running = true
            }
        } else {
            if (!listProc.running) {
                listProc.output = ""
                listProc.running = true
            }
        }
    }

    function refreshActiveWindow() {
        if (isNiri()) {
            if (Services.NiriService && Services.NiriService.connected) {
                const window = Services.NiriService.focusedWindow
                root.activeWindowTitle = window ? String(window.title || "") : ""
            } else if (!niriWindowProc.running) {
                niriWindowProc.output = ""
                niriWindowProc.running = true
            }
        } else {
            if (!windowProc.running) {
                windowProc.output = ""
                windowProc.running = true
            }
        }
    }

    function switchTo(id) {
        if (isNiri()) {
            if (Services.NiriService && Services.NiriService.connected) {
                Services.NiriService.focusWorkspaceIndex(id)
                root.activeWorkspaceId = parseInt(id) || root.activeWorkspaceId
                root.activeWorkspaceName = String(id)
                return
            }
            if (switchProc.running) switchProc.running = false
            switchProc.command = ["niri", "msg", "action", "focus-workspace", String(id)]
            switchProc.running = true
            root.activeWorkspaceId = parseInt(id) || root.activeWorkspaceId
            root.activeWorkspaceName = String(id)
        } else {
            if (switchProc.running) switchProc.running = false
            const n = parseInt(id)
            const arg = (String(n) === String(id)) ? String(n) : JSON.stringify(String(id))
            switchProc.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + arg + " })"]
            switchProc.running = true
        }
    }

    Process {
        id: switchProc
        running: false
        property string out: ""
        stdout: SplitParser { onRead: d => switchProc.out += d }
        stderr: SplitParser { onRead: d => switchProc.out += d }
        onExited: (code) => {
            const o = switchProc.out.trim()
            if (code !== 0 && isNiri()) {
                // Fallback for older Niri or numeric switch
                niriSwitchFallback.command = ["niri", "msg", "action", "focus-workspace", String(root.activeWorkspaceId)]
                niriSwitchFallback.running = true
            }
            switchProc.out = ""
        }
    }

    Process {
        id: niriSwitchFallback
        running: false
    }

    // ── NiriService Reactive Connections ─────────────────────────────────────
    Connections {
        target: Services.NiriService || null
        function onWorkspacesChanged() { if (root.isNiri()) root.syncFromNiri() }
        function onRunningWindowsChanged() { if (root.isNiri()) root.syncFromNiri() }
        function onFocusedWindowChanged() { if (root.isNiri()) root.syncFromNiri() }
        function onConnectedChanged() { if (root.isNiri()) root.syncFromNiri() }
    }

    // ── Niri Fallback Processes (Active when NiriService is unavailable) ──────
    Process {
        id: niriListProc
        command: ["niri", "msg", "-j", "workspaces"]
        running: root.isNiri() && (!Services.NiriService || !Services.NiriService.connected)
        property string output: ""
        stdout: SplitParser {
            onRead: data => niriListProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(niriListProc.output)
                if (Array.isArray(data)) {
                    root.workspaceIds = data.map(w => w.idx || w.id).sort((a, b) => a - b)
                    const activeWs = data.find(w => w.is_focused || w.is_active)
                    if (activeWs) {
                        const wsId = activeWs.idx || activeWs.id
                        root.activeWorkspaceId = wsId
                        root.activeWorkspaceName = activeWs.name || String(wsId)
                    }
                }
            } catch (e) {}
            niriListProc.output = ""
        }
    }

    Process {
        id: niriWindowProc
        command: ["niri", "msg", "-j", "focused-window"]
        running: root.isNiri() && (!Services.NiriService || !Services.NiriService.connected)
        property string output: ""
        stdout: SplitParser {
            onRead: data => niriWindowProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(niriWindowProc.output)
                root.activeWindowTitle = (data && data.title) ? data.title : ""
                if (data && data.is_fullscreen !== undefined) {
                    root.isFullscreen = Boolean(data.is_fullscreen)
                }
            } catch (e) {
                root.activeWindowTitle = ""
                root.isFullscreen = false
            }
            niriWindowProc.output = ""
        }
    }

    Process {
        id: niriEventProc
        command: ["niri", "msg", "-j", "event-stream"]
        running: root.isNiri() && (!Services.NiriService || !Services.NiriService.connected)
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = data.trim()
                if (!line) return
                try {
                    const evt = JSON.parse(line)
                    if (evt.WorkspacesChanged) {
                        root.refreshWorkspaceList()
                        root.refreshActiveWindow()
                    } else if (evt.WorkspaceActivated) {
                        const wsId = evt.WorkspaceActivated.idx || evt.WorkspaceActivated.id
                        if (wsId !== undefined) {
                            root.activeWorkspaceId = wsId
                            root.activeWorkspaceName = String(wsId)
                        }
                        root.refreshActiveWindow()
                    } else if (evt.WindowFocusChanged || evt.WindowOpenedOrChanged || evt.WindowClosed) {
                        root.refreshActiveWindow()
                    }
                } catch (e) {}
            }
        }
    }

    // ── Hyprland Queries & Socket2 Listener ──────────────────────────────────
    Process {
        id: initProc
        command: ["hyprctl", "activeworkspace", "-j"]
        running: !root.isNiri()
        property string output: ""
        stdout: SplitParser {
            onRead: data => initProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(initProc.output)
                root.activeWorkspaceId = data.id
                root.activeWorkspaceName = String(data.id)
                if (data.hasfullscreen !== undefined) {
                    root.isFullscreen = Boolean(data.hasfullscreen)
                }
            } catch (e) {}
        }
    }

    Process {
        id: listProc
        command: ["hyprctl", "workspaces", "-j"]
        running: !root.isNiri()
        property string output: ""
        stdout: SplitParser {
            onRead: data => listProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(listProc.output)
                root.workspaceIds = data.map(w => w.id).sort((a, b) => a - b)
            } catch (e) {}
            listProc.output = ""
        }
    }

    Process {
        id: windowProc
        command: ["hyprctl", "activewindow", "-j"]
        running: !root.isNiri()
        property string output: ""
        stdout: SplitParser {
            onRead: data => windowProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(windowProc.output)
                root.activeWindowTitle = data.title || ""
                if (data.fullscreen !== undefined) {
                    root.isFullscreen = Boolean(data.fullscreen)
                }
            } catch (e) {
                root.activeWindowTitle = ""
            }
            windowProc.output = ""
        }
    }

    // Hyprland live event stream via socket2
    Process {
        id: socatProc
        command: ["sh", "-c", "exec socat -U - UNIX-CONNECT:\"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock\""]
        running: !root.isNiri() && Boolean(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = data.trim()
                if (!line) return
                if (line.startsWith("workspace>>")) {
                    const ws = line.substring("workspace>>".length)
                    root.activeWorkspaceId = parseInt(ws) || 1
                    root.activeWorkspaceName = ws
                    root.refreshActiveWindow()
                } else if (line.startsWith("focusedmon>>")) {
                    const parts = line.substring("focusedmon>>".length).split(",")
                    if (parts.length > 1) {
                        root.activeWorkspaceId = parseInt(parts[1]) || 1
                        root.activeWorkspaceName = parts[1]
                        root.refreshActiveWindow()
                    }
                } else if (line.startsWith("createworkspacev2>>") || line.startsWith("createworkspace>>")
                        || line.startsWith("destroyworkspacev2>>") || line.startsWith("destroyworkspace>>")
                        || line.startsWith("renameworkspace>>")) {
                    root.refreshWorkspaceList()
                } else if (line.startsWith("activewindow>>")) {
                    const rest = line.substring("activewindow>>".length)
                    const commaIdx = rest.indexOf(",")
                    root.activeWindowTitle = commaIdx >= 0 ? rest.substring(commaIdx + 1) : ""
                } else if (line.startsWith("activewindowv2>>")) {
                    root.refreshActiveWindow()
                } else if (line.startsWith("fullscreen>>")) {
                    const fsVal = line.substring("fullscreen>>".length).trim()
                    root.isFullscreen = (fsVal === "1" || fsVal === "2" || fsVal === "true")
                }
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            if (root.isNiri()) {
                root.syncFromNiri()
            } else {
                root.refreshWorkspaceList()
                root.refreshActiveWindow()
            }
        })
    }
}
