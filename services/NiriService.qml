pragma Singleton
import QtQuick
import QtQml.Models
import Quickshell
import Niri

Singleton {
    id: root

    readonly property bool available: (Quickshell.env("NIRI_SOCKET") || "").length > 0
    property bool connected: false
    readonly property var focusedWindow: niri.focusedWindow
    property var workspaces: []
    property var runningWindows: []

    function _actionResult(label, result) {
        if (!result || !result.ok) {
            console.warn("[NiriService]", label, "failed:", result && result.error ? result.error : "unknown error")
            return false
        }
        return true
    }

    function refreshWorkspaces() {
        if (!root.connected) return

        const next = []
        for (let i = 0; i < niri.workspaces.count; i++) {
            const ws = niri.workspaces.get(i)
            if (!ws || ws.id === undefined) continue
            next.push({
                id: Number(ws.id),
                index: Number(ws.index),
                name: String(ws.name || ""),
                output: String(ws.output || ""),
                isActive: Boolean(ws.isActive),
                isFocused: Boolean(ws.isFocused),
                isUrgent: Boolean(ws.isUrgent),
                activeWindowId: Number(ws.activeWindowId || 0)
            })
        }
        root.workspaces = next
    }

    function refreshWindows() {
        if (!root.connected) {
            root.runningWindows = []
            return
        }

        const next = []
        for (let i = 0; i < windowObjects.count; i++) {
            const item = windowObjects.objectAt(i)
            if (item && item.snapshot && item.snapshot.address) next.push(item.snapshot)
        }
        root.runningWindows = next
    }

    function refreshAll() {
        if (!root.connected) return
        root.refreshWorkspaces()
        root.refreshWindows()
    }

    function focusWorkspaceIndex(index) {
        const wanted = Number(index)
        if (!Number.isFinite(wanted)) return false

        const focusedWorkspace = root.workspaces.find(ws => ws.isFocused)
        const focusedOutput = focusedWorkspace ? focusedWorkspace.output : ""
        let target = root.workspaces.find(ws => ws.index === wanted && (!focusedOutput || ws.output === focusedOutput))
        if (!target) target = root.workspaces.find(ws => ws.index === wanted)

        const result = target
            ? niri.focusWorkspaceById(target.id)
            : niri.focusWorkspace(wanted)
        return root._actionResult("focus workspace " + wanted, result)
    }

    function _windowId(value) {
        const text = String(value || "").trim()
        if (!text) return 0
        const id = text.startsWith("0x") ? parseInt(text, 16) : Number(text)
        return Number.isFinite(id) && id > 0 ? id : 0
    }

    function focusWindow(address) {
        const id = root._windowId(address)
        if (!id) return false
        return root._actionResult("focus window " + id, niri.focusWindow(id))
    }

    function closeWindow(address) {
        const id = root._windowId(address)
        if (!id) return false
        return root._actionResult("close window " + id, niri.closeWindow(id))
    }

    function launchDesktopId(desktopId) {
        const appId = String(desktopId || "").trim().replace(/\.desktop$/i, "")
        if (!appId) return
        // Applications normally launch through the DesktopEntry object. This is
        // the fallback for entries that could not be resolved by the index.
        Quickshell.execDetached(["gtk-launch", appId])
    }

    Niri {
        id: niri

        Component.onCompleted: {
            if (root.available) {
                if (!connect()) console.warn("[NiriService] Initial IPC connection did not start")
            } else {
                console.warn("[NiriService] NIRI_SOCKET is missing; Niri backend is unavailable")
            }
        }

        onConnected: {
            root.connected = true
            console.info("[NiriService] Connected to Niri IPC")
            Qt.callLater(root.refreshAll)
        }

        onDisconnected: {
            root.connected = false
            root.workspaces = []
            root.runningWindows = []
            console.warn("[NiriService] Disconnected from Niri IPC")
        }

        onErrorOccurred: function(error) {
            root.connected = false
            console.warn("[NiriService] IPC error:", error)
        }

        // The plugin emits this before its models process the same event.
        // callLater lets the model finish its synchronous update first.
        onRawEventReceived: Qt.callLater(root.refreshAll)
        onFocusedWindowChanged: Qt.callLater(root.refreshWindows)
    }

    Instantiator {
        id: windowObjects
        model: niri.windows

        delegate: QtObject {
            property var windowId: model.id
            property string windowTitle: model.title || ""
            property string appId: model.appId || ""
            property int processId: model.pid
            property var workspaceId: model.workspaceId
            property bool focused: model.isFocused
            property bool floating: model.isFloating

            readonly property var snapshot: ({
                id: Number(windowId),
                address: String(windowId),
                class: String(appId),
                initialClass: String(appId),
                appId: String(appId),
                title: String(windowTitle),
                pid: Number(processId),
                workspaceId: String(workspaceId),
                isFocused: Boolean(focused),
                isFloating: Boolean(floating),
                mapped: true,
                hidden: false,
                focusHistoryID: focused ? 0 : Number(windowId)
            })
        }

        onObjectAdded: Qt.callLater(root.refreshWindows)
        onObjectRemoved: Qt.callLater(root.refreshWindows)
    }

    Connections {
        target: niri.workspaces
        function onCountChanged() { Qt.callLater(root.refreshWorkspaces) }
        function onDataChanged() { Qt.callLater(root.refreshWorkspaces) }
    }

    Connections {
        target: niri.windows
        function onCountChanged() { Qt.callLater(root.refreshWindows) }
        function onFocusedWindowChanged() { Qt.callLater(root.refreshWindows) }
        function onDataChanged() { Qt.callLater(root.refreshWindows) }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.available && !root.connected
        onTriggered: {
            if (!niri.isConnected()) niri.connect()
        }
    }
}
