import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "../../services" as Services
import "../bar/components" as BarComponents

PanelWindow {
    id: root

    property bool isLocked: false
    property bool lockVisible: false
    property string passwordInput: ""
    property bool showPassword: false
    property bool isError: false
    property string errorMessage: ""

    property string timeStr: "00:00"
    property string dateStr: ""
    property string username: "user"
    property string hostname: "host"
    property bool capsLockOn: false

    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null && (player?.trackTitle ?? "").length > 0
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property int notifCount: Services.Notifications.popupList ? Services.Notifications.popupList.count : 0

    function open() {
        Services.OverlayManager.isLocked = true
        Services.OverlayManager.closeAllExcept(root)
        hideTimer.stop()
        passwordInput = ""
        isError = false
        errorMessage = ""
        showPassword = false
        lockVisible = true
        isLocked = true
        updateTime()
        userInfoProc.running = true
        pwTextInput.forceActiveFocus()
    }

    function close() {
        if (isLocked) {
            triggerShake("Password required")
            return
        }
        Services.OverlayManager.isLocked = false
        lockVisible = false
    }

    function lock() { open() }
    function show() { open() }
    function hide() {
        if (!isLocked) {
            Services.OverlayManager.isLocked = false
            lockVisible = false
        }
    }
    function toggle() { if (!isLocked) open() }

    function updateTime() {
        const now = new Date()
        let hours = now.getHours() % 12
        if (hours === 0) hours = 12
        const minutes = String(now.getMinutes()).padStart(2, "0")
        timeStr = hours + ":" + minutes
        dateStr = Qt.formatDateTime(now, "dddd, d MMMM")
    }

    function authenticate() {
        if (passwordInput.trim().length === 0) {
            triggerShake("Enter password")
            return
        }
        unlockSuccess()
    }

    function triggerShake(msg) {
        isError = true
        errorMessage = msg || "Incorrect password"
        shakeAnim.restart()
        passwordInput = ""
        pwTextInput.forceActiveFocus()
    }

    function unlockSuccess() {
        isError = false
        errorMessage = ""
        passwordInput = ""
        isLocked = false
        Services.OverlayManager.isLocked = false
        hideTimer.interval = 350
        hideTimer.restart()
    }

    visible: lockVisible

    Component.onCompleted: {
        Services.OverlayManager.register(root)
        updateTime()
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: Services.OverlayManager.controlCenterVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:lockscreen"
    anchors { top: true; bottom: true; left: true; right: true }

    Timer {
        id: hideTimer
        interval: 350
        onTriggered: root.lockVisible = false
    }

    Timer {
        id: clockTimer
        interval: 1000
        running: root.lockVisible
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

    // Keyboard Handler - Strictly prevents ESC from unlocking
    Item {
        id: keyFocus
        focus: root.lockVisible
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
    }

    // Fullscreen Wallpaper Layer
    Item {
        anchors.fill: parent
        opacity: root.lockVisible && root.isLocked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

        Image {
            id: bgImage
            anchors.fill: parent
            source: "file:///home/yasirfadhil/Pictures/background_zoomed.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            color: Services.Theme.bg
            opacity: 0.4
        }
    }

    // ── Top Header Bar (Center: DynamicIsland, Right: Quick Status & ControlCenter) ──
    Item {
        id: topBarHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48
        z: 100
        opacity: root.lockVisible && root.isLocked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        // Center: Dynamic Island (Collapsed Lock Icon on Lockscreen)
        BarComponents.DynamicIsland {
            id: dynamicIsland
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            allowOnLockscreen: true
            z: 999
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

                // Battery Icon (using Services.Icons) & Percentage
                RowLayout {
                    spacing: 4

                    Text {
                        text: Services.Icons.powerIcon(Services.Power.charging, Math.round((Services.Power.percentage || 0) * 100))
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : Services.Theme.textPrimary))
                    }

                    Text {
                        text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : Services.Theme.textPrimary)
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
            opacity: root.lockVisible && root.isLocked ? 1 : 0
            scale: root.lockVisible && root.isLocked ? 1 : 1.05

            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

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
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: root.lockVisible && root.isLocked ? (parent.height * 0.14) : (parent.height * 0.11)
                spacing: 4
                Behavior on anchors.topMargin { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.dateStr
                    color: Services.Theme.textPrimary
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.5
                    style: Text.Outline
                    styleColor: "#40000000"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.timeStr
                    color: Services.Theme.white
                    font.pixelSize: 96
                    font.weight: Font.Bold
                    font.family: "SF Pro Display, Inter, Sans-Serif"
                    style: Text.Outline
                    styleColor: "#30000000"
                }
            }

            // ── 2. Center Profile Picture & Password Input Pill ─────────────────────
            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.lockVisible && root.isLocked ? (parent.height * 0.25) : (parent.height * 0.22)
                spacing: 16
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

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
                        source: Services.OsInfo.avatarPath.length > 0 ? Services.OsInfo.avatarPath : ("file:///home/" + (root.username || "yasirfadhil") + "/.face")
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
                    styleColor: "#40000000"
                }

                // Translucent Password Input Pill
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 260
                    height: 40
                    radius: 20
                    color: pwTextInput.activeFocus ? "#55000000" : "#35000000"
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
                            font.pixelSize: 14
                            color: Services.Theme.textPrimary
                            selectByMouse: true
                            activeFocusOnPress: true
                            focus: true

                            onTextChanged: {
                                root.passwordInput = text
                                if (root.isError) root.isError = false
                            }

                            onAccepted: root.authenticate()

                            Text {
                                text: "Masukkan kata sandi..."
                                color: Services.Theme.textDisabled
                                font.pixelSize: 13
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
                                font.pixelSize: 11
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

                        // Submit Button
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: submitMouse.containsMouse ? Services.Theme.white : (root.passwordInput.length > 0 ? Services.Theme.accent : Services.Theme.surfaceVariant)
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.arrowRight
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: root.passwordInput.length > 0 ? "#000000" : Services.Theme.textDisabled
                            }

                            MouseArea {
                                id: submitMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.passwordInput.length > 0
                                onClicked: root.authenticate()
                            }
                        }
                    }
                }

                // Error Message Text
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.errorMessage
                    color: Services.Theme.danger
                    font.pixelSize: 11
                    visible: root.isError && text.length > 0
                    style: Text.Outline
                    styleColor: "#40000000"
                }

                // ── Red Area: Small Notification Popups ─────────────────────────────
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    width: Math.min(mainContainer.width - 40, 340)
                    visible: root.notifCount > 0

                    Repeater {
                        model: Services.Notifications.popupList
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            visible: index < 2 // Show up to 2 notification popups in the red area

                            Layout.fillWidth: true
                            height: 36
                            radius: 18
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.border
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: Services.Icons.bell
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: (modelData.appName || "Notifikasi") + ": " + (modelData.summary || "")
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    color: dismissMouse.containsMouse ? Services.Theme.danger : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        font.pixelSize: 9
                                        color: Services.Theme.textSecondary
                                    }

                                    MouseArea {
                                        id: dismissMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Notifications.dismiss(modelData.notifId)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── 3. Small Bottom Section: Music Pill Only ─────────────────────────────
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                height: 34
                implicitWidth: smallBarContent.implicitWidth + 24
                radius: 17
                color: Services.Theme.surfaceVariant
                border.color: Services.Theme.border
                border.width: 1
                visible: root.hasPlayer

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
                            font.pixelSize: 9
                            color: smallPlayMouse.containsMouse ? "#000000" : Services.Theme.textPrimary
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
}
