pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tracks active workspace, full workspace list, and active window title.
// Used by modules/bar/components/LeftSection.qml for the macOS-style
// full-width bar (logo -> workspace pills -> window title).
Singleton {
    id: root

    property int activeWorkspaceId: 1
    property string activeWorkspaceName: "1"
    property var workspaceIds: []       // sorted array of int workspace ids currently open
    property string activeWindowTitle: ""

    function refreshWorkspaceList() {
        listProc.output = ""
        listProc.running = true
    }

    // ---- initial state ----

    Process {
        id: initProc
        command: ["hyprctl", "activeworkspace", "-j"]
        running: true
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
        running: true
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
        running: true
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

    function switchTo(id) {
        switchProc.command = ["hyprctl", "dispatch", "workspace", '"' + id + '"']
        switchProc.running = true
        root.activeWorkspaceId = id
        root.activeWorkspaceName = String(id)
    }

    Process {
        id: switchProc
        running: false
    }

    function refreshActiveWindow() {
        windowProc.output = ""
        windowProc.running = true
    }

    // ---- live updates via hyprland event socket ----
    Process {
        id: socatProc
        command: ["sh", "-c", "socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"]
        running: true
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
        onExited: (exitCode) => console.warn("[Workspaces] socat process exited, code:", exitCode)
    }
}
