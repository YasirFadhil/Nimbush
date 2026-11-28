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
    readonly property int holdDurationMs: 800

    property string uptimeStr: ""

    readonly property string displayUser: {
        const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").trim()
        return u.length > 0 ? (u.charAt(0).toUpperCase() + u.slice(1)) : "User"
    }
    readonly property string displayHost: (Services.OsInfo.hostname || "").trim()
    readonly property bool hasBattery: Services.Power.ready && !isNaN(Services.Power.percentage) && Services.Power.percentage > 0
    readonly property var currentAction: (selectedIndex >= 0 && selectedIndex < actions.length) ? actions[selectedIndex] : null
    readonly property var holdingAction: (activeHoldIndex >= 0 && activeHoldIndex < actions.length) ? actions[activeHoldIndex] : null

    readonly property var actions: [
        { label: "Lock",         desc: "Lock screen",        icon: Services.Icons.pmLock,     proc: lockProc,     key: "L", danger: false, needsHold: false },
        { label: "Reload Shell", desc: "Restart Quickshell", icon: Services.Icons.reboot,     proc: reloadProc,   key: "Q", danger: false, needsHold: false },
        { label: "Suspend",      desc: "Suspend to RAM",     icon: Services.Icons.pmSleep,    proc: sleepProc,    key: "S", danger: false, needsHold: true  },
        { label: "Logout",       desc: "Exit user session",  icon: Services.Icons.pmLogout,   proc: logoutProc,   key: "X", danger: false, needsHold: true  },
        { label: "Reboot",       desc: "Restart system",     icon: Services.Icons.pmReboot,   proc: rebootProc,   key: "R", danger: true,  needsHold: true  },
        { label: "Power Off",    desc: "Turn off computer",  icon: Services.Icons.pmShutdown, proc: shutdownProc, key: "P", danger: true,  needsHold: true  }
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

    function startHold(index) {
        if (index < 0 || index >= actions.length) return
        const act = actions[index]
        selectedIndex = index
        if (!act.needsHold) {
            executeAction(index)
            return
        }
        activeHoldIndex = index
        releaseAnim.stop()
        holdProgress = 0.0
        holdAnim.restart()
    }

    function stopHold() {
        if (activeHoldIndex >= 0 || holdProgress > 0) {
            holdAnim.stop()
            activeHoldIndex = -1
            releaseAnim.restart()
        }
    }

    function executeAction(index) {
        if (index < 0 || index >= actions.length) return
        actions[index].proc.running = true
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
        if (menuVisible) keyFocus.forceActiveFocus()
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

            if (txt === "l" || k === Qt.Key_L) {
                root.startHold(0); event.accepted = true; return
            }
            if (txt === "q" || txt === "e" || k === Qt.Key_Q || k === Qt.Key_E) {
                root.startHold(1); event.accepted = true; return
            }
            if (txt === "s" || k === Qt.Key_S) {
                root.startHold(2); event.accepted = true; return
            }
            if (txt === "x" || k === Qt.Key_X) {
                root.startHold(3); event.accepted = true; return
            }
            if (txt === "r" || k === Qt.Key_R) {
                root.startHold(4); event.accepted = true; return
            }
            if (txt === "p" || k === Qt.Key_P) {
                root.startHold(5); event.accepted = true; return
            }

            if (k >= Qt.Key_1 && k <= Qt.Key_6) {
                root.startHold(k - Qt.Key_1)
                event.accepted = true
                return
            }

            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                root.startHold(root.selectedIndex)
                event.accepted = true
                return
            }

            if (k === Qt.Key_Left || k === Qt.Key_Backtab || (k === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                root.selectedIndex = (root.selectedIndex - 1 + root.actions.length) % root.actions.length
                event.accepted = true
            } else if (k === Qt.Key_Right || k === Qt.Key_Tab) {
                root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
                event.accepted = true
            } else if (k === Qt.Key_Up || k === Qt.Key_Down) {
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
        onClicked: root.close()

        Rectangle {
            anchors.fill: parent
            color: Services.Theme.overlayDim
            opacity: root.isOpen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        // Minimalist Floating Card
        Rectangle {
            id: card
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.isOpen ? 0 : 16
            width: 460
            implicitHeight: cardContent.implicitHeight + 36

            radius: Services.Theme.radiusLg + 2
            color: Services.Theme.surface
            border.color: (root.holdingAction && root.holdingAction.danger) ? Services.Theme.danger : Services.Theme.border
            border.width: 1

            opacity: root.isOpen ? 1 : 0
            scale: root.isOpen ? 1 : 0.96

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Block backdrop clicks inside card
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                id: cardContent
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 18
                spacing: 14

                // ── Compact Informative Header ──────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Services.AvatarFrame {
                        width: 36; height: 36
                        source: Services.OsInfo.avatarPath
                        shapeRadius: {
                            const s = Services.Config ? Services.Config.lockscreenAvatarShape : "squircle"
                            if (s === "circle") return 18
                            if (s === "squircle") return 10
                            return 7
                        }
                        backgroundColor: Services.Theme.surfaceVariant
                        borderColor: Services.Theme.border
                        borderWidth: 1
                        fallbackText: root.displayUser.charAt(0)
                        fallbackFontFamily: Services.Theme.fontDisplay || Services.Theme.fontSymbols
                        fallbackFontSize: 15
                        fallbackColor: Services.Theme.accent
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        // User @ Host
                        RowLayout {
                            spacing: 4
                            Text {
                                text: root.displayUser
                                font.pixelSize: Services.Theme.fontSize2xl
                                font.weight: Font.DemiBold
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                visible: root.displayHost !== ""
                                text: "@" + root.displayHost
                                font.pixelSize: Services.Theme.fontSizeMd
                                color: Services.Theme.textTertiary
                                elide: Text.ElideRight
                            }
                        }

                        // Inline Telemetry (Uptime • Battery)
                        RowLayout {
                            spacing: 6

                            RowLayout {
                                visible: root.uptimeStr !== ""
                                spacing: 4
                                Text {
                                    text: "󱑂"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: Services.Theme.textTertiary
                                }
                                Text {
                                    text: "up " + root.uptimeStr
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: Services.Theme.textSecondary
                                }
                            }

                            Text {
                                visible: root.uptimeStr !== "" && root.hasBattery
                                text: "•"
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textDisabled
                            }

                            RowLayout {
                                visible: root.hasBattery
                                spacing: 4
                                Text {
                                    text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: Services.Power.isLow ? Services.Theme.danger : (Services.Power.charging ? Services.Theme.success : Services.Theme.textTertiary)
                                }
                                Text {
                                    text: Math.round(Services.Power.percentage * 100) + "%" + (Services.Power.charging ? " charging" : "")
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: Services.Power.isLow ? Services.Theme.danger : Services.Theme.textSecondary
                                }
                            }
                        }
                    }

                    // Minimal Close Button
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: escMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: escMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textTertiary
                        }

                        MouseArea {
                            id: escMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // Subtle Divider
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.borderSubtle
                }

                // ── 2x3 Action Tiles ────────────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 8

                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            id: tile
                            readonly property bool isSelected: root.selectedIndex === index
                            readonly property bool isHolding: root.activeHoldIndex === index
                            readonly property color activeColor: modelData.danger ? Services.Theme.danger : Services.Theme.accent

                            Layout.fillWidth: true
                            height: 82
                            radius: Services.Theme.radiusMd
                            color: isHolding
                                ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.14)
                                : (isSelected || tileMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover)
                            border.color: (isHolding || isSelected) ? activeColor : Services.Theme.borderSubtle
                            border.width: 1
                            scale: isHolding ? 0.97 : 1.0
                            clip: true

                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            // Hold Fill Sweep
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 1 }
                                width: Math.max(0, (parent.width - 2) * (tile.isHolding ? root.holdProgress : 0))
                                radius: Math.max(0, parent.radius - 1)
                                color: Qt.rgba(tile.activeColor.r, tile.activeColor.g, tile.activeColor.b, 0.22)
                                visible: tile.isHolding && root.holdProgress > 0
                            }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = index
                                onPressed: root.startHold(index)
                                onReleased: root.stopHold()
                                onCanceled: root.stopHold()
                            }

                            // Subtle Key Hint (Top Right)
                            Text {
                                anchors { top: parent.top; right: parent.right; margins: 8 }
                                text: modelData.key
                                font.family: Services.Theme.fontMono
                                font.pixelSize: Services.Theme.fontSizeXs
                                font.weight: Font.DemiBold
                                color: (tile.isHolding || tile.isSelected) ? tile.activeColor : Services.Theme.textDisabled
                            }

                            // Centered Icon + Label
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.icon
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSize5xl
                                    color: (tile.isHolding || tile.isSelected)
                                        ? tile.activeColor
                                        : (modelData.danger ? Qt.lighter(Services.Theme.danger, 1.15) : Services.Theme.textPrimary)
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: tile.isHolding ? "Hold..." : modelData.label
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.weight: (tile.isHolding || tile.isSelected) ? Font.DemiBold : Font.Medium
                                    color: (tile.isHolding || tile.isSelected) ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }

                // ── Context-Aware Status Footer ─────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: root.holdingAction
                            ? ("Holding " + root.holdingAction.label + "...")
                            : (root.currentAction
                                ? (root.currentAction.desc + "  •  " + (root.currentAction.needsHold ? "Hold [" : "Press [") + root.currentAction.key + "] or Enter")
                                : "")
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: root.holdingAction
                            ? (root.holdingAction.danger ? Services.Theme.danger : Services.Theme.accent)
                            : Services.Theme.textTertiary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Esc to close"
                        font.pixelSize: Services.Theme.fontSizeXs
                        color: Services.Theme.textDisabled
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
        id: uptimeProc
        command: ["sh", "-c", "awk '{h=int($1/3600); m=int(($1%3600)/60); if(h>0) print h\"h \"m\"m\"; else print m\"m\"}' /proc/uptime 2>/dev/null || echo \"\""]
        running: false
        stdout: SplitParser {
            onRead: data => root.uptimeStr = data.trim()
        }
    }
}
