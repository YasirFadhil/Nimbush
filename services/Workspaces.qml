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

    // ---- live updates via hyprland event socket ----
    // Event names/payloads per Hyprland IPC docs (0.55+). If these stop
    // matching (Hyprland bumps event format), check `hyprctl` docs or
    // `socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/.../.socket2.sock`
    // manually to see the raw event lines.
    Process {
    id: socatProc
    command: ["sh", "-c", "socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"]
    running: true
    stdout: SplitParser {
        splitMarker: "\n"
        onRead: data => {
            const line = data.trim()
            console.log("[Workspaces] event:", line)

            if (line.startsWith("workspacev2>>")) {
                const parts = line.substring("workspacev2>>".length).split(",")
                root.activeWorkspaceId = parseInt(parts[0])
                root.activeWorkspaceName = parts[0]
            } else if (line.startsWith("createworkspacev2>>") || line.startsWith("destroyworkspacev2>>")) {
                root.refreshWorkspaceList()
            } else if (line.startsWith("activewindow>>")) {
                const rest = line.substring("activewindow>>".length)
                const commaIdx = rest.indexOf(",")
                root.activeWindowTitle = commaIdx >= 0 ? rest.substring(commaIdx + 1) : ""
            }
        }
    }
    stderr: SplitParser {
        onRead: data => console.warn("[Workspaces] socat stderr:", data)
    }
    onExited: (exitCode) => console.warn("[Workspaces] socat process exited, code:", exitCode)
}
}
