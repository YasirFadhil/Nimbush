import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import "../../services" as Services
import "../bar/components" as BarComponents
import "../notifications" as NotifModule

Scope {
    id: root

    property bool isLocked: sessionLock.locked
    property bool lockVisible: sessionLock.locked
    property string passwordInput: ""
    property string pendingPassword: ""
    property bool showPassword: false
    property bool isError: false
    property string errorMessage: ""
    property bool isAuthenticating: false

    property string timeStr: "00:00"
    property string hourStr: "00"
    property string minStr: "00"
    property string dateStr: ""
    property string greetingStr: "Welcome"
    property string username: "user"
    property string hostname: "host"
    property bool capsLockOn: false
    property bool isRevealed: false
    property bool lockscreenCcOpen: false
    property bool lockscreenPwrOpen: false
    property bool userRevealedInput: false

    readonly property string lockLayout: Services.Config ? (Services.Config.lockscreenLayout || "default") : "default"
    readonly property bool isCompact: lockLayout === "compact"
    readonly property bool isMinimal: lockLayout === "minimal"
    readonly property bool isDefault: !isCompact && !isMinimal

    function numberToWords(num) {
        const ones = ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN"];
        const tens = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY"];
        if (num < 20) return ones[num] || "";
        const t = Math.floor(num / 10);
        const o = num % 10;
        return tens[t] + (o > 0 ? (" " + ones[o]) : "");
    }

    readonly property string hourWords: numberToWords(Number(root.hourStr))
    readonly property string minWords: (Number(root.minStr) === 0) ? "O'CLOCK" : ((Number(root.minStr) < 10 ? "OH " : "") + numberToWords(Number(root.minStr)))

    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null && (player?.trackTitle ?? "").length > 0
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property int notifCount: Services.Notifications.historyList ? Services.Notifications.historyList.count : 0

    // Smart Adaptive state detections
    readonly property bool hasActiveNotifs: !root.isMinimal && root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
    readonly property bool hasActiveMedia: root.isDefault && root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
    readonly property bool isCrowded: hasActiveNotifs && hasActiveMedia
    readonly property bool isBusy: hasActiveNotifs || hasActiveMedia

    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Timer {
        id: lockMprisTimer
        interval: 500
        running: root.isLocked && root.isPlaying
        repeat: true
        onTriggered: root.player?.positionChanged?.()
    }

    Timer {
        id: revealTimer
        interval: 50
        onTriggered: root.isRevealed = true
    }

    Timer {
        id: unlockTimer
        interval: 220
        onTriggered: {
            root.isLocked = false
            Services.OverlayManager.isLocked = false
            sessionLock.locked = false
        }
    }

    function open() {
        if (isLocked) return
        isLocked = true
        passwordInput = ""
        pendingPassword = ""
        isError = false
        errorMessage = ""
        showPassword = false
        capsLockOn = false
        isAuthenticating = false
        isRevealed = false
        userRevealedInput = false
        updateTime()
        sessionLock.locked = true
        revealTimer.start()
    }

    function close() {
        if (isLocked) {
            triggerShake("Password required!")
            return
        }
        root.isLocked = false
        Services.OverlayManager.isLocked = false
        sessionLock.locked = false
    }

    function lock() { open() }
    function show() { open() }
    function hide() {
        if (!isLocked) {
            root.isLocked = false
            Services.OverlayManager.isLocked = false
            sessionLock.locked = false
        }
    }
    function toggle() {
        if (isLocked) close()
        else open()
    }

    function updateTime() {
        const now = new Date()
        const is24 = Services.Config ? Services.Config.lockscreen24h : false
        let h = now.getHours()
        if (h < 12) greetingStr = "Good Morning"
        else if (h < 18) greetingStr = "Good Afternoon"
        else greetingStr = "Good Evening"

        if (!is24) {
            h = h % 12
            if (h === 0) h = 12
        }
        hourStr = String(h).padStart(2, "0")
        minStr = String(now.getMinutes()).padStart(2, "0")
        timeStr = hourStr + ":" + minStr
        dateStr = Qt.formatDateTime(now, "dddd, MMMM d")
    }

    function authenticate() {
        if (isAuthenticating) return
        const pw = passwordInput.trim()
        if (pw.length === 0) {
            triggerShake("Enter password")
            return
        }
        isAuthenticating = true
        pendingPassword = passwordInput
        if (pam.active && pam.responseRequired) {
            pam.respond(pendingPassword)
            pendingPassword = ""
        } else {
            if (pam.active) pam.abort()
            pam.start()
        }
    }

    function triggerShake(msg) {
        isError = true
        errorMessage = msg || "Incorrect password!"
        isAuthenticating = false
        pendingPassword = ""
        passwordInput = ""
        showPassword = false
        if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
        if (pam.active) pam.abort()
        if (typeof shakeAnim !== "undefined" && shakeAnim) shakeAnim.restart()
    }

    function unlockSuccess() {
        isError = false
        errorMessage = ""
        passwordInput = ""
        pendingPassword = ""
        showPassword = false
        if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
        isAuthenticating = false
        isRevealed = false
        capsLockOn = false
        lockscreenCcOpen = false
        lockscreenPwrOpen = false
        unlockTimer.start()
    }

    Component.onCompleted: {
        Services.OverlayManager.register(root)
        updateTime()
        userInfoProc.running = true
    }

    Timer {
        id: clockTimer
        interval: 1000
        running: root.isLocked
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateTime()
    }

    // System info process
    Process {
        id: userInfoProc
        command: ["sh", "-c", "echo $USER && uname -n"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n")
                if (lines.length > 0 && lines[0]) root.username = lines[0]
                if (lines.length > 1 && lines[1]) root.hostname = lines[1]
            }
        }
    }

    // Power Action Processes
    Process { id: suspendProc; command: ["systemctl", "suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["systemctl", "poweroff"] }

    PamContext {
        id: pam
        config: "login"

        onResponseRequiredChanged: {
            if (responseRequired && root.pendingPassword !== "") {
                pam.respond(root.pendingPassword)
                root.pendingPassword = ""
            }
        }

        onCompleted: (result) => {
            if (result === PamResult.Success) {
                root.unlockSuccess()
            } else {
                root.triggerShake("Incorrect password")
            }
        }

        onError: (err) => {
            root.triggerShake(err || "Authentication error")
        }
    }

    WlSessionLock {
        id: sessionLock

        onLockedChanged: {
            root.isLocked = sessionLock.locked
            Services.OverlayManager.isLocked = sessionLock.locked
            if (!sessionLock.locked) {
                root.passwordInput = ""
                root.pendingPassword = ""
                root.isAuthenticating = false
                root.isRevealed = false
                root.capsLockOn = false
                if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
                if (pam.active) pam.abort()
            }
        }

        WlSessionLockSurface {
            id: surface

            // Fullscreen solid root container inside lock surface
            Rectangle {
                anchors.fill: parent
                color: Services.Theme.bgDeep
                focus: true

                Component.onCompleted: pwTextInput.forceActiveFocus()

                // Keyboard Handler - Strictly prevents ESC from unlocking
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        root.passwordInput = ""
                        root.userRevealedInput = false
                        if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
                        root.triggerShake("Password required")
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (typeof pwTextInput !== "undefined" && pwTextInput) root.passwordInput = pwTextInput.text
                        root.authenticate()
                        event.accepted = true
                    } else if (event.key === Qt.Key_CapsLock) {
                        root.capsLockOn = !root.capsLockOn
                        event.accepted = true
                    } else {
                        // Intelligent CapsLock auto-detection heuristic based on typed character casing vs Shift key
                        if (event.text && event.text.length === 1) {
                            const c = event.text
                            const isShift = !!(event.modifiers & Qt.ShiftModifier)
                            if (c >= 'A' && c <= 'Z') {
                                root.capsLockOn = !isShift
                            } else if (c >= 'a' && c <= 'z') {
                                root.capsLockOn = isShift
                            }
                        }
                        if (event.text.length > 0) {
                            root.userRevealedInput = true
                        }
                        if (typeof pwTextInput !== "undefined" && pwTextInput && !pwTextInput.activeFocus && event.text.length > 0) {
                            pwTextInput.forceActiveFocus()
                        }
                    }
                }

                // Fullscreen Wallpaper Layer (Gets image from Services.Wallpaper or custom lockscreen image, with smooth Zoom and MultiEffect blur)
                Item {
                    anchors.fill: parent

                    Image {
                        id: bgImage
                        anchors.fill: parent
                        source: {
                            if (Services.Config && Services.Config.lockscreenWallpaperMode === "custom" && Services.Config.lockscreenCustomWallpaper.length > 0) {
                                return "file://" + Services.Config.lockscreenCustomWallpaper
                            }
                            return Services.Wallpaper.currentWallpaper.length > 0 ? ("file://" + Services.Wallpaper.currentWallpaper) : ("file://" + Services.Wallpaper.darkWallbler)
                        }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: false
                        smooth: true
                        cache: true
                        scale: (Services.Config && !Services.Config.lockscreenWallpaperZoom) ? 1.0 : (root.isRevealed ? 1.16 : 1.0)
                        transformOrigin: Item.Center
                        visible: !(Services.Config && Services.Config.lockscreenBlur && (Services.Config.lockscreenBlurRadius > 0))
                        Behavior on scale { NumberAnimation { duration: 350; easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic } }
                    }

                    MultiEffect {
                        anchors.fill: bgImage
                        source: bgImage
                        scale: bgImage.scale
                        transformOrigin: Item.Center
                        blurEnabled: (Services.Config && Services.Config.lockscreenBlur) || false
                        blur: (Services.Config ? Services.Config.lockscreenBlurRadius : 0.40)
                        blurMax: 64
                        visible: (Services.Config && Services.Config.lockscreenBlur && (Services.Config.lockscreenBlurRadius > 0)) || false
                        Behavior on blur { NumberAnimation { duration: 250 } }
                    }

                    // Smooth Dark Dim / Vignette Overlay
                    Rectangle {
                        anchors.fill: parent
                        color: Services.Theme.bgDeep
                        opacity: {
                            if (!root.isRevealed) return 0.0
                            var baseDim = Services.Config ? Services.Config.lockscreenDim : 0.45
                            if (root.isCompact) return Math.min(0.85, baseDim + 0.15)
                            if (root.isMinimal) return Math.max(0.18, baseDim - 0.12)
                            return baseDim
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 900
                                easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic
                            }
                        }
                    }
                }

                // ── Top Header Bar (Center: DynamicIsland, Right: Quick Status & ControlCenter) ──
                Item {
                    id: topBarHeader
                    anchors.top: parent.top
                    anchors.topMargin: root.isRevealed ? 0 : -20
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 48
                    z: 100
                    visible: !root.isCompact
                    opacity: (root.isRevealed && !root.isCompact) ? 1.0 : 0.0
                    scale: root.isRevealed ? 1.0 : 0.96
                    Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                    // Center: Dynamic Island (Copied 1:1 System HUD Alert Expand 280x54px & Collapsed Capsule 48x30px from DynamicIsland.qml)
                    Rectangle {
                        id: lockIsland
                        visible: root.isDefault
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Services.Theme.bgDeep
                        border.color: Services.Theme.borderHighlight
                        border.width: 1

                        property bool islandExpanded: false
                        property var activeNotif: null

                        width: islandExpanded ? 260 : 140
                        height: islandExpanded ? 48 : 32
                        radius: islandExpanded ? 24 : 16

                        Behavior on width  { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }
                        Behavior on radius { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }

                        Timer {
                            id: lockIslandShrinkTimer
                            interval: 4500
                            repeat: false
                            onTriggered: {
                                lockIsland.islandExpanded = false
                                lockIsland.activeNotif = null
                            }
                        }

                        Connections {
                            target: root
                            function onIsRevealedChanged() {
                                if (root.isRevealed) {
                                    lockIsland.activeNotif = null
                                    lockIsland.islandExpanded = true
                                    lockIslandShrinkTimer.interval = 2400
                                    lockIslandShrinkTimer.restart()
                                } else {
                                    lockIsland.islandExpanded = false
                                    lockIslandShrinkTimer.stop()
                                }
                            }
                        }

                        Connections {
                            target: Services.Notifications
                            function onNewNotification(entry) {
                                lockIsland.activeNotif = entry
                                lockIsland.islandExpanded = true
                                lockIslandShrinkTimer.interval = 4500
                                lockIslandShrinkTimer.restart()
                            }
                        }

                        // ==================== Collapsed Status Icon (Left Edge in 140x32 Pill) ====================
                        Item {
                            id: statusIconContainer
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 16
                            implicitHeight: 16
                            z: 3
                            visible: !lockIsland.islandExpanded || opacity > 0.01
                            opacity: !lockIsland.islandExpanded ? 1 : 0
                            scale: !lockIsland.islandExpanded ? 1.0 : 0.2
                            transformOrigin: Item.Center

                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                            Behavior on scale   { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }

                            Text {
                                anchors.centerIn: parent
                                text: "󰌾"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: Services.Theme.accent
                            }
                        }

                        // ==================== Expanded: Dynamic Island Notification Banner ====================
                        Item {
                            id: notifContentContainer
                            anchors.fill: parent
                            visible: lockIsland.islandExpanded || opacity > 0.01
                            opacity: lockIsland.islandExpanded ? 1 : 0
                            scale: lockIsland.islandExpanded ? 1.0 : 0.2
                            transformOrigin: Item.Center
                            z: 1

                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                            Behavior on scale   { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }

                            // App Icon / Image Container (Centered inside left circular cap)
                            Rectangle {
                                id: notifIconBox
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                height: 32
                                radius: 16
                                color: notifAppIconImg.visible ? "transparent" : Services.Theme.surfaceVariant
                                clip: true

                                Image {
                                    id: notifAppIconImg
                                    anchors.fill: parent
                                    source: {
                                        if (!lockIsland.activeNotif) return ""
                                        const src = lockIsland.activeNotif.image || lockIsland.activeNotif.appIcon || lockIsland.activeNotif.icon || ""
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
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize: Qt.size(64, 64)
                                    visible: status === Image.Ready && source.toString().length > 0
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: lockIsland.activeNotif ? (Services.Icons.bell || "󰂚") : "󰌾"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: Services.Theme.accent
                                    visible: !notifAppIconImg.visible
                                }
                            }

                            // Notification Text Summary & Body (100% Guaranteed Mathematically Centered Vertically)
                            Column {
                                id: notifTextBox
                                anchors.left: notifIconBox.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: lockIsland.activeNotif ? (lockIsland.activeNotif.summary || lockIsland.activeNotif.appName || "Notification") : "Device Locked"
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: lockIsland.activeNotif ? (lockIsland.activeNotif.body || "") : "Authentication required"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // Mode A: Default Pill Box (Default Layout)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        implicitWidth: combinedCcRow.implicitWidth + 22
                        radius: 15
                        color: ccMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: root.lockscreenCcOpen ? Services.Theme.accent : Services.Theme.border
                        border.width: 1
                        visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowStatusPill : true)
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        RowLayout {
                            id: combinedCcRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Wi-Fi Status Icon (if enabled)
                            Text {
                                visible: Services.Wifi && Services.Wifi.enabled
                                text: Services.Icons.wifiIcon(Services.Wifi.signalStrength, Services.Wifi.connected, Services.Wifi.enabled)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: (Services.Wifi && Services.Wifi.connected) ? Services.Theme.accent : Services.Theme.textDisabled
                            }

                            // Bluetooth Status Icon (if enabled)
                            Text {
                                visible: Services.Bluetooth && Services.Bluetooth.enabled
                                text: (Services.Bluetooth && Services.Bluetooth.hasConnectedDevice)
                                      ? Services.Icons.btDeviceIcon(Services.Bluetooth.connectedDeviceIcon, Services.Bluetooth.connectedDeviceName)
                                      : Services.Icons.bluetooth
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: (Services.Bluetooth && Services.Bluetooth.hasConnectedDevice) ? Services.Theme.accent : Services.Theme.textDisabled
                            }

                            // Battery Icon & Percentage
                            RowLayout {
                                spacing: 4

                                Text {
                                    text: Services.Icons.powerIcon(Services.Power.charging, Math.round((Services.Power.percentage || 0) * 100))
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary))
                                }

                                Text {
                                    text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.bold: true
                                    color: Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary)
                                }
                            }

                            // Vertical Separator
                            Rectangle {
                                width: 1
                                height: 12
                                color: Services.Theme.border
                            }

                            // Control Center Toggle Icon
                            Text {
                                text: Services.Icons.sliders
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: root.lockscreenCcOpen ? Services.Theme.accent : Services.Theme.textPrimary
                            }
                        }

                        MouseArea {
                            id: ccMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.lockscreenCcOpen = !root.lockscreenCcOpen
                            }
                        }
                    }

                    // Mode B: Minimal Discrete Status Icons (Minimal Layout - Clean, subtle monochrome)
                    RowLayout {
                        visible: root.isMinimal && (Services.Config ? Services.Config.lockscreenShowStatusPill : true)
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        opacity: 0.75

                        // Wi-Fi
                        Text {
                            visible: Services.Wifi && Services.Wifi.enabled
                            text: Services.Icons.wifi
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: (Services.Wifi && Services.Wifi.connected) ? Services.Theme.accent : Services.Theme.textDisabled
                        }

                        // Battery
                        RowLayout {
                            spacing: 4
                            Text {
                                text: Services.Icons.powerIcon(Services.Power.charging, Math.round((Services.Power.percentage || 0) * 100))
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary))
                            }
                            Text {
                                text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textSecondary
                            }
                        }

                        // Subtle CC Button
                        Text {
                            text: Services.Icons.sliders
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: root.lockscreenCcOpen ? Services.Theme.accent : Services.Theme.textSecondary
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.lockscreenCcOpen = !root.lockscreenCcOpen
                            }
                        }
                    }
                }

                // Main Content Backdrop MouseArea
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.lockscreenCcOpen
                    onClicked: {
                        root.userRevealedInput = true
                        pwTextInput.forceActiveFocus()
                    }

                    Item {
                        id: mainContainer
                        anchors.fill: parent
                        anchors.horizontalCenterOffset: 0

                        // Shake Animation on Auth Error or ESC press
                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: 0; to: -14; duration: 40; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: -14; to: 14; duration: 40; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: 14; to: -8; duration: 35; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: -8; to: 8; duration: 35; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: 8; to: 0; duration: 30; easing.type: Easing.InOutQuad }
                        }

                        // ── 1. Top Clock & Date (Default & Minimal Layouts) ───────────────────
                        ColumnLayout {
                            id: topClockColumn
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: root.isMinimal
                                ? Math.max(90, Math.round(parent.height * 0.22))
                                : Math.max(102, Math.round(parent.height * 0.125))

                            spacing: 4
                            visible: !root.isCompact
                            opacity: (root.isRevealed && !root.isCompact) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on anchors.topMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                            readonly property string clockStyle: root.isMinimal ? "minimal" : (Services.Config ? Services.Config.lockscreenClockStyle : "hero")

                            // Date Line (for hero, modern, minimal)
                            Text {
                                visible: topClockColumn.clockStyle !== "compact" && topClockColumn.clockStyle !== "vertical" && topClockColumn.clockStyle !== "typographic" && topClockColumn.clockStyle !== "radial" && topClockColumn.clockStyle !== "cyber"
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? root.dateStr.toUpperCase() : root.dateStr
                                color: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? Services.Theme.accent : Services.Theme.textPrimary
                                font.pixelSize: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? Services.Theme.fontSizeSm : 18
                                font.weight: Font.DemiBold
                                font.letterSpacing: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? 2.5 : 0.4
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 1: Hero Clock (Single horizontal huge display)
                            Text {
                                visible: topClockColumn.clockStyle === "hero"
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: root.timeStr
                                color: Services.Theme.white
                                font.pixelSize: 94
                                font.weight: Font.Bold
                                font.letterSpacing: -1.0
                                font.family: Services.Theme.fontDisplay
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 2: Modern Stacked Clock (Bold Hour on top, Clean Minute below)
                            ColumnLayout {
                                visible: topClockColumn.clockStyle === "modern"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: -20

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.hourStr
                                    color: Services.Theme.accent
                                    font.pixelSize: 80
                                    font.weight: Font.Black
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.minStr
                                    color: Services.Theme.white
                                    font.pixelSize: 80
                                    font.weight: Font.Black
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Style 3: Compact Island Pill Clock
                            Rectangle {
                                visible: topClockColumn.clockStyle === "compact"
                                Layout.alignment: Qt.AlignHCenter
                                height: 48
                                implicitWidth: compactRow.implicitWidth + 32
                                radius: 24
                                color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.75)
                                border.color: Services.Theme.borderHighlight
                                border.width: 1

                                RowLayout {
                                    id: compactRow
                                    anchors.centerIn: parent
                                    spacing: 14

                                    Text {
                                        text: root.timeStr
                                        color: Services.Theme.accent
                                        font.pixelSize: Services.Theme.fontSize2xl
                                        font.bold: true
                                        font.family: Services.Theme.fontDisplay
                                    }
                                    Rectangle { width: 1.5; height: 18; color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4); radius: 1 }
                                    Text {
                                        text: root.dateStr
                                        color: Services.Theme.textPrimary
                                        font.pixelSize: Services.Theme.fontSizeMd
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            // Style 4: Minimalist Clock (Clean ultra-light display)
                            Text {
                                visible: topClockColumn.clockStyle === "minimal"
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: root.timeStr
                                color: Services.Theme.white
                                font.pixelSize: 96
                                font.weight: Font.ExtraLight
                                font.letterSpacing: 4
                                font.family: Services.Theme.fontDisplay
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 5: Vertical Aesthetic Clock
                            RowLayout {
                                visible: topClockColumn.clockStyle === "vertical"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 20

                                ColumnLayout {
                                    spacing: -16
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.hourStr
                                        color: Services.Theme.accent
                                        font.pixelSize: 68
                                        font.weight: Font.Black
                                        font.family: Services.Theme.fontDisplay
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.minStr
                                        color: Services.Theme.white
                                        font.pixelSize: 68
                                        font.weight: Font.Black
                                        font.family: Services.Theme.fontDisplay
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                }

                                Rectangle {
                                    width: 2.5
                                    height: 86
                                    color: Services.Theme.accent
                                    radius: 1.5
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Text {
                                        text: Qt.formatDateTime(new Date(), "dddd")
                                        color: Services.Theme.accent
                                        font.pixelSize: Services.Theme.fontSizeXl
                                        font.bold: true
                                    }
                                    Text {
                                        text: Qt.formatDateTime(new Date(), "MMMM d, yyyy")
                                        color: Services.Theme.textPrimary
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: root.greetingStr
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: Services.Theme.fontSizeXs
                                    }
                                }
                            }

                            // Style 6: Typographic Editorial Words Clock
                            ColumnLayout {
                                visible: topClockColumn.clockStyle === "typographic" || topClockColumn.clockStyle === "words"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.hourWords
                                    color: Services.Theme.accent
                                    font.pixelSize: 46
                                    font.weight: Font.Black
                                    font.letterSpacing: 3
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.minWords
                                    color: Services.Theme.white
                                    font.pixelSize: 46
                                    font.weight: Font.Black
                                    font.letterSpacing: 3
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 4
                                    width: 140; height: 2; radius: 1; color: Services.Theme.accent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.dateStr.toUpperCase()
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Style 7: Radial Ring Gauge Clock
                            Rectangle {
                                visible: topClockColumn.clockStyle === "radial"
                                Layout.alignment: Qt.AlignHCenter
                                width: 154; height: 154; radius: 77
                                color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.65)
                                border.color: Services.Theme.accent
                                border.width: 2.5

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    radius: 70
                                    color: "transparent"
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                                    border.width: 1.5
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.timeStr
                                        color: Services.Theme.white
                                        font.pixelSize: 36
                                        font.weight: Font.Bold
                                        font.family: Services.Theme.fontDisplay
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Qt.formatDateTime(new Date(), "ddd, MMM d")
                                        color: Services.Theme.accent
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.5
                                    }
                                }
                            }

                            // Style 8: Cyberpunk / Terminal Monospace HUD
                            Rectangle {
                                visible: topClockColumn.clockStyle === "cyber"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: cyberCol.implicitWidth + 40
                                implicitHeight: cyberCol.implicitHeight + 24
                                radius: 8
                                color: Qt.rgba(0, 0, 0, 0.75)
                                border.color: Services.Theme.accent
                                border.width: 1.5

                                ColumnLayout {
                                    id: cyberCol
                                    anchors.centerIn: parent
                                    spacing: 4

                                    RowLayout {
                                        spacing: 14
                                        Text {
                                            text: "┌[ SYS: LOCKED ]"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.accent
                                            font.bold: true
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "[ " + (Services.OsInfo.username || root.username) + "@" + (Services.OsInfo.hostname || root.hostname) + " ]┐"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.textSecondary
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.timeStr + ":" + String(new Date().getSeconds()).padStart(2, "0")
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: 44
                                        font.bold: true
                                        color: Services.Theme.white
                                    }

                                    RowLayout {
                                        spacing: 14
                                        Text {
                                            text: "└[ DATE: " + Qt.formatDateTime(new Date(), "yyyy.MM.dd") + " ]"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.textSecondary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "[ BAT: " + Math.round((Services.Power.percentage || 0.9) * 100) + "% ]┘"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.accent
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            // Ambient Greeting / Weather Subtitle (for styles other than vertical/radial/cyber)
                            RowLayout {
                                visible: (topClockColumn.clockStyle !== "vertical" && topClockColumn.clockStyle !== "radial" && topClockColumn.clockStyle !== "cyber") && (Services.Config ? Services.Config.lockscreenShowWeather : true)
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6
                                opacity: 0.85

                                Text {
                                    text: Services.Icons.sun || Services.Icons.sparkle
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 12
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: root.greetingStr + ", " + (Services.OsInfo.username || root.username)
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.weight: Font.Medium
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }
                        }

                        // ── 2. Bottom Profile Picture & Password Input System ────────────────────────
                        Item {
                            id: centerAuthCard
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: !root.isCompact ? parent.bottom : undefined
                            anchors.bottomMargin: !root.isCompact ? (root.isMinimal ? 24 : Math.max(36, Math.round(parent.height * 0.055))) : 0
                            anchors.verticalCenter: root.isCompact ? parent.verticalCenter : undefined
                            anchors.verticalCenterOffset: root.isCompact ? ((root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)) ? -15 : 0) : 0

                            width: root.isCompact ? Math.min(mainContainer.width - 40, 390) : 300
                            height: 195

                            readonly property string avatarShape: Services.Config ? Services.Config.lockscreenAvatarShape : "circle"
                            readonly property bool showAvatarRing: Services.Config ? Services.Config.lockscreenAvatarRing : true
                            readonly property string inputStyle: root.isMinimal ? "underline" : (Services.Config ? Services.Config.lockscreenInputStyle : "pill")
                            readonly property bool showPasswordBox: root.userRevealedInput || (root.passwordInput.length > 0) || root.isError || root.isAuthenticating || root.isCompact

                            readonly property int avatarRadius: {
                                if (avatarShape === "circle") return 24
                                if (avatarShape === "squircle") return 14
                                return 10
                            }
                            readonly property int ringRadius: {
                                if (avatarShape === "circle") return 27
                                if (avatarShape === "squircle") return 17
                                return 13
                            }

                            opacity: root.isRevealed ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                            // ── 1. Top Alerts & Banners (Fixed at Y: 0) ──────────────────────────
                            // Caps Lock Warning Banner
                            RowLayout {
                                visible: root.capsLockOn && !root.isError
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                spacing: 5

                                Text {
                                    text: Services.Icons.keyboard
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.warning
                                }

                                Text {
                                    text: "Caps Lock is on"
                                    color: Services.Theme.warning
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // PAM Authentication Error Banner
                            RowLayout {
                                visible: root.isError && root.errorMessage.length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                spacing: 5

                                Text {
                                    text: Services.Icons.error
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.danger
                                }

                                Text {
                                    text: root.errorMessage
                                    color: Services.Theme.danger
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Modern PIN Dots Indicator Bar
                            RowLayout {
                                visible: !root.isCompact && centerAuthCard.inputStyle === "dots"
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 2
                                spacing: 10

                                Repeater {
                                    model: 6
                                    Rectangle {
                                        required property int index
                                        width: 14; height: 14; radius: 7
                                        color: (pwTextInput.text.length > index)
                                            ? (root.isError ? Services.Theme.danger : Services.Theme.accent)
                                            : Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.7)
                                        border.color: (pwTextInput.text.length > index)
                                            ? (root.isError ? Services.Theme.danger : Services.Theme.accent)
                                            : Services.Theme.border
                                        border.width: 1.5
                                        scale: (pwTextInput.text.length > index) ? 1.15 : 1.0

                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    }
                                }
                            }

                            // ── 2. Password Input Box (Fixed at Y: 20 - Fades/Scales smoothly without pushing anything) ──
                            Rectangle {
                                id: inputContainer
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 20
                                width: root.isCompact ? (parent.width - 40) : ((centerAuthCard.inputStyle === "underline") ? 240 : 250)
                                height: (centerAuthCard.inputStyle === "box") ? 42 : 38
                                radius: {
                                    if (centerAuthCard.inputStyle === "pill" || root.isCompact) return 19
                                    if (centerAuthCard.inputStyle === "box") return 8
                                    return 0
                                }
                                color: {
                                    if (!root.isCompact && (centerAuthCard.inputStyle === "underline" || centerAuthCard.inputStyle === "dots")) return "transparent"
                                    if (!root.isCompact && centerAuthCard.inputStyle === "box") return Services.Theme.bgElevated
                                    return pwTextInput.activeFocus 
                                        ? Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.85) 
                                        : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.65)
                                }
                                border.color: (!root.isCompact && (centerAuthCard.inputStyle === "underline" || centerAuthCard.inputStyle === "dots"))
                                    ? "transparent"
                                    : (root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border))
                                border.width: (!root.isCompact && (centerAuthCard.inputStyle === "underline" || centerAuthCard.inputStyle === "dots")) ? 0 : 1.5

                                visible: opacity > 0.01
                                opacity: centerAuthCard.showPasswordBox ? 1.0 : 0.0
                                scale: centerAuthCard.showPasswordBox ? 1.0 : 0.94
                                transformOrigin: Item.Bottom

                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                // Underline bar for "underline" style
                                Rectangle {
                                    visible: !root.isCompact && centerAuthCard.inputStyle === "underline"
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: pwTextInput.activeFocus ? 2 : 1
                                    color: root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on height { NumberAnimation { duration: 120 } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: (!root.isCompact && centerAuthCard.inputStyle === "underline") ? 6 : 12
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    // Leading Lock / State Icon
                                    Item {
                                        id: lockIconBox
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        Layout.alignment: Qt.AlignVCenter

                                        Text {
                                            id: lockStateIcon
                                            anchors.centerIn: parent
                                            text: root.isAuthenticating ? Services.Icons.spinner : (root.isError ? Services.Icons.error : Services.Icons.lock)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            color: root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.textSecondary)

                                            RotationAnimation on rotation {
                                                id: lockSpinAnim
                                                running: root.isAuthenticating
                                                loops: Animation.Infinite
                                                from: 0; to: 360; duration: 850
                                                onRunningChanged: {
                                                    if (!running) {
                                                        lockStateIcon.rotation = 0
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Actual Password Input Container
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        TextInput {
                                            id: pwTextInput
                                            anchors.fill: parent
                                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                            passwordCharacter: "•"
                                            color: Services.Theme.textPrimary
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            font.family: Services.Theme.fontMono
                                            verticalAlignment: TextInput.AlignVCenter
                                            clip: true
                                            focus: false
                                            cursorVisible: activeFocus
                                            enabled: !root.isAuthenticating

                                            onAccepted: {
                                                root.passwordInput = text
                                                root.authenticate()
                                            }

                                            onTextChanged: {
                                                root.passwordInput = text
                                                if (root.isError) {
                                                    root.isError = false
                                                    root.errorMessage = ""
                                                }
                                            }
                                        }

                                        // Placeholder prompt
                                        Text {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.isAuthenticating ? "Authenticating..." : "Enter Password"
                                            color: Qt.rgba(Services.Theme.textSecondary.r, Services.Theme.textSecondary.g, Services.Theme.textSecondary.b, 0.4)
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.family: Services.Theme.fontPrimary
                                            visible: pwTextInput.text.length === 0 && !root.isAuthenticating
                                        }
                                    }
                                }
                            }

                            // ── 3. User Avatar (Fixed at Y: 72 - 100% IMMUTABLE POSITION) ────────
                            Item {
                                id: avatarBoxContainer
                                visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowAvatar : false)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 72
                                width: 56
                                height: 56

                                // Outer Glow / Focus Ring
                                Canvas {
                                    id: outerGlowRing
                                    anchors.centerIn: parent
                                    width: 54
                                    height: 54
                                    visible: centerAuthCard.showAvatarRing
                                    scale: pwTextInput.activeFocus ? 1.0 : 0.98

                                    property real r: centerAuthCard.ringRadius
                                    property real bw: pwTextInput.activeFocus ? 2 : 1.5
                                    property color bc: root.isError
                                        ? Services.Theme.danger
                                        : (pwTextInput.activeFocus
                                            ? Services.Theme.accent
                                            : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3))

                                    onRChanged: requestPaint()
                                    onBwChanged: requestPaint()
                                    onBcChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.clearRect(0, 0, width, height)
                                        if (width <= 0 || height <= 0 || bw <= 0) return
                                        ctx.strokeStyle = bc
                                        ctx.lineWidth = bw
                                        var half = bw / 2
                                        var rad = Math.max(0, Math.min(r - half, (width - bw) / 2, (height - bw) / 2))
                                        if (rad <= 0) return
                                        ctx.beginPath()
                                        ctx.moveTo(half + rad, half)
                                        ctx.lineTo(width - half - rad, half)
                                        ctx.arcTo(width - half, half, width - half, half + rad, rad)
                                        ctx.lineTo(width - half, height - half - rad)
                                        ctx.arcTo(width - half, height - half, width - half - rad, height - half, rad)
                                        ctx.lineTo(half + rad, height - half)
                                        ctx.arcTo(half, height - half, half, height - half - rad, rad)
                                        ctx.lineTo(half, half + rad)
                                        ctx.arcTo(half, half, half + rad, half, rad)
                                        ctx.closePath()
                                        ctx.stroke()
                                    }

                                    Behavior on bc { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    SequentialAnimation on opacity {
                                        running: pwTextInput.activeFocus || root.isAuthenticating
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 0.5; duration: 1200; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.5; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                                    }
                                }

                                // Main Avatar Container
                                Services.AvatarFrame {
                                    id: avatarBox
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 48
                                    source: Services.OsInfo.avatarPath.length > 0 ? Services.OsInfo.avatarPath : ("file://" + (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.face")
                                    shapeRadius: centerAuthCard.avatarRadius
                                    backgroundColor: Services.Theme.surfaceVariant
                                    borderColor: pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                    borderWidth: 1.5
                                    fallbackText: {
                                        const u = (Services.OsInfo.username || root.username) || "U"
                                        return u.charAt(0).toUpperCase()
                                    }
                                    fallbackFontFamily: Services.Theme.fontDisplay
                                    fallbackFontSize: 20
                                    fallbackColor: Services.Theme.accent
                                    Behavior on borderColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            // ── 4. Username Tag (Fixed at Y: 136 - 100% IMMUTABLE POSITION) ──────
                            Text {
                                id: usernameText
                                visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowGreeting : false)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 136
                                horizontalAlignment: Text.AlignHCenter
                                text: Services.OsInfo.username.length > 0 ? Services.OsInfo.username : root.username
                                color: Services.Theme.textPrimary
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                font.letterSpacing: 0.3
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // ── 5. Idle Prompt (Fixed at Y: 160 - Fades smoothly without shifting layout) ──
                            Item {
                                id: authPrompt
                                visible: opacity > 0.01
                                opacity: (!centerAuthCard.showPasswordBox && !root.isCompact) ? 0.85 : 0.0
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 160
                                width: promptLabel.implicitWidth + 20
                                height: 20
                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                Text {
                                    id: promptLabel
                                    anchors.centerIn: parent
                                    text: "Touch ID or Enter Password"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.userRevealedInput = true
                                        pwTextInput.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        // ── Minimalist Notification Pill Indicator (Minimal Layout Only) ──
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: centerAuthCard.bottom
                            anchors.topMargin: 18
                            height: 24
                            implicitWidth: minNotifRow.implicitWidth + 16
                            radius: 12
                            color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.6)
                            border.color: Services.Theme.border
                            border.width: 1
                            visible: root.isMinimal && root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: (root.isMinimal && root.notifCount > 0 && root.isRevealed) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 250 } }

                            RowLayout {
                                id: minNotifRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: Services.Icons.bell
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: root.notifCount + (root.notifCount === 1 ? " Notification" : " Notifications")
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Services.Theme.textPrimary
                                }
                            }
                        }

                        // ── Floating Overlapping Notification Cards Overlay (Default & Compact Layouts) ──
                        Item {
                            id: notifStackContainer
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: topClockColumn.bottom
                            anchors.topMargin: 36
                            width: Math.min(mainContainer.width - 50, 320)
                            height: 90
                            z: 100
                            visible: !root.isMinimal && root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: (!root.isMinimal && root.notifCount > 0 && root.isRevealed) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            Repeater {
                                model: Services.Notifications.historyList

                                delegate: NotifModule.PopupCard {
                                    required property var modelData
                                    required property int index

                                    visible: index < 2
                                    notif: modelData

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: notifStackContainer.width

                                    // Overlap Effect (Solid color, older card peeks UPWARDS)
                                    z: 20 - index
                                    y: -index * 8
                                    scale: index === 0 ? 1.0 : 0.96
                                    opacity: 1.0

                                    Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }
                        }

                        // ── 3. Bottom-Left Corner: Sleek Frosted Glass Music Tile (Not a Pill, Marquee Title, Play/Stop/Next) ───────────────
                        Rectangle {
                            id: cornerMediaCard
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 24
                            width: 250
                            height: 56
                            radius: 12
                            color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.82)
                            border.color: Services.Theme.borderHighlight
                            border.width: 1
                            clip: true
                            visible: root.isDefault && root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
                            opacity: (root.isDefault && root.isRevealed && root.hasPlayer) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                // Album Art Thumbnail (38x38, radius 8)
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 8
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1
                                    clip: true

                                    Image {
                                        id: cornerArtImg
                                        anchors.fill: parent
                                        source: root.player?.trackArtUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        visible: status === Image.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.musicNote
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 16
                                        color: Services.Theme.accent
                                        visible: cornerArtImg.status !== Image.Ready
                                    }
                                }

                                // Title (Marquee if long) & Artist
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    Item {
                                        id: marqueeBox
                                        Layout.fillWidth: true
                                        height: 16
                                        clip: true

                                        Text {
                                            id: marqueeTitle
                                            text: root.player?.trackTitle || "No Media"
                                            color: Services.Theme.textPrimary
                                            font.pixelSize: 11
                                            font.weight: Font.Bold

                                            property real overflow: Math.max(0, implicitWidth - marqueeBox.width)

                                            SequentialAnimation on x {
                                                running: marqueeTitle.overflow > 0 && root.isPlaying
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: 1600 }
                                                NumberAnimation {
                                                    from: 0
                                                    to: -marqueeTitle.overflow
                                                    duration: Math.max(2000, marqueeTitle.overflow * 35)
                                                    easing.type: Easing.Linear
                                                }
                                                PauseAnimation { duration: 1600 }
                                                NumberAnimation {
                                                    from: -marqueeTitle.overflow
                                                    to: 0
                                                    duration: 500
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: root.player?.trackArtist || (root.player?.trackAlbum || "Unknown Artist")
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Controls (Prev, Play/Pause, Next)
                                RowLayout {
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter

                                    // Prev
                                    Rectangle {
                                        width: 24; height: 24; radius: 6
                                        color: prevCornerMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaPrev
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Theme.textPrimary
                                        }
                                        MouseArea {
                                            id: prevCornerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.player?.previous()
                                        }
                                    }

                                    // Play / Pause / Stop
                                    Rectangle {
                                        width: 26; height: 26; radius: 6
                                        color: playCornerMouse.containsMouse ? Services.Theme.white : Services.Theme.accent
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaPlayPause(root.isPlaying)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            color: Services.Theme.bgDeep
                                        }
                                        MouseArea {
                                            id: playCornerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.player?.togglePlaying()
                                        }
                                    }

                                    // Next
                                    Rectangle {
                                        width: 24; height: 24; radius: 6
                                        color: nextCornerMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaNext
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Theme.textPrimary
                                        }
                                        MouseArea {
                                            id: nextCornerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.player?.next()
                                        }
                                    }
                                }
                            }
                        }

                        // Mode C: Minimalist Single-Line Media Player (Minimal Layout)
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 24
                            height: 28
                            implicitWidth: minMediaRow.implicitWidth + 16
                            visible: root.isMinimal && root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
                            opacity: (root.isMinimal && root.isRevealed && root.hasPlayer) ? 0.85 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            RowLayout {
                                id: minMediaRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: Services.Icons.musicNote
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: (root.player?.trackTitle || "") + (root.player?.trackArtist ? " — " + root.player.trackArtist : "")
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 240
                                }

                                Text {
                                    text: Services.Icons.mediaPlayPause(root.isPlaying)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.accent

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.player?.togglePlaying()
                                    }
                                }
                            }
                        }

                        // ── 4. Bottom Right: Power Button & Floating Power Menu Panel (Default & Minimal Layouts) ──
                        Item {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 24
                            anchors.bottomMargin: root.isRevealed ? 24 : 0
                            width: root.isMinimal ? 32 : 38
                            height: root.isMinimal ? 32 : 38
                            visible: !root.isCompact && (Services.Config ? Services.Config.lockscreenShowQuickPower : true)
                            opacity: (root.isRevealed && !root.isCompact) ? 1.0 : 0.0
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                            // Floating Power Menu Panel (Opens right above the button)
                            Rectangle {
                                id: pwrMenuPopup
                                anchors.bottom: pwrBtnRound.top
                                anchors.right: parent.right
                                anchors.bottomMargin: 12
                                width: 220
                                implicitHeight: pwrMenuCol.implicitHeight + 20
                                radius: Services.Theme.radiusLg
                                color: Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.95)
                                border.color: Services.Theme.borderHighlight
                                border.width: 1
                                clip: true

                                visible: root.lockscreenPwrOpen
                                opacity: root.lockscreenPwrOpen ? 1.0 : 0.0
                                scale: root.lockscreenPwrOpen ? 1.0 : 0.85
                                transformOrigin: Item.BottomRight
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {}
                                }

                                ColumnLayout {
                                    id: pwrMenuCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    // Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "Power Options"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            width: 20; height: 20; radius: 10
                                            color: pwrCloseMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.close
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 9
                                                color: Services.Theme.textSecondary
                                            }
                                            MouseArea {
                                                id: pwrCloseMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.lockscreenPwrOpen = false
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Services.Theme.border
                                    }

                                    // Sleep Option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: Services.Theme.radiusSm
                                        color: sleepMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.pmSleep
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: sleepMouse.containsMouse ? Services.Theme.accent : Services.Theme.accentDim
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { text: "Sleep"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary }
                                                Text { text: "Suspend session"; font.pixelSize: 8; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        MouseArea {
                                            id: sleepMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lockscreenPwrOpen = false
                                                suspendProc.running = true
                                            }
                                        }
                                    }

                                    // Reboot Option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: Services.Theme.radiusSm
                                        color: rebootMouse.containsMouse ? Qt.rgba(Services.Theme.warning.r, Services.Theme.warning.g, Services.Theme.warning.b, 0.15) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.pmReboot
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: Services.Theme.warning
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { text: "Reboot"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary }
                                                Text { text: "Restart system"; font.pixelSize: 8; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        MouseArea {
                                            id: rebootMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lockscreenPwrOpen = false
                                                rebootProc.running = true
                                            }
                                        }
                                    }

                                    // Shutdown Option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: Services.Theme.radiusSm
                                        color: shutdownMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.pmShutdown
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: Services.Theme.danger
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { text: "Power Off"; font.pixelSize: 11; font.bold: true; color: Services.Theme.danger }
                                                Text { text: "Turn off PC"; font.pixelSize: 8; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        MouseArea {
                                            id: shutdownMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lockscreenPwrOpen = false
                                                shutdownProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Single Circular Power Button
                            Rectangle {
                                id: pwrBtnRound
                                anchors.fill: parent
                                radius: root.isMinimal ? 16 : 19
                                color: root.isMinimal
                                    ? (pwrBtnMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) : "transparent")
                                    : ((root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) 
                                        ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.25)
                                        : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75))
                                border.color: root.isMinimal
                                    ? (pwrBtnMouse.containsMouse ? Services.Theme.danger : "transparent")
                                    : ((root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) ? Services.Theme.danger : Services.Theme.border)
                                border.width: root.isMinimal ? (pwrBtnMouse.containsMouse ? 1 : 0) : 1
                                opacity: root.isMinimal ? (pwrBtnMouse.containsMouse || root.lockscreenPwrOpen ? 1.0 : 0.6) : 1.0
                                scale: pwrBtnMouse.pressed ? 0.92 : 1.0
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.power
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: root.isMinimal ? 13 : 15
                                    color: (root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) ? Services.Theme.danger : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: pwrBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.lockscreenPwrOpen = !root.lockscreenPwrOpen
                                        if (root.lockscreenPwrOpen) root.lockscreenCcOpen = false
                                    }
                                }
                            }
                        }

                    }
                }

                // ── Control Center Overlay Panel on Lockscreen ──
                Item {
                    id: ccLockscreenOverlay
                    anchors.fill: parent
                    z: 9999
                    visible: root.lockscreenCcOpen
                    opacity: root.lockscreenCcOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.lockscreenCcOpen = false
                    }

                    LockscreenControlCenter {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 54
                        anchors.rightMargin: 20
                        onRequestClose: root.lockscreenCcOpen = false
                    }
                }
            }
        }
    }
}
