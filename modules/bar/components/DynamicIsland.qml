// DynamicIsland.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
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
    property bool mediaCollapsedReady: true
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

    // CapsLock Active State & Monitoring
    property bool capsLockActive: false

    // ── Smart Chronological 3-Dynamic System (Utama: Tengah, Sebelum: Kanan, Sebelumnya Lagi: Kiri) ──
    property double mediaActiveTime: 0
    property double sysHudActiveTime: 0
    property double cameraActiveTime: 0
    property double capsLockActiveTime: 0
    property string manualCenterId: ""

    // All candidates gathered and sorted strictly newest to oldest
    readonly property var allSortedCandidates: {
        const list = []

        // Modal overrides
        if (root.dropSendMode || root.isDropSending) {
            return [{ id: "dropsend", type: "dropsend", time: 9999999999999 }]
        }
        if (root.wallpaperMode) {
            return [{ id: "wallpaper", type: "wallpaper", time: 9999999999999 }]
        }

        // 1. SysHUD (volume, brightness, mute, etc.)
        if (root.sysHudActive) {
            list.push({
                id: "syshud",
                type: "syshud",
                icon: root.sysHudIcon,
                title: root.sysHudTitle,
                color: root.sysHudColor,
                time: root.sysHudActiveTime || Date.now()
            })
        }

        // 2. Notifications (each notification in popupList is an independent candidate)
        if (root.notifActive && root.popupList) {
            for (let i = 0; i < root.popupList.count; i++) {
                const n = root.popupList.get(i)
                if (n) {
                    const t = (n.time || Date.now()) - (i * 10)
                    list.push({
                        id: "notif_" + (n.notifId !== undefined ? n.notifId : i),
                        type: "notif",
                        index: i,
                        notif: n,
                        time: t
                    })
                }
            }
        }

        // 3. Media playback
        if (root.mediaPlaying || (root.mediaStopping && !root.mediaIconTransformed)) {
            if (!Services.OverlayManager.isLocked) {
                list.push({
                    id: "media",
                    type: "media",
                    time: root.mediaActiveTime || 1
                })
            }
        }

        // 4. Camera active
        if (root.cameraActive) {
            list.push({
                id: "camera",
                type: "camera",
                time: root.cameraActiveTime || 0
            })
        }

        // 5. CapsLock active
        if (root.capsLockActive && !root.expanded) {
            list.push({
                id: "capslock",
                type: "capslock",
                time: root.capsLockActiveTime || 0
            })
        }

        // Sort candidates strictly newest to oldest (highest time first)
        list.sort((a, b) => (b.time || 0) - (a.time || 0))
        return list
    }

    // Allocate into 3 slots with optional manual swap support
    readonly property var slotDistribution: {
        const candidates = root.allSortedCandidates
        if (!candidates || candidates.length === 0) {
            return { center: { type: "idle" }, right: null, left: null }
        }

        let centerIdx = 0
        if (root.manualCenterId !== "") {
            const foundIdx = candidates.findIndex(c => c.id === root.manualCenterId)
            if (foundIdx !== -1) {
                centerIdx = foundIdx
            }
        }

        const centerItem = candidates[centerIdx]
        const remaining = []
        for (let i = 0; i < candidates.length; i++) {
            if (i !== centerIdx) remaining.push(candidates[i])
        }

        // "sebelum baru ke kanan"
        const rightItem = remaining.length > 0 ? remaining[0] : null
        // "dan sebelumnya lagi ke kiri gitu"
        const leftItem = remaining.length > 1 ? remaining[1] : null

        return { center: centerItem, right: rightItem, left: leftItem }
    }

    readonly property var slotCenterItem: slotDistribution.center
    readonly property var slotRightItem: slotDistribution.right
    readonly property var slotLeftItem: slotDistribution.left

    readonly property string slot0Activity: slotCenterItem ? slotCenterItem.type : "idle"
    readonly property string slotRightType: slotRightItem ? slotRightItem.type : ""
    readonly property string slotLeftType: slotLeftItem ? slotLeftItem.type : ""

    readonly property bool isMediaSatellite: (slotRightType === "media" || slotLeftType === "media")
    readonly property bool isCameraSatellite: (slotRightType === "camera" || slotLeftType === "camera")
    readonly property bool isCapsLockSatellite: (slotRightType === "capslock" || slotLeftType === "capslock")

    readonly property int leftExtraWidth: (slotLeftType !== "") ? 40 : 0
    readonly property int rightExtraWidth: (slotRightType !== "") ? 40 : 0
    readonly property int satelliteExtraWidth: Math.max(leftExtraWidth, rightExtraWidth) * 2

    function resolveNotifIcon(n) {
        if (!n) return ""
        let src = n.appIcon || n.image || ""
        const appName = (n.appName || "").toLowerCase()
        const summary = (n.summary || "").toLowerCase()
        if (!src || src === "kdeconnect" || src.includes("kdeconnect")) {
            if (appName.includes("whatsapp") || summary.includes("whatsapp")) src = "whatsapp"
            else if (appName.includes("telegram") || summary.includes("telegram")) src = "telegram"
            else if (appName.includes("discord") || summary.includes("discord")) src = "discord"
            else if (appName.includes("signal") || summary.includes("signal")) src = "signal"
            else if (appName.includes("slack") || summary.includes("slack")) src = "slack"
            else if (appName.includes("instagram") || summary.includes("instagram")) src = "instagram"
            else if (appName.includes("tiktok") || summary.includes("tiktok")) src = "tiktok"
            else if (appName.includes("messages") || appName.includes("sms")) src = "message"
        }
        if (!src) src = n.image || ""
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

    function handleSatelliteClick(item) {
        if (!item) return
        if (item.type === "notif") {
            root.manualCenterId = item.id
            notifTimer.restart()
        } else if (item.type === "media") {
            root.manualCenterId = "media"
        } else if (item.type === "camera") {
            root.showSysHud("󰄀", "Camera Active", "Webcam in use", Services.Theme.success)
        } else if (item.type === "capslock") {
            root.showSysHud("󰘶", "Caps Lock", root.capsLockActive ? "Active" : "Disabled", Services.Theme.alertYellow)
        } else if (item.type === "transfer") {
            root.dropSendMode = true
        } else if (item.type === "syshud") {
            root.manualCenterId = "syshud"
        }
    }

    function selectNotifIndex(idx) {
        if (idx >= 0 && idx < root.notifCount && root.popupList) {
            const n = root.popupList.get(idx)
            if (n) {
                root.manualCenterId = "notif_" + (n.notifId !== undefined ? n.notifId : idx)
                notifTimer.restart()
            }
        }
    }

    function swapNotifications() {
        if (slotRightItem) {
            root.handleSatelliteClick(slotRightItem)
        } else if (slotLeftItem) {
            root.handleSatelliteClick(slotLeftItem)
        }
    }

    // NetworkManager / Wi-Fi State Monitoring
    property bool wifiLastConnected: false
    property string wifiLastSsid: ""

    // Bluetooth Devices State Monitoring
    property var btConnectedDevices: ({})
    property bool btInitialized: false

    // Media Stop & Motion Animation Choreography
    property bool isNextTrack: true
    property bool mediaStopping: false
    property bool mediaTextCollapsed: false
    property bool mediaIconTransformed: false

    Timer {
        id: mediaStopPhase1Timer
        interval: 200
        repeat: false
        onTriggered: {
            root.mediaTextCollapsed = true
            mediaStopPhase2Timer.restart()
        }
    }

    Timer {
        id: mediaStopPhase2Timer
        interval: 380
        repeat: false
        onTriggered: {
            root.mediaIconTransformed = true
            root.mediaStopping = false
            root.mediaCollapsedReady = false
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
        if (cameraActive) cameraActiveTime = Date.now()
        if (cameraActive && hudReady && root.notifCount === 0 && !Services.OverlayManager.isLocked) {
            root.showSysHud("󰄀", "Camera Active", "Webcam in use", Services.Theme.success)
        }
    }

    onCapsLockActiveChanged: {
        if (capsLockActive) capsLockActiveTime = Date.now()
        if (!hudReady) return
        const icon = "󰘶"
        const title = capsLockActive ? "Caps Lock On" : "Caps Lock Off"
        const detail = capsLockActive ? "Uppercase enabled" : "Standard lowercase"
        root.showSysHud(icon, title, detail, capsLockActive ? Services.Theme.alertYellow : Services.Theme.danger)
    }

    function showSysHud(icon, title, detail, iconColor, customDuration) {
        if (root.wallpaperMode) return
        sysHudIcon = icon
        sysHudTitle = title
        sysHudDetail = detail || ""
        sysHudColor = iconColor || Services.Theme.accent
        sysHudActiveTime = Date.now()
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

    readonly property bool hasExpandContent: (slot0Activity !== "idle") || wallpaperMode || dropSendMode || isDropSending
    readonly property bool expanded: !lockBlocked && hasExpandContent && (pinned || autoExpanded || (slot0Activity === "notif") || (slot0Activity === "syshud") || wallpaperMode || dropSendMode || isDropSending)
    readonly property bool isMediaPeek: !lockBlocked && autoExpanded && !pinned && (slot0Activity === "media") && !wallpaperMode && !dropSendMode && !isDropSending && hasMedia

    property int autoExpandDuration: 2500
    property int notifDuration: 5000

    // Safe retrieval of current notification entry from the center slot
    readonly property var currentNotif: {
        if (slotCenterItem && slotCenterItem.type === "notif" && slotCenterItem.notif) {
            return slotCenterItem.notif
        }
        return null
    }

    onCurrentNotifChanged: {
        replyMode = false
        activeReplyActionId = ""
        if (currentNotif && popupList) {
            for (let i = 0; i < popupList.count; i++) {
                if (popupList.get(i).notifId === currentNotif.notifId) {
                    activeNotifIndex = i
                    break
                }
            }
        } else {
            activeNotifIndex = 0
        }
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
            mediaActiveTime = Date.now()
            root.mediaCollapsedReady = false
            mediaStopPhase1Timer.stop()
            mediaStopPhase2Timer.stop()
            root.mediaStopping = false
            root.mediaTextCollapsed = false
            root.mediaIconTransformed = false
            if (currentMediaText !== "") {
                lastTrackText = currentMediaText
            }
            if (root.hudReady && root.notifCount === 0 && !root.pinned) {
                root.pulse()
            }
        } else {
            globalMediaMarqueeAnim.stop()
            if (root.hudReady && !root.notifActive) {
                root.mediaStopping = true
                root.mediaTextCollapsed = false
                root.mediaIconTransformed = false
                mediaStopPhase1Timer.restart()
            } else {
                root.mediaCollapsedReady = false
            }
        }
    }
    onCurrentMediaTextChanged: {
        if (mediaPlaying && currentMediaText !== "") {
            mediaActiveTime = Date.now()
            lastTrackText = currentMediaText
            root.restartGlobalMarquee()
        }
    }
    onExpandedChanged: {
        // Continuous marquee: preserve seamless running text motion across states
    }

    // ==================== Master Continuous Media Marquee Driver ====================
    property real globalMediaMarqueeRatio: 0.0
    property real globalMediaMarqueeDuration: 4200

    function restartGlobalMarquee() {
        globalMediaMarqueeAnim.stop()
        globalMediaMarqueeRatio = 0.0
        const tLen = (root.activePlayer?.trackTitle || "").length
        const aLen = (root.activePlayer?.trackArtist || "").length
        const maxLen = Math.max(tLen, aLen, (root.currentMediaText || "").length)
        const approxOverflow = Math.max(40, (maxLen * 7.5) - 130)
        globalMediaMarqueeDuration = Math.max(3000, Math.min(8500, approxOverflow * 35))
        if (root.mediaPlaying && !Services.OverlayManager.isLocked) {
            globalMediaMarqueeAnim.start()
        }
    }

    SequentialAnimation {
        id: globalMediaMarqueeAnim
        running: root.mediaPlaying && !Services.OverlayManager.isLocked
        loops: Animation.Infinite

        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "globalMediaMarqueeRatio"
            from: 0.0
            to: 1.0
            duration: root.globalMediaMarqueeDuration
            easing.type: Easing.InOutQuad
        }
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "globalMediaMarqueeRatio"
            from: 1.0
            to: 0.0
            duration: root.globalMediaMarqueeDuration
            easing.type: Easing.InOutQuad
        }
    }

    // Island Dimensions
    readonly property bool showCollapsedText: !lockBlocked && ((slot0Activity === "notif") || (mediaPlaying && mediaCollapsedReady))
    readonly property int calculatedCollapsedWidth: {
        if (showCollapsedText || (mediaStopping && !mediaTextCollapsed)) {
            const extraPadding = (mediaPlaying || mediaStopping) ? 72 : 52
            return Math.min(260, Math.max(140, collapsedTextContainer.currentSlotImplicitWidth + extraPadding))
        }
        return 140
    }
    property int collapsedWidth: 140
    property int collapsedHeight: 32

    readonly property int calculatedExpandedWidth: {
        if (slot0Activity === "notif") return replyMode ? 390 : 360
        if (dropSendMode) return 500
        if (isDropSending) return 400
        if (wallpaperMode) return 480
        if (slot0Activity === "syshud") return 280
        if (isMediaPeek) return 280
        if (hasMedia) return 360
        return 260
    }

    readonly property int calculatedExpandedHeight: {
        if (slot0Activity === "notif") {
            if (replyMode) return 146
            let h = 72
            if (hasNotifBody) h += 24
            if (hasNotifActions) h += 32
            return h
        }
        if (dropSendMode) return 148
        if (isDropSending) return 64
        if (wallpaperMode) return 120
        if (slot0Activity === "syshud") return 54
        if (isMediaPeek) return 54
        if (hasMedia) return 138
        return 52
    }

    // ── Bar layout negotiation ────────────────────────────────────
    // Lebar yang di-"klaim" island dari bar, sudah termasuk kompensasi overshoot animasi.
    readonly property real reservedWidth: {
        const base = expanded ? calculatedExpandedWidth : calculatedCollapsedWidth
        return base + satelliteExtraWidth + (expanded ? overshootAllowance : 0)
    }

    // Behavior on width memakai Easing.OutBack, yang MELAMPAUI nilai target sebelum settle.
    readonly property real overshootAllowance: 28

    readonly property string demand: {
        if (!expanded) return "idle"
        if (dropSendMode || isDropSending || wallpaperMode) return "greedy"
        if (isMediaPeek) return "peek"
        return "normal"
    }

    // Format seconds → "m:ss"
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function pulse() {
        if (pinned || notifActive) return
        if (autoExpanded) {
            autoCollapseTimer.restart()
            return
        }
        autoExpanded = true
        autoCollapseTimer.restart()
    }

    function togglePin() {
        if (!hasExpandContent) return
        if (isMediaPeek) {
            pinned = true
            autoExpanded = false
            autoCollapseTimer.stop()
        } else if (expanded) {
            collapse()
        } else {
            pinned = true
        }
    }

    function collapse() {
        pinned = false
        autoExpanded = false
        if (root.mediaPlaying) root.mediaCollapsedReady = true
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
        onTriggered: {
            root.autoExpanded = false
            if (root.mediaPlaying) root.mediaCollapsedReady = true
        }
    }

    Timer {
        id: notifTimer
        interval: root.notifDuration
        repeat: false
        onTriggered: {
            if (root.replyMode) return
            // Slot stability: no auto-incrementing
        }
    }

    Connections {
        target: Services.Notifications
        function onNewNotification(entry) {
            root.wallpaperMode = false
            root.sysHudActive = false
            sysHudTimer.stop()
            root.manualCenterId = ""
            root.activeNotifIndex = 0
            root.replyMode = false
            notifTimer.restart()
        }
    }

    Connections {
        target: Services.Mpris
        function onActivePlayerChanged() {
            root.restartGlobalMarquee()
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
            root.restartGlobalMarquee()
            if (collapsedTextContainer) {
                collapsedTextContainer.updateTrackPush(collapsedTextContainer.targetText, root.isNextTrack)
            }
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

        readonly property bool isCapsuleShape: !root.expanded || (!root.notifActive && (root.sysHudActive || root.isMediaPeek))
        radius: isCapsuleShape ? (height / 2) : Services.Theme.radiusLg

        color: Services.Theme.bgPure
        border.color: root.isCritical ? Services.Theme.danger : (root.expanded ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
        border.width: root.isCritical ? 1.5 : 1

        // Seamless, Continuous Fluid Morphing (Zero delay, zero hitching, pure iOS ease - synchronized with Lockscreen)
        Behavior on width {
            NumberAnimation {
                duration: root.expanded ? 360 : 380
                easing.type: Easing.OutBack
                easing.overshoot: root.expanded ? 1.35 : 1.45
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: 340
                easing.type: Easing.OutBack
                easing.overshoot: 0.65
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

            readonly property bool activeState: !root.expanded && !root.autoExpanded && (
                !root.mediaPlaying || root.mediaCollapsedReady || root.mediaStopping
            )
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.4
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: statusIconContainer.activeState ? 220 : 160; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: statusIconContainer.activeState ? 320 : 160; easing.type: Easing.OutCubic } }

            states: [
                State {
                    name: "ICON_LEFT"
                    when: !Services.OverlayManager.isLocked && !root.expanded && !root.autoExpanded && (
                        (root.mediaPlaying && root.mediaCollapsedReady) ||
                        root.mediaStopping ||
                        root.notifActive
                    )
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
                    when: !Services.OverlayManager.isLocked && (
                        root.expanded ||
                        root.autoExpanded ||
                        (!root.mediaPlaying && !root.mediaStopping && !root.notifActive && !root.cameraActive) ||
                        (root.mediaPlaying && !root.mediaCollapsedReady)
                    )
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: island.horizontalCenter
                        anchors.left: undefined
                        anchors.right: undefined
                    }
                },
                State {
                    name: "CAMERA_RIGHT"
                    when: !Services.OverlayManager.isLocked && !root.expanded && !root.autoExpanded && (!root.showCollapsedText && !root.mediaStopping && root.cameraActive)
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

            Text {
                id: statusIconTxt
                anchors.centerIn: parent
                text: {
                    if (Services.OverlayManager.isLocked) return "󰌾"
                    if (root.notifActive) return "󰂚"
                    if (root.expanded || root.autoExpanded) return "●"
                    if (root.mediaPlaying && !root.mediaCollapsedReady) return "●"
                    if (root.mediaPlaying || root.mediaStopping) return "󰎈"
                    return "●"
                }
                font.family: Services.Theme.fontSymbols
                font.pixelSize: (text === "●") ? 10 : 13
                color: {
                    if (Services.OverlayManager.isLocked) return Services.Theme.accent
                    if (root.notifActive) return Services.Theme.accent
                    if (root.expanded || root.autoExpanded) return Services.Theme.textDisabled
                    if (root.mediaPlaying && !root.mediaCollapsedReady) return Services.Theme.textDisabled
                    if (root.mediaPlaying || root.mediaStopping) return Services.Theme.success
                    if (root.cameraActive) return Services.Theme.success
                    return Services.Theme.textDisabled
                }
                scale: textScale

                property real textScale: 1.0

                onTextChanged: {
                    if (text === "●") {
                        statusIconTxt.rotation = 0
                    }
                    if (statusIconContainer.activeState && !root.expanded && !root.autoExpanded) {
                        iconScaleAnim.restart()
                    }
                }

                SequentialAnimation {
                    id: iconScaleAnim
                    NumberAnimation { target: statusIconTxt; property: "textScale"; to: 0.7; duration: 90; easing.type: Easing.InQuad }
                    NumberAnimation { target: statusIconTxt; property: "textScale"; to: 1.0; duration: 220; easing.type: Easing.OutQuad }
                }

                // Green Blinking when camera active and no music text
                SequentialAnimation on opacity {
                    running: root.cameraActive && !root.showCollapsedText && !root.expanded && !root.autoExpanded
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }

                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

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
                    running: !Services.OverlayManager.isLocked && root.mediaPlaying && !root.expanded && !root.autoExpanded && root.mediaCollapsedReady && statusIconContainer.state === "ICON_LEFT"
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
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.mediaPlaying && !root.expanded && !root.autoExpanded && root.mediaCollapsedReady && !root.notifActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1.0 : 0.0
            scale: activeState ? 1.0 : 0.3
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        }

        // ==================== Dedicated Collapsed Track Title / Notif Text Zone ====================
        Item {
            id: collapsedTextContainer
            anchors.left: statusIconContainer.right
            anchors.leftMargin: 6
            anchors.verticalCenter: island.verticalCenter
            // Lock width bounded to collapsed dimension to prevent stretching while expanding
            width: Math.max(40, (root.expanded ? root.calculatedCollapsedWidth : island.width) - 12 - 16 - 6 - (mediaVisualizer.visible ? 34 : (cameraIndicator.visible ? 24 : 12)))
            height: 16
            z: 3

            readonly property bool showCollapsedText: !Services.OverlayManager.isLocked && (root.notifActive || root.mediaPlaying)
            readonly property bool activeState: !Services.OverlayManager.isLocked && !root.expanded && !root.autoExpanded && root.mediaCollapsedReady && showCollapsedText && !root.mediaStopping

            clip: true
            transformOrigin: Item.Left
            opacity: activeState ? 1.0 : 0.0
            scale: activeState ? 1.0 : 0.95
            visible: activeState || opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: root.mediaStopping ? 180 : 140; easing.type: root.mediaStopping ? Easing.InQuad : Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

            transform: Translate {
                x: collapsedTextContainer.activeState ? 0 : (root.mediaStopping ? -20 : 20)
                Behavior on x { NumberAnimation { duration: root.mediaStopping ? 180 : 160; easing.type: root.mediaStopping ? Easing.InQuad : Easing.OutQuad } }
            }

            readonly property string targetText: Services.OverlayManager.isLocked ? "Locked" : (root.notifActive ? ("Notif (" + root.notifCount + ")") : (root.mediaPlaying ? root.currentMediaText : root.lastTrackText))

            property string displayedText: ""
            property bool useSlotA: true
            readonly property real currentSlotImplicitWidth: useSlotA ? slotA.implicitWidth : slotB.implicitWidth
            readonly property alias collapsedText: slotA

            Component.onCompleted: {
                displayedText = targetText
                slotA.text = targetText
                slotA.y = 0
                slotA.opacity = 1.0
                slotB.opacity = 0.0
                useSlotA = true
            }

            function updateTrackPush(newTitle, isNext) {
                if (!newTitle || newTitle === displayedText) return

                if (!activeState || opacity <= 0.5 || root.expanded || root.autoExpanded) {
                    slotPushAnimA.stop()
                    slotPushAnimB.stop()
                    displayedText = newTitle
                    if (useSlotA) {
                        slotA.text = newTitle
                        slotA.y = 0
                        slotA.opacity = 1.0
                        slotB.opacity = 0.0
                    } else {
                        slotB.text = newTitle
                        slotB.y = 0
                        slotB.opacity = 1.0
                        slotA.opacity = 0.0
                    }
                    return
                }

                displayedText = newTitle
                const offset = isNext ? 18 : -18

                if (useSlotA) {
                    slotB.text = newTitle
                    slotB.y = offset
                    slotB.opacity = 0.0
                    slotPushAnimB.restart()
                    useSlotA = false
                } else {
                    slotA.text = newTitle
                    slotA.y = offset
                    slotA.opacity = 0.0
                    slotPushAnimA.restart()
                    useSlotA = true
                }
            }

            onTargetTextChanged: {
                root.restartGlobalMarquee()
                updateTrackPush(targetText, root.isNextTrack)
                root.isNextTrack = true
            }

            ParallelAnimation {
                id: slotPushAnimB
                NumberAnimation {
                    target: slotA
                    property: "y"
                    to: root.isNextTrack ? -18 : 18
                    duration: 220
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotA
                    property: "opacity"
                    to: 0.0
                    duration: 200
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotB
                    property: "y"
                    to: 0
                    duration: 320
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.15
                }
                NumberAnimation {
                    target: slotB
                    property: "opacity"
                    to: 1.0
                    duration: 280
                    easing.type: Easing.OutQuad
                }
            }

            ParallelAnimation {
                id: slotPushAnimA
                NumberAnimation {
                    target: slotB
                    property: "y"
                    to: root.isNextTrack ? -18 : 18
                    duration: 220
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotB
                    property: "opacity"
                    to: 0.0
                    duration: 200
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotA
                    property: "y"
                    to: 0
                    duration: 320
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.15
                }
                NumberAnimation {
                    target: slotA
                    property: "opacity"
                    to: 1.0
                    duration: 280
                    easing.type: Easing.OutQuad
                }
            }

            Text {
                id: slotA
                text: collapsedTextContainer.targetText
                font.pixelSize: 11
                font.bold: true
                color: Services.Theme.textPrimary
                width: Math.max(implicitWidth, collapsedTextContainer.width)
                horizontalAlignment: (implicitWidth > collapsedTextContainer.width) ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 1.0
                y: 0
                readonly property real maxScroll: Math.max(0, implicitWidth - collapsedTextContainer.width + 8)
                x: (maxScroll > 0 && collapsedTextContainer.useSlotA && !slotPushAnimA.running && !slotPushAnimB.running) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                elide: Text.ElideNone
            }

            Text {
                id: slotB
                text: ""
                font.pixelSize: 11
                font.bold: true
                color: Services.Theme.textPrimary
                width: Math.max(implicitWidth, collapsedTextContainer.width)
                horizontalAlignment: (implicitWidth > collapsedTextContainer.width) ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 0.0
                y: 18
                readonly property real maxScroll: Math.max(0, implicitWidth - collapsedTextContainer.width + 8)
                x: (maxScroll > 0 && !collapsedTextContainer.useSlotA && !slotPushAnimA.running && !slotPushAnimB.running) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                elide: Text.ElideNone
            }
        }

        // ==================== Expanded: Notifications ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && (root.slot0Activity === "notif") && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.35 } }

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
            readonly property bool activeState: (root.sysHudTitle.includes("Caps Lock") || root.sysHudTitle.includes("Welcome") || !Services.OverlayManager.isLocked) && root.expanded && (root.slot0Activity === "syshud") && !root.wallpaperMode && !root.dropSendMode && !root.isDropSending
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

        // ==================== Expanded: Media View (Adaptive Peek & Full Controls) ====================
        ColumnLayout {
            id: mediaView
            anchors.fill: parent
            anchors.margins: 10
            spacing: root.isMediaPeek ? 0 : 6
            Behavior on spacing { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && (root.slot0Activity === "media") && !root.wallpaperMode && !root.dropSendMode && !root.isDropSending
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : (root.isMediaPeek ? 0.96 : 0.78)
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: root.expanded ? 140 : 160; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: root.isMediaPeek ? 0.4 : 1.2 } }

            // Row 1: Track Art + Info + (Right Status Icon / App Badge)
            RowLayout {
                Layout.fillWidth: true
                spacing: root.isMediaPeek ? 10 : 12
                Behavior on spacing { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                // Artwork Container: Morphs seamlessly between 34x34 circle in Peek and 46x46 in Full
                Item {
                    id: mediaArtWrapper
                    implicitWidth: root.isMediaPeek ? 34 : 46
                    implicitHeight: root.isMediaPeek ? 34 : 46
                    Layout.alignment: Qt.AlignVCenter
                    scale: mediaView.activeState ? 1.0 : 0.6
                    transformOrigin: Item.Center

                    Behavior on implicitWidth  { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on implicitHeight { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on scale          { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }

                    transform: Translate {
                        id: artSlideTranslate
                        x: mediaView.activeState ? 0 : -8
                        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    }

                    // 1. Layer Konten Gambar + MSAA Buffer
                    Item {
                        id: mediaArtContent
                        anchors.fill: parent
                        layer.enabled: mediaView.visible
                        layer.samples: 8
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: mediaArtMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 0.5
                        }

                        // Inner spinning disc (Artwork spins smoothly in peek mode, resets to 0deg in full controls)
                        Item {
                            id: mediaArtSpinContainer
                            anchors.fill: parent
                            transformOrigin: Item.Center
                            rotation: 0

                            readonly property bool shouldSpin: root.mediaPlaying && root.isMediaPeek && (mediaArtImg.status === Image.Ready)

                            onShouldSpinChanged: {
                                if (shouldSpin) {
                                    resetAnim.stop()
                                    spinAnim.start()
                                } else {
                                    spinAnim.stop()
                                    resetAnim.start()
                                }
                            }

                            Component.onCompleted: {
                                if (shouldSpin) {
                                    spinAnim.start()
                                }
                            }

                            // Base background fallback
                            Rectangle {
                                anchors.fill: parent
                                color: Services.Theme.surfaceVariant
                            }

                            // High-Res Resampled Album Artwork
                            Image {
                                id: mediaArtImg
                                anchors.fill: parent
                                source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                                mipmap: true
                                antialiasing: true
                                sourceSize: Qt.size(102, 102)
                                opacity: (status === Image.Ready && source !== "") ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                            }

                            // Smooth subtle vinyl rotation while in peek
                            RotationAnimation {
                                id: spinAnim
                                target: mediaArtSpinContainer
                                property: "rotation"
                                from: 0
                                to: 360
                                direction: RotationAnimation.Clockwise
                                duration: 12000
                                loops: Animation.Infinite
                            }

                            // Smooth shortest-path reset back to 0deg when leaving peek or stopping
                            RotationAnimation {
                                id: resetAnim
                                target: mediaArtSpinContainer
                                property: "rotation"
                                to: 0
                                direction: RotationAnimation.Shortest
                                duration: 280
                                easing.type: Easing.OutCubic
                                onFinished: {
                                    mediaArtSpinContainer.rotation = 0
                                }
                            }
                        }

                        // Fallback Music Symbol
                        Text {
                            anchors.centerIn: parent
                            text: "󰎈"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: root.isMediaPeek ? 15 : 22
                            color: Services.Theme.accent
                            opacity: (mediaArtImg.source !== "" && mediaArtImg.status !== Image.Error) ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                            Behavior on font.pixelSize { NumberAnimation { duration: 220 } }
                        }
                    }

                    // 2. High-Precision Mask (Morphs radius width/2 in peek -> 10 in full)
                    Item {
                        id: mediaArtMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: mediaView.visible
                        layer.samples: 8
                        layer.smooth: true

                        Rectangle {
                            anchors.fill: parent
                            radius: root.isMediaPeek ? (width / 2) : 10
                            color: "#ffffff"
                            antialiasing: true
                            smooth: true
                            Behavior on radius { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }

                    // 3. Sub-Pixel Rim Overlay (Morphs radius with mask)
                    Rectangle {
                        anchors.fill: parent
                        radius: root.isMediaPeek ? (width / 2) : 10
                        color: "transparent"
                        border.color: Qt.rgba(255, 255, 255, root.isMediaPeek ? 0.14 : 0.08)
                        border.width: 1
                        antialiasing: true
                        smooth: true
                        z: 3
                        Behavior on radius { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 250 } }
                    }
                }

                // Info (App Badge, Title, Artist)
                ColumnLayout {
                    id: mediaInfoCol
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: root.expanded ? (root.isMediaPeek ? 1 : 2) : 0
                    Behavior on spacing { NumberAnimation { duration: 220 } }

                    readonly property string fullTitle: root.activePlayer ? (root.activePlayer.trackTitle || "Playing") : "Playing"
                    readonly property string fullArtist: root.activePlayer ? (root.activePlayer.trackArtist || root.activePlayer.identity || "Now Playing") : "Now Playing"

                    onFullArtistChanged: {
                        if (!mediaTextSwitchAnim.running) {
                            mediaArtistText.text = fullArtist
                        }
                    }

                    onFullTitleChanged: {
                        root.restartGlobalMarquee()
                        const titleChanged = (mediaTitleText.text !== fullTitle)
                        const isRealTitle = (fullTitle !== "" && fullTitle !== "Playing")
                        const isSettled = (mediaView.activeState && mediaView.opacity > 0.95 && !root.autoExpanded)
                        if (titleChanged && isRealTitle && isSettled && !titleMorphAnim.running && !artistMorphAnim.running) {
                            mediaTextSwitchAnim.restart()
                        } else {
                            mediaTextSwitchAnim.stop()
                            mediaTitleText.text = fullTitle
                            mediaArtistText.text = fullArtist
                            mediaTitleText.y = 0
                            mediaArtistText.y = 0
                            mediaTitleText.opacity = 1.0
                            mediaArtistText.opacity = 1.0
                        }
                    }

                    SequentialAnimation {
                        id: mediaTextSwitchAnim
                        ParallelAnimation {
                            NumberAnimation { target: mediaTitleText; property: "opacity"; to: 0.0; duration: 90; easing.type: Easing.InQuad }
                            NumberAnimation { target: mediaArtistText; property: "opacity"; to: 0.0; duration: 90; easing.type: Easing.InQuad }
                        }
                        ScriptAction {
                            script: {
                                mediaTitleText.text = mediaInfoCol.fullTitle
                                mediaArtistText.text = mediaInfoCol.fullArtist
                                mediaTitleText.y = 0
                                mediaArtistText.y = 0
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: mediaTitleText; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutQuad }
                            NumberAnimation { target: mediaArtistText; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutQuad }
                        }
                    }

                    // App Badge (Only visible in full mode with smooth height unfurl)
                    RowLayout {
                        id: appBadgeRowContainer
                        spacing: 4
                        implicitHeight: (!root.isMediaPeek && (root.activePlayer?.identity ?? "").length > 0) ? 15 : 0
                        visible: opacity > 0.01
                        opacity: (!root.isMediaPeek && (root.activePlayer?.identity ?? "").length > 0) ? 1.0 : 0.0
                        clip: true
                        Behavior on implicitHeight { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        Behavior on opacity        { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

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

                    // Running Title Text (Seamless physical morph across states)
                    Item {
                        id: mediaTitleContainer
                        Layout.fillWidth: true
                        implicitHeight: mediaTitleText.implicitHeight
                        clip: true

                        transform: Translate {
                            id: titleMorphTranslate
                            x: 0
                            y: 0
                        }

                        Text {
                            id: mediaTitleText
                            text: mediaInfoCol.fullTitle
                            color: Services.Theme.textPrimary
                            font.pixelSize: root.isMediaPeek ? 12 : 13
                            font.bold: true
                            width: parent.width
                            readonly property real maxScroll: Math.max(0, implicitWidth - parent.width + 8)
                            x: (maxScroll > 0 && !mediaTextSwitchAnim.running) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                            elide: (maxScroll > 0 || mediaTextSwitchAnim.running) ? Text.ElideNone : Text.ElideRight
                            Behavior on font.pixelSize {
                                enabled: !titleMorphAnim.running
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    // Running Artist Text (Seamless physical morph across states)
                    Item {
                        id: mediaArtistContainer
                        Layout.fillWidth: true
                        implicitHeight: mediaArtistText.implicitHeight
                        clip: true
                        visible: mediaInfoCol.fullArtist.length > 0

                        transform: Translate {
                            id: artistMorphTranslate
                            x: 0
                            y: 0
                        }

                        Text {
                            id: mediaArtistText
                            text: mediaInfoCol.fullArtist
                            color: Services.Theme.textSecondary
                            font.pixelSize: root.isMediaPeek ? 10 : 11
                            width: parent.width
                            readonly property real maxScroll: Math.max(0, implicitWidth - parent.width + 8)
                            x: (maxScroll > 0 && !mediaTextSwitchAnim.running) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                            elide: (maxScroll > 0 || mediaTextSwitchAnim.running) ? Text.ElideNone : Text.ElideRight
                            Behavior on font.pixelSize { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                    }

                    function calculateTitleFlightOrigin() {
                        try {
                            const pt = collapsedTextContainer.mapToItem(mediaTitleContainer, 0, 0)
                            if (!isNaN(pt.x) && !isNaN(pt.y) && pt.x < 0) {
                                return { x: pt.x, y: pt.y }
                            }
                        } catch (e) {}
                        return {
                            x: root.isMediaPeek ? -20 : -34,
                            y: root.isMediaPeek ? -4 : -19
                        }
                    }

                    function triggerMorph(tStartX, tStartY, aStartX, aStartY, isEntrance) {
                        titleMorphAnim.stop()
                        artistMorphAnim.stop()
                        mediaTextSwitchAnim.stop()

                        // Immediate resting sync
                        mediaTitleText.text = mediaInfoCol.fullTitle
                        mediaArtistText.text = mediaInfoCol.fullArtist
                        mediaTitleText.y = 0
                        mediaArtistText.y = 0
                        mediaTitleText.opacity = 1.0
                        mediaArtistText.opacity = 1.0
                        mediaTitleContainer.opacity = 1.0
                        mediaArtistContainer.opacity = 1.0

                        if (isEntrance) {
                            // Fresh entrance from normal idle: no artificial sliding or opacity tampering
                            titleMorphTranslate.x = 0
                            titleMorphTranslate.y = 0
                            artistMorphTranslate.x = 0
                            artistMorphTranslate.y = 0
                            return
                        }

                        // Morphing from already visible collapsed pill: physical glide across states
                        titleMorphX.from = tStartX
                        titleMorphY.from = tStartY
                        titleMorphTranslate.x = tStartX
                        titleMorphTranslate.y = tStartY

                        artistMorphX.from = aStartX
                        artistMorphY.from = aStartY
                        artistMorphTranslate.x = aStartX
                        artistMorphTranslate.y = aStartY

                        artistMorphOpacity.from = 0.0
                        mediaArtistContainer.opacity = 0.0

                        titleMorphAnim.restart()
                        artistMorphAnim.restart()
                    }

                    ParallelAnimation {
                        id: titleMorphAnim
                        NumberAnimation {
                            id: titleMorphX
                            target: titleMorphTranslate
                            property: "x"
                            to: 0
                            duration: 360
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.12
                        }
                        NumberAnimation {
                            id: titleMorphY
                            target: titleMorphTranslate
                            property: "y"
                            to: 0
                            duration: 340
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            id: titleMorphFont
                            target: mediaTitleText
                            property: "font.pixelSize"
                            from: 11
                            to: root.isMediaPeek ? 12 : 13
                            duration: 320
                            easing.type: Easing.OutCubic
                        }
                    }

                    SequentialAnimation {
                        id: artistMorphAnim
                        PauseAnimation { duration: 30 }
                        ParallelAnimation {
                            NumberAnimation {
                                id: artistMorphX
                                target: artistMorphTranslate
                                property: "x"
                                to: 0
                                duration: 340
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.12
                            }
                            NumberAnimation {
                                id: artistMorphY
                                target: artistMorphTranslate
                                property: "y"
                                to: 0
                                duration: 320
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                id: artistMorphOpacity
                                target: mediaArtistContainer
                                property: "opacity"
                                to: 1.0
                                duration: 260
                                easing.type: Easing.OutQuad
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onExpandedChanged() {
                            if (root.expanded && root.hasMedia) {
                                const wasShowingCollapsed = (!root.autoExpanded && root.mediaPlaying && collapsedTextContainer.opacity > 0.7)
                                if (wasShowingCollapsed) {
                                    const origin = mediaInfoCol.calculateTitleFlightOrigin()
                                    mediaInfoCol.triggerMorph(origin.x, origin.y, origin.x + 6, origin.y + 10, false)
                                } else {
                                    mediaInfoCol.triggerMorph(0, 0, 0, 0, true)
                                }
                            }
                        }
                    }
                }

                // Animated Music Status Icon (Only in Media Peek)
                Item {
                    implicitWidth: 24
                    implicitHeight: 24
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.isMediaPeek || opacity > 0.01
                    opacity: root.isMediaPeek ? 1.0 : 0.0
                    scale: root.isMediaPeek ? 1.0 : 0.4
                    transformOrigin: Item.Center
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    Behavior on scale   { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }

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

            // Row 2: Progress Bar & Timers (Expands seamlessly in full mode)
            Item {
                Layout.fillWidth: true
                implicitHeight: (!root.isMediaPeek && root.activePlayer !== null) ? 22 : 0
                visible: (!root.isMediaPeek && root.activePlayer !== null) || opacity > 0.01
                opacity: !root.isMediaPeek ? 1.0 : 0.0
                clip: true
                Behavior on implicitHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity        { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                transform: Translate {
                    id: progressRowTranslate
                    y: (root.expanded && !root.isMediaPeek) ? 0 : 8
                    Behavior on y {
                        SequentialAnimation {
                            PauseAnimation { duration: 50 }
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }
                    }
                }

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
                visible: !root.isMediaPeek || opacity > 0.01
                opacity: !root.isMediaPeek ? 1.0 : 0.0
                clip: true
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                transform: Translate {
                    id: controlsRowTranslate
                    y: (root.expanded && !root.isMediaPeek) ? 0 : 8
                    Behavior on y {
                        SequentialAnimation {
                            PauseAnimation { duration: 75 }
                            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                        }
                    }
                }

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
                        onClicked: (mouse) => { root.isNextTrack = false; root.activePlayer.previous(); mouse.accepted = true }
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
                        onClicked: (mouse) => { root.isNextTrack = true; root.activePlayer.next(); mouse.accepted = true }
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
                    anchors.topMargin: 3
                    anchors.bottomMargin: 4
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
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
                        Item {
                            id: iCardRect
                            anchors.fill: parent
                            anchors.margins: 2
                            visible: !iWallCell.isAdd

                            // Base container holding image + gradient, masked to radius 10
                            Item {
                                id: iCardContent
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: iCardMask
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: Services.Theme.surfaceVariant
                                }

                                Image {
                                    anchors.fill: parent
                                    source: (iWallCell.modelData && iWallCell.modelData.path) ? ("file://" + iWallCell.modelData.path) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize: Qt.size(248, 148)
                                }

                                // Bottom shadow gradient for text readability
                                Rectangle {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 30
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.45) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
                                    }
                                }
                            }

                            // Rounded Mask Shape
                            Item {
                                id: iCardMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: "black"
                                }
                            }

                            // Dynamic Icon Badge (subtle, top-left)
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left
                                anchors.margins: 6
                                width: 18; height: 18; radius: 9
                                color: Qt.rgba(0, 0, 0, 0.72)
                                border.color: Qt.rgba(255, 255, 255, 0.25)
                                border.width: 1
                                visible: iWallCell.modelData && iWallCell.modelData.isDynamic === true
                                z: 4

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰖔"
                                    color: "#38bdf8"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 9
                                }
                            }

                            // Active Checkmark Pill (top-right)
                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 6
                                width: 18; height: 18; radius: 9
                                color: Services.Theme.accent
                                border.color: Qt.rgba(255, 255, 255, 0.4)
                                border.width: 1
                                visible: iWallCell.isActive
                                z: 4

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Services.Theme.bgOnAccent
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            // Bottom Wallpaper Title (Crisp, perfectly padded from borders)
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.bottomMargin: 6
                                text: (iWallCell.modelData && iWallCell.modelData.name) ? iWallCell.modelData.name : "Wallpaper"
                                color: Services.Theme.white
                                font.pixelSize: 9
                                font.bold: iWallCell.isActive || iWallCell.isSelected
                                elide: Text.ElideRight
                                z: 4
                            }

                            // Outer Border Ring (Exact 10px radius, perfectly aligned on top of mask)
                            Rectangle {
                                id: iCardBorderOverlay
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                z: 6
                                antialiasing: true
                                border.color: iWallCell.isSelected
                                    ? Services.Theme.accent
                                    : (iWallCell.isActive
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45)
                                        : (iWallMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.3) : Qt.rgba(255, 255, 255, 0.10)))
                                border.width: iWallCell.isSelected ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on border.width { NumberAnimation { duration: 150 } }
                            }
                        }

                        // Add Image Card
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 10
                            color: (iAddMouse.containsMouse || iWallCell.isSelected) ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12) : Qt.rgba(255, 255, 255, 0.03)
                            border.color: (iAddMouse.containsMouse || iWallCell.isSelected) ? Services.Theme.accent : Qt.rgba(255, 255, 255, 0.10)
                            border.width: (iAddMouse.containsMouse || iWallCell.isSelected) ? 2 : 1
                            visible: iWallCell.isAdd

                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Behavior on border.width { NumberAnimation { duration: 150 } }

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

    // ==================== Right Dynamic Satellite Dot ("Sebelum baru ke kanan") ====================
    Rectangle {
        id: rightSatDot
        readonly property var item: root.slotRightItem
        readonly property string activity: root.slotRightType
        readonly property bool isSatellite: activity !== ""
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
            id: rightTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                rightDetachAnim.restart()
            } else {
                rightRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: rightDetachAnim
            ParallelAnimation {
                NumberAnimation { target: rightTransform; property: "xScale"; to: 1.34; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: rightTransform; property: "yScale"; to: 0.74; duration: 150; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: rightTransform; property: "xScale"; to: 0.88; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: rightTransform; property: "yScale"; to: 1.14; duration: 180; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: rightTransform; property: "xScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: rightTransform; property: "yScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            }
        }

        SequentialAnimation {
            id: rightRetractAnim
            ParallelAnimation {
                NumberAnimation { target: rightTransform; property: "xScale"; to: 1.25; duration: 180; easing.type: Easing.InQuad }
                NumberAnimation { target: rightTransform; property: "yScale"; to: 0.80; duration: 180; easing.type: Easing.InQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: rightTransform; property: "xScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
                NumberAnimation { target: rightTransform; property: "yScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
            }
        }

        // ── Content: Media Waveform ──
        Row {
            anchors.centerIn: parent
            spacing: 2.5
            visible: rightSatDot.activity === "media"
            opacity: rightSatDot.activity === "media" ? 1.0 : 0.0
            scale: rightSatDot.activity === "media" ? 1.0 : 0.3
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
                        running: rightSatDot.activity === "media"
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

        // ── Content: Notification (App Icon + Badge) ──
        Item {
            anchors.centerIn: parent
            width: 18
            height: 18
            visible: rightSatDot.activity === "notif"
            opacity: rightSatDot.activity === "notif" ? 1.0 : 0.0
            scale: rightSatDot.activity === "notif" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            Image {
                id: rightNotifImg
                anchors.centerIn: parent
                width: 16
                height: 16
                source: (rightSatDot.item && rightSatDot.item.notif) ? root.resolveNotifIcon(rightSatDot.item.notif) : ""
                visible: status === Image.Ready && source.toString().length > 0
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize: Qt.size(32, 32)
            }

            Text {
                anchors.centerIn: parent
                text: "󰂚"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.accent
                visible: !rightNotifImg.visible
            }

            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: Services.Theme.danger
                anchors.top: parent.top
                anchors.topMargin: -1
                anchors.right: parent.right
                anchors.rightMargin: -1
            }
        }

        // ── Content: Camera Privacy Indicator ──
        Item {
            anchors.centerIn: parent
            width: 16
            height: 16
            visible: rightSatDot.activity === "camera"
            opacity: rightSatDot.activity === "camera" ? 1.0 : 0.0
            scale: rightSatDot.activity === "camera" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            Text {
                anchors.centerIn: parent
                text: "󰄀"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.success
            }

            SequentialAnimation on opacity {
                running: rightSatDot.activity === "camera"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
            }
        }

        // ── Content: CapsLock Indicator ──
        Text {
            anchors.centerIn: parent
            text: "󰘶"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: Services.Theme.alertYellow
            visible: rightSatDot.activity === "capslock"
            opacity: rightSatDot.activity === "capslock" ? 1.0 : 0.0
            scale: rightSatDot.activity === "capslock" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        }

        // ── Content: System HUD ──
        Text {
            anchors.centerIn: parent
            text: (rightSatDot.item && rightSatDot.item.icon) ? rightSatDot.item.icon : (root.sysHudIcon || "󰋩")
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: (rightSatDot.item && rightSatDot.item.color) ? rightSatDot.item.color : root.sysHudColor
            visible: rightSatDot.activity === "syshud"
            opacity: rightSatDot.activity === "syshud" ? 1.0 : 0.0
            scale: rightSatDot.activity === "syshud" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        }

        // ── Content: Transfer Progress ──
        Text {
            anchors.centerIn: parent
            text: "󰒍"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: Services.Theme.accent
            visible: rightSatDot.activity === "transfer"
            opacity: rightSatDot.activity === "transfer" ? 1.0 : 0.0
            scale: rightSatDot.activity === "transfer" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            SequentialAnimation on scale {
                running: rightSatDot.activity === "transfer"
                loops: Animation.Infinite
                NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.95; duration: 600; easing.type: Easing.InOutSine }
            }
        }

        // ── Smart Interactive Click Handler ──
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && rightSatDot.activity === "media") {
                    if (root.activePlayer) root.activePlayer.togglePlaying()
                } else if (rightSatDot.item) {
                    root.handleSatelliteClick(rightSatDot.item)
                }
            }
        }
    }

    // ==================== Left Dynamic Satellite Dot ("Sebelumnya lagi ke kiri gitu") ====================
    Rectangle {
        id: leftSatDot
        readonly property var item: root.slotLeftItem
        readonly property string activity: root.slotLeftType
        readonly property bool isSatellite: activity !== ""
        anchors.right: island.left
        anchors.rightMargin: isSatellite ? 8 : -32
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
        Behavior on anchors.rightMargin { NumberAnimation { duration: 550; easing.type: Easing.OutBack } }

        transform: Scale {
            id: leftTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                leftDetachAnim.restart()
            } else {
                leftRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: leftDetachAnim
            ParallelAnimation {
                NumberAnimation { target: leftTransform; property: "xScale"; to: 1.34; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: leftTransform; property: "yScale"; to: 0.74; duration: 150; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: leftTransform; property: "xScale"; to: 0.88; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { target: leftTransform; property: "yScale"; to: 1.14; duration: 180; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: leftTransform; property: "xScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: leftTransform; property: "yScale"; to: 1.0; duration: 160; easing.type: Easing.OutCubic }
            }
        }

        SequentialAnimation {
            id: leftRetractAnim
            ParallelAnimation {
                NumberAnimation { target: leftTransform; property: "xScale"; to: 1.25; duration: 180; easing.type: Easing.InQuad }
                NumberAnimation { target: leftTransform; property: "yScale"; to: 0.80; duration: 180; easing.type: Easing.InQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: leftTransform; property: "xScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
                NumberAnimation { target: leftTransform; property: "yScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
            }
        }

        // ── Content: Media Waveform ──
        Row {
            anchors.centerIn: parent
            spacing: 2.5
            visible: leftSatDot.activity === "media"
            opacity: leftSatDot.activity === "media" ? 1.0 : 0.0
            scale: leftSatDot.activity === "media" ? 1.0 : 0.3
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
                        running: leftSatDot.activity === "media"
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

        // ── Content: Notification (App Icon + Badge) ──
        Item {
            anchors.centerIn: parent
            width: 18
            height: 18
            visible: leftSatDot.activity === "notif"
            opacity: leftSatDot.activity === "notif" ? 1.0 : 0.0
            scale: leftSatDot.activity === "notif" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            Image {
                id: leftNotifImg
                anchors.centerIn: parent
                width: 16
                height: 16
                source: (leftSatDot.item && leftSatDot.item.notif) ? root.resolveNotifIcon(leftSatDot.item.notif) : ""
                visible: status === Image.Ready && source.toString().length > 0
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                sourceSize: Qt.size(32, 32)
            }

            Text {
                anchors.centerIn: parent
                text: "󰂚"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.accent
                visible: !leftNotifImg.visible
            }

            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: Services.Theme.danger
                anchors.top: parent.top
                anchors.topMargin: -1
                anchors.right: parent.right
                anchors.rightMargin: -1
            }
        }

        // ── Content: Camera Privacy Indicator ──
        Item {
            anchors.centerIn: parent
            width: 16
            height: 16
            visible: leftSatDot.activity === "camera"
            opacity: leftSatDot.activity === "camera" ? 1.0 : 0.0
            scale: leftSatDot.activity === "camera" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            Text {
                anchors.centerIn: parent
                text: "󰄀"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.success
            }

            SequentialAnimation on opacity {
                running: leftSatDot.activity === "camera"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
            }
        }

        // ── Content: CapsLock Indicator ──
        Text {
            anchors.centerIn: parent
            text: "󰘶"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: Services.Theme.alertYellow
            visible: leftSatDot.activity === "capslock"
            opacity: leftSatDot.activity === "capslock" ? 1.0 : 0.0
            scale: leftSatDot.activity === "capslock" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        }

        // ── Content: System HUD ──
        Text {
            anchors.centerIn: parent
            text: (leftSatDot.item && leftSatDot.item.icon) ? leftSatDot.item.icon : (root.sysHudIcon || "󰋩")
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: (leftSatDot.item && leftSatDot.item.color) ? leftSatDot.item.color : root.sysHudColor
            visible: leftSatDot.activity === "syshud"
            opacity: leftSatDot.activity === "syshud" ? 1.0 : 0.0
            scale: leftSatDot.activity === "syshud" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        }

        // ── Content: Transfer Progress ──
        Text {
            anchors.centerIn: parent
            text: "󰒍"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: Services.Theme.accent
            visible: leftSatDot.activity === "transfer"
            opacity: leftSatDot.activity === "transfer" ? 1.0 : 0.0
            scale: leftSatDot.activity === "transfer" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            SequentialAnimation on scale {
                running: leftSatDot.activity === "transfer"
                loops: Animation.Infinite
                NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.95; duration: 600; easing.type: Easing.InOutSine }
            }
        }

        // ── Smart Interactive Click Handler ──
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && leftSatDot.activity === "media") {
                    if (root.activePlayer) root.activePlayer.togglePlaying()
                } else if (leftSatDot.item) {
                    root.handleSatelliteClick(leftSatDot.item)
                }
            }
        }
    }

    // ── Backward Compatibility Aliases ──
    readonly property alias mediaSatelliteDot: rightSatDot
    readonly property alias cameraSatelliteDot: rightSatDot
    readonly property alias capsLockDot: leftSatDot
    readonly property alias satDot1: rightSatDot
    readonly property alias satDot2: leftSatDot

}




