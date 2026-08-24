pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    // ── Appearance Properties ────────────────────────────────────────────────
    property string themeMode: "dark"             // "dark" | "light" | "auto"
    property string accentColor: "#d4d4d4"        // Hex string
    property string accentName: "Graphite"        // Human readable name
    property int cornerRadius: 16                 // 8 | 12 | 16 | 20 | 24
    property real uiScale: 1.0                    // 0.9 (compact) | 1.0 (normal) | 1.15 (large)
    property bool useMatugen: false
    property string fontFamily: "Liga SFMono Nerd Font, monospace"
    property real glassOpacity: 0.85              // 0.70 | 0.85 | 0.98

    // ── Matugen Extracted Colors ─────────────────────────────────────────────
    property string matugenDarkPrimary: "#ffb599"
    property string matugenLightPrimary: "#8e4c32"
    property string matugenDarkSecondary: "#e7beaf"
    property string matugenLightSecondary: "#77574b"
    property string matugenDarkSurface: "#1a110e"
    property string matugenLightSurface: "#fff8f6"
    property string matugenDarkOnPrimary: "#552009"
    property string matugenLightOnPrimary: "#ffffff"
    property bool matugenGenerating: false

    // ── Bar & Widgets Customization ──────────────────────────────────────────
    property string barPosition: "top"            // "top" | "bottom"
    property string barStyle: "islands"           // "islands" | "floating" | "unified" | "minimal"
    property bool barFloating: false
    property bool showWorkspaces: true
    property bool showSysTray: true
    property bool showSysmonTray: true
    property bool showVolumeTray: true
    property bool showBatteryTray: true
    property bool showControlCenterTray: true
    property bool showClockTray: true
    property bool clock24h: true
    property bool clockShowSeconds: false
    property bool clockShowDate: true
    property string clockDateFormat: "short"      // "short" | "full"
    property string islandStyle: "expanded"       // "expanded" | "compact" | "minimal" | "hidden"
    property string workspaceStyle: "pills"       // "pills" | "numbers" | "dots" | "icons"
    property bool workspaceShowAll: true

    // ── Sound & Feedback ─────────────────────────────────────────────────────
    property bool soundFeedback: true
    property bool soundVolumeFeedback: true
    property bool soundWorkspaceFeedback: true
    property bool soundNotifFeedback: true
    property bool soundUiFeedback: true

    // ── Notifications ────────────────────────────────────────────────────────
    property int notificationTimeout: 5           // in seconds
    property int notificationRetentionDays: 7     // 1 to 7 days
    property bool dndEnabled: false
    property string notificationPosition: "top_right" // "top_right" | "top_center" | "top_left" | "bottom_right"

    // ── Lockscreen & System ──────────────────────────────────────────────────
    property string lockscreenClockStyle: "hero"  // "hero" | "modern" | "compact" | "minimal" | "vertical" | "typographic" | "radial" | "cyber"
    property string lockscreenAuthStyle: "pill"   // "pill" | "card"
    property string lockscreenLayout: "default"   // "default" | "compact" | "minimal"
    property string lockscreenAvatarShape: "circle" // "circle" | "squircle" | "rounded"
    property bool lockscreenAvatarRing: true
    property string lockscreenInputStyle: "pill"  // "pill" | "underline" | "box" | "dots"
    property bool lockscreenShowAvatar: false
    property bool lockscreenShowGreeting: false
    property bool lockscreenShowMedia: true
    property string lockscreenMediaStyle: "pill"  // "pill" | "card"
    property bool lockscreenShowWeather: true
    property bool lockscreenShowNotifs: true
    property bool lockscreenShowUptime: true
    property bool lockscreenWallpaperZoom: true
    property real lockscreenDim: 0.45
    property bool lockscreen24h: false
    property bool lockscreenBlur: true
    property real lockscreenBlurRadius: 0.40
    property string lockscreenWallpaperMode: "sync" // "sync" | "custom"
    property string lockscreenCustomWallpaper: ""
    property bool lockscreenShowQuickPower: true
    property bool lockscreenShowStatusPill: true
    property bool batteryShowWarnings: true
    property int batteryLowThreshold: 20
    property int clipboardLimit: 50
    property int launcherMaxResults: 8
    property bool firstRunCompleted: false
    property int customSettingsVersion: 2

    // ── Settings State Persistence ───────────────────────────────────────────
    property int lastSettingsTab: 0
    property int lastSettingsCompSubTab: 0

    // ── Status & Feedback ────────────────────────────────────────────────────
    property string lastBackupTime: ""
    property bool isLoaded: false

    signal configChanged()
    signal initialLoadFinished(bool isFirstRun)
    signal matugenUpdated()

    // ── Curated Accent Presets ───────────────────────────────────────────────
    readonly property var accentPresets: [
        { name: "Matugen (Wallpaper)", darkHex: root.matugenDarkPrimary, lightHex: root.matugenLightPrimary, preview: (root.themeMode === "light" ? root.matugenLightPrimary : root.matugenDarkPrimary), isMatugen: true },
        { name: "Graphite",     darkHex: "#d4d4d4", lightHex: "#2c2c2e", preview: "#8e8e93", isMatugen: false },
        { name: "Ocean Blue",   darkHex: "#38bdf8", lightHex: "#0071e3", preview: "#0071e3", isMatugen: false },
        { name: "Purple Iris",  darkHex: "#a78bfa", lightHex: "#7c3aed", preview: "#8b5cf6", isMatugen: false },
        { name: "Emerald Mint", darkHex: "#34d399", lightHex: "#059669", preview: "#10b981", isMatugen: false },
        { name: "Sunset Rose",  darkHex: "#fb7185", lightHex: "#e11d48", preview: "#f43f5e", isMatugen: false },
        { name: "Warm Amber",   darkHex: "#fbbf24", lightHex: "#d97706", preview: "#f59e0b", isMatugen: false },
        { name: "Cyan Breeze",  darkHex: "#22d3ee", lightHex: "#0891b2", preview: "#06b6d4", isMatugen: false },
        { name: "Neon Pink",    darkHex: "#f472b6", lightHex: "#db2777", preview: "#ec4899", isMatugen: false }
    ]

    // Paths
    readonly property string configDir: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell"
    readonly property string cacheDir: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.cache/quickshell"
    readonly property string declConfigPath: configDir + "/user_settings.json"
    readonly property string cacheConfigPath: cacheDir + "/user_settings.json"
    readonly property string defaultsConfigPath: configDir + "/defaults/settings_default.json"
    readonly property string backupConfigPath: configDir + "/backup_settings.json"

    FileView {
        id: configFileView
        path: root.declConfigPath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                var raw = configFileView.text()
                if (raw && raw.trim().startsWith("{")) {
                    var parsed = JSON.parse(raw.trim())
                    root.applyData(parsed)
                    root.isLoaded = true
                    var wasFirstRun = (parsed.firstRunCompleted !== true)
                    root.initialLoadFinished(wasFirstRun)
                }
            } catch (e) {
                loadConfigProc.running = true
            }
        }
        onLoadFailed: {
            loadConfigProc.running = true
        }
    }

    Component.onCompleted: {
        if (!root.isLoaded) {
            loadConfigProc.running = true
        }
    }

    function applyData(data) {
        if (!data || typeof data !== "object") return
        if (data.themeMode !== undefined) themeMode = data.themeMode
        if (data.useMatugen !== undefined) useMatugen = Boolean(data.useMatugen)
        if (data.accentName !== undefined) accentName = data.accentName
        if (data.accentColor !== undefined) {
            if (typeof data.accentColor === "string" && data.accentColor.startsWith("#")) {
                accentColor = data.accentColor
            } else {
                if (accentName === "Matugen (Wallpaper)" || data.accentColor === "Matugen (Wallpaper)" || useMatugen) {
                    accentName = "Matugen (Wallpaper)"
                    useMatugen = true
                    accentColor = (themeMode === "light") ? matugenLightPrimary : matugenDarkPrimary
                } else {
                    var presetFound = false
                    for (var p = 0; p < accentPresets.length; p++) {
                        if (accentPresets[p].name === data.accentColor || accentPresets[p].name === accentName) {
                            accentName = accentPresets[p].name
                            accentColor = (themeMode === "light") ? accentPresets[p].lightHex : accentPresets[p].darkHex
                            presetFound = true
                            break
                        }
                    }
                    if (!presetFound) {
                        accentName = "Graphite"
                        accentColor = (themeMode === "light") ? "#2c2c2e" : "#d4d4d4"
                    }
                }
            }
        }
        if (data.cornerRadius !== undefined) cornerRadius = Number(data.cornerRadius)
        if (data.uiScale !== undefined) uiScale = Number(data.uiScale)
        if (data.fontFamily !== undefined) fontFamily = data.fontFamily
        if (data.glassOpacity !== undefined) glassOpacity = Number(data.glassOpacity)

        if (data.barPosition !== undefined) barPosition = data.barPosition
        if (data.barStyle !== undefined) barStyle = data.barStyle
        if (data.barFloating !== undefined) barFloating = Boolean(data.barFloating)
        if (data.showWorkspaces !== undefined) showWorkspaces = Boolean(data.showWorkspaces)
        if (data.showSysTray !== undefined) showSysTray = Boolean(data.showSysTray)
        if (data.showSysmonTray !== undefined) showSysmonTray = Boolean(data.showSysmonTray)
        if (data.showVolumeTray !== undefined) showVolumeTray = Boolean(data.showVolumeTray)
        if (data.showBatteryTray !== undefined) showBatteryTray = Boolean(data.showBatteryTray)
        if (data.showControlCenterTray !== undefined) showControlCenterTray = Boolean(data.showControlCenterTray)
        if (data.showClockTray !== undefined) showClockTray = Boolean(data.showClockTray)
        if (data.clock24h !== undefined) clock24h = Boolean(data.clock24h)
        if (data.clockShowSeconds !== undefined) clockShowSeconds = Boolean(data.clockShowSeconds)
        if (data.clockShowDate !== undefined) clockShowDate = Boolean(data.clockShowDate)
        if (data.clockDateFormat !== undefined) clockDateFormat = data.clockDateFormat
        if (data.islandStyle !== undefined) islandStyle = data.islandStyle
        if (data.workspaceStyle !== undefined) workspaceStyle = data.workspaceStyle
        if (data.workspaceShowAll !== undefined) workspaceShowAll = Boolean(data.workspaceShowAll)

        if (data.soundFeedback !== undefined) soundFeedback = Boolean(data.soundFeedback)
        if (data.soundVolumeFeedback !== undefined) soundVolumeFeedback = Boolean(data.soundVolumeFeedback)
        if (data.soundWorkspaceFeedback !== undefined) soundWorkspaceFeedback = Boolean(data.soundWorkspaceFeedback)
        if (data.soundNotifFeedback !== undefined) soundNotifFeedback = Boolean(data.soundNotifFeedback)
        if (data.soundUiFeedback !== undefined) soundUiFeedback = Boolean(data.soundUiFeedback)

        if (data.notificationTimeout !== undefined) notificationTimeout = Number(data.notificationTimeout)
        if (data.notificationRetentionDays !== undefined) notificationRetentionDays = Math.max(1, Math.min(7, Number(data.notificationRetentionDays)))
        if (data.dndEnabled !== undefined) dndEnabled = Boolean(data.dndEnabled)
        if (data.notificationPosition !== undefined) notificationPosition = data.notificationPosition

        if (data.lockscreenClockStyle !== undefined) lockscreenClockStyle = data.lockscreenClockStyle
        if (data.lockscreenAuthStyle !== undefined) lockscreenAuthStyle = data.lockscreenAuthStyle
        if (data.lockscreenLayout !== undefined) {
            if (data.lockscreenLayout === "compact" || data.lockscreenLayout === "minimal" || data.lockscreenLayout === "default") {
                lockscreenLayout = data.lockscreenLayout
            } else {
                lockscreenLayout = "default"
            }
        }
        if (data.lockscreenAvatarShape !== undefined) lockscreenAvatarShape = data.lockscreenAvatarShape
        if (data.lockscreenAvatarRing !== undefined) lockscreenAvatarRing = Boolean(data.lockscreenAvatarRing)
        if (data.lockscreenInputStyle !== undefined) lockscreenInputStyle = data.lockscreenInputStyle
        if (data.lockscreenShowAvatar !== undefined) lockscreenShowAvatar = Boolean(data.lockscreenShowAvatar)
        if (data.lockscreenShowGreeting !== undefined) lockscreenShowGreeting = Boolean(data.lockscreenShowGreeting)
        if (data.lockscreenShowMedia !== undefined) lockscreenShowMedia = Boolean(data.lockscreenShowMedia)
        if (data.lockscreenMediaStyle !== undefined) lockscreenMediaStyle = data.lockscreenMediaStyle
        if (data.lockscreenShowWeather !== undefined) lockscreenShowWeather = Boolean(data.lockscreenShowWeather)
        if (data.lockscreenShowNotifs !== undefined) lockscreenShowNotifs = Boolean(data.lockscreenShowNotifs)
        if (data.lockscreenShowUptime !== undefined) lockscreenShowUptime = Boolean(data.lockscreenShowUptime)
        if (data.lockscreenWallpaperZoom !== undefined) lockscreenWallpaperZoom = Boolean(data.lockscreenWallpaperZoom)
        if (data.lockscreenDim !== undefined) lockscreenDim = Number(data.lockscreenDim)
        if (data.lockscreen24h !== undefined) lockscreen24h = Boolean(data.lockscreen24h)
        if (data.lockscreenBlur !== undefined) lockscreenBlur = Boolean(data.lockscreenBlur)
        if (data.lockscreenBlurRadius !== undefined) lockscreenBlurRadius = Number(data.lockscreenBlurRadius)
        if (data.lockscreenWallpaperMode !== undefined) lockscreenWallpaperMode = data.lockscreenWallpaperMode
        if (data.lockscreenCustomWallpaper !== undefined) lockscreenCustomWallpaper = String(data.lockscreenCustomWallpaper)
        if (data.lockscreenShowQuickPower !== undefined) lockscreenShowQuickPower = Boolean(data.lockscreenShowQuickPower)
        if (data.lockscreenShowStatusPill !== undefined) lockscreenShowStatusPill = Boolean(data.lockscreenShowStatusPill)
        if (data.batteryShowWarnings !== undefined) batteryShowWarnings = Boolean(data.batteryShowWarnings)
        if (data.batteryLowThreshold !== undefined) batteryLowThreshold = Number(data.batteryLowThreshold)
        if (data.clipboardLimit !== undefined) clipboardLimit = Number(data.clipboardLimit)
        if (data.launcherMaxResults !== undefined) launcherMaxResults = Number(data.launcherMaxResults)

        if (data.firstRunCompleted !== undefined) firstRunCompleted = Boolean(data.firstRunCompleted)
        if (data.lastSettingsTab !== undefined) lastSettingsTab = Number(data.lastSettingsTab)
        if (data.lastSettingsCompSubTab !== undefined) lastSettingsCompSubTab = Number(data.lastSettingsCompSubTab)
        root.configChanged()
    }

    Timer {
        id: saveDebounceTimer
        interval: 350
        repeat: false
        onTriggered: {
            var data = root.serializeData()
            var jsonStr = JSON.stringify(data, null, 2)
            saveConfigProc.payload = jsonStr
            saveConfigProc.running = true
        }
    }

    function serializeData() {
        return {
            themeMode: themeMode,
            accentColor: accentColor,
            accentName: accentName,
            useMatugen: useMatugen,
            cornerRadius: cornerRadius,
            uiScale: uiScale,
            fontFamily: fontFamily,
            glassOpacity: glassOpacity,

            lastSettingsTab: lastSettingsTab,
            lastSettingsCompSubTab: lastSettingsCompSubTab,

            barPosition: barPosition,
            barStyle: barStyle,
            barFloating: barFloating,
            showWorkspaces: showWorkspaces,
            showSysTray: showSysTray,
            showSysmonTray: showSysmonTray,
            showVolumeTray: showVolumeTray,
            showBatteryTray: showBatteryTray,
            showControlCenterTray: showControlCenterTray,
            showClockTray: showClockTray,
            clock24h: clock24h,
            clockShowSeconds: clockShowSeconds,
            clockShowDate: clockShowDate,
            clockDateFormat: clockDateFormat,
            islandStyle: islandStyle,
            workspaceStyle: workspaceStyle,
            workspaceShowAll: workspaceShowAll,

            soundFeedback: soundFeedback,
            soundVolumeFeedback: soundVolumeFeedback,
            soundWorkspaceFeedback: soundWorkspaceFeedback,
            soundNotifFeedback: soundNotifFeedback,
            soundUiFeedback: soundUiFeedback,

            notificationTimeout: notificationTimeout,
            notificationRetentionDays: notificationRetentionDays,
            dndEnabled: dndEnabled,
            notificationPosition: notificationPosition,

            lockscreenClockStyle: lockscreenClockStyle,
            lockscreenAuthStyle: lockscreenAuthStyle,
            lockscreenLayout: lockscreenLayout,
            lockscreenAvatarShape: lockscreenAvatarShape,
            lockscreenAvatarRing: lockscreenAvatarRing,
            lockscreenInputStyle: lockscreenInputStyle,
            lockscreenShowAvatar: lockscreenShowAvatar,
            lockscreenShowGreeting: lockscreenShowGreeting,
            lockscreenShowMedia: lockscreenShowMedia,
            lockscreenMediaStyle: lockscreenMediaStyle,
            lockscreenShowWeather: lockscreenShowWeather,
            lockscreenShowNotifs: lockscreenShowNotifs,
            lockscreenShowUptime: lockscreenShowUptime,
            lockscreenWallpaperZoom: lockscreenWallpaperZoom,
            lockscreenDim: lockscreenDim,
            lockscreen24h: lockscreen24h,
            lockscreenBlur: lockscreenBlur,
            lockscreenBlurRadius: lockscreenBlurRadius,
            lockscreenWallpaperMode: lockscreenWallpaperMode,
            lockscreenCustomWallpaper: lockscreenCustomWallpaper,
            lockscreenShowQuickPower: lockscreenShowQuickPower,
            lockscreenShowStatusPill: lockscreenShowStatusPill,
            batteryShowWarnings: batteryShowWarnings,
            batteryLowThreshold: batteryLowThreshold,
            clipboardLimit: clipboardLimit,
            launcherMaxResults: launcherMaxResults,

            firstRunCompleted: firstRunCompleted,
            customSettingsVersion: customSettingsVersion
        }
    }

    function saveConfig() {
        saveDebounceTimer.restart()
        root.configChanged()
    }

    function resetToDefaults() {
        themeMode = "light"
        accentColor = "#2c2c2e"
        accentName = "Graphite"
        useMatugen = false
        cornerRadius = 16
        uiScale = 1.0
        fontFamily = "Liga SFMono Nerd Font, monospace"
        glassOpacity = 0.85

        barPosition = "top"
        barStyle = "islands"
        barFloating = false
        showWorkspaces = true
        showSysTray = true
        showSysmonTray = true
        showVolumeTray = true
        showBatteryTray = true
        showControlCenterTray = true
        showClockTray = true
        clock24h = true
        clockShowSeconds = false
        clockShowDate = true
        clockDateFormat = "short"
        islandStyle = "expanded"
        workspaceStyle = "pills"
        workspaceShowAll = true

        soundFeedback = true
        soundVolumeFeedback = true
        soundWorkspaceFeedback = true
        soundNotifFeedback = true
        soundUiFeedback = true

        notificationTimeout = 5
        notificationRetentionDays = 7
        dndEnabled = false
        notificationPosition = "top_right"

        lockscreenClockStyle = "hero"
        lockscreenLayout = "default"
        lockscreenAvatarShape = "circle"
        lockscreenAvatarRing = true
        lockscreenInputStyle = "pill"
        lockscreenShowAvatar = true
        lockscreenShowGreeting = true
        lockscreenShowMedia = true
        lockscreenMediaStyle = "pill"
        lockscreenShowWeather = true
        lockscreenShowNotifs = true
        lockscreenWallpaperZoom = true
        lockscreenDim = 0.45
        lockscreen24h = false
        lockscreenBlur = true
        lockscreenBlurRadius = 0.40
        lockscreenWallpaperMode = "sync"
        lockscreenCustomWallpaper = ""
        lockscreenShowQuickPower = true
        lockscreenShowStatusPill = true
        batteryShowWarnings = true
        batteryLowThreshold = 20
        clipboardLimit = 50
        launcherMaxResults = 8

        firstRunCompleted = true
        saveConfig()
    }

    function generateMatugen(wallpaperPath) {
        if (!wallpaperPath) return
        matugenGenerating = true
        matugenProc.rawOutput = ""
        matugenProc.running = false
        matugenProc.command = [
            "matugen", "image", wallpaperPath,
            "-j", "hex",
            "--source-color-index", "0",
            "--dry-run"
        ]
        matugenProc.running = true
    }

    function setUseMatugen(enabled, currentWallpaper) {
        useMatugen = enabled
        if (enabled) {
            accentName = "Matugen (Wallpaper)"
            accentColor = (themeMode === "light") ? matugenLightPrimary : matugenDarkPrimary
            if (currentWallpaper) {
                generateMatugen(currentWallpaper)
            }
        } else {
            if (accentName === "Matugen (Wallpaper)") {
                accentName = "Graphite"
                accentColor = (themeMode === "light") ? "#2c2c2e" : "#d4d4d4"
            }
        }
        saveConfig()
    }

    function setThemeMode(mode) {
        themeMode = mode
        if (useMatugen || accentName === "Matugen (Wallpaper)") {
            accentColor = (mode === "light") ? matugenLightPrimary : matugenDarkPrimary
        } else {
            for (var i = 0; i < accentPresets.length; i++) {
                if (accentPresets[i].name === accentName) {
                    accentColor = (mode === "light") ? accentPresets[i].lightHex : accentPresets[i].darkHex
                    break
                }
            }
        }
        if (Services.SystemTheme) {
            Services.SystemTheme.setColorScheme(mode === "dark" ? "prefer-dark" : "prefer-light")
        }
        root.configChanged()
        saveConfig()
    }

    function setLastSettingsTab(tab) {
        lastSettingsTab = tab
        saveConfig()
    }

    function setLastSettingsCompSubTab(subTab) {
        lastSettingsCompSubTab = subTab
        saveConfig()
    }

    function setAccent(colorHex, name, isMatugen) {
        var chosenHex = colorHex
        var chosenName = name
        var matugenFlag = isMatugen

        // If called with single argument as a preset name (e.g. "Matugen (Wallpaper)" or "Graphite")
        if (!chosenName && typeof colorHex === "string" && !colorHex.startsWith("#")) {
            chosenName = colorHex
            var found = false
            for (var i = 0; i < accentPresets.length; i++) {
                if (accentPresets[i].name === chosenName) {
                    chosenHex = (themeMode === "light") ? accentPresets[i].lightHex : accentPresets[i].darkHex
                    matugenFlag = accentPresets[i].isMatugen
                    found = true
                    break
                }
            }
            if (!found) {
                chosenName = "Custom"
                chosenHex = (themeMode === "light") ? "#2c2c2e" : "#d4d4d4"
            }
        }

        useMatugen = Boolean(matugenFlag || chosenName === "Matugen (Wallpaper)")
        accentName = chosenName || "Custom"

        if (useMatugen) {
            accentName = "Matugen (Wallpaper)"
            accentColor = (themeMode === "light") ? matugenLightPrimary : matugenDarkPrimary
        } else {
            accentColor = chosenHex
        }

        saveConfig()
    }

    function setBarPosition(pos) { barPosition = pos; saveConfig() }
    function setBarStyle(style) { barStyle = style; saveConfig() }
    function setBarFloating(val) { barFloating = val; saveConfig() }
    function setShowWorkspaces(val) { showWorkspaces = val; saveConfig() }
    function setShowSysTray(val) { showSysTray = val; saveConfig() }
    function setShowSysmonTray(val) { showSysmonTray = val; saveConfig() }
    function setShowVolumeTray(val) { showVolumeTray = val; saveConfig() }
    function setShowBatteryTray(val) { showBatteryTray = val; saveConfig() }
    function setShowControlCenterTray(val) { showControlCenterTray = val; saveConfig() }
    function setShowClockTray(val) { showClockTray = val; saveConfig() }
    function setClock24h(val) { clock24h = val; saveConfig() }
    function setClockShowSeconds(val) { clockShowSeconds = val; saveConfig() }
    function setClockShowDate(val) { clockShowDate = val; saveConfig() }
    function setClockDateFormat(fmt) { clockDateFormat = fmt; saveConfig() }
    function setIslandStyle(style) { islandStyle = style; saveConfig() }
    function setWorkspaceStyle(style) { workspaceStyle = style; saveConfig() }
    function setWorkspaceShowAll(val) { workspaceShowAll = val; saveConfig() }

    function setSoundFeedback(val) { soundFeedback = val; saveConfig() }
    function setSoundVolumeFeedback(val) { soundVolumeFeedback = val; saveConfig() }
    function setSoundWorkspaceFeedback(val) { soundWorkspaceFeedback = val; saveConfig() }
    function setSoundNotifFeedback(val) { soundNotifFeedback = val; saveConfig() }
    function setSoundUiFeedback(val) { soundUiFeedback = val; saveConfig() }

    function setNotificationTimeout(sec) { notificationTimeout = sec; saveConfig() }
    function setNotificationRetentionDays(days) { notificationRetentionDays = Math.max(1, Math.min(7, days)); saveConfig() }
    function setNotificationPosition(pos) { notificationPosition = pos; saveConfig() }
    function setDndEnabled(val) { dndEnabled = val; saveConfig() }

    function setLockscreenClockStyle(style) { lockscreenClockStyle = style; saveConfig() }
    function setLockscreenAuthStyle(style) { lockscreenAuthStyle = style; saveConfig() }
    function setLockscreenLayout(layout) { lockscreenLayout = layout; saveConfig() }
    function setLockscreenAvatarShape(shape) { lockscreenAvatarShape = shape; saveConfig() }
    function setLockscreenAvatarRing(val) { lockscreenAvatarRing = val; saveConfig() }
    function setLockscreenInputStyle(style) { lockscreenInputStyle = style; saveConfig() }
    function setLockscreenShowAvatar(val) { lockscreenShowAvatar = val; saveConfig() }
    function setLockscreenShowGreeting(val) { lockscreenShowGreeting = val; saveConfig() }
    function setLockscreenShowMedia(val) { lockscreenShowMedia = val; saveConfig() }
    function setLockscreenMediaStyle(style) { lockscreenMediaStyle = style; saveConfig() }
    function setLockscreenShowWeather(val) { lockscreenShowWeather = val; saveConfig() }
    function setLockscreenShowNotifs(val) { lockscreenShowNotifs = val; saveConfig() }
    function setLockscreenShowUptime(val) { lockscreenShowUptime = val; saveConfig() }
    function setLockscreenWallpaperZoom(val) { lockscreenWallpaperZoom = val; saveConfig() }
    function setLockscreenDim(val) { lockscreenDim = val; saveConfig() }
    function setLockscreen24h(val) { lockscreen24h = val; saveConfig() }
    function setLockscreenBlur(val) { lockscreenBlur = val; saveConfig() }
    function setLockscreenBlurRadius(val) { lockscreenBlurRadius = val; saveConfig() }
    function setLockscreenWallpaperMode(mode) { lockscreenWallpaperMode = mode; saveConfig() }
    function setLockscreenCustomWallpaper(path) { lockscreenCustomWallpaper = path; saveConfig() }
    function setLockscreenShowQuickPower(val) { lockscreenShowQuickPower = val; saveConfig() }
    function setLockscreenShowStatusPill(val) { lockscreenShowStatusPill = val; saveConfig() }
    function setBatteryShowWarnings(val) { batteryShowWarnings = val; saveConfig() }
    function setBatteryLowThreshold(val) { batteryLowThreshold = val; saveConfig() }
    function setClipboardLimit(val) { clipboardLimit = val; saveConfig() }
    function setLauncherMaxResults(val) { launcherMaxResults = val; saveConfig() }

    function setFirstRunCompleted(val) { firstRunCompleted = val; saveConfig() }
    function setCornerRadius(radius) {
        cornerRadius = radius
        if (Services.Compositor) {
            Services.Compositor.setOption("rounding", radius)
        }
        saveConfig()
    }
    function setUiScale(scale) { uiScale = scale; saveConfig() }
    function setFontFamily(family) { fontFamily = family; saveConfig() }
    function setGlassOpacity(op) { glassOpacity = op; saveConfig() }

    // ── Processes ────────────────────────────────────────────────────────────
    Process {
        id: matugenProc
        property string rawOutput: ""
        stdout: SplitParser {
            onRead: chunk => {
                matugenProc.rawOutput += chunk
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.matugenGenerating = false
            var trimmed = matugenProc.rawOutput.trim()
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    var data = JSON.parse(trimmed)
                    if (data && data.colors) {
                        if (data.colors.primary) {
                            if (data.colors.primary.dark) root.matugenDarkPrimary = data.colors.primary.dark.color
                            if (data.colors.primary.light) root.matugenLightPrimary = data.colors.primary.light.color
                        }
                        if (data.colors.secondary) {
                            if (data.colors.secondary.dark) root.matugenDarkSecondary = data.colors.secondary.dark.color
                            if (data.colors.secondary.light) root.matugenLightSecondary = data.colors.secondary.light.color
                        }
                        if (data.colors.surface) {
                            if (data.colors.surface.dark) root.matugenDarkSurface = data.colors.surface.dark.color
                            if (data.colors.surface.light) root.matugenLightSurface = data.colors.surface.light.color
                        }
                        if (data.colors.on_primary) {
                            if (data.colors.on_primary.dark) root.matugenDarkOnPrimary = data.colors.on_primary.dark.color
                            if (data.colors.on_primary.light) root.matugenLightOnPrimary = data.colors.on_primary.light.color
                        }

                        if (root.useMatugen || root.accentName === "Matugen (Wallpaper)") {
                            root.accentName = "Matugen (Wallpaper)"
                            root.accentColor = (root.themeMode === "light") ? root.matugenLightPrimary : root.matugenDarkPrimary
                            root.saveConfig()
                        }
                        root.matugenUpdated()
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: loadConfigProc
        property string rawData: ""
        command: [
            "sh", "-c",
            "if [ -f \"" + root.declConfigPath + "\" ]; then tr -d '\\r\\n' < \"" + root.declConfigPath + "\"; " +
            "elif [ -f \"" + root.cacheConfigPath + "\" ]; then tr -d '\\r\\n' < \"" + root.cacheConfigPath + "\"; " +
            "elif [ -f \"" + root.defaultsConfigPath + "\" ]; then tr -d '\\r\\n' < \"" + root.defaultsConfigPath + "\"; " +
            "else echo ''; fi"
        ]
        stdout: SplitParser {
            onRead: chunk => {
                loadConfigProc.rawData += chunk
            }
        }
        onExited: (exitCode, exitStatus) => {
            var wasFirstRun = false
            var trimmed = loadConfigProc.rawData.trim()
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    var parsed = JSON.parse(trimmed)
                    root.applyData(parsed)
                    root.isLoaded = true
                    if (parsed.firstRunCompleted !== true && root.firstRunCompleted !== true) {
                        wasFirstRun = true
                    }
                } catch (e) {
                    root.isLoaded = true
                }
            } else {
                root.isLoaded = true
                wasFirstRun = true
            }
            root.initialLoadFinished(wasFirstRun)
        }
    }

    Process {
        id: saveConfigProc
        property string payload: ""
        command: ["sh", "-c",
            "mkdir -p \"" + root.cacheDir + "\" \"" + root.configDir + "\" && " +
            "printf '%s' \"$1\" > \"" + root.cacheConfigPath + "\" && " +
            "printf '%s' \"$1\" > \"" + root.declConfigPath + "\"",
            "sh", payload]
    }

    Process {
        id: backupProc
        stdout: SplitParser {
            onRead: data => {
                const t = data.trim()
                if (t.length > 0) root.lastBackupTime = t
            }
        }
    }

    Process {
        id: restoreProc
        stdout: SplitParser {
            onRead: data => {
                try {
                    var parsed = JSON.parse(data.trim())
                    root.applyData(parsed)
                    root.saveConfig()
                } catch (e) {
                }
            }
        }
    }
}
