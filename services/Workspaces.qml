pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tracks active workspace, full workspace list, and active window title.
// Supports both Hyprland and Niri compositors automatically.
Singleton {
    id: root

    property int activeWorkspaceId: 1
    property string activeWorkspaceName: "1"
    property var workspaceIds: []       // sorted array of int workspace ids currently open
    property string activeWindowTitle: ""

    // "hyprland", "niri", or "auto"
    property string detectedCompositor: {
        const niriSock = Quickshell.env("NIRI_SOCKET") || ""
        const hyprSig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        const desktop = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
        if (niriSock !== "" || desktop.includes("niri")) return "niri"
        if (hyprSig !== "" || desktop.includes("hyprland")) return "hyprland"
        return "auto"
    }

    function isNiri() {
        return root.detectedCompositor === "niri"
    }

    function refreshWorkspaceList() {
        if (isNiri()) {
            niriListProc.output = ""
            niriListProc.running = true
        } else {
            listProc.output = ""
            listProc.running = true
        }
    }

    function refreshActiveWindow() {
        if (isNiri()) {
            niriWindowProc.output = ""
            niriWindowProc.running = true
        } else {
            windowProc.output = ""
            windowProc.running = true
        }
    }

    function switchTo(id) {
        if (switchProc.running) {
            switchProc.running = false
        }
        if (isNiri()) {
            switchProc.command = ["niri", "msg", "action", "focus-workspace", String(id)]
        } else {
            switchProc.command = ["hyprctl", "dispatch", "workspace", String(id)]
        }
        switchProc.running = true
        root.activeWorkspaceId = parseInt(id) || root.activeWorkspaceId
        root.activeWorkspaceName = String(id)
    }

    Process {
        id: switchProc
        running: false
    }

    // Fallback compositor auto-detection process if env variables are not present
    Process {
        id: detectProc
        command: ["sh", "-c", "if [ -n \"$NIRI_SOCKET\" ] || command -v niri &>/dev/null; then echo 'niri'; else echo 'hyprland'; fi"]
        running: root.detectedCompositor === "auto"
        stdout: SplitParser {
            onRead: data => {
                const comp = data.trim()
                if (comp === "niri" || comp === "hyprland") {
                    root.detectedCompositor = comp
                }
            }
        }
    }

    // ---- Hyprland Processes ----

    Process {
        id: initProc
        command: ["hyprctl", "activeworkspace", "-j"]
        running: root.detectedCompositor === "hyprland"
        property string output: ""
        stdout: SplitParser {
            onRead: data => initProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(initProc.output)
                root.activeWorkspaceId = data.id
                root.activeWorkspaceName = String(data.id)
            } catch (e) {}
        }
    }

    Process {
        id: listProc
        command: ["hyprctl", "workspaces", "-j"]
        running: root.detectedCompositor === "hyprland"
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
        running: root.detectedCompositor === "hyprland"
        property string output: ""
        stdout: SplitParser {
            onRead: data => windowProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(windowProc.output)
                root.activeWindowTitle = data.title || ""
            } catch (e) {
                root.activeWindowTitle = ""
            }
            windowProc.output = ""
        }
    }

    // ---- Hyprland live updates via event socket ----
    Process {
        id: socatProc
        command: ["sh", "-c", "socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"]
        running: root.detectedCompositor === "hyprland"
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = data.trim()
                if (!line) return

                if (line.startsWith("workspacev2>>")) {
                    const parts = line.substring("workspacev2>>".length).split(",")
                    root.activeWorkspaceId = parseInt(parts[0]) || 1
                    root.activeWorkspaceName = parts[0]
                    root.refreshActiveWindow()
                } else if (line.startsWith("workspace>>")) {
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
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {}
        }
        onExited: (exitCode) => console.warn("[Workspaces] Hyprland socat process exited, code:", exitCode)
    }

    // ---- Niri Processes ----

    Process {
        id: niriListProc
        command: ["niri", "msg", "-j", "workspaces"]
        running: root.detectedCompositor === "niri"
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
        running: root.detectedCompositor === "niri"
        property string output: ""
        stdout: SplitParser {
            onRead: data => niriWindowProc.output += data
        }
        onExited: {
            try {
                const data = JSON.parse(niriWindowProc.output)
                root.activeWindowTitle = (data && data.title) ? data.title : ""
            } catch (e) {
                root.activeWindowTitle = ""
            }
            niriWindowProc.output = ""
        }
    }

    // ---- Niri live event stream ----
    Process {
        id: niriEventProc
        command: ["niri", "msg", "-j", "event-stream"]
        running: root.detectedCompositor === "niri"
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
        stderr: SplitParser {
            onRead: data => {}
        }
        onExited: (exitCode) => console.warn("[Workspaces] Niri event-stream process exited, code:", exitCode)
    }
}

