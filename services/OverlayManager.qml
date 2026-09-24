pragma Singleton
import Quickshell
import QtQuick
import "." as Services

Singleton {
    id: root
    property var _windows: []
    property bool isLocked: false
    // ── Lockscreen / Desktop Bridge State ──
    property bool isUnlockingWithGenie: false
    property real unlockSuctionProgress: 0.0
    property bool lockVerified: false
    property bool isLockAbsorbing: false
    property bool desktopIslandIsWide: false
    // ── Seamless Island / Bar Bridge (0.0 = fully locked/hidden, 1.0 = fully desktop) ──
    // Bar writes this; lockscreen reads it to phase-sync its island & status pill
    property real barIslandProgress: 0.0
    property bool wizardOpen: false
    readonly property bool isWizardActive: wizardOpen || (Services.Config ? !Services.Config.firstRunCompleted : false)
    property bool controlCenterVisible: false
    property bool wifiPanelVisible: false
    property bool btPanelVisible: false
    property bool audioPanelVisible: false
    property bool updatePanelVisible: false
    property bool calendarVisible: false
    property bool batteryPanelVisible: false
    property bool volumePanelVisible: false
    property bool sysmonPanelVisible: false
    property bool identifyMonitorsActive: false
    property real batteryTargetX: -1
    property real volumeTargetX: -1
    property real sysmonTargetX: -1

    signal launcherToggleRequested()
    signal dashboardToggleRequested()
    signal settingsToggleRequested()
    signal settingsShowRequested(var tabIndex, var subTabIndex)
    signal welcomeToggleRequested()
    signal welcomeShowRequested()
    signal wallpaperToggleRequested()
    signal wallpaperShowRequested()
    signal emojiToggleRequested()
    signal emojiShowRequested()

    function openWallpaper() {
        if (isLocked || isWizardActive) return
        closeAllExcept("wallpaper")
        wallpaperShowRequested()
    }

    function toggleWallpaper() {
        if (isLocked || isWizardActive) return
        wallpaperToggleRequested()
    }

    function openEmoji() {
        if (isLocked || isWizardActive) return
        closeAllExcept("emoji")
        emojiShowRequested()
    }

    function toggleEmoji() {
        if (isLocked || isWizardActive) return
        emojiToggleRequested()
    }

    function openSettings(tabIndex, subTabIndex) {
        if (isLocked || isWizardActive) return
        closeAllExcept("settings")
        settingsShowRequested(tabIndex, subTabIndex)
    }

    function toggleSettings() {
        if (isLocked || isWizardActive) return
        closeAllExcept("settings")
        settingsToggleRequested()
    }

    function openWelcome() {
        closeAllExcept("welcome")
        welcomeShowRequested()
    }

    function toggleWelcome() {
        if (isLocked) return
        welcomeToggleRequested()
    }

    function register(win) {
        _windows.push(win)
    }

    // 'except' can be a window object (PowerMenu/Launcher/NotifCenter etc.)
    // OR a string id ("controlCenter"/"calendar"/"batteryPanel"/"volumePanel"/"notifCenter") — matched
    // against the overlayId property if the window possesses it.
    function closeAllExcept(except) {
        for (let i = 0; i < _windows.length; i++) {
            const w = _windows[i]
            if (w.overlayId === "settings") continue
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
            updatePanelVisible = false
        }
        if (except !== "calendar") {
            calendarVisible = false
        }
        if (except !== "batteryPanel") {
            batteryPanelVisible = false
        }
        if (except !== "volumePanel") {
            volumePanelVisible = false
        }
        if (except !== "sysmonPanel") {
            sysmonPanelVisible = false
        }
    }

    function triggerIdentifyMonitors() {
        identifyMonitorsActive = true
        identifyTimer.restart()
    }

    Timer {
        id: identifyTimer
        interval: 2500
        repeat: false
        onTriggered: root.identifyMonitorsActive = false
    }
}
