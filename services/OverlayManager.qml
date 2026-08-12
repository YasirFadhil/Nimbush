pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    property var _windows: []
    property bool controlCenterVisible: false
    property bool wifiPanelVisible: false
    property bool btPanelVisible: false
    property bool audioPanelVisible: false
    property bool calendarVisible: false

    signal launcherToggleRequested()

    function register(win) {
        _windows.push(win)
    }

    // except bisa berupa window object (PowerMenu/Launcher/NotifCenter dst)
    // ATAU string id ("controlCenter"/"calendar"/"notifCenter") — dicocokkan
    // ke property overlayId kalau window itu punya.
    function closeAllExcept(except) {
        for (let i = 0; i < _windows.length; i++) {
            const w = _windows[i]
            const isExcepted = (w === except) || (w.overlayId !== undefined && w.overlayId === except)
            if (!isExcepted && w.visible) {
                w.hide()
            }
        }
        if (except !== "controlCenter") {
            controlCenterVisible = false
            wifiPanelVisible = false
            btPanelVisible = false
            audioPanelVisible = false
        }
        if (except !== "calendar") {
            calendarVisible = false
        }
    }
}
