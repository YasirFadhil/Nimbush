//@ pragma UseQApplication
//@ pragma IconTheme MacTahoe-dark
import QtQuick
import Quickshell
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

ShellRoot {
    // Native QML wallpaper layer (serves as wallpaper renderer and fallback for swww)
    WallpaperModule.Wallpaper {}

    Osd.Osd {}
    Notif.Center {}
    Notif.Popup {}
    // Osd.PowerOsd {} // Disabled — charging status is now shown in DynamicIsland
    Launcher.Launcher  { id: launcherWindow }
    DashboardModule.Dashboard { id: dashboardWindow }
    Clipboard.ClipboardHistory { id: clipboardWindow }
    PowerMenu.PowerMenu { id: powerMenu }
    Bar.Bar {}
    ControlCenter.ControlCenter { id: controlCenter }
    BatteryModule.Battery { id: batteryWindow }
    VolumeModule.Volume { id: volumeWindow }
    CalendarModule.Calendar {}
    LockscreenModule.Lockscreen { id: lockscreenWindow }
    SettingsModule.Settings { id: settingsWindow }
    WelcomeModule.Welcome { id: welcomeWindow }


    Connections {
        target: Services.OverlayManager
        function onLauncherToggleRequested() { launcherWindow.toggle() }
        function onDashboardToggleRequested() { dashboardWindow.toggle() }
        function onSettingsToggleRequested() { settingsWindow.toggle() }
        function onSettingsShowRequested(tabIndex) { settingsWindow.show(tabIndex) }
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


