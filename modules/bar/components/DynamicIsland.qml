// DynamicIsland.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../../../services" as Services
import "../../media" as MediaModule

Item {
    id: root

    // ----- Public API & State -----
    property bool pinned: false
    property bool autoExpanded: false
    property int activeNotifIndex: 0

    // Inline Reply Type Zone State
    property bool replyMode: false
    property string activeReplyActionId: ""

    // Wallpaper Studio State inside Dynamic Island
    property bool wallpaperMode: false
    property int wallpaperIndex: 0

    // Drop & Send Hub State inside Dynamic Island
    property bool dropSendMode: false
    property string dropHoverTarget: "" // "kde" | "local" | ""
    property var dropUrls: []
    property string dropPreviewUrl: ""
    property int dropFileCount: 0
    property string dropFileName: ""
    property bool dropStagedChoice: false
    readonly property bool isDropSending: Services.DeviceShare ? (Services.DeviceShare.transferState === "sending" || Services.DeviceShare.transferState === "success") : false

    Timer {
        id: dropExitDebounceTimer
        interval: 650
        repeat: false
        onTriggered: {
            if (!root.isDropSending && !islandDropArea.containsDrag && !kdeDropTarget.containsDrag && !localDropTarget.containsDrag && !root.dropStagedChoice) {
                root.dropSendMode = false
                root.dropHoverTarget = ""
            }
        }
    }

    Timer {
        id: dropStagedAutoCollapseTimer
        interval: 12000
        repeat: false
        onTriggered: {
            if (root.dropStagedChoice && !root.isDropSending) {
                root.collapse()
            }
        }
    }

    Connections {
        target: Services.DeviceShare
        function onTransferStateChanged() {
            if (Services.DeviceShare && Services.DeviceShare.transferState === "idle") {
                root.dropSendMode = false
                root.dropStagedChoice = false
                root.dropUrls = []
                root.dropPreviewUrl = ""
            }
        }
    }

    function extractDropDetails(urls) {
        if (!urls || urls.length === 0) return
        root.dropUrls = urls
        root.dropFileCount = urls.length
        let path = urls[0].toString()
        if (path.startsWith("file://")) path = path.substring(7)
        try { path = decodeURIComponent(path) } catch (e) {}
        root.dropFileName = path.substring(path.lastIndexOf("/") + 1)
        
        let lower = path.toLowerCase()
        if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".webp") || lower.endsWith(".gif") || lower.endsWith(".svg") ||
            lower.endsWith(".ico") || lower.endsWith(".bmp")) {
            root.dropPreviewUrl = "file://" + path
        } else {
            root.dropPreviewUrl = ""
        }
    }

    function handleDropOnKde(urls) {
        extractDropDetails(urls)
        if (Services.DeviceShare) {
            Services.DeviceShare.sendKdeConnect(Services.DeviceShare.defaultDevice ? Services.DeviceShare.defaultDevice.id : "", urls)
        }
        root.dropHoverTarget = ""
        root.dropStagedChoice = false
    }

    function handleDropOnLocalSend(urls) {
        extractDropDetails(urls)
        if (Services.DeviceShare) {
            Services.DeviceShare.sendLocalSend(urls)
        }
        root.dropHoverTarget = ""
        root.dropStagedChoice = false
    }

    function handleDropGeneral(urls) {
        extractDropDetails(urls)
        root.dropStagedChoice = true
        root.dropHoverTarget = ""
        dropStagedAutoCollapseTimer.restart()
    }

    onWallpaperIndexChanged: {
        if (wallpaperMode && islandWallList) {
            islandWallList.positionViewAtIndex(wallpaperIndex, ListView.Contain)
        }
    }

    onWallpaperModeChanged: {
        if (wallpaperMode) {
            Qt.callLater(() => {
                if (islandWallList) {
                    islandWallList.forceActiveFocus()
                    islandWallList.positionViewAtIndex(wallpaperIndex, ListView.Contain)
                }
            })
        }
    }

    readonly property var wallpaperList: {
        const all = (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers : []
        return all.concat([{ isAddAction: true }])
    }

    // Island visual dimensions for window masking
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property int islandWidth: island.width
    readonly property int islandHeight: island.height

    // Lockscreen compatibility
    property bool allowOnLockscreen: true
    readonly property bool lockBlocked: Services.OverlayManager.isLocked

    // Notification model shortcuts
    readonly property var popupList: Services.Notifications.popupList
    readonly property int notifCount: popupList ? popupList.count : 0
    readonly property bool notifActive: !(Services.Workspaces && Services.Workspaces.isFullscreen) && (notifCount > 0)

    // System HUD Alert State (Mute, DnD, Charging, Camera)
    property bool sysHudActive: false
    property string sysHudIcon: ""
    property string sysHudTitle: ""
    property string sysHudDetail: ""
    property color sysHudColor: Services.Theme.accent
    property bool hudReady: false
    property var lastAudioSink: null
    property bool lastAudioMuted: false

    // Camera Active State & Monitoring
    property bool cameraActive: false
    readonly property bool isMediaSatellite: !Services.OverlayManager.isLocked && mediaPlaying && (notifActive || sysHudActive || wallpaperMode || dropSendMode || isDropSending)
    readonly property bool isCameraSatellite: cameraActive && (mediaPlaying || mediaStopping || showCollapsedText || expanded)
    readonly property int satelliteExtraWidth: (isMediaSatellite ? 40 : 0) + (isCameraSatellite ? 40 : 0) + ((capsLockActive && !expanded) ? 40 : 0)

    // CapsLock Active State & Monitoring
    property bool capsLockActive: false

    // NetworkManager / Wi-Fi State Monitoring
    property bool wifiLastConnected: false
    property string wifiLastSsid: ""

    // Bluetooth Devices State Monitoring
    property var btConnectedDevices: ({})
    property bool btInitialized: false

    // Media Stop Animation Choreography
    property bool mediaStopping: false
    property bool mediaTextCollapsed: false
    property bool mediaIconTransformed: false

    Timer {
        id: mediaStopPhase1Timer
        interval: 220
        repeat: false
        onTriggered: {
            root.mediaTextCollapsed = true
            mediaStopPhase2Timer.restart()
        }
    }

    Timer {
        id: mediaStopPhase2Timer
        interval: 360
        repeat: false
        onTriggered: {
            root.mediaIconTransformed = true
            root.mediaStopping = false
        }
    }

    Timer {
        id: cameraPollTimer
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cameraProc.running) cameraProc.running = true
        }
    }

    Process {
        id: cameraProc
        command: ["sh", "-c", "ls /dev/video* >/dev/null 2>&1 || { echo 0; exit 0; }; pids=$(fuser /dev/video* 2>/dev/null); [ -z \"$pids\" ] && { echo 0; exit 0; }; active=0; for p in $pids; do cmd=$(ps -p \"$p\" -o args= 2>/dev/null); case \"$cmd\" in *faceid-helper*) ;; *) active=1; break ;; esac; done; echo $active"]
        stdout: SplitParser {
            onRead: data => {
                const isActive = data.trim() === "1"
                root.cameraActive = isActive
            }
        }
    }

    Timer {
        id: capsLockPollTimer
        interval: 1200
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!capsLockProc.running) capsLockProc.running = true
        }
    }

    Process {
        id: capsLockProc
        command: ["sh", "-c", "grep -qh 1 /sys/class/leds/*capslock*/brightness 2>/dev/null && echo 1 || echo 0"]
        stdout: SplitParser {
            onRead: data => {
                const isActive = data.trim() === "1"
                if (root.capsLockActive !== isActive) {
                    root.capsLockActive = isActive
                }
            }
        }
    }

    // ── USB Plug/Unplug Sound Feedback ───────────────────────────────────────
    // Monitor udev USB events and play freedesktop device-added/removed sounds.
    // Filter to UDEV (processed) events only on usb_device (not hub ports).
    property bool usbSoundReady: false
    property string lastUsbAction: ""
    Timer {
        id: usbSoundThrottle
        interval: 800   // debounce — USB enumeration fires many events at once
        repeat: false
        onTriggered: {
            if (root.lastUsbAction === "add")
                Services.SoundFeedback.playDeviceAdded()
            else if (root.lastUsbAction === "remove")
                Services.SoundFeedback.playDeviceRemoved()
            root.lastUsbAction = ""
        }
    }

    Process {
        id: usbMonitorProc
        // udevadm --property emits blocks like:
        //   UDEV  [...]
        //   ACTION=add
        //   DEVTYPE=usb_device
        // We grab ACTION= lines and DEVTYPE= lines, filter only usb_device actions.
        command: ["sh", "-c",
            "udevadm monitor --udev --subsystem-match=usb --property 2>/dev/null" +
            " | stdbuf -oL awk '/^ACTION=/{act=$0} /^DEVTYPE=usb_device/{print act}'" +
            " | stdbuf -oL sed 's/ACTION=//'"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!root.hudReady) return
                const action = data.trim()
                if (action === "add" || action === "remove") {
                    root.lastUsbAction = action
                    usbSoundThrottle.restart()
                }
            }
        }
    }

    onCameraActiveChanged: {
        if (cameraActive && hudReady && root.notifCount === 0 && !Services.OverlayManager.isLocked) {
            root.showSysHud("󰄀", "Camera Active", "Webcam in use", Services.Theme.success)
        }
    }

    onCapsLockActiveChanged: {
        if (!hudReady) return
        const icon = "󰘶"
        const title = capsLockActive ? "Caps Lock On" : "Caps Lock Off"
        const detail = capsLockActive ? "Uppercase enabled" : "Standard lowercase"
        root.showSysHud(icon, title, detail, capsLockActive ? Services.Theme.alertYellow : Services.Theme.danger)
    }

    function showSysHud(icon, title, detail, iconColor, customDuration) {
        if (root.notifActive || root.wallpaperMode) return
        sysHudIcon = icon
        sysHudTitle = title
        sysHudDetail = detail || ""
        sysHudColor = iconColor || Services.Theme.accent
        sysHudActive = true
        sysHudTimer.interval = customDuration || 2200
        sysHudTimer.restart()
    }

    Timer {
        id: sysHudTimer
        interval: 2200
        onTriggered: root.sysHudActive = false
    }

    Timer {
        id: hudInitTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            root.hudReady = true
            welcomeProc.running = true
        }
    }

    Process {
        id: welcomeProc
        command: ["sh", "-c", "whoami || echo $USER"]
        stdout: SplitParser {
            onRead: data => {
                const rawUser = data.trim()
                const user = rawUser ? rawUser.charAt(0).toUpperCase() + rawUser.slice(1) : "User"
                const icon = Services.OsInfo.logoGlyph || "󰀉"
                root.showSysHud(icon, "Welcome back!", "Logged in as " + user, Services.Theme.accent, 3500)
            }
        }
    }

    Component.onCompleted: {
        root.lastAudioSink = Services.Audio.sink
        if (Services.Audio.sink) {
            root.lastAudioMuted = Services.Audio.muted
        }
    }

    // Connections for System Events
    Connections {
        target: Services.Audio
        function onMutedChanged() {
            if (!root.hudReady || !Services.Audio.sink) return

            const currentSink = Services.Audio.sink
            // If sink changed (e.g. bluetooth disconnect/connect), update sink ref and ignore fake mute notification
            if (root.lastAudioSink !== currentSink) {
                root.lastAudioSink = currentSink
                root.lastAudioMuted = Services.Audio.muted
                return
            }

            const isMuted = Services.Audio.muted
            if (root.lastAudioMuted === isMuted) return
            root.lastAudioMuted = isMuted

            const vol = Services.Audio.volume || 0
            const icon = Services.Icons.volumeIcon(vol, isMuted, Services.Audio.isHeadphone, Services.Audio.isTws)
            const title = isMuted ? "Audio Muted" : "Audio Unmuted"
            const detail = Math.round(vol * 100) + "%"
            root.showSysHud(icon, title, detail, isMuted ? Services.Theme.danger : Services.Theme.success)
        }

        function onSinkChanged() {
            if (root.lastAudioSink !== Services.Audio.sink) {
                root.lastAudioSink = Services.Audio.sink
                if (Services.Audio.sink) {
                    root.lastAudioMuted = Services.Audio.muted
                }
            }
        }
    }

    Connections {
        target: Services.Notifications
        function onDoNotDisturbChanged() {
            if (!root.hudReady) return
            const dnd = Services.Notifications.doNotDisturb
            const icon = dnd ? "󰂛" : "󰂚"
            const title = dnd ? "Do Not Disturb" : "Notifications On"
            const detail = dnd ? "On" : "Off"
            root.showSysHud(icon, title, detail, dnd ? Services.Theme.danger : Services.Theme.accent)
        }
    }

    Connections {
        target: Services.Power
        function onChargingChanged() {
            if (!root.hudReady) return
            const isCharging = Services.Power.charging
            const rawPct = Services.Power.percentage || 0
            const pct = Math.round(rawPct > 1 ? rawPct : rawPct * 100)
            const icon = Services.Icons.powerIcon(isCharging, pct)
            const title = isCharging ? "Charging" : "Discharging"
            const detail = pct + "%"
            root.showSysHud(icon, title, detail, isCharging ? Services.Theme.success : Services.Theme.accent)
            // Sound feedback for charge/discharge
            if (isCharging) Services.SoundFeedback.playPowerPlug()
            else Services.SoundFeedback.playPowerUnplug()
        }

        function onBatteryWarning(level, title, message) {
            if (!root.hudReady) return
            const icon = Services.Icons.powerIcon(false, level)
            const color = level <= 10 ? Services.Theme.danger : "#ff9800"
            root.showSysHud(icon, title, message, color)
        }
    }

    Connections {
        target: Services.PowerProfile
        function onSaverEnabledChanged() {
            if (!root.hudReady) return
            const isSaver = Services.PowerProfile.saverEnabled
            const icon = Services.Icons.tree
            const title = isSaver ? "Power Saver On" : "Power Saver Off"
            const detail = isSaver ? "Battery saver active" : "Standard performance"
            root.showSysHud(icon, title, detail, isSaver ? "#ff9800" : Services.Theme.accent)
        }
    }

    Connections {
        target: Services.Wifi
        function onConnectedChanged() {
            const isConn = Services.Wifi.connected
            const currentSsid = Services.Wifi.ssid

            if (!root.hudReady) {
                root.wifiLastConnected = isConn
                if (currentSsid) root.wifiLastSsid = currentSsid
                return
            }

            if (isConn && !root.wifiLastConnected) {
                const name = currentSsid || root.wifiLastSsid || "Network"
                root.showSysHud("󰤨", "Wi-Fi Connected", name, Services.Theme.success)
                if (currentSsid) root.wifiLastSsid = currentSsid
            } else if (!isConn && root.wifiLastConnected) {
                const name = root.wifiLastSsid || "Network"
                root.showSysHud("󰤭", "Wi-Fi Disconnected", name, Services.Theme.danger)
            }
            root.wifiLastConnected = isConn
        }

        function onSsidChanged() {
            if (Services.Wifi.ssid && Services.Wifi.ssid !== "") {
                if (root.hudReady && Services.Wifi.connected && root.wifiLastConnected && root.wifiLastSsid !== "" && root.wifiLastSsid !== Services.Wifi.ssid) {
                    root.showSysHud("󰤨", "Wi-Fi Switched", Services.Wifi.ssid, Services.Theme.accent)
                }
                root.wifiLastSsid = Services.Wifi.ssid
            }
        }

        function onEnabledChanged() {
            if (!root.hudReady) return
            const isEnabled = Services.Wifi.enabled
            const icon = isEnabled ? "󰤨" : "󰤭"
            const title = isEnabled ? "Wi-Fi On" : "Wi-Fi Off"
            const detail = isEnabled ? "Wi-Fi enabled" : "Wi-Fi disabled"
            root.showSysHud(icon, title, detail, isEnabled ? Services.Theme.accent : Services.Theme.danger)
        }
    }

    Connections {
        target: Services.Bluetooth
        function onDevicesChanged() {
            const currentDevices = Services.Bluetooth.devices || []
            const newMap = {}

            for (let i = 0; i < currentDevices.length; i++) {
                const dev = currentDevices[i]
                if (dev && dev.connected && dev.mac) {
                    const mac = dev.mac.toLowerCase()
                    newMap[mac] = {
                        name: dev.name || dev.mac,
                        battery: (dev.battery !== undefined && dev.battery >= 0) ? dev.battery : -1,
                        icon: dev.icon || ""
                    }
                }
            }

            if (!root.hudReady || !root.btInitialized) {
                root.btConnectedDevices = newMap
                root.btInitialized = true
                return
            }

            // Detect newly connected devices
            for (const mac in newMap) {
                if (!root.btConnectedDevices[mac]) {
                    const devInfo = newMap[mac]
                    const devName = typeof devInfo === "string" ? devInfo : devInfo.name
                    const battery = typeof devInfo === "object" ? devInfo.battery : -1
                    const devIconType = (typeof devInfo === "object" ? (devInfo.icon || "") : "").toLowerCase()

                    // Select HUD icon based on device type / name
                    let hudIcon = "󰂱"
                    if (devIconType.includes("headset") || devIconType.includes("headphone") || devName.toLowerCase().includes("tws") || devName.toLowerCase().includes("earbuds") || devName.toLowerCase().includes("airpods")) {
                        hudIcon = "󰋋"
                    } else if (devIconType.includes("speaker") || devIconType.includes("audio")) {
                        hudIcon = "󰓃"
                    } else if (devIconType.includes("phone") || devIconType.includes("cellphone")) {
                        hudIcon = "󰄋"
                    } else if (devIconType.includes("computer") || devIconType.includes("laptop")) {
                        hudIcon = "󰌢"
                    } else if (devIconType.includes("gamepad") || devIconType.includes("gaming")) {
                        hudIcon = "󰊴"
                    }

                    // Detail text with battery level if available
                    let detailText = devName
                    if (battery >= 0) {
                        detailText += " • " + battery + "%"
                    }

                    root.showSysHud(hudIcon, "Bluetooth Connected", detailText, Services.Theme.success)
                }
            }

            // Detect disconnected devices
            for (const mac in root.btConnectedDevices) {
                if (!newMap[mac]) {
                    const prevDev = root.btConnectedDevices[mac]
                    const devName = typeof prevDev === "string" ? prevDev : prevDev.name
                    root.showSysHud("󰂲", "Bluetooth Disconnected", devName, Services.Theme.danger)
                }
            }

            root.btConnectedDevices = newMap
        }

        function onEnabledChanged() {
            if (!root.hudReady) return
            const isEnabled = Services.Bluetooth.enabled
            if (!isEnabled) {
                root.btConnectedDevices = {}
            }
            const icon = isEnabled ? "󰂯" : "󰂲"
            const title = isEnabled ? "Bluetooth On" : "Bluetooth Off"
            const detail = isEnabled ? "Bluetooth enabled" : "Bluetooth disabled"
            root.showSysHud(icon, title, detail, isEnabled ? Services.Theme.accent : Services.Theme.danger)
        }
    }

    Connections {
        target: Services.Wallpaper
        function onCurrentWallpaperChanged() {
            if (!root.hudReady || !Services.Wallpaper || !Services.Wallpaper.currentWallpaper) return
            const path = Services.Wallpaper.currentWallpaper
            const name = path.substring(path.lastIndexOf("/") + 1)
            root.showSysHud(Services.Icons.image || "󰋩", "Wallpaper Applied", name, Services.Theme.accent, 2600)
        }
    }

    // MPRIS shortcuts
    readonly property var activePlayer: Services.Mpris.activePlayer
    readonly property bool mediaPlaying: activePlayer !== null && activePlayer.isPlaying
    readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle !== "" || mediaPlaying)

    readonly property bool hasExpandContent: notifActive || sysHudActive || hasMedia || wallpaperMode || dropSendMode || isDropSending
    readonly property bool expanded: !lockBlocked && hasExpandContent && (pinned || autoExpanded || notifActive || sysHudActive || wallpaperMode || dropSendMode || isDropSending)
    readonly property bool isMediaPeek: !lockBlocked && autoExpanded && !pinned && !notifActive && !sysHudActive && !wallpaperMode && !dropSendMode && !isDropSending && hasMedia

    property int autoExpandDuration: 2500
    property int notifDuration: 5000

    // Safe retrieval of current notification entry
    readonly property var currentNotif: {
        if (!popupList || notifCount === 0) return null
        const idx = Math.max(0, Math.min(activeNotifIndex, notifCount - 1))
        return popupList.get(idx)
    }

    onCurrentNotifChanged: {
        replyMode = false
        activeReplyActionId = ""
    }

    onReplyModeChanged: {
        if (replyMode) {
            if (currentNotif) {
                Services.Notifications.replyingNotifId = currentNotif.notifId
            }
            Qt.callLater(() => replyInput.forceActiveFocus())
        } else {
            Services.Notifications.replyingNotifId = -1
        }
    }

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    readonly property bool isCritical: currentNotif !== null && currentNotif.urgency === 2
    readonly property bool hasNotifBody: currentNotif !== null && currentNotif.body !== undefined && currentNotif.body.length > 0
    readonly property bool hasNotifActions: currentNotif !== null && currentNotif.actions !== undefined && (currentNotif.actions.count > 0 || (currentNotif.actions.length !== undefined && currentNotif.actions.length > 0))

    readonly property string currentMediaText: {
        if (!activePlayer) return ""
        const title = activePlayer.trackTitle || ""
        const artist = activePlayer.trackArtist || ""
        if (title !== "" && artist !== "") return title + " • " + artist
        return title || artist || "Playing"
    }

    property string lastTrackText: ""
    onMediaPlayingChanged: {
        if (mediaPlaying) {
            mediaStopPhase1Timer.stop()
            mediaStopPhase2Timer.stop()
            root.mediaStopping = false
            root.mediaTextCollapsed = false
            root.mediaIconTransformed = false
            if (currentMediaText !== "") {
                lastTrackText = currentMediaText
            }
        } else {
            if (root.hudReady && !root.notifActive) {
                root.mediaStopping = true
                root.mediaTextCollapsed = false
                root.mediaIconTransformed = false
                mediaStopPhase1Timer.restart()
            }
        }
    }
    onCurrentMediaTextChanged: {
        if (mediaPlaying && currentMediaText !== "") {
            lastTrackText = currentMediaText
        }
    }
    onExpandedChanged: {
        if (typeof collapsedText !== "undefined") {
            collapsedText.x = 0
        }
    }

    // Island Dimensions
    readonly property bool showCollapsedText: !lockBlocked && (notifActive || mediaPlaying)
    readonly property int calculatedCollapsedWidth: {
        if (showCollapsedText || (mediaStopping && !mediaTextCollapsed)) {
            const extraPadding = mediaPlaying ? 72 : 52
            return Math.min(220, Math.max(140, collapsedText.implicitWidth + extraPadding))
        }
        return 140
    }
    property int collapsedWidth: 140
    property int collapsedHeight: 32

    readonly property int calculatedExpandedWidth: {
        if (notifActive) return replyMode ? 390 : 360
        if (dropSendMode) return 500
        if (isDropSending) return 400
        if (wallpaperMode) return 480
        if (sysHudActive) return 280
        if (isMediaPeek) return 280
        if (hasMedia) return 360
        return 260
    }

    readonly property int calculatedExpandedHeight: {
        if (notifActive) {
            if (replyMode) return 146
            let h = 72
            if (hasNotifBody) h += 24
            if (hasNotifActions) h += 32
            return h
        }
        if (dropSendMode) return 148
        if (isDropSending) return 64
        if (wallpaperMode) return 120
        if (sysHudActive) return 54
        if (isMediaPeek) return 54
        if (hasMedia) return 138
        return 52
    }

    // Format seconds → "m:ss"
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function pulse() {
        if (pinned || notifActive) return
        autoExpanded = true
        autoCollapseTimer.restart()
    }

    function togglePin() {
        if (!hasExpandContent) return
        if (expanded) {
            collapse()
        } else {
            pinned = true
        }
    }

    function collapse() {
        pinned = false
        autoExpanded = false
        replyMode = false
        wallpaperMode = false
        dropSendMode = false
        dropStagedChoice = false
        dropHoverTarget = ""
        if (notifActive && currentNotif) {
            Services.Notifications.dismiss(currentNotif.notifId)
        }
    }

    function toggleWallpaperMode() {
        if (lockBlocked) return
        if (wallpaperMode) {
            collapse()
        } else {
            pinned = false
            autoExpanded = false
            autoCollapseTimer.stop()
            replyMode = false
            sysHudActive = false
            sysHudTimer.stop()
            wallpaperMode = true
            if (Services.Wallpaper && Services.Wallpaper.currentWallpaper) {
                const cur = Services.Wallpaper.currentWallpaper
                const list = wallpaperList || []
                for (let i = 0; i < list.length; i++) {
                    if (list[i].path === cur || (list[i].isDynamic && Services.Wallpaper.isWallblerActive)) {
                        wallpaperIndex = i
                        break
                    }
                }
            }
        }
    }

    Connections {
        target: Services.OverlayManager
        function onWallpaperToggleRequested() { root.toggleWallpaperMode() }
        function onWallpaperShowRequested() { root.toggleWallpaperMode() }
        function onIsLockedChanged() {
            if (Services.OverlayManager.isLocked) {
                if (root.sysHudActive && root.sysHudTitle === "Camera Active") {
                    root.sysHudActive = false
                }
            } else {
                if (root.sysHudActive && root.sysHudTitle === "Camera Active") {
                    root.sysHudActive = false
                }
                if (!cameraProc.running) cameraProc.running = true
            }
        }
    }

    function nextNotif() {
        if (notifCount > 0) {
            activeNotifIndex = (activeNotifIndex + 1) % notifCount
            notifTimer.restart()
        }
    }

    function prevNotif() {
        if (notifCount > 0) {
            activeNotifIndex = (activeNotifIndex - 1 + notifCount) % notifCount
            notifTimer.restart()
        }
    }

    Timer {
        id: mprisRefreshTimer
        interval: 500
        running: root.mediaPlaying
        repeat: true
        onTriggered: root.activePlayer?.positionChanged?.()
    }

    Timer {
        id: autoCollapseTimer
        interval: root.autoExpandDuration
        onTriggered: root.autoExpanded = false
    }

    Timer {
        id: notifTimer
        interval: root.notifDuration
        repeat: false
        onTriggered: {
            if (root.replyMode) return
            if (root.notifCount > 1 && root.activeNotifIndex < root.notifCount - 1) {
                root.activeNotifIndex++
                notifTimer.restart()
            }
        }
    }

    Connections {
        target: Services.Notifications
        function onNewNotification(entry) {
            root.wallpaperMode = false
            root.sysHudActive = false
            sysHudTimer.stop()
            root.activeNotifIndex = 0
            root.replyMode = false
            notifTimer.restart()
        }
    }

    Connections {
        target: Services.Mpris
        function onActivePlayerChanged() {
            if (root.hudReady && Services.Mpris.activePlayer && Services.Mpris.activePlayer.isPlaying && root.notifCount === 0 && !root.pinned) {
                root.pulse()
            }
        }
    }

    Connections {
        target: root.activePlayer
        function onIsPlayingChanged() {
            if (root.hudReady && root.activePlayer && root.activePlayer.isPlaying && root.notifCount === 0 && !root.pinned) {
                root.pulse()
            }
        }
        function onTrackTitleChanged() {
            if (root.hudReady && root.activePlayer && root.activePlayer.isPlaying && root.notifCount === 0 && !root.pinned) {
                root.pulse()
            }
        }
    }

    // Click outside area to collapse expanded island
    MouseArea {
        id: outsideMouseArea
        anchors.fill: parent
        enabled: root.expanded
        visible: root.expanded
        z: -1
        propagateComposedEvents: true
        onClicked: mouse => {
            root.collapse()
            mouse.accepted = false
        }
    }

    // ── Seamless Adaptive Morphing Capsule Island ──
    Rectangle {
        id: island
        z: 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.isBottom ? (parent.height - height - 6) : 6
        clip: true

        // Direct Reactive Dimensions adapting to content type
        width: root.expanded ? root.calculatedExpandedWidth : root.calculatedCollapsedWidth
        height: root.expanded ? root.calculatedExpandedHeight : root.collapsedHeight

        readonly property bool isCapsuleShape: !root.expanded || (!root.notifActive && root.sysHudActive)
        radius: isCapsuleShape ? (height / 2) : Services.Theme.radiusLg

        color: Services.Theme.bgPure
        border.color: root.isCritical ? Services.Theme.danger : (root.expanded ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
        border.width: root.isCritical ? 1.5 : 1

        // Seamless, Continuous Fluid Morphing (Zero delay, zero hitching, pure iOS ease - synchronized with Lockscreen)
        Behavior on width {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutBack
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutBack
            }
        }
        Behavior on radius {
            enabled: !island.isCapsuleShape || root.notifActive
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            id: islandMouseArea
            anchors.fill: parent
            z: 0
            enabled: root.hasExpandContent && !root.dropSendMode && !root.isDropSending
            cursorShape: (root.hasExpandContent && !root.dropSendMode && !root.isDropSending) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.togglePin()
        }

        // Global DropArea over Island
        DropArea {
            id: islandDropArea
            anchors.fill: parent
            z: 5
            onEntered: (drag) => {
                dropExitDebounceTimer.stop()
                root.extractDropDetails(drag.urls)
                root.dropSendMode = true
            }
            onPositionChanged: (drag) => {
                dropExitDebounceTimer.stop()
                if (!root.dropSendMode) root.dropSendMode = true
            }
            onExited: () => {
                dropExitDebounceTimer.restart()
            }
            onDropped: (drop) => {
                dropExitDebounceTimer.stop()
                root.extractDropDetails(drop.urls)
                if (root.dropHoverTarget === "kde") {
                    root.handleDropOnKde(drop.urls)
                } else if (root.dropHoverTarget === "local") {
                    root.handleDropOnLocalSend(drop.urls)
                } else {
                    root.handleDropGeneral(drop.urls)
                }
            }
        }



        // ==================== Camera Privacy Indicator (Right Edge when not detached) ====================
        Item {
            id: cameraIndicator
            anchors.right: island.right
            anchors.rightMargin: 10
            anchors.verticalCenter: island.verticalCenter
            implicitWidth: 14
            implicitHeight: 14
            z: 2
            visible: (root.cameraActive && root.showCollapsedText && !root.isCameraSatellite) || opacity > 0
            opacity: (root.cameraActive && root.showCollapsedText && !root.isCameraSatellite) ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }

            // Blinking Green Privacy Dot
            Rectangle {
                anchors.centerIn: parent
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: Services.Theme.success

                SequentialAnimation on opacity {
                    running: root.cameraActive
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }

        // ==================== Collapsed Status Icon (Left Edge / Centered when Idle) ====================
        Item {
            id: statusIconContainer
            anchors.verticalCenter: island.verticalCenter
            implicitWidth: 16
            implicitHeight: 16
            z: 3

            readonly property bool activeState: !root.expanded
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.4
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            states: [
                State {
                    name: "ICON_LEFT"
                    when: !Services.OverlayManager.isLocked && (root.showCollapsedText || root.mediaStopping)
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: undefined
                        anchors.left: island.left
                        anchors.right: undefined
                    }
                    PropertyChanges {
                        target: statusIconContainer
                        anchors.leftMargin: 12
                    }
                },
                State {
                    name: "LOCKED_COLLAPSED"
                    when: Services.OverlayManager.isLocked
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: undefined
                        anchors.left: island.left
                        anchors.right: undefined
                    }
                    PropertyChanges {
                        target: statusIconContainer
                        anchors.leftMargin: 12
                    }
                },
                State {
                    name: "IDLE_CENTER"
                    when: !Services.OverlayManager.isLocked && !root.showCollapsedText && !root.mediaStopping && !root.cameraActive
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: island.horizontalCenter
                        anchors.left: undefined
                        anchors.right: undefined
                    }
                },
                State {
                    name: "CAMERA_RIGHT"
                    when: !Services.OverlayManager.isLocked && (!root.showCollapsedText && !root.mediaStopping && root.cameraActive)
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: undefined
                        anchors.left: undefined
                        anchors.right: island.right
                    }
                    PropertyChanges {
                        target: statusIconContainer
                        anchors.rightMargin: 12
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "ICON_LEFT"; to: "IDLE_CENTER"
                    AnchorAnimation { duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "anchors.leftMargin"; duration: 320; easing.type: Easing.OutCubic }
                },
                Transition {
                    AnchorAnimation { duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "anchors.rightMargin"; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "anchors.leftMargin"; duration: 320; easing.type: Easing.OutCubic }
                }
            ]

            transform: Scale {
                id: statusIconSquishScale
                origin.x: 8
                origin.y: 8
                xScale: 1.0
                yScale: 1.0
            }

            SequentialAnimation {
                id: statusIconSquishAnim
                ParallelAnimation {
                    NumberAnimation { target: statusIconSquishScale; property: "xScale"; to: 1.25; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: statusIconSquishScale; property: "yScale"; to: 0.80; duration: 110; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: statusIconSquishScale; property: "xScale"; to: 0.94; duration: 140; easing.type: Easing.OutQuad }
                    NumberAnimation { target: statusIconSquishScale; property: "yScale"; to: 1.06; duration: 140; easing.type: Easing.OutQuad }
                }
                ParallelAnimation {
                    NumberAnimation { target: statusIconSquishScale; property: "xScale"; to: 1.0; duration: 100; easing.type: Easing.OutCubic }
                    NumberAnimation { target: statusIconSquishScale; property: "yScale"; to: 1.0; duration: 100; easing.type: Easing.OutCubic }
                }
            }

            readonly property string targetGlyph: {
                if (Services.OverlayManager.isLocked) return "󰌾"
                if (root.notifActive) return "󰂚"
                if (root.mediaPlaying || root.mediaStopping) return "󰎈"
                return ""
            }

            readonly property color targetGlyphColor: {
                if (Services.OverlayManager.isLocked) return Services.Theme.accent
                if (root.notifActive) return Services.Theme.accent
                if (root.mediaPlaying || root.mediaStopping || root.cameraActive) return Services.Theme.success
                return Services.Theme.textDisabled
            }

            readonly property bool isIdleDot: targetGlyph === ""

            onTargetGlyphChanged: {
                statusIconSquishAnim.restart()
                morphToNextGlyph(targetGlyph, targetGlyphColor)
            }

            onTargetGlyphColorChanged: {
                if (useSlotA) {
                    slotAGlyph.color = targetGlyphColor
                } else {
                    slotBGlyph.color = targetGlyphColor
                }
            }

            property bool useSlotA: true

            function morphToNextGlyph(glyph, glyphColor) {
                if (glyph === "") {
                    slotAAnimOut.restart()
                    slotBAnimOut.restart()
                    return
                }

                if (useSlotA) {
                    slotBGlyph.text = glyph
                    slotBGlyph.color = glyphColor
                    slotAAnimOut.restart()
                    slotBAnimIn.restart()
                    useSlotA = false
                } else {
                    slotAGlyph.text = glyph
                    slotAGlyph.color = glyphColor
                    slotBAnimOut.restart()
                    slotAAnimIn.restart()
                    useSlotA = true
                }
            }

            // Pure Geometric Dot for Idle State (Fluid Bloom & Splash)
            Rectangle {
                id: idleDot
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 3.5
                color: root.cameraActive ? Services.Theme.success : Services.Theme.textDisabled
                visible: opacity > 0.01
                opacity: statusIconContainer.isIdleDot ? 1.0 : 0.0
                scale: statusIconContainer.isIdleDot ? 1.0 : 0.2

                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                // Green Blinking when camera active while idle
                SequentialAnimation on opacity {
                    running: root.cameraActive && statusIconContainer.isIdleDot && !root.showCollapsedText && !root.expanded
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // Rotating Glyph Container with Dual-Layer Morph Slots
            Item {
                id: glyphRotator
                anchors.centerIn: parent
                width: 16
                height: 16
                visible: !statusIconContainer.isIdleDot || slotAGlyph.opacity > 0.01 || slotBGlyph.opacity > 0.01

                rotation: (!Services.OverlayManager.isLocked && root.mediaPlaying && !root.expanded) ? rotation : 0

                Behavior on rotation {
                    RotationAnimation {
                        direction: RotationAnimation.Clockwise
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }

                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: 4000
                    loops: Animation.Infinite
                    running: !Services.OverlayManager.isLocked && root.mediaPlaying && !root.expanded
                }

                Text {
                    id: slotAGlyph
                    anchors.centerIn: parent
                    text: statusIconContainer.targetGlyph
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: statusIconContainer.targetGlyphColor
                    opacity: !statusIconContainer.isIdleDot ? 1.0 : 0.0
                    scale: !statusIconContainer.isIdleDot ? 1.0 : 0.3
                    transformOrigin: Item.Center
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }

                Text {
                    id: slotBGlyph
                    anchors.centerIn: parent
                    text: ""
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: statusIconContainer.targetGlyphColor
                    opacity: 0.0
                    scale: 0.3
                    transformOrigin: Item.Center
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }

                ParallelAnimation {
                    id: slotAAnimIn
                    NumberAnimation { target: slotAGlyph; property: "opacity"; from: 0.0; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slotAGlyph; property: "scale"; from: 0.35; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    id: slotAAnimOut
                    NumberAnimation { target: slotAGlyph; property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.InQuad }
                    NumberAnimation { target: slotAGlyph; property: "scale"; to: 0.25; duration: 180; easing.type: Easing.InQuad }
                }

                ParallelAnimation {
                    id: slotBAnimIn
                    NumberAnimation { target: slotBGlyph; property: "opacity"; from: 0.0; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slotBGlyph; property: "scale"; from: 0.35; to: 1.0; duration: 320; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    id: slotBAnimOut
                    NumberAnimation { target: slotBGlyph; property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.InQuad }
                    NumberAnimation { target: slotBGlyph; property: "scale"; to: 0.25; duration: 180; easing.type: Easing.InQuad }
                }
            }
        }

        // ==================== Mini Audio Wave Visualizer (Right Edge) ====================
        MediaModule.CavaWave {
            id: mediaVisualizer
            anchors.right: island.right
            anchors.rightMargin: 12
            anchors.verticalCenter: island.verticalCenter
            z: 3
            barCount: 4
            barWidth: 2.8
            barSpacing: 2.2
            minHeight: 3.5
            maxHeight: 16.0
            barColor: Services.Theme.success
            isPlaying: root.mediaPlaying
            active: visible
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.mediaPlaying && !root.expanded && !root.notifActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1.0 : 0.0
            scale: activeState ? 1.0 : 0.3
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        // ==================== Dedicated Collapsed Track Title / Notif Text Zone ====================
        Item {
            id: collapsedTextContainer
            anchors.left: statusIconContainer.right
            anchors.leftMargin: 6
            anchors.right: mediaVisualizer.visible ? mediaVisualizer.left : (cameraIndicator.visible ? cameraIndicator.left : island.right)
            anchors.rightMargin: (mediaVisualizer.visible || cameraIndicator.visible) ? 6 : 12
            anchors.verticalCenter: island.verticalCenter
            height: 16
            z: 3

            readonly property bool showCollapsedText: !Services.OverlayManager.isLocked && (root.notifActive || root.mediaPlaying)
            readonly property bool activeState: !Services.OverlayManager.isLocked && !root.expanded && showCollapsedText

            clip: true
            transformOrigin: Item.Left
            opacity: activeState ? 1.0 : 0.0
            scale: activeState ? 1.0 : 0.8
            visible: activeState || opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

            Text {
                id: collapsedText
                text: Services.OverlayManager.isLocked ? "Locked" : (root.notifActive ? ("Notif (" + root.notifCount + ")") : (root.mediaPlaying ? root.currentMediaText : root.lastTrackText))
                font.pixelSize: 11
                font.bold: true
                color: Services.Theme.textPrimary
                width: collapsedTextContainer.width
                horizontalAlignment: (collapsedText.implicitWidth > collapsedTextContainer.width) ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: marqueeAnim.running ? Text.ElideNone : Text.ElideRight

                onTextChanged: {
                    collapsedText.x = 0
                    if (marqueeAnim.running) {
                        marqueeAnim.restart()
                    }
                }

                SequentialAnimation on x {
                    id: marqueeAnim
                    running: root.mediaPlaying && !root.expanded && !Services.OverlayManager.isLocked && collapsedText.implicitWidth > collapsedTextContainer.width
                    loops: Animation.Infinite

                    onRunningChanged: {
                        if (!running) {
                            collapsedText.x = 0
                        }
                    }

                    PauseAnimation { duration: 1500 }
                    NumberAnimation {
                        to: -(collapsedText.implicitWidth - collapsedTextContainer.width + 4)
                        duration: Math.max(2500, (collapsedText.implicitWidth - collapsedTextContainer.width) * 45)
                        easing.type: Easing.InOutQuad
                    }
                    PauseAnimation { duration: 1500 }
                    NumberAnimation {
                        to: 0
                        duration: Math.max(2500, (collapsedText.implicitWidth - collapsedTextContainer.width) * 45)
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }

        // ==================== Expanded: Notifications ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && root.notifActive && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            // Header: Icon, AppName, Queue Indicator, Controls & Close
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // App Icon / Image
                Item {
                    implicitWidth: 20
                    implicitHeight: 20
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: appIconImg
                        anchors.fill: parent
                        source: {
                            if (!root.currentNotif) return ""
                            const src = root.currentNotif.image || root.currentNotif.appIcon || ""
                            if (!src) return ""
                            if (src.startsWith("file://") || src.startsWith("http://") || src.startsWith("https://"))
                                return src
                            if (src.startsWith("/"))
                                return "file://" + src
                            if (Services.SystemTheme) {
                                const res = Services.SystemTheme.getIcon(src)
                                if (res && res.length > 0) return res
                            }
                            const qp = Quickshell.iconPath(src, true)
                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                        }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(40, 40)
                        visible: status === Image.Ready && source.toString().length > 0
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 14
                        color: Services.Theme.accent
                        visible: !appIconImg.visible
                    }
                }

                // App Name
                Text {
                    text: root.currentNotif ? root.currentNotif.appName : ""
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Queue indicator & Navigation if multiple notifications
                RowLayout {
                    spacing: 4
                    visible: root.notifCount > 1 && !root.replyMode
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        color: Services.Theme.surfaceVariant
                        radius: 8
                        implicitWidth: queueText.implicitWidth + 10
                        implicitHeight: 18

                        Text {
                            id: queueText
                            anchors.centerIn: parent
                            text: (root.activeNotifIndex + 1) + "/" + root.notifCount
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // Prev Notif Button
                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20
                        radius: 10
                        color: prevMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: "‹"; color: Services.Theme.textPrimary; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => { root.prevNotif(); mouse.accepted = true }
                        }
                    }

                    // Next Notif Button
                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20
                        radius: 10
                        color: nextMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: "›"; color: Services.Theme.textPrimary; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => { root.nextNotif(); mouse.accepted = true }
                        }
                    }
                }

                // Dismiss Button (X)
                Rectangle {
                    implicitWidth: 20; implicitHeight: 20
                    radius: 10
                    color: dismissBtnMouse.containsMouse ? Services.Theme.danger : Services.Theme.surfaceVariant
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: dismissBtnMouse.containsMouse ? "#ffffff" : Services.Theme.textPrimary
                        font.pixelSize: 10
                        font.bold: true
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: dismissBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (root.currentNotif) {
                                root.replyMode = false
                                Services.Notifications.dismiss(root.currentNotif.notifId)
                            }
                            mouse.accepted = true
                        }
                    }
                }
            }

            // Summary & Body (Only when NOT in Reply Mode)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: !root.replyMode

                Text {
                    text: root.currentNotif ? (root.currentNotif.summary || "") : ""
                    color: Services.Theme.textPrimary
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.hasNotifBody
                    text: root.currentNotif ? (root.currentNotif.body || "") : ""
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Action Buttons (Only when NOT in Reply Mode)
            RowLayout {
                id: notifActionsRow
                visible: root.hasNotifActions && !root.replyMode
                spacing: 6
                Layout.topMargin: 2
                Layout.fillWidth: true

                Repeater {
                    model: root.currentNotif ? root.currentNotif.actions : null
                    delegate: Rectangle {
                        id: actBtn
                        required property string identifier
                        required property string text

                        implicitHeight: 24
                        implicitWidth: actLabel.implicitWidth + 16
                        radius: Services.Theme.radiusSm
                        color: actMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.surfaceVariant

                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: actBtn.text
                            color: Services.Theme.textPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                if (root.currentNotif) {
                                    if (root.isReplyAction(actBtn)) {
                                        root.activeReplyActionId = actBtn.identifier
                                        root.replyMode = true
                                    } else {
                                        Services.Notifications.invokeAction(root.currentNotif.notifId, actBtn.identifier)
                                    }
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }

            // ==================== Type Zone (Inline Reply Mode) ====================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.replyMode

                Text {
                    text: root.currentNotif ? ("Reply: " + (root.currentNotif.summary || root.currentNotif.appName)) : "Reply Notification"
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 8
                    color: Services.Theme.surfaceVariant
                    border.color: replyInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                    border.width: 1

                    TextInput {
                        id: replyInput
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Services.Theme.textPrimary
                        font.pixelSize: 12
                        clip: true
                        focus: root.replyMode

                        Text {
                            text: (root.currentNotif && root.currentNotif.inlineReplyPlaceholder) ? root.currentNotif.inlineReplyPlaceholder : "Write a reply..."
                            color: Services.Theme.textDisabled
                            font.pixelSize: 12
                            visible: replyInput.text.length === 0 && !replyInput.activeFocus
                        }

                        Keys.onReturnPressed: {
                            if (root.currentNotif && replyInput.text.trim().length > 0) {
                                const msg = replyInput.text.trim()
                                const nId = root.currentNotif.notifId
                                const aId = root.activeReplyActionId
                                root.replyMode = false
                                replyInput.text = ""
                                Services.Notifications.invokeAction(nId, aId, msg)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    // Cancel Button
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: cancelTxt.implicitWidth + 14
                        radius: 6
                        color: cancelMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.surfaceVariant

                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                root.replyMode = false
                                replyInput.text = ""
                                mouse.accepted = true
                            }
                        }
                    }

                    // Send Button
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: sendRow.implicitWidth + 16
                        radius: 6
                        color: sendMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent

                        RowLayout {
                            id: sendRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Send"
                                font.family: Services.Theme.fontMono
                                color: Services.Theme.bgOnAccent
                                font.pixelSize: 10
                                font.bold: true
                            }

                            Text {
                                text: Services.Icons.send || "\uf1d8"
                                font.family: Services.Theme.fontSymbols
                                color: Services.Theme.bgOnAccent
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (root.currentNotif && replyInput.text.trim().length > 0) {
                                    const msg = replyInput.text.trim()
                                    const nId = root.currentNotif.notifId
                                    const aId = root.activeReplyActionId
                                    root.replyMode = false
                                    replyInput.text = ""
                                    Services.Notifications.invokeAction(nId, aId, msg)
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }
        }

        // ==================== Expanded: System HUD Alert (Mute, DnD, Charging, CapsLock) ====================
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            readonly property bool activeState: (root.sysHudTitle.includes("Caps Lock") || root.sysHudTitle.includes("Welcome") || !Services.OverlayManager.isLocked) && root.expanded && !root.notifActive && !root.wallpaperMode && root.sysHudActive && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            Rectangle {
                id: sysHudBubble
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: Services.Theme.surfaceVariant
                Layout.alignment: Qt.AlignVCenter
                clip: true

                transform: Scale {
                    id: sysHudBubbleScale
                    origin.x: 16
                    origin.y: 16
                    xScale: 1.0
                    yScale: 1.0
                }

                SequentialAnimation {
                    id: sysHudBubblePunch
                    ParallelAnimation {
                        NumberAnimation { target: sysHudBubbleScale; property: "xScale"; to: 1.15; duration: 90; easing.type: Easing.OutQuad }
                        NumberAnimation { target: sysHudBubbleScale; property: "yScale"; to: 1.15; duration: 90; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: sysHudBubbleScale; property: "xScale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                        NumberAnimation { target: sysHudBubbleScale; property: "yScale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                    }
                }

                property string hudCurrentIcon: root.sysHudIcon
                property color hudCurrentColor: root.sysHudColor
                property bool hudUseSlotA: true

                onHudCurrentIconChanged: {
                    sysHudBubblePunch.restart()
                    if (hudUseSlotA) {
                        hudSlotB.text = hudCurrentIcon
                        hudSlotB.color = hudCurrentColor
                        hudSlotAAnimOut.restart()
                        hudSlotBAnimIn.restart()
                        hudUseSlotA = false
                    } else {
                        hudSlotA.text = hudCurrentIcon
                        hudSlotA.color = hudCurrentColor
                        hudSlotBAnimOut.restart()
                        hudSlotAAnimIn.restart()
                        hudUseSlotA = true
                    }
                }

                onHudCurrentColorChanged: {
                    if (hudUseSlotA) {
                        hudSlotA.color = hudCurrentColor
                    } else {
                        hudSlotB.color = hudCurrentColor
                    }
                }

                Text {
                    id: hudSlotA
                    anchors.centerIn: parent
                    text: root.sysHudIcon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 15
                    color: root.sysHudColor
                    opacity: 1.0
                    scale: 1.0
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                Text {
                    id: hudSlotB
                    anchors.centerIn: parent
                    text: ""
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 15
                    color: root.sysHudColor
                    opacity: 0.0
                    scale: 0.4
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                ParallelAnimation {
                    id: hudSlotAAnimIn
                    NumberAnimation { target: hudSlotA; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hudSlotA; property: "scale"; from: 0.4; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    id: hudSlotAAnimOut
                    NumberAnimation { target: hudSlotA; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
                    NumberAnimation { target: hudSlotA; property: "scale"; to: 0.4; duration: 160; easing.type: Easing.InQuad }
                }

                ParallelAnimation {
                    id: hudSlotBAnimIn
                    NumberAnimation { target: hudSlotB; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hudSlotB; property: "scale"; from: 0.4; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    id: hudSlotBAnimOut
                    NumberAnimation { target: hudSlotB; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
                    NumberAnimation { target: hudSlotB; property: "scale"; to: 0.4; duration: 160; easing.type: Easing.InQuad }
                }

                // Red Cross overlay when Caps Lock is Off with smooth rotation & spring pop
                Text {
                    id: capsOffCross
                    anchors.centerIn: parent
                    text: "✕"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 12
                    font.bold: true
                    color: Services.Theme.danger
                    readonly property bool isCapsOff: root.sysHudTitle === "Caps Lock Off"
                    opacity: isCapsOff ? 1.0 : 0.0
                    scale: isCapsOff ? 1.0 : 0.1
                    rotation: isCapsOff ? 0 : -45
                    visible: opacity > 0.01

                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    text: root.sysHudTitle
                    color: Services.Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.sysHudDetail.length > 0
                    text: root.sysHudDetail
                    color: Services.Theme.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // ==================== Expanded: Media Peek (Compact auto-expand on play) ====================
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.notifActive && !root.wallpaperMode && !root.sysHudActive && root.isMediaPeek && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            // Compact Track Artwork / Icon
            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: Services.Theme.radiusSm
                color: Services.Theme.surfaceVariant
                clip: true
                Layout.alignment: Qt.AlignVCenter

                Image {
                    id: peekArtImg
                    anchors.fill: parent
                    source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(64, 64)
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰎈"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 16
                    color: Services.Theme.accent
                    visible: !peekArtImg.visible
                }
            }

            // Compact Track Title & Artist
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    text: root.activePlayer ? (root.activePlayer.trackTitle || "Playing") : "Playing"
                    color: Services.Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: root.activePlayer ? (root.activePlayer.trackArtist || root.activePlayer.identity || "Now Playing") : "Now Playing"
                    color: Services.Theme.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Animated Music Status Icon
            Item {
                implicitWidth: 24
                implicitHeight: 24
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: "󰎈"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 14
                    color: Services.Theme.success

                    RotationAnimation on rotation {
                        from: 0; to: 360
                        duration: 4000
                        loops: Animation.Infinite
                        running: root.mediaPlaying && root.isMediaPeek
                    }
                }
            }
        }

        // ==================== Expanded: Media Controls (Full Control) ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.notifActive && !root.sysHudActive && !root.isMediaPeek && root.hasMedia && !root.wallpaperMode && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            // Row 1: Track Art + Info + App Badge
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Artwork
                Rectangle {
                    implicitWidth: 46
                    implicitHeight: 46
                    radius: 10
                    color: Services.Theme.surfaceVariant
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: albumArtImg
                        anchors.fill: parent
                        source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(92, 92)
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰎈"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 22
                        color: Services.Theme.accent
                        visible: !albumArtImg.visible
                    }
                }

                // Info (App Badge, Title, Artist)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        spacing: 4
                        visible: (root.activePlayer?.identity ?? "").length > 0

                        Rectangle {
                            implicitHeight: 15
                            implicitWidth: appBadgeRow.implicitWidth + 8
                            radius: 4
                            color: Services.Theme.surfaceVariant

                            RowLayout {
                                id: appBadgeRow
                                anchors.centerIn: parent
                                spacing: 3

                                Text {
                                    text: Services.Icons.playerIcon(root.activePlayer?.identity)
                                    color: Services.Theme.accent
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 9
                                }

                                Text {
                                    text: root.activePlayer ? (root.activePlayer.identity || "") : ""
                                    color: Services.Theme.textDisabled
                                    font.pixelSize: 8
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 80
                                }
                            }
                        }
                    }

                    Text {
                        text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown Track") : "—"
                        color: Services.Theme.textPrimary
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""
                        color: Services.Theme.textSecondary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text.length > 0
                    }
                }
            }

            // Row 2: Progress Bar & Timers
            Item {
                Layout.fillWidth: true
                implicitHeight: 22
                visible: root.activePlayer !== null

                Text {
                    id: posLabel
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: root.fmtTime(wavyBar.livePosition)
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                    font.family: Services.Theme.fontMono
                }

                Text {
                    id: durLabel
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: {
                        const len = root.activePlayer?.length ?? 0
                        return len > 0 ? root.fmtTime(len) : "--:--"
                    }
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                    font.family: Services.Theme.fontMono
                }

                MediaModule.WavyProgressBar {
                    id: wavyBar
                    anchors {
                        left: posLabel.right; right: durLabel.left
                        leftMargin: 8; rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    height: 20
                    isPlaying: root.mediaPlaying
                    waveColor: Services.Theme.accent
                    trackColor: Services.Theme.surfaceVariant
                    lineWidth: 3.0
                    maxAmplitude: 2.8
                    position: root.activePlayer?.position ?? 0
                    duration: root.activePlayer?.length ?? 0
                    onSeekRequested: (ratio) => {
                        const len = root.activePlayer?.length ?? 0
                        if (len > 0 && root.activePlayer) {
                            root.activePlayer.position = ratio * len
                            root.activePlayer.positionChanged()
                        }
                    }
                }
            }

            // Row 3: Full Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // Shuffle
                Item {
                    implicitWidth: 30; implicitHeight: 30
                    opacity: (root.activePlayer?.shuffleSupported ?? false) ? 1 : 0.2
                    Rectangle {
                        anchors.fill: parent; radius: 8
                        color: shArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaShuffle
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: (root.activePlayer?.shuffle ?? false) ? Services.Theme.accent : Services.Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: shArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: (root.activePlayer?.shuffleSupported ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.shuffleSupported ?? false
                        onClicked: (mouse) => { root.activePlayer.shuffle = !root.activePlayer.shuffle; mouse.accepted = true }
                    }
                }

                Item { Layout.fillWidth: true }

                // Previous
                Item {
                    implicitWidth: 32; implicitHeight: 32
                    opacity: (root.activePlayer?.canGoPrevious ?? false) ? 1 : 0.3
                    Rectangle {
                        anchors.fill: parent; radius: 16
                        color: prvArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaPrev
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 13
                        color: prvArea.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: prvArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: (root.activePlayer?.canGoPrevious ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.canGoPrevious ?? false
                        onClicked: (mouse) => { root.activePlayer.previous(); mouse.accepted = true }
                    }
                }

                Item { Layout.fillWidth: true }

                // Play / Pause (Natural Optical Glass Lens)
                Rectangle {
                    id: playGlassBtn
                    implicitWidth: 38; implicitHeight: 38
                    radius: 19

                    // Natural convex lens gradient: subtle top ambient light, crystal body, soft base depth
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: playArea.pressed
                                ? Qt.rgba(255, 255, 255, 0.18)
                                : (playArea.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.07))
                        }
                        GradientStop {
                            position: 0.55
                            color: playArea.pressed
                                ? Qt.rgba(255, 255, 255, 0.08)
                                : (playArea.containsMouse ? Qt.rgba(255, 255, 255, 0.05) : Qt.rgba(255, 255, 255, 0.02))
                        }
                        GradientStop {
                            position: 1.0
                            color: playArea.pressed
                                ? Qt.rgba(0, 0, 0, 0.06)
                                : (playArea.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : Qt.rgba(0, 0, 0, 0.08))
                        }
                    }

                    // Whisper-thin natural glass rim reflection
                    border.color: playArea.pressed
                        ? Qt.rgba(255, 255, 255, 0.28)
                        : (playArea.containsMouse ? Qt.rgba(255, 255, 255, 0.18) : Qt.rgba(255, 255, 255, 0.09))
                    border.width: 1

                    scale: playArea.pressed ? 0.92 : (playArea.containsMouse ? 1.06 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                    Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    // Soft physical contact shadow under the glass
                    Rectangle {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1.5
                        width: parent.width - 2
                        height: parent.height - 2
                        radius: parent.radius
                        color: Qt.rgba(0, 0, 0, 0.30)
                        z: -1
                    }

                    Text {
                        id: playGlassIcon
                        anchors.centerIn: parent
                        text: Services.Icons.mediaPlayPause(root.mediaPlaying)
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 15
                        color: Services.Theme.textPrimary
                        opacity: playArea.containsMouse ? 1.0 : 0.92
                        scale: playIconScale

                        property real playIconScale: 1.0

                        onTextChanged: playGlassMorphAnim.restart()

                        SequentialAnimation {
                            id: playGlassMorphAnim
                            NumberAnimation { target: playGlassIcon; property: "playIconScale"; to: 0.70; duration: 80; easing.type: Easing.InQuad }
                            NumberAnimation { target: playGlassIcon; property: "playIconScale"; to: 1.15; duration: 150; easing.type: Easing.OutBack }
                            NumberAnimation { target: playGlassIcon; property: "playIconScale"; to: 1.0; duration: 80; easing.type: Easing.OutQuad }
                        }
                    }

                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: (root.activePlayer?.canTogglePlaying ?? true) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.canTogglePlaying ?? true
                        onClicked: (mouse) => { root.activePlayer?.togglePlaying(); mouse.accepted = true }
                    }
                }

                Item { Layout.fillWidth: true }

                // Next
                Item {
                    implicitWidth: 32; implicitHeight: 32
                    opacity: (root.activePlayer?.canGoNext ?? false) ? 1 : 0.3
                    Rectangle {
                        anchors.fill: parent; radius: 16
                        color: nxtArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaNext
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 13
                        color: nxtArea.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: nxtArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: (root.activePlayer?.canGoNext ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.canGoNext ?? false
                        onClicked: (mouse) => { root.activePlayer.next(); mouse.accepted = true }
                    }
                }

                Item { Layout.fillWidth: true }

                // Repeat
                Item {
                    implicitWidth: 30; implicitHeight: 30
                    opacity: (root.activePlayer?.loopSupported ?? false) ? 1 : 0.2
                    Rectangle {
                        anchors.fill: parent; radius: 8
                        color: rpArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        anchors.centerIn: parent
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        text: (root.activePlayer?.loop ?? MprisLoopState.None) === MprisLoopState.Track ? Services.Icons.mediaLoopOne : Services.Icons.mediaLoopAll
                        color: (root.activePlayer?.loop ?? MprisLoopState.None) !== MprisLoopState.None ? Services.Theme.accent : (rpArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: rpArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: (root.activePlayer?.loopSupported ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.loopSupported ?? false
                        onClicked: (mouse) => {
                            const l = root.activePlayer?.loop ?? MprisLoopState.None
                            if (l === MprisLoopState.None)           root.activePlayer.loop = MprisLoopState.Playlist
                            else if (l === MprisLoopState.Playlist)  root.activePlayer.loop = MprisLoopState.Track
                            else                                     root.activePlayer.loop = MprisLoopState.None
                            mouse.accepted = true
                        }
                    }
                }
            }
        }

        // ==================== Expanded: Wallpaper Studio (Minimalist) ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.notifActive && root.wallpaperMode && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.75
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            // Row 1: Minimal Header
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 6

                Text {
                    text: "󰋩"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: Services.Theme.accent
                }

                Text {
                    text: "Wallpapers"
                    color: Services.Theme.textPrimary
                    font.pixelSize: Services.Theme.fontSizeSm
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Add Custom Button
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: addBtnMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                    border.color: addBtnMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 13
                        font.bold: true
                        color: addBtnMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                    }

                    MouseArea {
                        id: addBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.collapse()
                            if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                        }
                    }
                }

                // Close Button
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: closeIslandWallMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 10
                        color: closeIslandWallMouse.containsMouse ? "#ef4444" : Services.Theme.textDisabled
                    }

                    MouseArea {
                        id: closeIslandWallMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.collapse()
                    }
                }
            }

            // Row 2: Clean 16:9 Wallpaper Cards Carousel
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: islandWallList
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    focus: root.wallpaperMode
                    currentIndex: root.wallpaperIndex
                    keyNavigationEnabled: false

                    model: root.wallpaperList

                    Keys.onPressed: (event) => {
                        const count = root.wallpaperList ? root.wallpaperList.length : 0
                        if (count === 0) return

                        if (event.key === Qt.Key_Right) {
                            root.wallpaperIndex = (root.wallpaperIndex + 1) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left) {
                            root.wallpaperIndex = (root.wallpaperIndex - 1 + count) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                            root.wallpaperIndex = (root.wallpaperIndex - 1 + count) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            root.wallpaperIndex = (root.wallpaperIndex + 1) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (root.wallpaperList && root.wallpaperList.length > root.wallpaperIndex) {
                                const item = root.wallpaperList[root.wallpaperIndex]
                                if (item && item.isAddAction) {
                                    root.collapse()
                                    if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                } else if (item && item.path && Services.Wallpaper) {
                                    Services.Wallpaper.setWallpaper(item.path)
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.collapse()
                            event.accepted = true
                        }
                    }

                    delegate: Item {
                        id: iWallCell
                        required property var modelData
                        required property int index

                        readonly property bool isAdd: iWallCell.modelData && iWallCell.modelData.isAddAction === true
                        width: isAdd ? 72 : 124
                        height: islandWallList.height

                        readonly property bool isSelected: iWallCell.index === root.wallpaperIndex
                        readonly property bool isActive: !isAdd && Services.Wallpaper && (
                            Services.Wallpaper.currentWallpaper === iWallCell.modelData.path ||
                            (iWallCell.modelData.isDynamic === true && Services.Wallpaper.isWallblerActive)
                        )

                        // Wallpaper Card
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Services.Theme.surfaceVariant
                            border.color: (iWallCell.isActive || iWallCell.isSelected)
                                ? Services.Theme.accent
                                : (iWallMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
                            border.width: (iWallCell.isActive || iWallCell.isSelected) ? 2 : 1
                            clip: true
                            scale: (iWallMouse.containsMouse || iWallCell.isSelected) ? 1.03 : 1.0
                            visible: !iWallCell.isAdd

                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Image {
                                anchors.fill: parent
                                source: (iWallCell.modelData && iWallCell.modelData.path) ? ("file://" + iWallCell.modelData.path) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(248, 148)
                            }

                            // Active Checkmark Pill
                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 4
                                width: 18; height: 18; radius: 9
                                color: Services.Theme.accent
                                visible: iWallCell.isActive

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Services.Theme.bgOnAccent
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            // Dynamic Icon Badge (subtle)
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left
                                anchors.margins: 4
                                width: 18; height: 18; radius: 9
                                color: Qt.rgba(0, 0, 0, 0.65)
                                visible: iWallCell.modelData && iWallCell.modelData.isDynamic === true

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰖔"
                                    color: "#38bdf8"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 9
                                }
                            }

                            // Bottom Gradient with Wallpaper Title
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 26
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.4) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.85) }
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6; anchors.rightMargin: 6; anchors.bottomMargin: 2
                                    verticalAlignment: Text.AlignBottom
                                    text: (iWallCell.modelData && iWallCell.modelData.name) ? iWallCell.modelData.name : "Wallpaper"
                                    color: Services.Theme.white
                                    font.pixelSize: 9
                                    font.bold: iWallCell.isActive || iWallCell.isSelected
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Add Image Card
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: (iAddMouse.containsMouse || iWallCell.isSelected) ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12) : Qt.rgba(255, 255, 255, 0.03)
                            border.color: (iAddMouse.containsMouse || iWallCell.isSelected) ? Services.Theme.accent : Services.Theme.borderSubtle
                            border.width: iWallCell.isSelected ? 2 : 1
                            scale: (iAddMouse.containsMouse || iWallCell.isSelected) ? 1.03 : 1.0
                            visible: iWallCell.isAdd

                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "+"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Services.Theme.accent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Add"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: iAddMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.wallpaperIndex = iWallCell.index
                                onClicked: {
                                    root.collapse()
                                    if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                }
                            }
                        }

                        // Click to set wallpaper
                        MouseArea {
                            id: iWallMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            visible: !iWallCell.isAdd
                            onEntered: root.wallpaperIndex = iWallCell.index
                            onClicked: {
                                root.wallpaperIndex = iWallCell.index
                                if (iWallCell.modelData && iWallCell.modelData.path && Services.Wallpaper) {
                                    Services.Wallpaper.setWallpaper(iWallCell.modelData.path)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==================== Expanded: Drop to Send Hub (KDE Connect & LocalSend) ====================
        Item {
            id: dropSendHubContainer
            anchors.fill: parent
            anchors.margins: 12
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.notifActive && !root.wallpaperMode && (root.dropSendMode || root.isDropSending)
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.94
            transformOrigin: Item.Center
            enabled: activeState
            z: 10

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            // ─── Sub-View 1: Active Drag & Drop Targets / Choice ───
            ColumnLayout {
                anchors.fill: parent
                spacing: 8
                visible: !root.isDropSending

                // ── Header Row ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    spacing: 8

                    // Animated Transfer / Radar Icon (Borderless)
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)

                        Text {
                            anchors.centerIn: parent
                            text: "󰄶"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 13
                            color: Services.Theme.accent
                        }

                        SequentialAnimation on scale {
                            running: dropSendHubContainer.activeState && !root.isDropSending
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.08; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutSine }
                        }
                    }

                    Text {
                        text: root.dropStagedChoice ? "Select Destination" : "Drop here to Send"
                        color: Services.Theme.textPrimary
                        font.pixelSize: Services.Theme.fontSizeSm
                        font.bold: true
                    }

                    // File Count Badge (Borderless)
                    Rectangle {
                        visible: root.dropFileCount > 0
                        height: 18
                        implicitWidth: fileCountText.implicitWidth + 12
                        radius: 9
                        color: Qt.rgba(255, 255, 255, 0.07)

                        Text {
                            id: fileCountText
                            anchors.centerIn: parent
                            text: root.dropFileCount + (root.dropFileCount > 1 ? " files" : " file")
                            color: Services.Theme.accent
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Image Thumbnail Preview (Borderless)
                    RowLayout {
                        visible: root.dropPreviewUrl !== ""
                        spacing: 6
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: Qt.rgba(255, 255, 255, 0.08)
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: root.dropPreviewUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                        }

                        Text {
                            text: root.dropFileName
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            Layout.maximumWidth: 120
                            elide: Text.ElideMiddle
                        }
                    }

                    // Cancel / Close Button (Borderless)
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        color: closeDropMouse.containsMouse ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.2) : Qt.rgba(255, 255, 255, 0.06)

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 10
                            color: closeDropMouse.containsMouse ? "#ef4444" : Services.Theme.textDisabled
                        }

                        MouseArea {
                            id: closeDropMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.collapse()
                        }
                    }
                }

                // ── Drop Target Cards Row (Borderless) ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    // ── Card 1: KDE Connect ──
                    Rectangle {
                        id: kdeCard
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        readonly property bool isHovered: root.dropHoverTarget === "kde" || kdeCardMouse.containsMouse
                        readonly property var dev: Services.DeviceShare ? Services.DeviceShare.defaultDevice : null
                        readonly property bool hasDev: Services.DeviceShare ? Services.DeviceShare.hasKdeDevice : false

                        color: isHovered
                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                            : Qt.rgba(255, 255, 255, 0.05)
                        scale: isHovered ? 1.02 : 1.0

                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            // Top Info Row: Icon + Title + Status
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    width: 36; height: 36; radius: 18
                                    color: kdeCard.isHovered
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                                        : Qt.rgba(255, 255, 255, 0.07)

                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰄡"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 18
                                        color: kdeCard.hasDev ? Services.Theme.accent : Services.Theme.textDisabled
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    RowLayout {
                                        spacing: 5
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: kdeCard.hasDev ? "#22c55e" : "#eab308"
                                        }
                                        Text {
                                            text: "KDE Connect"
                                            font.bold: true
                                            font.pixelSize: 12
                                            color: Services.Theme.textPrimary
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: kdeCard.hasDev ? (kdeCard.dev ? kdeCard.dev.name : "Connected Device") : "No paired device"
                                        color: kdeCard.hasDev ? Services.Theme.textSecondary : Services.Theme.textDisabled
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Bottom Action Pill (Borderless)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 7
                                color: kdeCard.isHovered
                                    ? Services.Theme.accent
                                    : (kdeCardMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.2) : Qt.rgba(255, 255, 255, 0.06))

                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        text: kdeCard.isHovered ? "󰄶" : "󰄡"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 11
                                        color: kdeCard.isHovered ? Services.Theme.bgOnAccent : Services.Theme.accent
                                    }
                                    Text {
                                        text: kdeCard.isHovered ? "Release to Send" : (root.dropStagedChoice ? ("Send to " + (kdeCard.dev ? kdeCard.dev.name : "Device")) : "Drop to Send")
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: kdeCard.isHovered ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                    }
                                }
                            }
                        }

                        // Child DropArea for KDE Connect
                        DropArea {
                            id: kdeDropTarget
                            anchors.fill: parent
                            onEntered: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "kde"
                            }
                            onPositionChanged: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "kde"
                            }
                            onExited: () => {
                                if (root.dropHoverTarget === "kde") root.dropHoverTarget = ""
                                dropExitDebounceTimer.restart()
                            }
                            onDropped: (drop) => {
                                dropExitDebounceTimer.stop()
                                root.handleDropOnKde(drop.urls)
                            }
                        }

                        MouseArea {
                            id: kdeCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.dropUrls && root.dropUrls.length > 0) {
                                    root.handleDropOnKde(root.dropUrls)
                                }
                            }
                        }
                    }

                    // ── Card 2: LocalSend ──
                    Rectangle {
                        id: localCard
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        readonly property bool isHovered: root.dropHoverTarget === "local" || localCardMouse.containsMouse

                        color: isHovered
                            ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.18)
                            : Qt.rgba(255, 255, 255, 0.05)
                        scale: isHovered ? 1.02 : 1.0

                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            // Top Info Row: Icon + Title + Status
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    width: 36; height: 36; radius: 18
                                    color: localCard.isHovered
                                        ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.3)
                                        : Qt.rgba(255, 255, 255, 0.07)

                                    Behavior on color { ColorAnimation { duration: 200 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅠"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 18
                                        color: "#38bdf8"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    RowLayout {
                                        spacing: 5
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: "#38bdf8"
                                        }
                                        Text {
                                            text: "LocalSend"
                                            font.bold: true
                                            font.pixelSize: 12
                                            color: Services.Theme.textPrimary
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Nearby Devices (LAN)"
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            // Bottom Action Pill (Borderless)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 7
                                color: localCard.isHovered
                                    ? "#38bdf8"
                                    : (localCardMouse.containsMouse ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.2) : Qt.rgba(255, 255, 255, 0.06))

                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        text: localCard.isHovered ? "󰄶" : "󰅠"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 11
                                        color: localCard.isHovered ? "#000000" : "#38bdf8"
                                    }
                                    Text {
                                        text: localCard.isHovered ? "Release to Send" : (root.dropStagedChoice ? "Open in LocalSend" : "Drop to Send")
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: localCard.isHovered ? "#000000" : Services.Theme.textPrimary
                                    }
                                }
                            }
                        }

                        // Child DropArea for LocalSend
                        DropArea {
                            id: localDropTarget
                            anchors.fill: parent
                            onEntered: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "local"
                            }
                            onPositionChanged: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "local"
                            }
                            onExited: () => {
                                if (root.dropHoverTarget === "local") root.dropHoverTarget = ""
                                dropExitDebounceTimer.restart()
                            }
                            onDropped: (drop) => {
                                dropExitDebounceTimer.stop()
                                root.handleDropOnLocalSend(drop.urls)
                            }
                        }

                        MouseArea {
                            id: localCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.dropUrls && root.dropUrls.length > 0) {
                                    root.handleDropOnLocalSend(root.dropUrls)
                                }
                            }
                        }
                    }
                }
            }

            // ─── Sub-View 2: Sending / Success Transfer Feedback ───
            RowLayout {
                anchors.fill: parent
                spacing: 12
                visible: root.isDropSending

                readonly property string previewUrl: (Services.DeviceShare && Services.DeviceShare.transferPreviewUrl !== "") ? Services.DeviceShare.transferPreviewUrl : root.dropPreviewUrl
                readonly property bool hasPreview: previewUrl !== ""
                readonly property bool isSuccess: Services.DeviceShare && Services.DeviceShare.transferState === "success"
                readonly property string targetDevice: Services.DeviceShare ? Services.DeviceShare.transferTargetName : (root.dropFileName || "Device")

                // Left Thumbnail / Icon Squircle
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 10
                    color: Services.Theme.surfaceVariant
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    // Image Preview
                    Image {
                        anchors.fill: parent
                        visible: parent.parent.hasPreview
                        source: parent.parent.previewUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    // Fallback Icon if not an image
                    Text {
                        anchors.centerIn: parent
                        visible: !parent.parent.hasPreview
                        text: parent.parent.isSuccess ? "󰄬" : "󰄶"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 22
                        font.bold: true
                        color: parent.parent.isSuccess ? Services.Theme.success : Services.Theme.accent
                    }

                    // Corner Mini Badge
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 2
                        width: 14
                        height: 14
                        radius: 7
                        color: parent.parent.isSuccess ? Services.Theme.success : Services.Theme.accent
                        visible: parent.parent.hasPreview

                        Text {
                            anchors.centerIn: parent
                            text: parent.parent.parent.isSuccess ? "✓" : "󰄶"
                            font.family: parent.parent.parent.isSuccess ? Services.Theme.fontPrimary : Services.Theme.fontSymbols
                            font.pixelSize: 8
                            font.bold: true
                            color: "#ffffff"
                        }
                    }
                }

                // Center Progress & Info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    // Top Row: Title + Status Done Pill
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: parent.parent.parent.isSuccess
                                ? ("Sent to " + parent.parent.parent.targetDevice)
                                : ("Sending to " + parent.parent.parent.targetDevice + "...")
                            font.bold: true
                            font.pixelSize: 12
                            color: Services.Theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Success "Done" Badge
                        Rectangle {
                            visible: parent.parent.parent.isSuccess
                            height: 16
                            implicitWidth: doneText.implicitWidth + 10
                            radius: 8
                            color: Qt.rgba(34 / 255, 197 / 255, 94 / 255, 0.18)

                            Text {
                                id: doneText
                                anchors.centerIn: parent
                                text: "Done"
                                font.pixelSize: 9
                                font.bold: true
                                color: Services.Theme.success
                            }
                        }
                    }

                    // Animated Glowing Progress Bar (Borderless)
                    Rectangle {
                        id: progressBarTrack
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: Qt.rgba(255, 255, 255, 0.08)
                        clip: true

                        // Full width fill when success
                        Rectangle {
                            id: progressSuccessBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.parent.parent.isSuccess ? parent.width : 0
                            color: Services.Theme.success
                            radius: 2

                            Behavior on width {
                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                            }
                        }

                        // Indeterminate glowing sweep beam while sending
                        Rectangle {
                            id: progressSendingBeam
                            visible: root.isDropSending && !parent.parent.parent.isSuccess
                            width: 140
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Services.Theme.accent }
                                GradientStop { position: 1.0; color: "transparent" }
                            }

                            SequentialAnimation on x {
                                running: progressSendingBeam.visible
                                loops: Animation.Infinite
                                NumberAnimation { from: -140; to: progressBarTrack.width + 40; duration: 1000; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    // Subtitle: File name or transfer message
                    Text {
                        Layout.fillWidth: true
                        text: parent.parent.parent.isSuccess
                            ? (root.dropFileName !== "" ? root.dropFileName : (Services.DeviceShare ? Services.DeviceShare.transferMessage : "Transfer completed"))
                            : (Services.DeviceShare ? Services.DeviceShare.transferMessage : "Transfer in progress")
                        font.pixelSize: 10
                        color: Services.Theme.textSecondary
                        elide: Text.ElideRight
                    }
                }

                // Right Status Circle
                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    Layout.alignment: Qt.AlignVCenter
                    color: parent.isSuccess
                        ? Qt.rgba(34 / 255, 197 / 255, 94 / 255, 0.18)
                        : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        anchors.centerIn: parent
                        text: parent.parent.isSuccess ? "󰄬" : "󰄶"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 15
                        color: parent.parent.isSuccess ? Services.Theme.success : Services.Theme.accent
                    }

                    SequentialAnimation on scale {
                        running: root.isDropSending && !parent.parent.isSuccess
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.12; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

    }

    // ==================== Media Player Satellite Dot (Right of Island when Notif/HUD Active) ====================
    Rectangle {
        id: mediaSatelliteDot
        readonly property bool isSatellite: root.isMediaSatellite
        anchors.left: island.right
        anchors.leftMargin: isSatellite ? 8 : -32
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - implicitHeight) / 2)
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: Services.Theme.bgPure
        border.color: Services.Theme.borderSubtle
        border.width: 1
        z: 1
        visible: isSatellite || opacity > 0 || scale > 0

        opacity: isSatellite ? 1 : 0
        scale: isSatellite ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
        Behavior on anchors.leftMargin { NumberAnimation { duration: 550; easing.type: Easing.OutBack } }

        transform: Scale {
            id: mediaSatTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                mediaSatDetachAnim.restart()
            } else {
                mediaSatRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: mediaSatDetachAnim
            ParallelAnimation {
                NumberAnimation { target: mediaSatTransform; property: "xScale"; to: 1.34; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: mediaSatTransform; property: "yScale"; to: 0.74; duration: 150; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: mediaSatTransform; property: "xScale"; to: 0.88; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: mediaSatTransform; property: "yScale"; to: 1.14; duration: 180; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: mediaSatTransform; property: "xScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: mediaSatTransform; property: "yScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            }
        }

        SequentialAnimation {
            id: mediaSatRetractAnim
            ParallelAnimation {
                NumberAnimation { target: mediaSatTransform; property: "xScale"; to: 1.25; duration: 180; easing.type: Easing.InQuad }
                NumberAnimation { target: mediaSatTransform; property: "yScale"; to: 0.80; duration: 180; easing.type: Easing.InQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: mediaSatTransform; property: "xScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
                NumberAnimation { target: mediaSatTransform; property: "yScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
            }
        }

        // Mini Audio Wave Visualizer inside Media Satellite Dot
        Row {
            anchors.centerIn: parent
            spacing: 2.5
            opacity: mediaSatelliteDot.isSatellite ? 1.0 : 0.0
            scale: mediaSatelliteDot.isSatellite ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: 2.5
                    height: 10
                    radius: 1.25
                    color: Services.Theme.success
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on height {
                        running: mediaSatelliteDot.isSatellite
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: index === 0 ? 14 : (index === 1 ? 6 : 12)
                            duration: index === 0 ? 280 : (index === 1 ? 400 : 340)
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: index === 0 ? 4 : (index === 1 ? 14 : 4)
                            duration: index === 0 ? 320 : (index === 1 ? 300 : 380)
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (Services.Media) Services.Media.playPause()
            }
        }
    }

    // ==================== Camera Satellite Dot (Right of Island / Media) ====================
    Rectangle {
        id: cameraSatelliteDot
        readonly property bool isSatellite: root.isCameraSatellite
        anchors.left: (mediaSatelliteDot.isSatellite && mediaSatelliteDot.visible) ? mediaSatelliteDot.right : island.right
        anchors.leftMargin: isSatellite ? 8 : -32
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - implicitHeight) / 2)
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: Services.Theme.bgPure
        border.color: Services.Theme.borderSubtle
        border.width: 1
        z: 1
        visible: root.cameraActive || opacity > 0 || scale > 0

        opacity: isSatellite ? 1 : 0
        scale: isSatellite ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
        Behavior on anchors.leftMargin { NumberAnimation { duration: 550; easing.type: Easing.OutBack } }

        transform: Scale {
            id: camSatTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                camSatDetachAnim.restart()
            } else {
                camSatRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: camSatDetachAnim
            ParallelAnimation {
                NumberAnimation { target: camSatTransform; property: "xScale"; to: 1.34; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: camSatTransform; property: "yScale"; to: 0.74; duration: 150; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: camSatTransform; property: "xScale"; to: 0.88; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: camSatTransform; property: "yScale"; to: 1.14; duration: 180; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: camSatTransform; property: "xScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: camSatTransform; property: "yScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            }
        }

        SequentialAnimation {
            id: camSatRetractAnim
            ParallelAnimation {
                NumberAnimation { target: camSatTransform; property: "xScale"; to: 1.25; duration: 180; easing.type: Easing.InQuad }
                NumberAnimation { target: camSatTransform; property: "yScale"; to: 0.80; duration: 180; easing.type: Easing.InQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: camSatTransform; property: "xScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
                NumberAnimation { target: camSatTransform; property: "yScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
            }
        }

        // Camera Icon with blinking green privacy effect
        Item {
            anchors.centerIn: parent
            width: 16
            height: 16
            opacity: cameraSatelliteDot.isSatellite ? 1.0 : 0.0
            scale: cameraSatelliteDot.isSatellite ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            Text {
                id: camSatIcon
                anchors.centerIn: parent
                text: "󰄀"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.success
            }

            SequentialAnimation on opacity {
                running: cameraSatelliteDot.isSatellite
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
            }
        }
    }

    // ==================== CapsLock Satellite Dot (Right of Island / Camera / Media) ====================
    Rectangle {
        id: capsLockDot
        readonly property bool isSatellite: root.capsLockActive && !root.expanded
        anchors.left: (cameraSatelliteDot.isSatellite && cameraSatelliteDot.visible) ? cameraSatelliteDot.right : ((mediaSatelliteDot.isSatellite && mediaSatelliteDot.visible) ? mediaSatelliteDot.right : island.right)
        anchors.leftMargin: isSatellite ? 8 : -32
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - implicitHeight) / 2)
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: Services.Theme.bgPure
        border.color: Services.Theme.borderSubtle
        border.width: 1
        z: 1
        visible: root.capsLockActive || opacity > 0 || scale > 0

        opacity: isSatellite ? 1 : 0
        scale: isSatellite ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
        Behavior on anchors.leftMargin { NumberAnimation { duration: 550; easing.type: Easing.OutBack } }

        transform: Scale {
            id: capsSatTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                capsSatDetachAnim.restart()
            } else {
                capsSatRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: capsSatDetachAnim
            ParallelAnimation {
                NumberAnimation { target: capsSatTransform; property: "xScale"; to: 1.34; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: capsSatTransform; property: "yScale"; to: 0.74; duration: 150; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: capsSatTransform; property: "xScale"; to: 0.88; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: capsSatTransform; property: "yScale"; to: 1.14; duration: 180; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: capsSatTransform; property: "xScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: capsSatTransform; property: "yScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            }
        }

        SequentialAnimation {
            id: capsSatRetractAnim
            ParallelAnimation {
                NumberAnimation { target: capsSatTransform; property: "xScale"; to: 1.25; duration: 180; easing.type: Easing.InQuad }
                NumberAnimation { target: capsSatTransform; property: "yScale"; to: 0.80; duration: 180; easing.type: Easing.InQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: capsSatTransform; property: "xScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
                NumberAnimation { target: capsSatTransform; property: "yScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
            }
        }

        // CapsLock Icon with delayed floating bloom
        Text {
            anchors.centerIn: parent
            text: "󰘶"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: Services.Theme.alertYellow
            opacity: capsLockDot.isSatellite ? 1.0 : 0.0
            scale: capsLockDot.isSatellite ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        }
    }

}




