//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "services" as Services
import "modules/notifications" as Notif
import "modules/launcher" as Launcher
import "modules/clipboard" as Clipboard
import "modules/osd" as Osd
import "modules/powermenu" as PowerMenu
import "modules/bar" as Bar
import "modules/controlcenter" as ControlCenter
import "modules/calendar" as CalendarModule
import "modules/lockscreen" as LockscreenModule
import "modules/dashboard" as DashboardModule
import "modules/wallpaper" as WallpaperModule
import "modules/settings" as SettingsModule
import "modules/welcome" as WelcomeModule
import "modules/battery" as BatteryModule
import "modules/volume" as VolumeModule
import "modules/emoji" as EmojiModule
import "modules/sysmon" as SysmonModule

ShellRoot {
    // Native QML wallpaper layer (serves as wallpaper renderer and fallback for swww)
    WallpaperModule.Wallpaper {}

    Osd.Osd {}
    Notif.Center {}
    Notif.Popup {}
    // Osd.PowerOsd {} // Disabled — charging status is now shown in DynamicIsland
    Launcher.Launcher  { id: launcherWindow }
    // Wallpaper is integrated into Dynamic Island in Bar.qml
    EmojiModule.EmojiPicker { id: emojiPickerWindow }
    DashboardModule.Dashboard { id: dashboardWindow }
    Clipboard.ClipboardHistory { id: clipboardWindow }
    PowerMenu.PowerMenu { id: powerMenu }
    Bar.Bar {}
    ControlCenter.ControlCenter { id: controlCenter }
    BatteryModule.Battery { id: batteryWindow }
    VolumeModule.Volume { id: volumeWindow }
    SysmonModule.Sysmon { id: sysmonWindow }
    CalendarModule.Calendar {}
    LockscreenModule.Lockscreen { id: lockscreenWindow }
    WelcomeModule.Welcome { id: welcomeWindow }

    Loader {
        id: identifyLoader
        active: Services.OverlayManager ? Services.OverlayManager.identifyMonitorsActive : false
        sourceComponent: Variants {
            model: Quickshell.screens
            delegate: PanelWindow {
                id: idWin
                required property var modelData
                screen: modelData
                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell:identify"
                exclusiveZone: -1

                Rectangle {
                    anchors.centerIn: parent
                    width: 280
                    height: 180
                    radius: 20
                    color: Qt.rgba(0.08, 0.08, 0.12, 0.94)
                    border.color: Services.Theme.accent
                    border.width: 3

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 19
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                        border.width: 1
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 52; height: 52; radius: 26
                            color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22)
                            border.color: Services.Theme.accent
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (!Quickshell.screens) return "1"
                                    for (let i = 0; i < Quickshell.screens.length; i++) {
                                        if (Quickshell.screens[i].name === idWin.modelData.name) return String(i + 1)
                                    }
                                    return "1"
                                }
                                font.pixelSize: 26
                                font.bold: true
                                color: Services.Theme.accent
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: idWin.modelData.name || "Display"
                            font.pixelSize: 20
                            font.bold: true
                            color: "#ffffff"
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: idWin.modelData.width + " × " + idWin.modelData.height
                            font.pixelSize: 13
                            font.family: Services.Theme.fontMono
                            color: Services.Theme.textSecondary
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: settingsLoader
        active: false
        sourceComponent: SettingsModule.Settings {
            onVisibleChanged: {
                if (!visible) settingsLoader.active = false
            }
        }
    }

    QtObject {
        id: settingsWindow
        readonly property bool visible: settingsLoader.active && settingsLoader.item && settingsLoader.item.visible

        function show(tabIndex) {
            if (!settingsLoader.active) {
                settingsLoader.active = true
            }
            if (settingsLoader.item) {
                settingsLoader.item.show(tabIndex)
            }
        }

        function hide() {
            if (settingsLoader.item) {
                settingsLoader.item.hide()
            }
            settingsLoader.active = false
        }

        function toggle() {
            if (settingsLoader.active && settingsLoader.item && settingsLoader.item.visible) {
                hide()
            } else {
                show()
            }
        }
    }


    Connections {
        target: Services.OverlayManager
        function onLauncherToggleRequested() { launcherWindow.toggle() }
        function onEmojiToggleRequested() { emojiPickerWindow.toggle() }
        function onEmojiShowRequested() { emojiPickerWindow.show() }
        function onDashboardToggleRequested() { dashboardWindow.toggle() }
        function onSettingsToggleRequested() { settingsWindow.toggle() }
        function onSettingsShowRequested(tabIndex, subTabIndex) { settingsWindow.show(tabIndex, subTabIndex) }
        function onWelcomeToggleRequested() { welcomeWindow.toggle() }
        function onWelcomeShowRequested() { welcomeWindow.show() }
    }

    // ── Notification center (history panel) ──────────────────────────────────
    IpcHandler {
        target: "notifCenter"
        function toggle() { Services.Notifications.centerVisible = !Services.Notifications.centerVisible }
        function clear()  { Services.Notifications.clearHistory() }
        function dnd()    { Services.Notifications.doNotDisturb = !Services.Notifications.doNotDisturb }
    }

    // ── Control Center ───────────────────────────────────────────────────────
    IpcHandler {
        target: "controlCenter"
        function toggle() { controlCenter.toggle() }
        function show()   { controlCenter.show() }
        function hide()   { controlCenter.hide() }
    }

    // ── Battery Panel ────────────────────────────────────────────────────────
    IpcHandler {
        target: "battery"
        function toggle(): void { if (!Services.OverlayManager.isLocked) batteryWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) batteryWindow.show() }
        function hide():   void { batteryWindow.hide() }
    }

    // ── Volume Panel ─────────────────────────────────────────────────────────
    IpcHandler {
        target: "volume"
        function toggle(): void { if (!Services.OverlayManager.isLocked) volumeWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) volumeWindow.show() }
        function hide():   void { volumeWindow.hide() }
    }

    // ── System & Task Manager Panel ──────────────────────────────────────────
    IpcHandler {
        target: "sysmon"
        function toggle(): void { if (!Services.OverlayManager.isLocked) sysmonWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) sysmonWindow.show() }
        function hide():   void { sysmonWindow.hide() }
    }

    // ── Calendar Panel ───────────────────────────────────────────────────────
    IpcHandler {
        target: "calendar"
        function toggle(): void {
            if (!Services.OverlayManager.isLocked) {
                const newState = !Services.OverlayManager.calendarVisible
                if (newState) Services.OverlayManager.closeAllExcept("calendar")
                Services.OverlayManager.calendarVisible = newState
            }
        }
        function show(): void {
            if (!Services.OverlayManager.isLocked) {
                Services.OverlayManager.closeAllExcept("calendar")
                Services.OverlayManager.calendarVisible = true
            }
        }
        function hide(): void { Services.OverlayManager.calendarVisible = false }
    }

    // ── Dashboard ────────────────────────────────────────────────────────────
    IpcHandler {
        target: "dashboard"
        function toggle(): void { if (!Services.OverlayManager.isLocked) dashboardWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) dashboardWindow.show() }
        function hide():   void { dashboardWindow.hide() }
    }

    // ── Launcher ─────────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        function toggle(): void { if (!Services.OverlayManager.isLocked) launcherWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) launcherWindow.show() }
        function hide():   void { launcherWindow.hide() }
    }

    // ── Wallpaper Selector (Integrated in Dynamic Island) ───────────────────
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { if (!Services.OverlayManager.isLocked) Services.OverlayManager.wallpaperToggleRequested() }
        function show():   void { if (!Services.OverlayManager.isLocked) Services.OverlayManager.wallpaperShowRequested() }
        function hide():   void { if (!Services.OverlayManager.isLocked) Services.OverlayManager.wallpaperToggleRequested() }
    }

    IpcHandler {
        target: "wallpaperSelector"
        function toggle(): void { if (!Services.OverlayManager.isLocked) Services.OverlayManager.wallpaperToggleRequested() }
        function show():   void { if (!Services.OverlayManager.isLocked) Services.OverlayManager.wallpaperShowRequested() }
        function hide():   void { if (!Services.OverlayManager.isLocked) Services.OverlayManager.wallpaperToggleRequested() }
    }

    // ── Emoji Picker ─────────────────────────────────────────────────────────
    IpcHandler {
        target: "emoji"
        function toggle(): void { if (!Services.OverlayManager.isLocked) emojiPickerWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) emojiPickerWindow.show() }
        function hide():   void { emojiPickerWindow.hide() }
    }

    IpcHandler {
        target: "emojiPicker"
        function toggle(): void { if (!Services.OverlayManager.isLocked) emojiPickerWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) emojiPickerWindow.show() }
        function hide():   void { emojiPickerWindow.hide() }
    }

    // ── Clipboard ────────────────────────────────────────────────────────────
    IpcHandler {
        target: "clipboard"
        function toggle(): void { if (!Services.OverlayManager.isLocked) clipboardWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) clipboardWindow.show() }
        function hide():   void { clipboardWindow.hide() }
    }

    // ── Power menu ───────────────────────────────────────────────────────────
    IpcHandler {
        target: "powermenu"
        function toggle() { (powerMenu.menuVisible ? powerMenu.close() : powerMenu.open()) }
        function open()   { powerMenu.open() }
        function close()  { powerMenu.close() }
    }

    // ── Lockscreen ───────────────────────────────────────────────────────────
    IpcHandler {
        target: "lockscreen"
        function toggle() { lockscreenWindow.toggle() }
        function show()   { lockscreenWindow.show() }
        function hide()   { lockscreenWindow.hide() }
        function lock()   { lockscreenWindow.lock() }
    }

    // ── Settings ─────────────────────────────────────────────────────────────
    IpcHandler {
        target: "settings"
        function toggle(): void { if (!Services.OverlayManager.isLocked) settingsWindow.toggle() }
        function show(): void { if (!Services.OverlayManager.isLocked) settingsWindow.show() }
        function hide(): void { settingsWindow.hide() }
    }

    // ── Welcome Setup Wizard ─────────────────────────────────────────────────
    IpcHandler {
        target: "welcome"
        function toggle(): void { if (!Services.OverlayManager.isLocked) welcomeWindow.toggle() }
        function show():   void { if (!Services.OverlayManager.isLocked) welcomeWindow.show() }
        function hide():   void { welcomeWindow.hide() }
    }

    // ── Shell lifecycle / reload ──────────────────────────────────────────────
    Process {
        id: reloadTriggerProc
        command: ["sh", "-c", "touch \"" + (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/shell.qml\" || pkill -USR1 qs || pkill -USR1 quickshell"]
    }

    IpcHandler {
        target: "shell"
        function reload(): void {
            reloadTriggerProc.running = true
        }
    }

    // ── Auto-lock on system suspend / sleep ──────────────────────────────────
    Process {
        id: sleepWatcher
        command: [
            "dbus-monitor", "--system",
            "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
        ]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data.includes("boolean true")) {
                    lockscreenWindow.lock()
                }
            }
        }
    }
}


