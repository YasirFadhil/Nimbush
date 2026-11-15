pragma Singleton
import QtQuick
import Quickshell

// Shared compositor-facing API for Nimbush services.
// The qml-niri plugin is loaded only in a Niri session so Hyprland systems
// do not need qml-niri installed.
Singleton {
    id: root

    readonly property bool available: (Quickshell.env("NIRI_SOCKET") || "") !== ""
    readonly property bool connected: backendLoader.item ? backendLoader.item.connected : false
    readonly property var workspaceIds: backendLoader.item ? backendLoader.item.workspaceIds : []
    readonly property int activeWorkspaceId: backendLoader.item ? backendLoader.item.activeWorkspaceId : 1
    readonly property string activeWorkspaceName: backendLoader.item ? backendLoader.item.activeWorkspaceName : "1"
    readonly property string activeWindowTitle: backendLoader.item ? backendLoader.item.activeWindowTitle : ""
    readonly property string activeWindowAddress: backendLoader.item ? backendLoader.item.activeWindowAddress : ""
    readonly property string activeWindowClass: backendLoader.item ? backendLoader.item.activeWindowClass : ""
    readonly property bool isFullscreen: backendLoader.item ? backendLoader.item.isFullscreen : false
    readonly property var runningWindows: backendLoader.item ? backendLoader.item.runningWindows : []

    signal stateChanged()

    Loader {
        id: backendLoader
        active: root.available
        source: Qt.resolvedUrl("NiriBackend.qml")

        onLoaded: root.stateChanged()
        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("[NiriService] Failed to load Niri backend. Check qml-niri installation and library paths.")
            }
        }
    }

    Connections {
        target: backendLoader.item
        function onStateChanged() { root.stateChanged() }
        function onConnectedChanged() { root.stateChanged() }
    }

    function focusWorkspace(index) {
        return backendLoader.item ? backendLoader.item.focusWorkspace(index) : false
    }

    function focusWindow(id) {
        return backendLoader.item ? backendLoader.item.focusWindow(id) : false
    }

    function closeWindow(id) {
        return backendLoader.item ? backendLoader.item.closeWindow(id) : false
    }
}
