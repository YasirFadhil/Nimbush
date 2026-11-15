import QtQuick
import QtQml.Models
import Niri

// Loaded lazily by NiriService only when NIRI_SOCKET is present.
// Keeping this import in a separately loaded file preserves Hyprland-only
// installations that do not have the qml-niri plugin installed.
Item {
    id: root

    visible: false

    property bool connected: false
    property var workspaceIds: []
    property int activeWorkspaceId: 1
    property string activeWorkspaceName: "1"
    property string activeWindowTitle: ""
    property string activeWindowAddress: ""
    property string activeWindowClass: ""
    property bool isFullscreen: false
    property var runningWindows: []

    signal backendUpdated()

    function scheduleSync() {
        syncTimer.restart()
    }

    function syncWorkspaces() {
        const ids = []
        let focusedWorkspace = null

        for (let i = 0; i < niri.workspaces.count; i++) {
            const workspace = niri.workspaces.get(i)
            if (!workspace) continue

            // Niri workspace indices are the 1-based workspace numbers used
            // by Nimbush's existing workspace indicator.
            const index = Number(workspace.index)
            if (Number.isFinite(index) && index > 0 && !ids.includes(index)) {
                ids.push(index)
            }

            if (workspace.isFocused) focusedWorkspace = workspace
        }

        ids.sort((a, b) => a - b)
        root.workspaceIds = ids

        if (focusedWorkspace) {
            const index = Number(focusedWorkspace.index)
            root.activeWorkspaceId = Number.isFinite(index) && index > 0 ? index : 1
            root.activeWorkspaceName = focusedWorkspace.name
                ? String(focusedWorkspace.name)
                : String(root.activeWorkspaceId)
        }
    }

    function syncFocusedWindow() {
        const focused = niri.focusedWindow
        if (focused) {
            root.activeWindowAddress = String(focused.id)
            root.activeWindowClass = focused.appId || ""
            root.activeWindowTitle = focused.title || ""
        } else {
            root.activeWindowAddress = ""
            root.activeWindowClass = ""
            root.activeWindowTitle = ""
        }

        // qml-niri 0.4.0 does not expose a fullscreen role on Window.
        // Do not infer fullscreen state from a property that is not available.
        root.isFullscreen = false
    }

    function syncWindows() {
        const windows = []

        for (let i = 0; i < windowInstantiator.count; i++) {
            const delegate = windowInstantiator.objectAt(i)
            if (delegate && delegate.snapshot && delegate.snapshot.class) windows.push(delegate.snapshot)
        }

        root.runningWindows = windows
        syncFocusedWindow()
        syncWorkspaces()
        root.backendUpdated()
    }

    function syncAll() {
        syncWindows()
    }

    function focusWorkspace(index) {
        const workspaceIndex = Number(index)
        if (!Number.isInteger(workspaceIndex) || workspaceIndex < 1) return false

        const result = niri.focusWorkspace(workspaceIndex)
        if (!result.ok) {
            console.warn("[NiriBackend] focus workspace failed:", result.error || "unknown error")
            return false
        }
        return true
    }

    function focusWindow(id) {
        const windowId = Number(id)
        if (!Number.isFinite(windowId) || windowId <= 0) return false

        const result = niri.focusWindow(windowId)
        if (!result.ok) {
            console.warn("[NiriBackend] focus window failed:", result.error || "unknown error")
            return false
        }
        return true
    }

    function closeWindow(id) {
        const windowId = Number(id)
        if (!Number.isFinite(windowId) || windowId <= 0) return false

        const result = niri.closeWindow(windowId)
        if (!result.ok) {
            console.warn("[NiriBackend] close window failed:", result.error || "unknown error")
            return false
        }
        return true
    }

    Niri {
        id: niri

        Component.onCompleted: connect()

        onConnected: {
            root.connected = true
            root.scheduleSync()
        }

        onDisconnected: {
            root.connected = false
            root.workspaceIds = []
            root.runningWindows = []
            root.activeWindowAddress = ""
            root.activeWindowClass = ""
            root.activeWindowTitle = ""
            root.backendUpdated()
        }

        onErrorOccurred: function(error) {
            console.warn("[NiriBackend] IPC error:", error)
        }

        onRawEventReceived: root.scheduleSync()
        onFocusedWindowChanged: root.scheduleSync()
    }

    Connections {
        target: niri.workspaces
        function onCountChanged() { root.scheduleSync() }
        function onDataChanged() { root.scheduleSync() }
        function onRowsInserted() { root.scheduleSync() }
        function onRowsRemoved() { root.scheduleSync() }
        function onModelReset() { root.scheduleSync() }
    }

    Connections {
        target: niri.windows
        function onCountChanged() { root.scheduleSync() }
        function onDataChanged() { root.scheduleSync() }
        function onRowsInserted() { root.scheduleSync() }
        function onRowsRemoved() { root.scheduleSync() }
        function onModelReset() { root.scheduleSync() }
    }

    // Instantiator turns qml-niri's QAbstractListModel roles into plain
    // JavaScript window records consumed by the existing DockService matcher.
    Instantiator {
        id: windowInstantiator
        model: niri.windows

        delegate: QtObject {
            property var snapshot: ({
                address: String(model.id),
                class: String(model.appId || ""),
                initialClass: String(model.appId || ""),
                title: String(model.title || ""),
                pid: Number(model.pid),
                workspaceId: Number(model.workspaceId),
                mapped: true,
                hidden: false,
                isFocused: Boolean(model.isFocused),
                isFloating: Boolean(model.isFloating),
                isUrgent: Boolean(model.isUrgent),
                iconPath: String(model.iconPath || ""),
                focusHistoryID: model.isFocused ? 0 : Number(model.id)
            })

            onSnapshotChanged: root.scheduleSync()
        }

        onObjectAdded: root.scheduleSync()
        onObjectRemoved: root.scheduleSync()
    }

    Timer {
        id: syncTimer
        interval: 0
        repeat: false
        onTriggered: root.syncAll()
    }
}
