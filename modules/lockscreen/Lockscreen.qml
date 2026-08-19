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

    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null && (player?.trackTitle ?? "").length > 0
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property int notifCount: Services.Notifications.historyList ? Services.Notifications.historyList.count : 0

    Timer {
        id: revealTimer
        interval: 50
        onTriggered: root.isRevealed = true
    }

    Timer {
        id: unlockTimer
        interval: 220
        onTriggered: {
            Services.OverlayManager.isLocked = false
            sessionLock.locked = false
        }
    }

    function open() {
        Services.OverlayManager.isLocked = true
        Services.OverlayManager.closeAllExcept(root)
        passwordInput = ""
        pendingPassword = ""
        isError = false
        errorMessage = ""
        showPassword = false
        isAuthenticating = false
        isRevealed = false
        updateTime()
        sessionLock.locked = true
        revealTimer.start()
    }

    function close() {
        if (isLocked) {
            triggerShake("Password required!")
            return
        }
        Services.OverlayManager.isLocked = false
        sessionLock.locked = false
    }

    function lock() { open() }
    function show() { open() }
    function hide() {
        if (!isLocked) {
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
        if (pam.active) pam.abort()
        if (typeof shakeAnim !== "undefined" && shakeAnim) shakeAnim.restart()
    }

    function unlockSuccess() {
        isError = false
        errorMessage = ""
        passwordInput = ""
        pendingPassword = ""
        isAuthenticating = false
        isRevealed = false
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
        command: ["sh", "-c", "echo $USER && hostname"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n")
                if (lines.length > 0 && lines[0]) root.username = lines[0]
                if (lines.length > 1 && lines[1]) root.hostname = lines[1]
            }
        }
    }

    // Action processes
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
            Services.OverlayManager.isLocked = sessionLock.locked
            if (!sessionLock.locked) {
                root.passwordInput = ""
                root.pendingPassword = ""
                root.isAuthenticating = false
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
                        root.triggerShake("Password required")
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.authenticate()
                        event.accepted = true
                    } else if (event.key === Qt.Key_CapsLock) {
                        root.capsLockOn = !root.capsLockOn
                        event.accepted = true
                    } else {
                        if (!pwTextInput.activeFocus && event.text.length > 0) {
                            pwTextInput.forceActiveFocus()
                        }
                    }
                }

                // Fullscreen Wallpaper Layer (Gets image from Services.Wallpaper with smooth Zoom-In 1.0 -> 1.14 & Zoom-Out 1.14 -> 1.0)
                Item {
                    anchors.fill: parent

                    Image {
                        id: bgImage
                        anchors.fill: parent
                        source: Services.Wallpaper.currentWallpaper.length > 0 ? ("file://" + Services.Wallpaper.currentWallpaper) : ("file://" + (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/assets/wallpapers/wallbler.jpg")
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: false
                        smooth: true
                        cache: true
                        scale: (Services.Config && !Services.Config.lockscreenWallpaperZoom) ? 1.0 : (root.isRevealed ? 1.20 : 1.0)
                        transformOrigin: Item.Center
                        Behavior on scale { NumberAnimation { duration: 350; easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic } }
                    }

                    // Smooth Dark Dim / Vignette Overlay
                    Rectangle {
                        anchors.fill: parent
                        color: Services.Theme.bgDeep
                        opacity: root.isRevealed ? (Services.Config ? Services.Config.lockscreenDim : 0.45) : 0.0
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
                    opacity: root.isRevealed ? 1.0 : 0.0
                    scale: root.isRevealed ? 1.0 : 0.96
                    Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                    // Center: Dynamic Island (Copied 1:1 System HUD Alert Expand 280x54px & Collapsed Capsule 48x30px from DynamicIsland.qml)
                    Rectangle {
                        id: lockIsland
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Services.Theme.bgDeep
                        border.color: Services.Theme.borderHighlight
                        border.width: 1

                        property bool islandExpanded: false

                        height: islandExpanded ? 54 : 32
                        implicitWidth: islandExpanded ? 280 : 140
                        radius: islandExpanded ? 27 : 16

                        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }
                        Behavior on implicitWidth { NumberAnimation { duration: 350; easing.type: Easing.OutQuad } }
                        Behavior on radius { NumberAnimation { duration: 320; easing.type: Easing.OutQuad } }

                        Timer {
                            id: lockIslandShrinkTimer
                            interval: 2800
                            repeat: false
                            onTriggered: lockIsland.islandExpanded = false
                        }

                        Connections {
                            target: root
                            function onIsRevealedChanged() {
                                if (root.isRevealed) {
                                    lockIsland.islandExpanded = true
                                    lockIslandShrinkTimer.restart()
                                } else {
                                    lockIsland.islandExpanded = false
                                    lockIslandShrinkTimer.stop()
                                }
                            }
                        }

                        // ==================== Collapsed Status Icon (Left Edge in 140x32 Pill - Copied 1:1 from DynamicIsland.qml) ====================
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
                                font.family: Services.Theme.fontMono
                                font.pixelSize: 13
                                color: Services.Theme.accent
                            }
                        }

                        // ==================== Expanded: System HUD Alert (Copied 1:1 from DynamicIsland.qml L1288-L1353) ====================
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10
                            visible: lockIsland.islandExpanded || opacity > 0.01
                            opacity: lockIsland.islandExpanded ? 1 : 0
                            scale: lockIsland.islandExpanded ? 1.0 : 0.15
                            transformOrigin: Item.Center
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
                                    text: "󰌾"
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 15
                                    color: Services.Theme.accent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    text: "Device Locked"
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "Authentication required"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Right Side: Combined Battery & Control Center Pill
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        implicitWidth: combinedCcRow.implicitWidth + 22
                        radius: 15
                        color: ccMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: Services.OverlayManager.controlCenterVisible ? Services.Theme.accent : Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            id: combinedCcRow
                            anchors.centerIn: parent
                            spacing: 8

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
                                color: Services.OverlayManager.controlCenterVisible ? Services.Theme.accent : Services.Theme.textPrimary
                            }
                        }

                        MouseArea {
                            id: ccMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.OverlayManager.controlCenterVisible = !Services.OverlayManager.controlCenterVisible
                            }
                        }
                    }
                }

                // Main Content Backdrop MouseArea
                MouseArea {
                    anchors.fill: parent
                    enabled: !Services.OverlayManager.controlCenterVisible
                    onClicked: pwTextInput.forceActiveFocus()

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

                        // ── 1. Top Clock & Date ─────────────────────────────────────────────────
                        ColumnLayout {
                            id: topClockColumn
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: root.isRevealed 
                                ? (Services.Config && Services.Config.lockscreenClockStyle === "modern" ? (parent.height * 0.08) : (parent.height * 0.13)) 
                                : (parent.height * 0.13 - 35)
                            spacing: 4
                            opacity: root.isRevealed ? 1.0 : 0.0
                            scale: root.isRevealed ? 1.0 : 0.92
                            transformOrigin: Item.Center
                            Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                            readonly property string clockStyle: Services.Config ? Services.Config.lockscreenClockStyle : "hero"

                            // Date Line (for hero & modern)
                            Text {
                                visible: topClockColumn.clockStyle !== "compact"
                                Layout.alignment: Qt.AlignHCenter
                                text: root.dateStr
                                color: Services.Theme.textPrimary
                                font.pixelSize: Services.Theme.fontSize5xl
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.5
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 1: Hero Clock (Single horizontal huge display)
                            Text {
                                visible: topClockColumn.clockStyle === "hero"
                                Layout.alignment: Qt.AlignHCenter
                                text: root.timeStr
                                color: Services.Theme.white
                                font.pixelSize: Services.Theme.fontSizeHero
                                font.weight: Font.Bold
                                font.family: Services.Theme.fontDisplay
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 2: Modern Stacked Clock (Large Hour above Minute)
                            ColumnLayout {
                                visible: topClockColumn.clockStyle === "modern"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: -20

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.hourStr
                                    color: Services.Theme.accent
                                    font.pixelSize: 84
                                    font.weight: Font.Bold
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.minStr
                                    color: Services.Theme.white
                                    font.pixelSize: 84
                                    font.weight: Font.Bold
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Style 3: Compact Pill Clock
                            Rectangle {
                                visible: topClockColumn.clockStyle === "compact"
                                Layout.alignment: Qt.AlignHCenter
                                height: 44
                                implicitWidth: compactRow.implicitWidth + 28
                                radius: 22
                                color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.65)
                                border.color: Services.Theme.borderHighlight
                                border.width: 1

                                RowLayout {
                                    id: compactRow
                                    anchors.centerIn: parent
                                    spacing: 12

                                    Text {
                                        text: root.timeStr
                                        color: Services.Theme.accent
                                        font.pixelSize: Services.Theme.fontSize3xl
                                        font.bold: true
                                        font.family: Services.Theme.fontDisplay
                                    }
                                    Rectangle { width: 1; height: 16; color: Services.Theme.border }
                                    Text {
                                        text: root.dateStr
                                        color: Services.Theme.textPrimary
                                        font.pixelSize: Services.Theme.fontSizeMd
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            // Ambient Greeting / Weather Subtitle
                            RowLayout {
                                visible: Services.Config ? Services.Config.lockscreenShowWeather : true
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

                        // ── 2. Center Profile Picture & Password Input Pill ─────────────────────
                        ColumnLayout {
                            id: centerAuthColumn
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.isRevealed ? (parent.height * 0.29) : (parent.height * 0.29 - 45)
                            spacing: 16
                            opacity: root.isRevealed ? 1.0 : 0.0
                            scale: root.isRevealed ? 1.0 : 0.88
                            transformOrigin: Item.Center
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                            // Rounded User Picture Avatar (Using .face image with MultiEffect mask)
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 84; height: 84; radius: 22
                                color: Services.Theme.surfaceVariant
                                border.color: pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.borderHighlight
                                border.width: 2
                                antialiasing: true
                                smooth: true
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Image {
                                    id: userAvatarImg
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: Services.OsInfo.avatarPath.length > 0 ? Services.OsInfo.avatarPath : ("file://" + (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.face")
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    antialiasing: true
                                    visible: false
                                }

                                MultiEffect {
                                    anchors.fill: userAvatarImg
                                    source: userAvatarImg
                                    maskEnabled: true
                                    maskSource: avatarMask
                                    visible: userAvatarImg.status === Image.Ready
                                }

                                Item {
                                    id: avatarMask
                                    anchors.fill: userAvatarImg
                                    visible: false
                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.samples: 8
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 20
                                        color: "black"
                                        antialiasing: true
                                        smooth: true
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.user
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 34
                                    color: Services.Theme.textPrimary
                                    visible: userAvatarImg.status !== Image.Ready
                                }
                            }

                            // Username Label
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: Services.OsInfo.username.length > 0 ? Services.OsInfo.username : root.username
                                color: Services.Theme.textPrimary
                                font.pixelSize: 17
                                font.weight: Font.Bold
                                font.letterSpacing: 0.3
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Translucent Password Input Pill
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 260
                                height: 40
                                radius: 20
                                color: pwTextInput.activeFocus ? Services.Theme.surfaceVariant : Services.Theme.surface
                                border.color: root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border)
                                border.width: 1.5
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    TextInput {
                                        id: pwTextInput
                                        Layout.fillWidth: true
                                        text: root.passwordInput
                                        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                        font.pixelSize: Services.Theme.fontSize2xl
                                        color: Services.Theme.textPrimary
                                        selectByMouse: true
                                        activeFocusOnPress: true
                                        focus: true
                                        enabled: !root.isAuthenticating

                                        onTextChanged: {
                                            root.passwordInput = text
                                            if (text.length > 0 && root.isError) root.isError = false
                                        }

                                        onAccepted: root.authenticate()

                                        Text {
                                            text: root.isAuthenticating ? "Authenticating..." : "Enter password..."
                                            color: Services.Theme.textDisabled
                                            font.pixelSize: Services.Theme.fontSizeXl
                                            visible: pwTextInput.text.length === 0 && !pwTextInput.activeFocus
                                        }
                                    }

                                    // Eye Password Visibility Toggle
                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: eyeMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.showPassword ? Services.Icons.eyeOpen : Services.Icons.eyeClosed
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            color: Services.Theme.textSecondary
                                        }

                                        MouseArea {
                                            id: eyeMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.showPassword = !root.showPassword
                                        }
                                    }

                                    // Submit Button / Loading Indicator
                                    Rectangle {
                                        width: 28; height: 28; radius: 14
                                        color: submitMouse.containsMouse ? Services.Theme.white : (root.passwordInput.length > 0 ? Services.Theme.accent : Services.Theme.surfaceVariant)
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.isAuthenticating ? Services.Icons.spinner : Services.Icons.arrowRight
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            color: root.passwordInput.length > 0 ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                        }

                                        MouseArea {
                                            id: submitMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: root.passwordInput.length > 0 && !root.isAuthenticating
                                            onClicked: root.authenticate()
                                        }
                                    }
                                }
                            }



                            // Caps Lock Warning Pill
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6
                                visible: root.capsLockOn && !root.isError

                                Text {
                                    text: "󰌎"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 13
                                    color: Services.Theme.warning
                                }

                                Text {
                                    text: "Caps Lock is ON"
                                    color: Services.Theme.warning
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Error Warning Message Pill
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6
                                visible: root.isError && root.errorMessage.length > 0

                                Text {
                                    text: "󰅙"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 14
                                    color: Services.Theme.danger
                                }

                                Text {
                                    text: root.errorMessage
                                    color: Services.Theme.danger
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }
                        }

                        // ── Floating Overlapping Notification Cards Overlay (Below input, persistent history) ──
                        Item {
                            id: notifStackContainer
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: centerAuthColumn.bottom
                            anchors.topMargin: 24
                            width: Math.min(mainContainer.width - 50, 305)
                            height: 90
                            z: 100
                            visible: root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: root.isRevealed ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            Repeater {
                                model: Services.Notifications.historyList

                                delegate: NotifModule.Popup {
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

                        // ── 3. Small Bottom Section: Music Pill Only ─────────────────────────────
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.isRevealed ? 24 : 0
                            height: 34
                            implicitWidth: smallBarContent.implicitWidth + 24
                            radius: 17
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1
                            visible: root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
                            opacity: root.isRevealed ? 1.0 : 0.0
                            scale: root.isRevealed ? 1.0 : 0.9
                            transformOrigin: Item.Center
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

                            RowLayout {
                                id: smallBarContent
                                anchors.centerIn: parent
                                spacing: 6

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
                                    Layout.maximumWidth: 160
                                }

                                // Small Play/Pause Button
                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: smallPlayMouse.containsMouse ? Services.Theme.accent : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.mediaPlayPause(root.isPlaying)
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: Services.Theme.fontSizeXs
                                        color: smallPlayMouse.containsMouse ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                    }

                                    MouseArea {
                                        id: smallPlayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.player?.togglePlaying()
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
                    visible: Services.OverlayManager.controlCenterVisible
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Services.OverlayManager.controlCenterVisible = false
                    }

                    LockscreenControlCenter {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 54
                        anchors.rightMargin: 16
                    }
                }
            }
        }
    }
}
