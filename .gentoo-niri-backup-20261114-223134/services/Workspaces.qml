pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

// Tracks active workspace, full workspace list, and active window title.
// Hyprland keeps its existing IPC/socket backend; Niri uses qml-niri.
Singleton {
    id: root

    property int activeWorkspaceId: 1
    property string activeWorkspaceName: "1"
    property var workspaceIds: []
    property string activeWindowTitle: ""
    property bool isFullscreen: false

    readonly property string detectedCompositor: {
        const niriSock = Quickshell.env("NIRI_SOCKET") || ""
        const hyprSig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        const desktop = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
        const session = (Quickshell.env("DESKTOP_SESSION") || "").toLowerCase()

        // Prefer the live compositor socket/signature over installed binaries.
        if (niriSock !== "" || desktop.includes("niri") || session.includes("niri")) return "niri"
        if (hyprSig !== "" || desktop.includes("hyprland") || session.includes("hyprland")) return "hyprland"
        return "unknown"
    }

    function isNiri() {
        return root.detectedCompositor === "niri"
    }

    function isHyprland() {
        return root.detectedCompositor === "hyprland"
    }

    function _syncNiriState() {
        if (!isNiri()) return
        const niri = Services.NiriService
        root.workspaceIds = niri.workspaceIds ? niri.workspaceIds.slice() : []
        root.activeWorkspaceId = niri.activeWorkspaceId || 1
        root.activeWorkspaceName = niri.activeWorkspaceName || String(root.activeWorkspaceId)
        root.activeWindowTitle = niri.activeWindowTitle || ""
        root.isFullscreen = niri.isFullscreen
    }

    function refreshWorkspaceList() {
        if (isNiri()) {
            _syncNiriState()
        } else if (isHyprland()) {
            listProc.output = ""
            listProc.running = true
        }
    }

    function refreshActiveWindow() {
        if (isNiri()) {
            _syncNiriState()
        } else if (isHyprland()) {
            windowProc.output = ""
            windowProc.running = true
        }
    }

    function switchTo(id) {
        if (isNiri()) {
            if (!Services.NiriService.focusWorkspace(Number(id))) {
                console.warn("[Workspaces] Niri workspace switch failed:", id)
            }
            return
        }

        if (!isHyprland()) return
        if (switchProc.running) switchProc.running = false

        // Hyprland 0.55+: dispatch = one Lua expression (hl.dsp.*).
        // Let socket2 events update the indicator instead of optimistic state.
        const n = parseInt(id)
        const arg = (String(n) === String(id)) ? String(n) : JSON.stringify(String(id))
        switchProc.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + arg + " })"]
        switchProc.running = true
    }

    Connections {
        target: Services.NiriService
        function onStateChanged() { root._syncNiriState() }
    }

    Component.onCompleted: {
        if (isNiri()) _syncNiriState()
    }

    Process {
        id: switchProc
        running: false
        property string out: ""
        stdout: SplitParser { onRead: d => switchProc.out += d }
        stderr: SplitParser { onRead: d => switchProc.out += d }
        onExited: (code) => {
            const output = switchProc.out.trim()
            if (code !== 0 || (output.length > 0 && output !== "ok"))
                console.warn("[Workspaces] switch failed:", switchProc.command.join(" "), "->", output)
            switchProc.out = ""
        }
    }

    // ---- Hyprland initial state ----
    Process {
        id: initProc
        command: ["hyprctl", "activeworkspace", "-j"]
        running: root.isHyprland()
        property string output: ""
        stdout: SplitParser { onRead: data => initProc.output += data }
        onExited: {
            try {
                const data = JSON.parse(initProc.output)
                root.activeWorkspaceId = data.id
                root.activeWorkspaceName = String(data.id)
                if (data.hasfullscreen !== undefined) root.isFullscreen = Boolean(data.hasfullscreen)
            } catch (e) {
                console.warn("[Workspaces] Unable to parse Hyprland active workspace:", e)
            }
            initProc.output = ""
        }
    }

    Process {
        id: listProc
        command: ["hyprctl", "workspaces", "-j"]
        running: root.isHyprland()
        property string output: ""
        stdout: SplitParser { onRead: data => listProc.output += data }
        onExited: {
            try {
                const data = JSON.parse(listProc.output)
                root.workspaceIds = data.map(w => w.id).sort((a, b) => a - b)
            } catch (e) {
                console.warn("[Workspaces] Unable to parse Hyprland workspaces:", e)
            }
            listProc.output = ""
        }
    }

    Process {
        id: windowProc
        command: ["hyprctl", "activewindow", "-j"]
        running: root.isHyprland()
        property string output: ""
        stdout: SplitParser { onRead: data => windowProc.output += data }
        onExited: {
            try {
                const data = JSON.parse(windowProc.output)
                root.activeWindowTitle = data.title || ""
                root.isFullscreen = Boolean(data.fullscreen && data.fullscreen > 0)
            } catch (e) {
                root.activeWindowTitle = ""
                root.isFullscreen = false
            }
            windowProc.output = ""
        }
    }

    // ---- Hyprland live updates via socket2 ----
    Process {
        id: socatProc
        command: ["sh", "-c", "socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"]
        running: root.isHyprland()
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
                    const workspace = line.substring("workspace>>".length)
                    root.activeWorkspaceId = parseInt(workspace) || 1
                    root.activeWorkspaceName = workspace
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
                    const commaIndex = rest.indexOf(",")
                    root.activeWindowTitle = commaIndex >= 0 ? rest.substring(commaIndex + 1) : ""
                } else if (line.startsWith("activewindowv2>>")) {
                    root.refreshActiveWindow()
                } else if (line.startsWith("fullscreen>>")) {
                    const value = line.substring("fullscreen>>".length).trim()
                    root.isFullscreen = value === "1" || value === "2" || value === "true"
                }
            }
        }
        stderr: SplitParser { onRead: data => {} }
        onExited: (exitCode) => console.warn("[Workspaces] Hyprland socket process exited, code:", exitCode)
    }
}
