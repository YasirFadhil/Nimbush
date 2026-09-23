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
    property string fontMono: "Liga SFMono Nerd Font, monospace"
    property string fontDisplay: "SF Pro Display, Inter, Sans-Serif"
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
    property bool islandCavaWave: true            // Live CAVA audio spectrum visualizer
    property string workspaceStyle: "pills"       // "pills" | "numbers" | "dots" | "icons"
    property bool workspaceShowAll: true
    property string barMonitorMode: "all"         // "all" | "primary" | "custom"
    property var barMonitorsList: []              // string[] of monitor names e.g. ["eDP-1", "DP-1"]

    readonly property var barScreens: {
        if (!Quickshell.screens || Quickshell.screens.length === 0) return []
        const count = Quickshell.screens.length
        if (barMonitorMode === "all") {
            var all = []
            for (var i = 0; i < count; i++) {
                if (Quickshell.screens[i]) all.push(Quickshell.screens[i])
            }
            return all
        } else if (barMonitorMode === "primary") {
            var prim = ""
            if (Services.Compositor && Services.Compositor.monitorsList && Services.Compositor.monitorsList.length > 0) {
                var f = Services.Compositor.monitorsList.find(m => m.focused)
                prim = f ? f.name : Services.Compositor.monitorsList[0].name
            }
            for (var j = 0; j < count; j++) {
                if (Quickshell.screens[j] && Quickshell.screens[j].name === prim) {
                    return [Quickshell.screens[j]]
                }
            }
            return Quickshell.screens[0] ? [Quickshell.screens[0]] : []
        } else if (barMonitorMode === "custom") {
            var list = barMonitorsList || []
            var res = []
            for (var k = 0; k < count; k++) {
                var sc = Quickshell.screens[k]
                if (sc && list.indexOf(sc.name) !== -1) {
                    res.push(sc)
                }
            }
            if (res.length > 0) return res
            return Quickshell.screens[0] ? [Quickshell.screens[0]] : []
        }
        return Quickshell.screens
    }

    // ── Dashboard & Weather ──────────────────────────────────────────────────
    property string dashboardWidget: "weather"    // "weather" | "wallpaper" | "both"
    property string weatherLocationMode: "auto"   // "auto" | "custom"
    property string weatherCustomCity: ""
    property string weatherUnit: "celsius"        // "celsius" | "fahrenheit"
    property bool weatherAutoRefresh: true
    property bool dashboardShowMetrics: true
    property bool dashboardShowSpecs: true
    property bool dashboardShowActions: true
    property string dashboardMetricsStyle: "cards" // "cards" | "minimal"

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
    property bool notificationShowInFullscreen: false

    // ── Application Dock ─────────────────────────────────────────────────────
    property bool dockEnabled: true
    property string dockPosition: "bottom"        // "bottom" | "left" | "right"
    property bool dockAutoHide: false
    property int dockIconSize: 48                 // 36 | 44 | 48 | 56 | 64
    property bool dockMagnification: true
    property real dockMagnificationScale: 1.35    // 1.1 to 1.8
    property bool dockShowIndicators: true
    property string dockIndicatorStyle: "dot"     // "dot" | "line" | "pill" | "glow"
    property bool dockShowTooltips: true
    property bool dockShowWindowCount: true
    property bool dockBounceOnClick: true
    property bool dockShowSeparator: true
    property int dockFloatingDistance: 6          // 0 | 6 | 12 | 18
    property string dockMonitorMode: "all"        // "all" | "primary"
    property var dockPinnedApps: [
        "kitty.desktop",
        "org.gnome.Nautilus.desktop",
        "zen.desktop",
        "org.gnome.Snapshot.desktop",
        "org.gnome.DiskUtility.desktop"
    ]

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
    property bool lockscreenGenieUnlock: true
    property bool faceIdEnabled: true
    property string faceIdCameraDevice: "/dev/video0"
    property real faceIdConfidence: 98.0
    property bool faceIdAutoUnlock: true
    property bool batteryShowWarnings: true
    property int batteryLowThreshold: 20
    property string customAvatar: ""
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
        if (data.fontMono !== undefined) fontMono = data.fontMono
        if (data.fontDisplay !== undefined) fontDisplay = data.fontDisplay
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
        if (data.islandCavaWave !== undefined) islandCavaWave = Boolean(data.islandCavaWave)
        if (data.workspaceStyle !== undefined) workspaceStyle = data.workspaceStyle
        if (data.workspaceShowAll !== undefined) workspaceShowAll = Boolean(data.workspaceShowAll)
        if (data.barMonitorMode !== undefined) barMonitorMode = data.barMonitorMode
        if (data.barMonitorsList !== undefined && Array.isArray(data.barMonitorsList)) barMonitorsList = data.barMonitorsList

        if (data.soundFeedback !== undefined) soundFeedback = Boolean(data.soundFeedback)
        if (data.soundVolumeFeedback !== undefined) soundVolumeFeedback = Boolean(data.soundVolumeFeedback)
        if (data.soundWorkspaceFeedback !== undefined) soundWorkspaceFeedback = Boolean(data.soundWorkspaceFeedback)
        if (data.soundNotifFeedback !== undefined) soundNotifFeedback = Boolean(data.soundNotifFeedback)
        if (data.soundUiFeedback !== undefined) soundUiFeedback = Boolean(data.soundUiFeedback)

        if (data.notificationTimeout !== undefined) notificationTimeout = Number(data.notificationTimeout)
        if (data.notificationRetentionDays !== undefined) notificationRetentionDays = Math.max(1, Math.min(7, Number(data.notificationRetentionDays)))
        if (data.dndEnabled !== undefined) dndEnabled = Boolean(data.dndEnabled)
        if (data.notificationPosition !== undefined) notificationPosition = data.notificationPosition
        if (data.notificationShowInFullscreen !== undefined) notificationShowInFullscreen = Boolean(data.notificationShowInFullscreen)

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
        if (data.lockscreenGenieUnlock !== undefined) lockscreenGenieUnlock = Boolean(data.lockscreenGenieUnlock)
        if (data.faceIdEnabled !== undefined) faceIdEnabled = Boolean(data.faceIdEnabled)
        if (data.faceIdCameraDevice !== undefined) faceIdCameraDevice = String(data.faceIdCameraDevice)
        if (data.faceIdConfidence !== undefined) faceIdConfidence = Number(data.faceIdConfidence)
        if (data.faceIdAutoUnlock !== undefined) faceIdAutoUnlock = Boolean(data.faceIdAutoUnlock)
        if (data.batteryShowWarnings !== undefined) batteryShowWarnings = Boolean(data.batteryShowWarnings)
        if (data.batteryLowThreshold !== undefined) batteryLowThreshold = Number(data.batteryLowThreshold)
        if (data.customAvatar !== undefined) customAvatar = String(data.customAvatar)
        if (data.clipboardLimit !== undefined) clipboardLimit = Number(data.clipboardLimit)
        if (data.launcherMaxResults !== undefined) launcherMaxResults = Number(data.launcherMaxResults)

        if (data.dockEnabled !== undefined) dockEnabled = Boolean(data.dockEnabled)
        if (data.dockPosition !== undefined) dockPosition = String(data.dockPosition)
        if (data.dockAutoHide !== undefined) dockAutoHide = Boolean(data.dockAutoHide)
        if (data.dockIconSize !== undefined) dockIconSize = Number(data.dockIconSize)
        if (data.dockMagnification !== undefined) dockMagnification = Boolean(data.dockMagnification)
        if (data.dockMagnificationScale !== undefined) dockMagnificationScale = Number(data.dockMagnificationScale)
        if (data.dockShowIndicators !== undefined) dockShowIndicators = Boolean(data.dockShowIndicators)
        if (data.dockIndicatorStyle !== undefined) dockIndicatorStyle = String(data.dockIndicatorStyle)
        if (data.dockShowTooltips !== undefined) dockShowTooltips = Boolean(data.dockShowTooltips)
        if (data.dockShowWindowCount !== undefined) dockShowWindowCount = Boolean(data.dockShowWindowCount)
        if (data.dockBounceOnClick !== undefined) dockBounceOnClick = Boolean(data.dockBounceOnClick)
        if (data.dockShowSeparator !== undefined) dockShowSeparator = Boolean(data.dockShowSeparator)
        if (data.dockFloatingDistance !== undefined) dockFloatingDistance = Number(data.dockFloatingDistance)
        if (data.dockMonitorMode !== undefined) dockMonitorMode = String(data.dockMonitorMode)
        if (data.dockPinnedApps !== undefined && Array.isArray(data.dockPinnedApps)) dockPinnedApps = data.dockPinnedApps

        if (data.dashboardWidget !== undefined) dashboardWidget = data.dashboardWidget
        if (data.weatherLocationMode !== undefined) weatherLocationMode = data.weatherLocationMode
        if (data.weatherCustomCity !== undefined) weatherCustomCity = String(data.weatherCustomCity)
        if (data.weatherUnit !== undefined) weatherUnit = data.weatherUnit
        if (data.weatherAutoRefresh !== undefined) weatherAutoRefresh = Boolean(data.weatherAutoRefresh)
        if (data.dashboardShowMetrics !== undefined) dashboardShowMetrics = Boolean(data.dashboardShowMetrics)
        if (data.dashboardShowSpecs !== undefined) dashboardShowSpecs = Boolean(data.dashboardShowSpecs)
        if (data.dashboardShowActions !== undefined) dashboardShowActions = Boolean(data.dashboardShowActions)
        if (data.dashboardMetricsStyle !== undefined) dashboardMetricsStyle = data.dashboardMetricsStyle

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
            fontMono: fontMono,
            fontDisplay: fontDisplay,
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
            islandCavaWave: islandCavaWave,
            workspaceStyle: workspaceStyle,
            workspaceShowAll: workspaceShowAll,
            barMonitorMode: barMonitorMode,
            barMonitorsList: barMonitorsList,

            soundFeedback: soundFeedback,
            soundVolumeFeedback: soundVolumeFeedback,
            soundWorkspaceFeedback: soundWorkspaceFeedback,
            soundNotifFeedback: soundNotifFeedback,
            soundUiFeedback: soundUiFeedback,

            notificationTimeout: notificationTimeout,
            notificationRetentionDays: notificationRetentionDays,
            dndEnabled: dndEnabled,
            notificationPosition: notificationPosition,
            notificationShowInFullscreen: notificationShowInFullscreen,

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
            lockscreenGenieUnlock: lockscreenGenieUnlock,
            faceIdEnabled: faceIdEnabled,
            faceIdCameraDevice: faceIdCameraDevice,
            faceIdConfidence: faceIdConfidence,
            faceIdAutoUnlock: faceIdAutoUnlock,
            batteryShowWarnings: batteryShowWarnings,
            batteryLowThreshold: batteryLowThreshold,
            customAvatar: customAvatar,
            clipboardLimit: clipboardLimit,
            launcherMaxResults: launcherMaxResults,

            dashboardWidget: dashboardWidget,
            weatherLocationMode: weatherLocationMode,
            weatherCustomCity: weatherCustomCity,
            weatherUnit: weatherUnit,
            weatherAutoRefresh: weatherAutoRefresh,
            dashboardShowMetrics: dashboardShowMetrics,
            dashboardShowSpecs: dashboardShowSpecs,
            dashboardShowActions: dashboardShowActions,
            dashboardMetricsStyle: dashboardMetricsStyle,

            dockEnabled: dockEnabled,
            dockPosition: dockPosition,
            dockAutoHide: dockAutoHide,
            dockIconSize: dockIconSize,
            dockMagnification: dockMagnification,
            dockMagnificationScale: dockMagnificationScale,
            dockShowIndicators: dockShowIndicators,
            dockIndicatorStyle: dockIndicatorStyle,
            dockShowTooltips: dockShowTooltips,
            dockShowWindowCount: dockShowWindowCount,
            dockBounceOnClick: dockBounceOnClick,
            dockShowSeparator: dockShowSeparator,
            dockFloatingDistance: dockFloatingDistance,
            dockMonitorMode: dockMonitorMode,
            dockPinnedApps: dockPinnedApps,

            firstRunCompleted: firstRunCompleted,
            customSettingsVersion: customSettingsVersion
        }
    }

    function saveConfig() {
        saveDebounceTimer.restart()
        root.configChanged()
    }

    function saveConfigImmediately() {
        saveDebounceTimer.stop()
        var data = root.serializeData()
        var jsonStr = JSON.stringify(data, null, 2)
        saveConfigProc.payload = jsonStr
        saveConfigProc.running = true
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
        fontMono = "Liga SFMono Nerd Font, monospace"
        fontDisplay = "SF Pro Display, Inter, Sans-Serif"
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
        islandCavaWave = true
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
        notificationShowInFullscreen = false

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
        customAvatar = ""
        clipboardLimit = 50
        launcherMaxResults = 8

        dashboardWidget = "weather"
        weatherLocationMode = "auto"
        weatherCustomCity = ""
        weatherUnit = "celsius"
        weatherAutoRefresh = true
        dashboardShowMetrics = true
        dashboardShowSpecs = true
        dashboardShowActions = true
        dashboardMetricsStyle = "cards"

        dockEnabled = true
        dockPosition = "bottom"
        dockAutoHide = false
        dockIconSize = 48
        dockMagnification = true
        dockMagnificationScale = 1.35
        dockShowIndicators = true
        dockIndicatorStyle = "dot"
        dockShowTooltips = true
        dockShowWindowCount = true
        dockBounceOnClick = true
        dockShowSeparator = true
        dockFloatingDistance = 6
        dockMonitorMode = "all"
        dockPinnedApps = resolveDefaultPinnedApps()

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
    function setIslandCavaWave(val) { islandCavaWave = val; saveConfig() }
    function setWorkspaceStyle(style) { workspaceStyle = style; saveConfig() }
    function setWorkspaceShowAll(val) { workspaceShowAll = val; saveConfig() }
    function setBarMonitorMode(mode) { barMonitorMode = mode; saveConfig() }
    function toggleBarMonitor(monName) {
        if (!monName) return
        var list = barMonitorsList ? barMonitorsList.slice() : []
        var idx = list.indexOf(monName)
        if (idx !== -1) {
            list.splice(idx, 1)
        } else {
            list.push(monName)
        }
        barMonitorsList = list
        saveConfig()
    }
    function setBarMonitor(monName, enabled) {
        if (!monName) return
        var list = barMonitorsList ? barMonitorsList.slice() : []
        var idx = list.indexOf(monName)
        if (enabled && idx === -1) {
            list.push(monName)
        } else if (!enabled && idx !== -1) {
            list.splice(idx, 1)
        }
        barMonitorsList = list
        saveConfig()
    }
    function isBarMonitorEnabled(monName) {
        if (!monName) return true
        if (barMonitorMode === "all") return true
        if (barMonitorMode === "primary") {
            var prim = (Services.Compositor && Services.Compositor.monitorsList && Services.Compositor.monitorsList.length > 0)
                ? (Services.Compositor.monitorsList.find(m => m.focused)?.name || Services.Compositor.monitorsList[0].name)
                : ""
            return monName === prim
        }
        return (barMonitorsList || []).indexOf(monName) !== -1
    }

    function setSoundFeedback(val) { soundFeedback = val; saveConfig() }
    function setSoundVolumeFeedback(val) { soundVolumeFeedback = val; saveConfig() }
    function setSoundWorkspaceFeedback(val) { soundWorkspaceFeedback = val; saveConfig() }
    function setSoundNotifFeedback(val) { soundNotifFeedback = val; saveConfig() }
    function setSoundUiFeedback(val) { soundUiFeedback = val; saveConfig() }

    function setNotificationTimeout(sec) { notificationTimeout = sec; saveConfig() }
    function setNotificationRetentionDays(days) { notificationRetentionDays = Math.max(1, Math.min(7, days)); saveConfig() }
    function setNotificationPosition(pos) { notificationPosition = pos; saveConfig() }
    function setNotificationShowInFullscreen(val) { notificationShowInFullscreen = Boolean(val); saveConfig() }
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
    function setFaceIdEnabled(val) { faceIdEnabled = val; saveConfig() }
    function setFaceIdCameraDevice(path) { faceIdCameraDevice = path; saveConfig() }
    function setFaceIdConfidence(val) { faceIdConfidence = val; saveConfig() }
    function setFaceIdAutoUnlock(val) { faceIdAutoUnlock = val; saveConfig() }
    function setBatteryShowWarnings(val) { batteryShowWarnings = val; saveConfig() }
    function setBatteryLowThreshold(val) { batteryLowThreshold = val; saveConfig() }
    function setCustomAvatar(path) { customAvatar = path; saveConfig() }
    function clearCustomAvatar() { customAvatar = ""; saveConfig() }
    function setClipboardLimit(val) { clipboardLimit = val; saveConfig() }
    function setLauncherMaxResults(val) { launcherMaxResults = val; saveConfig() }

    function setDockEnabled(val) { dockEnabled = val; saveConfig() }
    function setDockPosition(val) { dockPosition = val; saveConfig() }
    function setDockAutoHide(val) { dockAutoHide = val; saveConfig() }
    function setDockIconSize(val) { dockIconSize = val; saveConfig() }
    function setDockMagnification(val) { dockMagnification = val; saveConfig() }
    function setDockMagnificationScale(val) { dockMagnificationScale = val; saveConfig() }
    function setDockShowIndicators(val) { dockShowIndicators = val; saveConfig() }
    function setDockIndicatorStyle(val) { dockIndicatorStyle = val; saveConfig() }
    function setDockShowTooltips(val) { dockShowTooltips = val; saveConfig() }
    function setDockShowWindowCount(val) { dockShowWindowCount = val; saveConfig() }
    function setDockBounceOnClick(val) { dockBounceOnClick = val; saveConfig() }
    function setDockShowSeparator(val) { dockShowSeparator = val; saveConfig() }
    function setDockFloatingDistance(val) { dockFloatingDistance = val; saveConfig() }
    function setDockMonitorMode(val) { dockMonitorMode = val; saveConfig() }
    function setDockPinnedApps(apps) { dockPinnedApps = apps; saveConfig() }

    function resolveDefaultPinnedApps() {
        const raw = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []

        const terminalCandidates = [
            "kitty.desktop", "ghostty.desktop", "com.mitchellh.ghostty.desktop",
            "foot.desktop", "org.gnome.Console.desktop", "gnome-terminal.desktop",
            "alacritty.desktop", "wezterm.desktop", "org.kde.konsole.desktop", "konsole.desktop",
            "com.system76.CosmicTerm.desktop", "xterm.desktop"
        ]
        const fileManagerCandidates = [
            "org.gnome.Nautilus.desktop", "nautilus.desktop", "thunar.desktop",
            "org.kde.dolphin.desktop", "dolphin.desktop", "com.system76.CosmicFiles.desktop",
            "nemo.desktop", "pcmanfm.desktop", "caja.desktop"
        ]
        const browserCandidates = [
            "zen.desktop", "firefox.desktop", "org.mozilla.firefox.desktop",
            "google-chrome.desktop", "chromium.desktop", "brave-browser.desktop",
            "microsoft-edge.desktop", "helium.desktop", "org.gnome.Epiphany.desktop"
        ]
        const cameraCandidates = [
            "org.gnome.Snapshot.desktop", "snapshot.desktop", "cheese.desktop",
            "org.gnome.Cheese.desktop", "kamoso.desktop", "org.kde.kamoso.desktop",
            "io.github.cameractrls.desktop", "cameractrls.desktop", "qv4l2.desktop", "qvidcap.desktop"
        ]
        const diskCandidates = [
            "org.gnome.DiskUtility.desktop", "gnome-disk-utility.desktop",
            "gparted.desktop", "partitionmanager.desktop", "org.kde.partitionmanager.desktop",
            "org.gnome.baobab.desktop", "baobab.desktop"
        ]

        function findMatch(candidates, categoryName, keywordList) {
            for (let c = 0; c < candidates.length; c++) {
                const targetClean = candidates[c].toLowerCase().replace(/\.desktop$/, '')
                for (let i = 0; i < raw.length; i++) {
                    const app = raw[i]
                    if (!app || !app.id) continue
                    const appIdClean = app.id.toLowerCase().replace(/\.desktop$/, '')
                    if (appIdClean === targetClean) {
                        return app.id.endsWith(".desktop") ? app.id : (app.id + ".desktop")
                    }
                }
            }
            if (categoryName) {
                for (let i = 0; i < raw.length; i++) {
                    const app = raw[i]
                    if (!app || !app.id) continue
                    const cats = (app.categories || []).map(cat => String(cat).toLowerCase())
                    if (cats.includes(categoryName.toLowerCase())) {
                        return app.id.endsWith(".desktop") ? app.id : (app.id + ".desktop")
                    }
                }
            }
            if (keywordList && keywordList.length > 0) {
                for (let i = 0; i < raw.length; i++) {
                    const app = raw[i]
                    if (!app || !app.id) continue
                    const text = ((app.id || "") + " " + (app.name || "") + " " + (app.description || "")).toLowerCase()
                    if (keywordList.some(k => text.includes(k.toLowerCase()))) {
                        return app.id.endsWith(".desktop") ? app.id : (app.id + ".desktop")
                    }
                }
            }
            return null
        }

        const term = findMatch(terminalCandidates, "TerminalEmulator", ["terminal", "console"]) || "kitty.desktop"
        const fm = findMatch(fileManagerCandidates, "FileManager", ["filemanager", "files", "nautilus", "thunar"]) || "org.gnome.Nautilus.desktop"
        const browser = findMatch(browserCandidates, "WebBrowser", ["browser", "firefox", "chrome", "zen"]) || "zen.desktop"
        const cam = findMatch(cameraCandidates, null, ["camera", "snapshot", "webcam", "kamera"]) || "org.gnome.Snapshot.desktop"
        const disk = findMatch(diskCandidates, null, ["disk", "partition", "gparted", "diskutility"]) || "org.gnome.DiskUtility.desktop"

        return [term, fm, browser, cam, disk]
    }

    function setDashboardWidget(val) { dashboardWidget = val; saveConfig() }
    function setWeatherLocationMode(val) {
        weatherLocationMode = val
        saveConfig()
        if (Services.Weather) Services.Weather.refresh()
    }
    function setWeatherCustomCity(val) {
        weatherCustomCity = val
        saveConfig()
        if (Services.Weather) Services.Weather.refresh()
    }
    function setWeatherUnit(val) {
        weatherUnit = val
        saveConfig()
        if (Services.Weather) Services.Weather.refresh()
    }
    function setWeatherAutoRefresh(val) { weatherAutoRefresh = val; saveConfig() }
    function setDashboardShowMetrics(val) { dashboardShowMetrics = val; saveConfig() }
    function setDashboardShowSpecs(val) { dashboardShowSpecs = val; saveConfig() }
    function setDashboardShowActions(val) { dashboardShowActions = val; saveConfig() }
    function setDashboardMetricsStyle(val) { dashboardMetricsStyle = val; saveConfig() }

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
    function setFontMono(family) { fontMono = family; saveConfig() }
    function setFontDisplay(family) { fontDisplay = family; saveConfig() }
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
