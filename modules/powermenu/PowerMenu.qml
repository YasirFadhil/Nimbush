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
    property int activeHoldIndex: -1
    property real holdProgress: 0.0
    property string activeHoldKey: ""
    readonly property int holdDurationMs: 800

    property string username: ""
    property string hostname: ""
    property string uptimeStr: ""

    readonly property var actions: [
        { label: "Lock",         sublabel: "Lock screen",        icon: Services.Icons.pmLock,     proc: lockProc,     key: "L", num: "1", danger: false, needsHold: false },
        { label: "Reload Shell", sublabel: "Restart Quickshell", icon: Services.Icons.reboot,     proc: reloadProc,   key: "Q", num: "2", danger: false, needsHold: false },
        { label: "Suspend",      sublabel: "Suspend to RAM",     icon: Services.Icons.pmSleep,    proc: sleepProc,    key: "S", num: "3", danger: false, needsHold: true  },
        { label: "Logout",       sublabel: "Exit user session",  icon: Services.Icons.pmLogout,   proc: logoutProc,   key: "X", num: "4", danger: false, needsHold: true  },
        { label: "Reboot",       sublabel: "Restart system",     icon: Services.Icons.pmReboot,   proc: rebootProc,   key: "R", num: "5", danger: true,  needsHold: true  },
        { label: "Power Off",    sublabel: "Turn off computer",  icon: Services.Icons.pmShutdown, proc: shutdownProc, key: "P", num: "6", danger: true,  needsHold: true  }
    ]

    NumberAnimation {
        id: holdAnim
        target: root
        property: "holdProgress"
        from: 0.0
        to: 1.0
        duration: root.holdDurationMs
        easing.type: Easing.Linear
        onFinished: {
            if (root.activeHoldIndex >= 0 && root.holdProgress >= 0.98) {
                root.executeAction(root.activeHoldIndex)
                root.stopHold()
            }
        }
    }

    NumberAnimation {
        id: releaseAnim
        target: root
        property: "holdProgress"
        to: 0.0
        duration: 140
        easing.type: Easing.OutQuad
    }

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        hideTimer.stop()
        stopHold()
        selectedIndex = 0
        menuVisible = true
        isOpen = true
        userInfoProc.running = true
        uptimeProc.running = true
        keyFocus.forceActiveFocus()
    }

    function close() {
        if (!isOpen && !menuVisible) return
        stopHold()
        isOpen = false
        hideTimer.restart()
    }

    function hide() { close() }
    function show() { open() }

    function startHold(index, keyName) {
        if (index < 0 || index >= actions.length) return
        const act = actions[index]
        selectedIndex = index
        if (!act.needsHold) {
            executeAction(index)
            return
        }
        activeHoldIndex = index
        activeHoldKey = keyName || ""
        releaseAnim.stop()
        holdProgress = 0.0
        holdAnim.restart()
    }

    function stopHold() {
        if (activeHoldIndex >= 0 || holdProgress > 0) {
            holdAnim.stop()
            activeHoldIndex = -1
            activeHoldKey = ""
            releaseAnim.restart()
        }
    }

    function executeAction(index) {
        if (index < 0 || index >= actions.length) return
        const act = actions[index]
        if (act.label === "Reload Shell") {
            reloadProc.running = true
            close()
            return
        }
        act.proc.running = true
        close()
    }

    visible: menuVisible

    Component.onCompleted: {
        Services.OverlayManager.register(root)
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:powermenu"
    anchors { top: true; bottom: true; left: true; right: true }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: root.menuVisible = false
    }

    onMenuVisibleChanged: {
        if (menuVisible) {
            keyFocus.forceActiveFocus()
        }
    }

    // Keyboard navigation & hold hotkeys
    Item {
        id: keyFocus
        focus: true
        Keys.onPressed: (event) => {
            if (event.isAutoRepeat) {
                event.accepted = true
                return
            }

            const txt = (event.text || "").toLowerCase()
            const k = event.key

            // ── Direct Letter Hotkeys (L, Q, S, X, R, P) ─────────────────────
            if (txt === "l" || k === Qt.Key_L) {
                root.startHold(0, "l"); event.accepted = true; return
            }
            if (txt === "q" || txt === "e" || k === Qt.Key_Q || k === Qt.Key_E) {
                root.startHold(1, "q"); event.accepted = true; return
            }
            if (txt === "s" || k === Qt.Key_S) {
                root.startHold(2, "s"); event.accepted = true; return
            }
            if (txt === "x" || k === Qt.Key_X) {
                root.startHold(3, "x"); event.accepted = true; return
            }
            if (txt === "r" || k === Qt.Key_R) {
                root.startHold(4, "r"); event.accepted = true; return
            }
            if (txt === "p" || k === Qt.Key_P) {
                root.startHold(5, "p"); event.accepted = true; return
            }

            // ── Number Hotkeys (1-6) ─────────────────────────────────────────
            if (k >= Qt.Key_1 && k <= Qt.Key_6) {
                const idx = k - Qt.Key_1
                root.startHold(idx, "num" + (idx + 1)); event.accepted = true; return
            }

            // ── Enter / Space to Hold/Trigger Selected Card ──────────────────
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                root.startHold(root.selectedIndex, "enter")
                event.accepted = true
                return
            }

            // ── Arrow Keys & Tab Navigation (No letter conflicts) ────────────
            if (k === Qt.Key_Left) {
                root.selectedIndex = (root.selectedIndex - 1 + root.actions.length) % root.actions.length
                event.accepted = true
            } else if (k === Qt.Key_Right || k === Qt.Key_Tab) {
                root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
                event.accepted = true
            } else if (k === Qt.Key_Up) {
                root.selectedIndex = (root.selectedIndex < 3) ? (root.selectedIndex + 3) : (root.selectedIndex - 3)
                event.accepted = true
            } else if (k === Qt.Key_Down) {
                root.selectedIndex = (root.selectedIndex < 3) ? (root.selectedIndex + 3) : (root.selectedIndex - 3)
                event.accepted = true
            } else if (k === Qt.Key_Escape) {
                root.stopHold()
                root.close()
                event.accepted = true
            }
        }

        Keys.onReleased: (event) => {
            if (event.isAutoRepeat) return
            root.stopHold()
            event.accepted = true
        }
    }

    // Fullscreen Dimmed Backdrop
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
            color: Services.Theme.overlayDim
            opacity: root.isOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        // Floating Glass Card HUD
        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.isOpen ? 0 : 24
            width: 580
            implicitHeight: cardContent.implicitHeight + 40

            radius: Services.Theme.radiusLg + 4
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

            // Block backdrop clicks
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                id: cardContent
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 20
                spacing: 18

                // ── Header Section ──────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // User / Distro Avatar
                    Rectangle {
                        width: 44; height: 44; radius: 22
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Services.OsInfo.logoGlyph
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSize6xl + 2
                            color: Services.Theme.accent
                        }

                        // Online dot indicator
                        Rectangle {
                            anchors { right: parent.right; bottom: parent.bottom; margins: 1 }
                            width: 10; height: 10; radius: 5
                            color: Services.Theme.success
                            border.color: Services.Theme.surface
                            border.width: 1.5
                        }
                    }

                    // User Info & Status Badges
                    ColumnLayout {
                        spacing: 4
                        Layout.fillWidth: true

                        RowLayout {
                            spacing: 8
                            Text {
                                text: root.username !== "" ? ("Hi, " + root.username.charAt(0).toUpperCase() + root.username.slice(1)) : "Power Menu"
                                font.pixelSize: Services.Theme.fontSize3xl + 1
                                font.weight: Font.Bold
                                color: Services.Theme.textPrimary
                            }

                            // Hostname Tag
                            Rectangle {
                                visible: root.hostname !== ""
                                implicitWidth: hostText.implicitWidth + 10
                                height: 18
                                radius: 9
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1

                                Text {
                                    id: hostText
                                    anchors.centerIn: parent
                                    text: root.hostname
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.weight: Font.Medium
                                    color: Services.Theme.textSecondary
                                }
                            }
                        }

                        // Telemetry chips
                        RowLayout {
                            spacing: 8

                            // Uptime Chip
                            Rectangle {
                                visible: root.uptimeStr !== ""
                                implicitWidth: upRow.implicitWidth + 12
                                height: 20
                                radius: 10
                                color: Services.Theme.bgHover
                                border.color: Services.Theme.borderSubtle
                                border.width: 1

                                RowLayout {
                                    id: upRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: "󱑂"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.accent
                                    }
                                    Text {
                                        text: "up " + root.uptimeStr
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textSecondary
                                    }
                                }
                            }

                            // Battery Chip
                            Rectangle {
                                visible: Services.Power.ready && !isNaN(Services.Power.percentage) && Services.Power.percentage > 0
                                implicitWidth: batRow.implicitWidth + 12
                                height: 20
                                radius: 10
                                color: Services.Theme.bgHover
                                border.color: Services.Theme.borderSubtle
                                border.width: 1

                                RowLayout {
                                    id: batRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Power.isLow ? Services.Theme.danger : Services.Theme.textSecondary
                                    }
                                    Text {
                                        text: Math.round(Services.Power.percentage * 100) + "%" + (Services.Power.charging ? " (Charging)" : "")
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textSecondary
                                    }
                                }
                            }
                        }
                    }

                    // Close (Esc) Button
                    Rectangle {
                        width: 32; height: 32; radius: 16
                        color: escMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover
                        border.color: Services.Theme.border
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSizeMd
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
                    opacity: 0.7
                }

                // ── 2x3 Action Cards Grid ──────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 10
                    columnSpacing: 10

                    Repeater {
                        model: root.actions
                        PowerCard {
                            Layout.fillWidth: true
                            cardLabel: modelData.label
                            cardSublabel: modelData.sublabel
                            cardIcon: modelData.icon
                            cardKey: modelData.key
                            cardNum: modelData.num
                            isDangerAction: modelData.danger
                            needsHoldAction: modelData.needsHold
                            cardIndex: index
                        }
                    }
                }

                // ── Footer Hint ─────────────────────────────────────────────
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6

                    Text {
                        text: (root.activeHoldIndex >= 0 && root.actions[root.activeHoldIndex]) ? "󰔛" : "󰌌"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: (root.activeHoldIndex >= 0 && root.actions[root.activeHoldIndex]) 
                            ? (root.actions[root.activeHoldIndex].danger ? Services.Theme.danger : Services.Theme.accent) 
                            : Services.Theme.textDisabled
                    }

                    Text {
                        text: (root.activeHoldIndex >= 0 && root.actions[root.activeHoldIndex]) 
                            ? ("Hold to confirm " + root.actions[root.activeHoldIndex].label + "...") 
                            : "Press hotkey (L, Q) or hold (S, X, R, P) to execute"
                        font.pixelSize: Services.Theme.fontSizeXs
                        color: (root.activeHoldIndex >= 0 && root.actions[root.activeHoldIndex]) 
                            ? (root.actions[root.activeHoldIndex].danger ? Services.Theme.danger : Services.Theme.accent) 
                            : Services.Theme.textSecondary
                    }
                }
            }
        }
    }

    // ── Action Processes ────────────────────────────────────────────────────
    Process { id: lockProc; command: ["sh", "-c", "qs ipc call lockscreen lock || hyprlock || swaylock"] }
    Process { id: reloadProc; command: ["sh", "-c", "touch \"" + (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/shell.qml\" || pkill -USR1 qs || pkill -USR1 quickshell"] }
    Process { id: logoutProc; command: ["sh", "-c", "niri msg action quit --skip-confirmation || hyprctl dispatch 'hl.dsp.exit()' || loginctl terminate-user $USER"] }
    Process { id: sleepProc; command: ["sh", "-c", "qs ipc call lockscreen lock && sleep 0.2 && systemctl suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["systemctl", "poweroff"] }

    Process {
        id: userInfoProc
        command: ["sh", "-c", "echo $(whoami)@$(uname -n)"]
        running: true
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

    // ── Action Card Component ───────────────────────────────────────────────
    component PowerCard: Rectangle {
        id: pCard
        property string cardLabel: ""
        property string cardSublabel: ""
        property string cardIcon: ""
        property string cardKey: ""
        property string cardNum: ""
        property bool isDangerAction: false
        property bool needsHoldAction: false
        property int cardIndex: -1

        readonly property bool isSelected: root.selectedIndex === cardIndex
        readonly property bool isHolding: (root.activeHoldIndex === cardIndex)

        height: 104
        radius: Services.Theme.radiusMd
        color: isHolding 
            ? (isDangerAction ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.15) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)) 
            : (pMouse.containsMouse || isSelected ? Services.Theme.surfaceVariant : Services.Theme.bgHover)
        border.color: isHolding 
            ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) 
            : (isSelected ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : (pMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border))
        border.width: (isHolding || isSelected) ? 1.5 : 1
        scale: isHolding ? 0.98 : (pMouse.containsMouse ? 1.02 : 1.0)
        clip: true

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // Clean Hold Fill Progress
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (pCard.isHolding ? root.holdProgress : 0)
            radius: parent.radius
            color: pCard.isDangerAction 
                ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.15) 
                : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
            visible: pCard.isHolding && root.holdProgress > 0
        }

        MouseArea {
            id: pMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = pCard.cardIndex
            onPressed: root.startHold(pCard.cardIndex, "mouse")
            onReleased: root.stopHold()
            onCanceled: root.stopHold()
        }

        // Hotkey Badge (Top Right)
        Rectangle {
            anchors { top: parent.top; right: parent.right; margins: 7 }
            width: 20; height: 20; radius: 6
            color: isHolding 
                ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) 
                : (isSelected ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : Services.Theme.border)
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: pCard.cardKey
                font.pixelSize: Services.Theme.fontSizeSm
                font.weight: Font.Bold
                color: (isHolding || isSelected) ? (isDangerAction ? "#ffffff" : Services.Theme.bgOnAccent) : Services.Theme.textSecondary
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 5

            // Icon Box
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 40; height: 40; radius: 20
                color: isHolding 
                    ? (isDangerAction ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.25) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)) 
                    : (isSelected ? (isDangerAction ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.15) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)) : Services.Theme.bgElevated)
                border.color: (isHolding || isSelected) ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : "transparent"
                border.width: (isHolding || isSelected) ? 1 : 0
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: pCard.cardIcon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize5xl
                    color: (isHolding || isSelected) ? (isDangerAction ? Services.Theme.danger : Services.Theme.accent) : (isDangerAction ? Qt.lighter(Services.Theme.danger, 1.1) : Services.Theme.textPrimary)
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            // Title
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pCard.cardLabel
                font.pixelSize: Services.Theme.fontSizeMd
                font.weight: Font.DemiBold
                color: (isHolding || isSelected) ? Services.Theme.textPrimary : Services.Theme.textSecondary
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            // Sublabel / Hold Hint
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pCard.isHolding 
                    ? "Holding..." 
                    : (pCard.needsHoldAction ? (pMouse.containsMouse || pCard.isSelected ? ("Hold [" + pCard.cardKey + "]") : pCard.cardSublabel) : pCard.cardSublabel)
                font.pixelSize: Services.Theme.fontSizeXs - 1
                font.bold: pCard.isHolding
                color: pCard.isHolding ? (pCard.isDangerAction ? Services.Theme.danger : Services.Theme.accent) : Services.Theme.textDisabled
                elide: Text.ElideRight
                Layout.maximumWidth: parent.width - 8
            }
        }
    }
}

