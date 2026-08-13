import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root

    property bool menuVisible: false
    property bool isOpen: false
    property int selectedIndex: 0
    property int pendingActionIndex: -1
    property int countdownSeconds: 5

    property string username: ""
    property string hostname: ""
    property string uptimeStr: ""

    readonly property var actions: [
        { label: "Lock",      sublabel: "Lock screen",    icon: "\u{f033e}", proc: lockProc,     key: "1", danger: false, instant: true },
        { label: "Logout",    sublabel: "Exit session",   icon: "\u{f0343}", proc: logoutProc,   key: "2", danger: false, instant: false },
        { label: "Sleep",     sublabel: "Suspend system", icon: "\u{f04b2}", proc: sleepProc,    key: "3", danger: false, instant: true },
        { label: "Reboot",    sublabel: "Restart PC",     icon: "\u{f0709}", proc: rebootProc,   key: "4", danger: true,  instant: false },
        { label: "Power Off", sublabel: "Turn off PC",    icon: "\u{f0425}", proc: shutdownProc, key: "5", danger: true,  instant: false }
    ]

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        hideTimer.stop()
        countdownTimer.stop()
        pendingActionIndex = -1
        selectedIndex = 0
        menuVisible = true
        isOpen = true
        userInfoProc.running = true
        uptimeProc.running = true
        keyFocus.forceActiveFocus()
    }

    function close() {
        if (!isOpen && !menuVisible) return
        countdownTimer.stop()
        pendingActionIndex = -1
        isOpen = false
        hideTimer.restart()
    }

    function hide() { close() }
    function show() { open() }

    function triggerAction(index) {
        if (index < 0 || index >= actions.length) return
        const act = actions[index]
        if (act.instant) {
            act.proc.running = true
            close()
        } else {
            pendingActionIndex = index
            countdownSeconds = 5
            countdownTimer.restart()
        }
    }

    function confirmPendingAction() {
        if (pendingActionIndex >= 0 && pendingActionIndex < actions.length) {
            actions[pendingActionIndex].proc.running = true
        }
        close()
    }

    function cancelPendingAction() {
        countdownTimer.stop()
        pendingActionIndex = -1
    }

    visible: menuVisible

    Component.onCompleted: {
        Services.OverlayManager.register(root)
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:hud"
    anchors { top: true; bottom: true; left: true; right: true }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: root.menuVisible = false
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (root.countdownSeconds > 1) {
                root.countdownSeconds -= 1
            } else {
                countdownTimer.stop()
                root.confirmPendingAction()
            }
        }
    }

    // Keyboard handler
    Item {
        id: keyFocus
        focus: root.menuVisible
        Keys.onPressed: (event) => {
            if (root.pendingActionIndex >= 0) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    root.confirmPendingAction()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    root.cancelPendingAction()
                    event.accepted = true
                }
                return
            }

            if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
                event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                root.selectedIndex = Math.min(root.selectedIndex + 1, root.actions.length - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.triggerAction(root.selectedIndex)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                root.selectedIndex = event.key - Qt.Key_1
                root.triggerAction(root.selectedIndex)
                event.accepted = true
            }
        }
    }

    // Fullscreen Backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.pendingActionIndex >= 0) {
                root.cancelPendingAction()
            } else {
                root.close()
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            opacity: root.isOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        // Dialog Card
        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.isOpen ? 0 : 20
            width: 620
            implicitHeight: cardContent.implicitHeight + 36

            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: root.pendingActionIndex >= 0 && root.actions[root.pendingActionIndex].danger ? Services.Theme.danger : Services.Theme.border
            border.width: 1

            opacity: root.isOpen ? 1 : 0
            scale: root.isOpen ? 1 : 0.94

            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 200 } }

            // Block click propagation to backdrop
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                id: cardContent
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 18
                spacing: 16

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Distro / Avatar Icon
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Services.OsInfo.logoGlyph
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 20
                            color: Services.Theme.accent
                        }
                    }

                    // User & System Info
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Text {
                            text: root.username !== "" ? "Goodbye, " + root.username : "Power Options"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Services.Theme.textPrimary
                        }

                        RowLayout {
                            spacing: 6
                            Text {
                                text: (root.username !== "" && root.hostname !== "") ? (root.username + "@" + root.hostname) : "System Controls"
                                font.pixelSize: 11
                                color: Services.Theme.textSecondary
                            }
                            Text {
                                visible: root.uptimeStr !== ""
                                text: "•"
                                font.pixelSize: 11
                                color: Services.Theme.textDisabled
                            }
                            Text {
                                visible: root.uptimeStr !== ""
                                text: "up " + root.uptimeStr
                                font.pixelSize: 11
                                color: Services.Theme.textSecondary
                            }
                            Text {
                                visible: Services.Power.ready && !isNaN(Services.Power.percentage) && Services.Power.percentage > 0
                                text: "•"
                                font.pixelSize: 11
                                color: Services.Theme.textDisabled
                            }
                            Text {
                                visible: Services.Power.ready && !isNaN(Services.Power.percentage) && Services.Power.percentage > 0
                                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100) + " " + Math.round(Services.Power.percentage * 100) + "%"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 11
                                color: Services.Power.isLow ? "#ff4444" : Services.Theme.textSecondary
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 30; height: 30; radius: 15
                        color: escMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover
                        border.color: Services.Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\u{f05ad}"
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 14
                            color: Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: escMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.pendingActionIndex >= 0) root.cancelPendingAction()
                                else root.close()
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                }

                // Normal Mode: Action Cards Grid
                RowLayout {
                    visible: root.pendingActionIndex === -1
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: root.actions
                        PowerCard {
                            Layout.fillWidth: true
                            cardLabel: modelData.label
                            cardSublabel: modelData.sublabel
                            cardIcon: modelData.icon
                            cardKey: modelData.key
                            isDangerAction: modelData.danger
                            cardIndex: index

                            onClicked: {
                                root.selectedIndex = index
                                root.triggerAction(index)
                            }
                        }
                    }
                }

                // Confirmation / Countdown Mode
                ColumnLayout {
                    visible: root.pendingActionIndex >= 0
                    Layout.fillWidth: true
                    spacing: 14

                    RowLayout {
                        spacing: 12
                        Layout.alignment: Qt.AlignHCenter

                        Rectangle {
                            width: 44; height: 44; radius: 22
                            color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? "#2a1515" : Services.Theme.surfaceVariant
                            border.color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? Services.Theme.danger : Services.Theme.accent
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].icon
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 22
                                color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? Services.Theme.danger : Services.Theme.accent
                            }
                        }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].label + " System?"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                text: "Executing automatically in " + root.countdownSeconds + " second" + (root.countdownSeconds > 1 ? "s..." : "...")
                                font.pixelSize: 12
                                color: Services.Theme.textSecondary
                            }
                        }
                    }

                    // Progress Bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: Services.Theme.border
                        clip: true

                        Rectangle {
                            height: parent.height
                            width: parent.width * (root.countdownSeconds / 5.0)
                            radius: 2
                            color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? Services.Theme.danger : Services.Theme.accent
                            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        }
                    }

                    // Button Row
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        // Confirm Button
                        Rectangle {
                            implicitWidth: 160
                            height: 38
                            radius: Services.Theme.radiusMd
                            color: confirmMouse.containsMouse ? (root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? "#9e4848" : "#e0e0e0") : (root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? Services.Theme.danger : Services.Theme.accent)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    text: "Confirm Now"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? "#ffffff" : "#111111"
                                }
                                Rectangle {
                                    width: 44; height: 18; radius: 4
                                    color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? "#5e2424" : "#b0b0b0"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "↵ Enter"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: root.actions[root.pendingActionIndex >= 0 ? root.pendingActionIndex : 0].danger ? "#ffffff" : "#111111"
                                    }
                                }
                            }

                            MouseArea {
                                id: confirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmPendingAction()
                            }
                        }

                        // Cancel Button
                        Rectangle {
                            implicitWidth: 140
                            height: 38
                            radius: Services.Theme.radiusMd
                            color: cancelMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover
                            border.color: Services.Theme.border
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    text: "Cancel"
                                    font.pixelSize: 13
                                    color: Services.Theme.textPrimary
                                }
                                Rectangle {
                                    width: 34; height: 18; radius: 4
                                    color: Services.Theme.surfaceVariant
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Esc"
                                        font.pixelSize: 9
                                        color: Services.Theme.textSecondary
                                    }
                                }
                            }

                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelPendingAction()
                            }
                        }
                    }
                }
            }
        }
    }

    // Action Processes
    Process { id: lockProc; command: ["sh", "-c", "qs ipc call lockscreen lock || hyprlock || swaylock"] }
    Process { id: logoutProc; command: ["sh", "-c", "hyprctl dispatch 'hl.dsp.exit()' || loginctl terminate-user $USER"] }
    Process { id: sleepProc; command: ["systemctl", "suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["systemctl", "poweroff"] }

    Process {
        id: userInfoProc
        command: ["sh", "-c", "echo $(whoami)@$(hostname)"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("@")
                if (parts.length >= 1) root.username = parts[0]
                if (parts.length >= 2) root.hostname = parts[1]
            }
        }
    }

    Process {
        id: uptimeProc
        command: ["sh", "-c", "awk '{h=int($1/3600); m=int(($1%3600)/60); if(h>0) print h\"h \"m\"m\"; else print m\"m\"}' /proc/uptime 2>/dev/null || echo \"\""]
        running: false
        stdout: SplitParser {
            onRead: data => root.uptimeStr = data.trim()
        }
    }

    // Card Component
    component PowerCard: Rectangle {
        id: pCard
        property string cardLabel: ""
        property string cardSublabel: ""
        property string cardIcon: ""
        property string cardKey: ""
        property bool isDangerAction: false
        property int cardIndex: -1

        signal clicked()

        readonly property bool isSelected: root.selectedIndex === cardIndex

        height: 114
        radius: Services.Theme.radiusMd
        color: pMouse.containsMouse || isSelected ? Services.Theme.surfaceVariant : Services.Theme.bgHover
        border.color: isSelected ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : (pMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
        border.width: isSelected ? 2 : 1
        scale: pMouse.containsMouse ? 1.03 : (isSelected ? 1.01 : 1.0)

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea {
            id: pMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = pCard.cardIndex
            onClicked: pCard.clicked()
        }

        // Hotkey Badge
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 8 }
            width: 18; height: 18; radius: 9
            color: isSelected ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : Services.Theme.border
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: pCard.cardKey
                font.pixelSize: 10
                font.weight: Font.Bold
                color: isSelected ? (isDangerAction ? "#ffffff" : "#111111") : Services.Theme.textSecondary
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            // Icon Box
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 44; height: 44; radius: 22
                color: isSelected ? (isDangerAction ? "#2a1515" : "#2a2a2a") : Services.Theme.bgElevated
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: pCard.cardIcon
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: 22
                    color: isSelected ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : Services.Theme.textPrimary
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            // Title
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pCard.cardLabel
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: isSelected ? Services.Theme.textPrimary : Services.Theme.textSecondary
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            // Sublabel
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pCard.cardSublabel
                font.pixelSize: 9
                color: Services.Theme.textDisabled
                elide: Text.ElideRight
                Layout.maximumWidth: parent.width - 16
            }
        }
    }
}
