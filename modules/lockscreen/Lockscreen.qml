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
        lockscreenCcOpen = false
        lockscreenPwrOpen = false
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

                    // Right Side: Combined Quick Status & Control Center Pill
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
                        visible: Services.Config ? Services.Config.lockscreenShowStatusPill : true
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            id: combinedCcRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Wi-Fi Status Icon (if enabled)
                            Text {
                                visible: Services.Wifi && Services.Wifi.enabled
                                text: Services.Icons.wifi
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: (Services.Wifi && Services.Wifi.connected) ? Services.Theme.accent : Services.Theme.textDisabled
                            }

                            // Bluetooth Status Icon (if enabled)
                            Text {
                                visible: Services.Bluetooth && Services.Bluetooth.enabled
                                text: Services.Icons.bluetooth
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: (Services.Bluetooth && Services.Bluetooth.devices.some(d => d.connected)) ? Services.Theme.accent : Services.Theme.textDisabled
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
                }

                // Main Content Backdrop MouseArea
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.lockscreenCcOpen
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
                                ? (Services.Config && (Services.Config.lockscreenClockStyle === "modern" || Services.Config.lockscreenClockStyle === "vertical") ? (parent.height * 0.07) : (parent.height * 0.12)) 
                                : (parent.height * 0.12 - 35)
                            spacing: 4
                            opacity: root.isRevealed ? 1.0 : 0.0
                            scale: root.isRevealed ? 1.0 : 0.92
                            transformOrigin: Item.Center
                            Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                            readonly property string clockStyle: Services.Config ? Services.Config.lockscreenClockStyle : "hero"

                            // Date Line (for hero, modern, minimal)
                            Text {
                                visible: topClockColumn.clockStyle !== "compact" && topClockColumn.clockStyle !== "vertical" && topClockColumn.clockStyle !== "typographic" && topClockColumn.clockStyle !== "radial" && topClockColumn.clockStyle !== "cyber"
                                Layout.alignment: Qt.AlignHCenter
                                text: topClockColumn.clockStyle === "minimal" ? root.dateStr.toUpperCase() : root.dateStr
                                color: topClockColumn.clockStyle === "minimal" ? Services.Theme.accent : Services.Theme.textPrimary
                                font.pixelSize: topClockColumn.clockStyle === "minimal" ? Services.Theme.fontSizeSm : Services.Theme.fontSize5xl
                                font.weight: topClockColumn.clockStyle === "minimal" ? Font.Bold : Font.DemiBold
                                font.letterSpacing: topClockColumn.clockStyle === "minimal" ? 2.5 : 0.5
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

                            // Style 4: Minimalist Clock (Clean ultra-light display)
                            Text {
                                visible: topClockColumn.clockStyle === "minimal"
                                Layout.alignment: Qt.AlignHCenter
                                text: root.timeStr
                                color: Services.Theme.white
                                font.pixelSize: 88
                                font.weight: Font.ExtraLight
                                font.letterSpacing: 2
                                font.family: Services.Theme.fontDisplay
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 5: Vertical Aesthetic Clock
                            RowLayout {
                                visible: topClockColumn.clockStyle === "vertical"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 18

                                ColumnLayout {
                                    spacing: -14
                                    Text {
                                        text: root.hourStr
                                        color: Services.Theme.accent
                                        font.pixelSize: 64
                                        font.weight: Font.Bold
                                        font.family: Services.Theme.fontDisplay
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                    Text {
                                        text: root.minStr
                                        color: Services.Theme.white
                                        font.pixelSize: 64
                                        font.weight: Font.Bold
                                        font.family: Services.Theme.fontDisplay
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                }

                                Rectangle {
                                    width: 2
                                    height: 80
                                    color: Services.Theme.accent
                                    radius: 1
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Text {
                                        text: Qt.formatDateTime(new Date(), "dddd")
                                        color: Services.Theme.accent
                                        font.pixelSize: Services.Theme.fontSizeLg
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
                                spacing: 3

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.hourWords
                                    color: Services.Theme.accent
                                    font.pixelSize: 44
                                    font.weight: Font.Black
                                    font.letterSpacing: 2.5
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.minWords
                                    color: Services.Theme.white
                                    font.pixelSize: 44
                                    font.weight: Font.Black
                                    font.letterSpacing: 2.5
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
                                width: 146; height: 146; radius: 73
                                color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.55)
                                border.color: Services.Theme.accent
                                border.width: 2.5

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    radius: 67
                                    color: "transparent"
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)
                                    border.width: 1.5
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.timeStr
                                        color: Services.Theme.white
                                        font.pixelSize: 34
                                        font.weight: Font.Bold
                                        font.family: Services.Theme.fontDisplay
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Qt.formatDateTime(new Date(), "ddd, MMM d")
                                        color: Services.Theme.accent
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.5
                                    }
                                }
                            }

                            // Style 8: Cyberpunk / Terminal Monospace HUD
                            Rectangle {
                                visible: topClockColumn.clockStyle === "cyber"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: cyberCol.implicitWidth + 36
                                implicitHeight: cyberCol.implicitHeight + 22
                                radius: 8
                                color: Qt.rgba(0, 0, 0, 0.7)
                                border.color: Services.Theme.accent
                                border.width: 1.5

                                ColumnLayout {
                                    id: cyberCol
                                    anchors.centerIn: parent
                                    spacing: 4

                                    RowLayout {
                                        spacing: 12
                                        Text {
                                            text: "┌[ SYS: LOCKED ]"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 10
                                            color: Services.Theme.accent
                                            font.bold: true
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "[ " + (Services.OsInfo.username || root.username) + "@" + (Services.OsInfo.hostname || root.hostname) + " ]┐"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 10
                                            color: Services.Theme.textSecondary
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.timeStr + ":" + String(new Date().getSeconds()).padStart(2, "0")
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: 42
                                        font.bold: true
                                        color: Services.Theme.white
                                    }

                                    RowLayout {
                                        spacing: 12
                                        Text {
                                            text: "└[ DATE: " + Qt.formatDateTime(new Date(), "yyyy.MM.dd") + " ]"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 10
                                            color: Services.Theme.textSecondary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "[ BAT: " + Math.round((Services.Power.percentage || 0.9) * 100) + "% ]┘"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 10
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

                        // ── 2. Center Profile Picture & Password Input Pill ─────────────────────
                        // ── 2. Center Profile Picture & Password Input System ───────────────────
                        ColumnLayout {
                            id: centerAuthColumn
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.isRevealed ? (parent.height * 0.28) : (parent.height * 0.28 - 45)
                            spacing: 14
                            opacity: root.isRevealed ? 1.0 : 0.0
                            scale: root.isRevealed ? 1.0 : 0.88
                            transformOrigin: Item.Center
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                            readonly property string avatarShape: Services.Config ? Services.Config.lockscreenAvatarShape : "circle"
                            readonly property bool showAvatarRing: Services.Config ? Services.Config.lockscreenAvatarRing : true
                            readonly property string inputStyle: Services.Config ? Services.Config.lockscreenInputStyle : "pill"

                            readonly property int avatarRadius: {
                                if (avatarShape === "circle") return 46
                                if (avatarShape === "squircle") return 28
                                return 16
                            }
                            readonly property int ringRadius: {
                                if (avatarShape === "circle") return 53
                                if (avatarShape === "squircle") return 33
                                return 20
                            }

                            // ── User Avatar with Shape Options, Monogram Fallback & Glow Ring ──
                            Item {
                                visible: Services.Config ? Services.Config.lockscreenShowAvatar : true
                                Layout.alignment: Qt.AlignHCenter
                                width: 106; height: 106

                                // Outer Glow / Focus Ring
                                Rectangle {
                                    id: outerGlowRing
                                    anchors.centerIn: parent
                                    width: 104; height: 104
                                    radius: centerAuthColumn.ringRadius
                                    color: "transparent"
                                    visible: centerAuthColumn.showAvatarRing
                                    border.color: root.isError 
                                        ? Services.Theme.danger 
                                        : (pwTextInput.activeFocus 
                                            ? Services.Theme.accent 
                                            : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3))
                                    border.width: pwTextInput.activeFocus ? 2 : 1.5
                                    scale: pwTextInput.activeFocus ? 1.0 : 0.98

                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    // Subtle focus breath animation
                                    SequentialAnimation on opacity {
                                        running: pwTextInput.activeFocus || root.isAuthenticating
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 0.5; duration: 1200; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.5; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                                    }
                                }

                                // Main Avatar Container
                                Rectangle {
                                    id: avatarBox
                                    anchors.centerIn: parent
                                    width: 92; height: 92
                                    radius: centerAuthColumn.avatarRadius
                                    color: Services.Theme.surfaceVariant
                                    border.color: pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                    border.width: 1.5
                                    antialiasing: true
                                    smooth: true
                                    clip: true
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    // Monogram Fallback (Bold Initial Letter with Tinted Backdrop)
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                        visible: userAvatarImg.status !== Image.Ready

                                        Text {
                                            anchors.centerIn: parent
                                            text: {
                                                const u = (Services.OsInfo.username || root.username) || "U"
                                                return u.charAt(0).toUpperCase()
                                            }
                                            font.family: Services.Theme.fontDisplay
                                            font.pixelSize: 36
                                            font.weight: Font.Bold
                                            color: Services.Theme.accent
                                        }
                                    }

                                    // User Avatar Image
                                    Image {
                                        id: userAvatarImg
                                        anchors.fill: parent
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
                                            radius: centerAuthColumn.avatarRadius
                                            color: "black"
                                            antialiasing: true
                                            smooth: true
                                        }
                                    }
                                }
                            }

                            // ── User Identity & Host Tag ──────────────────────────────
                            ColumnLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Services.OsInfo.username.length > 0 ? Services.OsInfo.username : root.username
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.3
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }

                                RowLayout {
                                    visible: Services.Config ? Services.Config.lockscreenShowGreeting : true
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 4
                                    opacity: 0.85

                                    Text {
                                        text: root.greetingStr + " • " + (Services.OsInfo.hostname || root.hostname)
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                }
                            }

                            // ── Password Input System (Pill / Underline / Box / Dots) ─
                            Rectangle {
                                id: inputContainer
                                Layout.alignment: Qt.AlignHCenter
                                width: (centerAuthColumn.inputStyle === "underline") ? 250 : 270
                                height: (centerAuthColumn.inputStyle === "box") ? 44 : 40
                                radius: {
                                    if (centerAuthColumn.inputStyle === "pill") return 20
                                    if (centerAuthColumn.inputStyle === "box") return 8
                                    return 0
                                }
                                color: {
                                    if (centerAuthColumn.inputStyle === "underline" || centerAuthColumn.inputStyle === "dots") return "transparent"
                                    if (centerAuthColumn.inputStyle === "box") return Services.Theme.bgElevated
                                    return pwTextInput.activeFocus 
                                        ? Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.85) 
                                        : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.65)
                                }
                                border.color: (centerAuthColumn.inputStyle === "underline" || centerAuthColumn.inputStyle === "dots")
                                    ? "transparent"
                                    : (root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border))
                                border.width: (centerAuthColumn.inputStyle === "underline" || centerAuthColumn.inputStyle === "dots") ? 0 : 1.5

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                // Underline bar for "underline" style
                                Rectangle {
                                    visible: centerAuthColumn.inputStyle === "underline"
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: pwTextInput.activeFocus ? 2 : 1
                                    color: root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on height { NumberAnimation { duration: 120 } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: (centerAuthColumn.inputStyle === "underline") ? 6 : 12
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    // Lock Icon Prefix
                                    Text {
                                        text: Services.Icons.lock
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 11
                                        color: pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                                        visible: centerAuthColumn.inputStyle !== "dots"
                                    }

                                    // Real Text Input
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        // Standard Text Input (Pill, Box, Underline)
                                        TextInput {
                                            id: pwTextInput
                                            anchors.fill: parent
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: root.passwordInput
                                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                            font.pixelSize: Services.Theme.fontSizeXl
                                            color: Services.Theme.textPrimary
                                            selectByMouse: true
                                            activeFocusOnPress: true
                                            focus: true
                                            enabled: !root.isAuthenticating
                                            visible: centerAuthColumn.inputStyle !== "dots"

                                            onTextChanged: {
                                                root.passwordInput = text
                                                if (text.length > 0 && root.isError) root.isError = false
                                            }

                                            onAccepted: root.authenticate()

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root.isAuthenticating ? "Authenticating..." : "Password..."
                                                color: Services.Theme.textDisabled
                                                font.pixelSize: Services.Theme.fontSizeMd
                                                visible: pwTextInput.text.length === 0 && !pwTextInput.activeFocus
                                            }
                                        }

                                        // Discrete Dot Slots Layout for "dots" style
                                        RowLayout {
                                            visible: centerAuthColumn.inputStyle === "dots"
                                            anchors.centerIn: parent
                                            spacing: 8

                                            Repeater {
                                                model: 6
                                                delegate: Rectangle {
                                                    required property int index
                                                    width: 12; height: 12; radius: 6
                                                    readonly property bool isFilled: root.passwordInput.length > index
                                                    color: isFilled ? Services.Theme.accent : "transparent"
                                                    border.color: root.isError ? Services.Theme.danger : (isFilled ? Services.Theme.accent : Services.Theme.border)
                                                    border.width: 1.5
                                                    scale: isFilled ? 1.2 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }
                                            }
                                        }
                                    }

                                    // Eye Password Visibility Toggle
                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: eyeMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        visible: centerAuthColumn.inputStyle !== "dots"

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.showPassword ? Services.Icons.eyeOpen : Services.Icons.eyeClosed
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            color: root.showPassword ? Services.Theme.accent : Services.Theme.textSecondary
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
                                        color: submitMouse.containsMouse 
                                            ? Services.Theme.textPrimary 
                                            : (root.passwordInput.length > 0 ? Services.Theme.accent : Qt.rgba(1, 1, 1, 0.08))
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.isAuthenticating ? (Services.Icons.refresh || "󰑐") : (Services.Icons.arrowRight || "→")
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
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
                                    text: Services.Icons.lock
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
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
                                    text: Services.Icons.close
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

                        // ── 3. Bottom Section: Music Pill or Full Interactive Card ───────────────
                        // Mode A: Minimalist Pill
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
                            visible: root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true) && ((Services.Config ? Services.Config.lockscreenMediaStyle : "pill") === "pill")
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

                        // Mode B: Full Interactive Media Card
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: root.isRevealed ? 24 : 0
                            width: 320
                            implicitHeight: mediaCardCol.implicitHeight + 20
                            radius: Services.Theme.radiusLg
                            color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75)
                            border.color: Services.Theme.borderHighlight
                            border.width: 1
                            visible: root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true) && ((Services.Config ? Services.Config.lockscreenMediaStyle : "pill") === "card")
                            opacity: root.isRevealed ? 1.0 : 0.0
                            scale: root.isRevealed ? 1.0 : 0.92
                            transformOrigin: Item.Center
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

                            ColumnLayout {
                                id: mediaCardCol
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Album Art Thumbnail with Mask
                                    Rectangle {
                                        width: 44; height: 44; radius: 10
                                        color: Services.Theme.surfaceVariant
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        Image {
                                            id: lockArtImg
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            source: root.player?.trackArtUrl ?? ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            visible: false
                                        }

                                        MultiEffect {
                                            anchors.fill: lockArtImg
                                            source: lockArtImg
                                            maskEnabled: true
                                            maskSource: lockArtMask
                                            visible: lockArtImg.status === Image.Ready
                                        }

                                        Item {
                                            id: lockArtMask
                                            anchors.fill: lockArtImg
                                            visible: false
                                            layer.enabled: true
                                            Rectangle { anchors.fill: parent; radius: 9; color: "black" }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.musicNote
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 18
                                            color: Services.Theme.accent
                                            visible: lockArtImg.status !== Image.Ready
                                        }
                                    }

                                    // Title & Artist
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: root.player?.trackTitle || "No title"
                                            color: Services.Theme.textPrimary
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.bold: true
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: root.player?.trackArtist || (root.player?.trackAlbum || "Unknown Artist")
                                            color: Services.Theme.textSecondary
                                            font.pixelSize: Services.Theme.fontSizeXs
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    // Media Controls (Prev, Play/Pause, Next)
                                    RowLayout {
                                        spacing: 4

                                        Rectangle {
                                            width: 28; height: 28; radius: 14
                                            color: lsPrevMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.mediaPrev
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 12
                                                color: Services.Theme.textPrimary
                                            }
                                            MouseArea {
                                                id: lsPrevMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.player?.previous()
                                            }
                                        }

                                        Rectangle {
                                            width: 32; height: 32; radius: 16
                                            color: lsPlayMouse.containsMouse ? Services.Theme.white : Services.Theme.accent
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.mediaPlayPause(root.isPlaying)
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: Services.Theme.bgDeep
                                            }
                                            MouseArea {
                                                id: lsPlayMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.player?.togglePlaying()
                                            }
                                        }

                                        Rectangle {
                                            width: 28; height: 28; radius: 14
                                            color: lsNextMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.mediaNext
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 12
                                                color: Services.Theme.textPrimary
                                            }
                                            MouseArea {
                                                id: lsNextMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.player?.next()
                                            }
                                        }
                                    }
                                }

                                // Playback Progress Bar (if length > 0)
                                Rectangle {
                                    visible: (root.player?.length ?? 0) > 0
                                    Layout.fillWidth: true
                                    height: 4
                                    radius: 2
                                    color: Services.Theme.bgHover

                                    Rectangle {
                                        height: parent.height
                                        radius: 2
                                        color: Services.Theme.accent
                                        width: Math.max(4, Math.min(parent.width, ((root.player?.position ?? 0) / Math.max(1, root.player?.length ?? 1)) * parent.width))
                                    }
                                }
                            }
                        }

                        // ── 4. Bottom Right: Power Button & Floating Power Menu Panel ──
                        Item {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 24
                            anchors.bottomMargin: root.isRevealed ? 24 : 0
                            width: 38
                            height: 38
                            visible: Services.Config ? Services.Config.lockscreenShowQuickPower : true
                            opacity: root.isRevealed ? 1.0 : 0.0
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
                                        Behavior on color { ColorAnimation { duration: 120 } }

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
                                        Behavior on color { ColorAnimation { duration: 120 } }

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
                                        Behavior on color { ColorAnimation { duration: 120 } }

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
                                radius: 19
                                color: (root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) 
                                       ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.25)
                                       : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75)
                                border.color: (root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) ? Services.Theme.danger : Services.Theme.border
                                border.width: 1
                                scale: pwrBtnMouse.pressed ? 0.92 : 1.0
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.power
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: (root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) ? Services.Theme.danger : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 150 } }
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
