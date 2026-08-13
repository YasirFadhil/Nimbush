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

ShellRoot {
    // Notif.Popup {} // dimatiin — notif sekarang lewat DynamicIsland
    Osd.Osd {}
    Notif.Center {}
    // Osd.PowerOsd {} // dimatiin — status charging sekarang lewat DynamicIsland
    Launcher.Launcher  { id: launcherWindow }
    DashboardModule.Dashboard { id: dashboardWindow }
    Clipboard.ClipboardHistory { id: clipboardWindow }
    PowerMenu.PowerMenu { id: powerMenu }
    Bar.Bar {}
    ControlCenter.ControlCenter { id: controlCenter }
    CalendarModule.Calendar {}
    LockscreenModule.Lockscreen { id: lockscreenWindow }


    Connections {
        target: Services.OverlayManager
        function onLauncherToggleRequested() { launcherWindow.toggle() }
        function onDashboardToggleRequested() { dashboardWindow.toggle() }
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
}


