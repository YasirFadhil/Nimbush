// DynamicIsland.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../../../services" as Services

Item {
    id: root

    // ----- Public API & State -----
    property bool pinned: false
    property bool autoExpanded: false
    property int activeNotifIndex: 0

    // Inline Reply Type Zone State
    property bool replyMode: false
    property string activeReplyActionId: ""

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
    readonly property bool notifActive: notifCount > 0

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
        interval: 240
        repeat: false
        onTriggered: {
            root.mediaTextCollapsed = true
            mediaStopPhase2Timer.restart()
        }
    }

    Timer {
        id: mediaStopPhase2Timer
        interval: 320
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
        command: ["sh", "-c", "ls /dev/video* >/dev/null 2>&1 && fuser /dev/video* 2>/dev/null | grep -q [0-9] && echo 1 || echo 0"]
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
        if (cameraActive && hudReady && root.notifCount === 0) {
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

    // MPRIS shortcuts
    readonly property var activePlayer: Services.Mpris.activePlayer
    readonly property bool mediaPlaying: activePlayer !== null && activePlayer.isPlaying
    readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle !== "" || mediaPlaying)

    readonly property bool hasExpandContent: notifActive || sysHudActive || hasMedia
    readonly property bool expanded: !lockBlocked && hasExpandContent && (pinned || autoExpanded || notifActive || sysHudActive)
    readonly property bool isMediaPeek: !lockBlocked && autoExpanded && !pinned && !notifActive && !sysHudActive && hasMedia

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
    readonly property int calculatedCollapsedWidth: (showCollapsedText || (mediaStopping && !mediaIconTransformed)) ? Math.min(210, Math.max(160, collapsedText.implicitWidth + 52)) : 140
    property int collapsedWidth: 140
    property int collapsedHeight: 32

    readonly property int calculatedExpandedWidth: {
        if (notifActive) return replyMode ? 390 : 360
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
        if (sysHudActive) return 54
        if (isMediaPeek) return 54
        if (hasMedia) return 120
        return 52
    }

    // Format seconds → "m:ss"
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function pulse() {
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
        if (notifActive && currentNotif) {
            Services.Notifications.dismiss(currentNotif.notifId)
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
        interval: 1000
        running: root.mediaPlaying
        repeat: true
        onTriggered: root.activePlayer?.refreshPosition?.()
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
        z: -1
        propagateComposedEvents: true
        onClicked: mouse => {
            root.collapse()
            mouse.accepted = false
        }
    }

    Rectangle {
        id: island
        z: 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.isBottom ? (parent.height - height - 6) : 6
        clip: true

        width: root.expanded ? root.calculatedExpandedWidth : root.calculatedCollapsedWidth
        height: root.expanded ? root.calculatedExpandedHeight : root.collapsedHeight
        radius: root.expanded ? Services.Theme.radiusLg : (height / 2)
        color: Services.Theme.bgPure
        border.color: root.isCritical ? Services.Theme.danger : (root.expanded ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
        border.width: root.isCritical ? 1.5 : 1

        Behavior on width  { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }
        Behavior on radius { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }
        Behavior on border.color { ColorAnimation { duration: 200 } }

        MouseArea {
            id: islandMouseArea
            anchors.fill: parent
            z: 0
            enabled: root.hasExpandContent
            cursorShape: root.hasExpandContent ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.togglePin()
        }



        // ==================== Camera Privacy Indicator (Right Edge) ====================
        Item {
            id: cameraIndicator
            anchors.right: island.right
            anchors.rightMargin: 10
            anchors.verticalCenter: island.verticalCenter
            implicitWidth: 14
            implicitHeight: 14
            z: 2
            visible: (root.cameraActive && root.showCollapsedText) || opacity > 0
            opacity: (root.cameraActive && root.showCollapsedText) ? 1 : 0

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
            scale: activeState ? 1.0 : 0.2
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }

            states: [
                State {
                    name: "ICON_LEFT"
                    when: !Services.OverlayManager.isLocked && (root.showCollapsedText || (root.mediaStopping && !root.mediaIconTransformed))
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
                    when: !Services.OverlayManager.isLocked && !root.showCollapsedText && !(root.mediaStopping && !root.mediaIconTransformed) && !root.cameraActive
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: island.horizontalCenter
                        anchors.left: undefined
                        anchors.right: undefined
                    }
                },
                State {
                    name: "CAMERA_RIGHT"
                    when: !Services.OverlayManager.isLocked && (!root.showCollapsedText && !(root.mediaStopping && !root.mediaIconTransformed) && root.cameraActive)
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
                    AnchorAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    NumberAnimation { properties: "anchors.leftMargin"; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                },
                Transition {
                    AnchorAnimation { duration: 320; easing.type: Easing.OutExpo }
                    NumberAnimation { properties: "anchors.rightMargin"; duration: 320; easing.type: Easing.OutExpo }
                    NumberAnimation { properties: "anchors.leftMargin"; duration: 320; easing.type: Easing.OutExpo }
                }
            ]

            Text {
                id: statusIconTxt
                anchors.centerIn: parent
                text: {
                    if (Services.OverlayManager.isLocked) return "󰌾"
                    if (root.notifActive) return "󰂚"
                    if (root.mediaPlaying || (root.mediaStopping && !root.mediaTextCollapsed)) return "󰎈"
                    return "●"
                }
                font.family: Services.Theme.fontMono
                font.pixelSize: 13
                color: {
                    if (Services.OverlayManager.isLocked) return Services.Theme.accent
                    if (root.notifActive) return Services.Theme.accent
                    if (root.mediaPlaying || (root.mediaStopping && !root.mediaTextCollapsed) || root.cameraActive) return Services.Theme.success
                    return Services.Theme.textDisabled
                }
                scale: textScale

                property real textScale: 1.0

                onTextChanged: {
                    iconScaleAnim.restart()
                }

                SequentialAnimation {
                    id: iconScaleAnim
                    NumberAnimation { target: statusIconTxt; property: "textScale"; to: 0.2; duration: 120; easing.type: Easing.InQuad }
                    NumberAnimation { target: statusIconTxt; property: "textScale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                }

                // Green Blinking when camera active and no music text
                SequentialAnimation on opacity {
                    running: root.cameraActive && !root.showCollapsedText && !root.expanded
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                }

                Behavior on color { ColorAnimation { duration: 350 } }

                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: 4000
                    loops: Animation.Infinite
                    running: !Services.OverlayManager.isLocked && root.mediaPlaying && !root.expanded
                    onRunningChanged: {
                        if (!running) {
                            statusIconTxt.rotation = 0
                        }
                    }
                }
            }
        }

        // ==================== Dedicated Collapsed Track Title / Notif Text Zone ====================
        Item {
            id: collapsedTextContainer
            anchors.left: statusIconContainer.right
            anchors.leftMargin: 8
            anchors.right: island.right
            anchors.rightMargin: 12
            anchors.verticalCenter: island.verticalCenter
            height: 16
            z: 3

            readonly property bool showCollapsedText: !Services.OverlayManager.isLocked && (root.notifActive || root.mediaPlaying)
            readonly property bool activeState: !Services.OverlayManager.isLocked && !root.expanded && showCollapsedText

            clip: true
            opacity: activeState ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

            Text {
                id: collapsedText
                text: Services.OverlayManager.isLocked ? "Locked" : (root.notifActive ? ("Notif (" + root.notifCount + ")") : (root.mediaPlaying ? root.currentMediaText : root.lastTrackText))
                font.pixelSize: 11
                font.bold: true
                color: Services.Theme.textPrimary
                width: collapsedTextContainer.width
                horizontalAlignment: Text.AlignLeft
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
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && root.notifActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.15
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }

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
                            if (src.startsWith("/") || src.startsWith("file://") || src.startsWith("http"))
                                return src
                            return Quickshell.iconPath(src, true)
                        }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(40, 40)
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        font.family: Services.Theme.fontMono
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
                        Behavior on color { ColorAnimation { duration: 120 } }
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
                        Behavior on color { ColorAnimation { duration: 120 } }
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
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: dismissBtnMouse.containsMouse ? "#ffffff" : Services.Theme.textPrimary
                        font.pixelSize: 10
                        font.bold: true
                        Behavior on color { ColorAnimation { duration: 120 } }
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
            readonly property bool activeState: (root.sysHudTitle.includes("Caps Lock") || root.sysHudTitle.includes("Welcome") || !Services.OverlayManager.isLocked) && root.expanded && !root.notifActive && root.sysHudActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.15
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: Services.Theme.surfaceVariant
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: root.sysHudIcon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 15
                    color: root.sysHudColor
                }

                // Red Cross overlay when Caps Lock is Off
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 12
                    font.bold: true
                    color: Services.Theme.danger
                    visible: root.sysHudTitle === "Caps Lock Off"
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
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.notifActive && !root.sysHudActive && root.isMediaPeek
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.15
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }

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
                    font.family: Services.Theme.fontMono
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
                    font.family: Services.Theme.fontMono
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
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.notifActive && !root.sysHudActive && !root.isMediaPeek && root.hasMedia
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.15
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }

            // Row 1: Track Art + Info + Player Badge
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Artwork
                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Services.Theme.radiusMd
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
                        sourceSize: Qt.size(80, 80)
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰎈"
                        font.family: Services.Theme.fontMono
                        font.pixelSize: 20
                        color: Services.Theme.accent
                        visible: !albumArtImg.visible
                    }
                }

                // Info (Title, Artist, Identity)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    RowLayout {
                        spacing: 6
                        visible: (root.activePlayer?.identity ?? "").length > 0

                        Rectangle {
                            implicitHeight: 14
                            implicitWidth: Math.min(identityTxt.implicitWidth + 8, 80)
                            radius: 4
                            color: Services.Theme.surfaceVariant

                            Text {
                                id: identityTxt
                                anchors.centerIn: parent
                                text: root.activePlayer ? (root.activePlayer.identity || "") : ""
                                color: Services.Theme.textDisabled
                                font.pixelSize: 8
                                font.bold: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        text: root.activePlayer ? (root.activePlayer.trackTitle || "Unknown Track") : "—"
                        color: Services.Theme.textPrimary
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.activePlayer ? (root.activePlayer.trackArtist || "") : ""
                        color: Services.Theme.textSecondary
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        visible: text.length > 0
                    }
                }
            }

            // Row 2: Progress Bar & Timers
            Item {
                Layout.fillWidth: true
                implicitHeight: 16
                visible: root.activePlayer !== null

                Text {
                    id: posLabel
                    anchors { left: parent.left; top: parent.top }
                    text: root.fmtTime(root.activePlayer?.position)
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                }

                Text {
                    id: durLabel
                    anchors { right: parent.right; top: parent.top }
                    text: {
                        const len = root.activePlayer?.length ?? 0
                        return len > 0 ? root.fmtTime(len) : "--:--"
                    }
                    color: Services.Theme.textDisabled
                    font.pixelSize: 9
                }

                Rectangle {
                    id: progressBg
                    anchors {
                        left: posLabel.right; right: durLabel.left
                        leftMargin: 8; rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    height: 4
                    radius: 2
                    color: Services.Theme.surfaceVariant

                    Rectangle {
                        id: progressFill
                        height: parent.height
                        radius: 2
                        color: Services.Theme.accent
                        width: {
                            const len = root.activePlayer?.length ?? 0
                            const pos = root.activePlayer?.position ?? 0
                            return len > 0 ? Math.max(0, Math.min(1, pos / len)) * parent.width : 0
                        }
                        Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: progressBg
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        const ratio = mouse.x / width
                        const len = root.activePlayer?.length ?? 0
                        if (len > 0 && (root.activePlayer?.positionSupported ?? false))
                            root.activePlayer.position = ratio * len
                    }
                }
            }

            // Row 3: Full Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                // Shuffle
                Item {
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.shuffleSupported ?? false) ? 1 : 0.2
                    Rectangle {
                        anchors.fill: parent; radius: 6
                        color: shArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaShuffle
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        color: (root.activePlayer?.shuffle ?? false) ? Services.Theme.accent : Services.Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: 120 } }
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
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.canGoPrevious ?? false) ? 1 : 0.3
                    Rectangle {
                        anchors.fill: parent; radius: 6
                        color: prvArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaPrev
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: prvArea.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: prvArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: (root.activePlayer?.canGoPrevious ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.canGoPrevious ?? false
                        onClicked: (mouse) => { root.activePlayer.previous(); mouse.accepted = true }
                    }
                }

                // Play / Pause (Filled button)
                Rectangle {
                    implicitWidth: 30; implicitHeight: 30
                    radius: 8
                    color: playArea.containsMouse ? Qt.lighter(Services.Theme.accent, 1.15) : Services.Theme.accent
                    scale: playArea.containsMouse ? 1.05 : 1.0

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaPlayPause(root.mediaPlaying)
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: Services.Theme.bgDeep
                    }
                    MouseArea {
                        id: playArea; anchors.fill: parent; hoverEnabled: true
                        cursorShape: (root.activePlayer?.canTogglePlaying ?? true) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: root.activePlayer?.canTogglePlaying ?? true
                        onClicked: (mouse) => { root.activePlayer.playPause(); mouse.accepted = true }
                    }
                }

                // Next
                Item {
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.canGoNext ?? false) ? 1 : 0.3
                    Rectangle {
                        anchors.fill: parent; radius: 6
                        color: nxtArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.mediaNext
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: nxtArea.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                        Behavior on color { ColorAnimation { duration: 120 } }
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
                    implicitWidth: 28; implicitHeight: 28
                    opacity: (root.activePlayer?.loopSupported ?? false) ? 1 : 0.2
                    Rectangle {
                        anchors.fill: parent; radius: 6
                        color: rpArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        text: (root.activePlayer?.loop ?? MprisLoopState.None) === MprisLoopState.Track ? Services.Icons.mediaLoopOne : Services.Icons.mediaLoopAll
                        color: (root.activePlayer?.loop ?? MprisLoopState.None) !== MprisLoopState.None ? Services.Theme.accent : (rpArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                        Behavior on color { ColorAnimation { duration: 120 } }
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


    }

    // ==================== CapsLock Satellite Dot (Right of Island) ====================
    Rectangle {
        id: capsLockDot
        anchors.left: island.right
        anchors.leftMargin: (root.capsLockActive && !root.expanded) ? 8 : -32
        anchors.verticalCenter: island.verticalCenter
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: Services.Theme.bgPure
        border.color: Services.Theme.borderSubtle
        border.width: 1
        z: 1
        visible: root.capsLockActive || opacity > 0 || scale > 0

        opacity: (root.capsLockActive && !root.expanded) ? 1 : 0
        scale: (root.capsLockActive && !root.expanded) ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
        Behavior on anchors.leftMargin { NumberAnimation { duration: 550; easing.type: Easing.OutBack } }

        // CapsLock Icon
        Text {
            anchors.centerIn: parent
            text: "󰘶"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: Services.Theme.alertYellow
        }
    }

}




