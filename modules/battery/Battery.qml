import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "batteryPanel"

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property int barTotalHeight: Services.Config ? (barStyle === "minimal" ? 30 : (barStyle === "unified" ? 38 : (barStyle === "floating" ? 46 : 36))) : 36

    readonly property bool isOpen: Services.OverlayManager.batteryPanelVisible
    readonly property int pct: Math.round((Services.Power.percentage || 0) * 100)
    readonly property bool chargeLimitOn: Boolean(Services.Config && Services.Config.batteryChargeLimitEnabled)

    readonly property color stateColor: {
        if (Services.Power.isChargeInhibited) return Services.Theme.accent
        if (Services.Power.charging) return Services.Theme.success
        if (Services.Power.isLow) return Services.Theme.danger
        if (Services.Power.isWarning) return Services.Theme.warning
        if (Services.PowerProfile.saverEnabled) return "#f59e0b"
        return Services.Theme.accent
    }

    readonly property string statusLabel: {
        if (Services.Power.isChargeInhibited) return "Bypass"
        if (Services.Power.charging) return "Charging"
        if (Services.Power.hasBattery) return "On Battery"
        return "AC Power"
    }

    readonly property string subStatusText: {
        if (Services.Power.isChargeInhibited) return "Power bypassed • Charge limit (80%) active"
        if (Services.Power.charging) {
            return Services.Power.timeRemaining ? (Services.Power.timeRemaining + " until full") : "Connected to power source"
        }
        return Services.Power.timeRemaining ? (Services.Power.timeRemaining + " remaining") : Services.Power.stateString
    }

    readonly property color tileBg: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color tileBgHover: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color tileBorder: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: isOpen || (panel && panel.opacity > 0.01)
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:battery"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        Services.OverlayManager.batteryPanelVisible = true
        Services.Power.refreshDetails()
        Services.PowerProfile.refresh()
    }
    function close() {
        Services.OverlayManager.batteryPanelVisible = false
    }
    function hide() { close() }
    function show() { open() }
    function toggle() {
        if (Services.OverlayManager.batteryPanelVisible) close()
        else open()
    }

    onVisibleChanged: {
        if (visible) {
            Services.Power.refreshDetails()
            Services.PowerProfile.refresh()
        }
    }

    Component.onCompleted: Services.OverlayManager.register(root)

    Item {
        id: escFocus
        focus: Services.OverlayManager.batteryPanelVisible
        Keys.onEscapePressed: root.close()
    }

    MouseArea {
        anchors.fill: parent
        enabled: Services.OverlayManager.batteryPanelVisible
        onClicked: root.close()

        Rectangle {
            id: panel
            width: 340
            implicitHeight: mainCol.implicitHeight + 32
            readonly property real targetX: Services.OverlayManager.batteryTargetX > 0
                ? Services.OverlayManager.batteryTargetX
                : (parent.width - 160)
            x: Math.max(12, Math.min(parent.width - width - 12, targetX - (width / 2)))
            y: root.isBottom ? (parent.height - height - 12) : 12
            radius: 20
            color: Services.Theme.isDark ? Qt.rgba(0.14, 0.14, 0.15, 0.62) : Qt.rgba(1, 1, 1, 0.66)
            border.color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            border.width: 1
            clip: true

            opacity: root.isOpen ? 1.0 : 0.0
            scale: root.isOpen ? 1.0 : 0.96
            transform: Translate {
                y: root.isOpen ? 0 : (root.isBottom ? 20 : -20)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // ── 1. Unified Hero Header ──────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: Services.Power.isChargeInhibited ? "󰚥" : Services.Icons.powerIcon(Services.Power.charging, root.pct)
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 22
                            color: root.stateColor
                        }

                        Text {
                            text: root.pct + "%"
                            font.family: Services.Theme.fontMono
                            font.pixelSize: 28
                            font.bold: true
                            color: Services.Power.isLow ? Services.Theme.danger : Services.Theme.textPrimary
                        }

                        // Compact Status Pill
                        Rectangle {
                            implicitHeight: 20
                            implicitWidth: statusPillText.implicitWidth + 12
                            radius: 10
                            color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.16)

                            Text {
                                id: statusPillText
                                anchors.centerIn: parent
                                text: root.statusLabel
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: root.stateColor
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Minimal Close Button
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: closeMouse.containsMouse ? root.tileBgHover : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.close
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: closeMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textTertiary
                            }
                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.close()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.subStatusText
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: Services.Theme.textSecondary
                        elide: Text.ElideRight
                    }

                    // Clean Battery Level Bar (with 80% marker when limit is active)
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: Math.max(6, Math.min(parent.width, (Services.Power.percentage || 0) * parent.width))
                            color: root.stateColor
                            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }

                        // Subtle 80% threshold marker
                        Rectangle {
                            visible: Services.Power.chargeLimitSupported && root.chargeLimitOn
                            x: parent.width * 0.8 - 1
                            width: 2
                            height: parent.height
                            color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.35)
                        }
                    }
                }

                // ── 2. Power Profile Selector (Segmented Row) ───────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "power-saver", label: "Saver",    icon: Services.Icons.leaf,    tint: "#f59e0b" },
                            { id: "balanced",    label: "Balanced", icon: Services.Icons.balance, tint: Services.Theme.accent },
                            { id: "performance", label: "Perf",     icon: Services.Icons.speed,   tint: Services.Theme.danger }
                        ]
                        delegate: Rectangle {
                            readonly property bool isCurrent: Services.PowerProfile.profile === modelData.id
                            readonly property color activeTint: modelData.tint

                            Layout.fillWidth: true
                            height: 38
                            radius: Services.Theme.radiusMd
                            color: isCurrent
                                ? Qt.rgba(activeTint.r, activeTint.g, activeTint.b, 0.16)
                                : (profMouse.containsMouse ? root.tileBgHover : root.tileBg)
                            border.color: isCurrent ? activeTint : root.tileBorder
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            MouseArea {
                                id: profMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.PowerProfile.setProfile(modelData.id)
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: modelData.icon
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 13
                                    color: isCurrent ? activeTint : Services.Theme.textSecondary
                                }
                                Text {
                                    text: modelData.label
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.weight: isCurrent ? Font.DemiBold : Font.Medium
                                    color: isCurrent ? activeTint : Services.Theme.textPrimary
                                }
                            }
                        }
                    }
                }

                // ── 3. Charge Limit (80%) Compact Toggle ────────────────────
                Rectangle {
                    visible: Services.Power.chargeLimitSupported
                    Layout.fillWidth: true
                    height: 46
                    radius: Services.Theme.radiusMd
                    color: root.chargeLimitOn
                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.10)
                        : (limitMouse.containsMouse ? root.tileBgHover : root.tileBg)
                    border.color: root.chargeLimitOn ? Services.Theme.accent : root.tileBorder
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    MouseArea {
                        id: limitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Services.Config) {
                                Services.Config.setBatteryChargeLimitEnabled(!Services.Config.batteryChargeLimitEnabled)
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            text: Services.Power.isChargeInhibited ? "󰚥" : "󰂄"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 16
                            color: root.chargeLimitOn
                                ? (Services.Power.isChargeInhibited ? Services.Theme.success : Services.Theme.accent)
                                : Services.Theme.textSecondary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Charge Limit (80%)"
                                font.weight: Font.DemiBold
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                text: Services.Power.isChargeInhibited
                                    ? "Bypass active (AC direct)"
                                    : (root.chargeLimitOn ? "Stops charging at 80%" : "Charges up to 100%")
                                font.pixelSize: 10
                                color: Services.Theme.textTertiary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Switch
                        Rectangle {
                            width: 34; height: 20; radius: 10
                            color: root.chargeLimitOn ? Services.Theme.accent : root.tileBg
                            border.color: root.chargeLimitOn ? Services.Theme.accent : root.tileBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 180 } }

                            Rectangle {
                                width: 14; height: 14; radius: 7
                                color: root.chargeLimitOn ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                                x: root.chargeLimitOn ? parent.width - width - 3 : 3
                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                // ── 4. Compact 2x2 Telemetry Grid ───────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 6
                    rowSpacing: 6

                    Repeater {
                        model: [
                            {
                                icon: Services.Icons.heartPulse,
                                iconColor: Services.Theme.accent,
                                label: "Health",
                                value: Services.Power.health || "100%"
                            },
                            {
                                icon: Services.Power.isChargeInhibited ? "󰚥" : Services.Icons.bolt,
                                iconColor: Services.Power.isChargeInhibited ? Services.Theme.accent : (Services.Power.charging ? Services.Theme.success : Services.Theme.warning),
                                label: Services.Power.isChargeInhibited ? "Power Flow" : (Services.Power.charging ? "Charge Rate" : "Power Draw"),
                                value: Services.Power.isChargeInhibited ? "Bypass" : (Services.Power.energyRate || "0.0 W")
                            },
                            {
                                icon: Services.Icons.sliders,
                                iconColor: Services.Theme.textSecondary,
                                label: "Voltage",
                                value: Services.Power.voltage || "--"
                            },
                            {
                                icon: Services.Icons.cycle,
                                iconColor: Services.Theme.textSecondary,
                                label: "Cycles",
                                value: Services.Power.chargeCycles ? (Services.Power.chargeCycles + " cycles") : "N/A"
                            }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: Services.Theme.radiusMd
                            color: root.tileBg
                            border.color: root.tileBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: modelData.icon
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 14
                                    color: modelData.iconColor
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: 10
                                        color: Services.Theme.textTertiary
                                    }
                                    Text {
                                        text: modelData.value
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 5. Subtle Model & Energy Footer ─────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: Services.Icons.disk
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        color: Services.Theme.textDisabled
                    }

                    Text {
                        text: (Services.Power.model ? (Services.Power.model + " • ") : "")
                            + (Services.Power.energyCurrent ? (Services.Power.energyCurrent + " / " + Services.Power.energyFull) : "Battery")
                        font.pixelSize: 10
                        color: Services.Theme.textTertiary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
