import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "batteryPanel"

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isFloating: barStyle === "floating"
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.batteryPanelVisible
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

    readonly property bool isCenteredBar: barStyle !== "islands"

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
        onClicked: root.close()

        Rectangle {
            id: panel
            width: 360
            implicitHeight: mainCol.implicitHeight + 32
            readonly property real targetX: Services.OverlayManager.batteryTargetX > 0 
                ? Services.OverlayManager.batteryTargetX 
                : (parent.width - 160)
            x: Math.max(12, Math.min(parent.width - width - 12, targetX - (width / 2)))
            y: root.isBottom ? (parent.height - height - 12) : 12
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.batteryPanelVisible ? 1 : 0
            transform: Translate {
                y: Services.OverlayManager.batteryPanelVisible ? 0 : (root.isBottom ? 32 : -32)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            }
            scale: Services.OverlayManager.batteryPanelVisible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // ── 1. Header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 16
                        color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.accent))
                    }

                    Text {
                        text: "Battery & Power"
                        font.family: Services.Theme.fontPrimary
                        font.bold: true
                        font.pixelSize: Services.Theme.fontSizeXl
                        color: Services.Theme.textPrimary
                        Layout.fillWidth: true
                    }

                    // Status Badge
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: statusBadgeText.implicitWidth + 14
                        radius: 11
                        color: Services.Power.charging 
                            ? Qt.rgba(Services.Theme.success.r, Services.Theme.success.g, Services.Theme.success.b, 0.18)
                            : (Services.Power.isLow 
                                ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.18)
                                : Qt.rgba(Services.Theme.textSecondary.r, Services.Theme.textSecondary.g, Services.Theme.textSecondary.b, 0.15))
                        border.color: Services.Power.charging ? Services.Theme.success : "transparent"
                        border.width: 1

                        Text {
                            id: statusBadgeText
                            anchors.centerIn: parent
                            text: Services.Power.charging ? "Charging" : (Services.Power.hasBattery ? "On Battery" : "AC Power")
                            font.pixelSize: 10
                            font.bold: true
                            color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : Services.Theme.textSecondary)
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: closeBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: closeBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: closeBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // ── 2. Hero Battery Status Card ──
                Rectangle {
                    Layout.fillWidth: true
                    radius: Services.Theme.radiusMd
                    color: Services.Theme.surfaceVariant
                    border.color: Services.Theme.borderSubtle
                    border.width: 1
                    implicitHeight: heroCol.implicitHeight + 24

                    ColumnLayout {
                        id: heroCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    spacing: 6
                                    Text {
                                        text: Math.round(Services.Power.percentage * 100) + "%"
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: 32
                                        font.bold: true
                                        color: Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary)
                                    }
                                    Text {
                                        visible: Services.Power.charging
                                        text: Services.Icons.bolt
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 18
                                        color: Services.Theme.success
                                    }
                                }

                                Text {
                                    text: {
                                        if (Services.Power.charging) {
                                            if (Services.Power.timeRemaining) return Services.Power.timeRemaining + " until full"
                                            return "Connected to power source"
                                        }
                                        if (Services.Power.timeRemaining) return Services.Power.timeRemaining + " remaining"
                                        return Services.Power.stateString
                                    }
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: Services.Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // Battery Icon Big Visual
                            Rectangle {
                                width: 44
                                height: 44
                                radius: 22
                                color: Services.Power.charging 
                                    ? Qt.rgba(Services.Theme.success.r, Services.Theme.success.g, Services.Theme.success.b, 0.2)
                                    : (Services.PowerProfile.saverEnabled ? Qt.rgba(245/255, 158/255, 11/255, 0.2) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15))
                                border.color: Services.Power.charging ? Services.Theme.success : "transparent"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 20
                                    color: Services.Power.charging ? Services.Theme.success : (Services.PowerProfile.saverEnabled ? "#f59e0b" : Services.Theme.accent)
                                }
                            }
                        }

                        // Animated Level Progress Bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Services.Theme.bgDeep

                            Rectangle {
                                id: levelFill
                                height: parent.height
                                radius: parent.radius
                                width: Math.max(8, Math.min(parent.width, (Services.Power.percentage || 0) * parent.width))
                                color: Services.Power.charging 
                                    ? Services.Theme.success 
                                    : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : (Services.PowerProfile.saverEnabled ? "#f59e0b" : Services.Theme.accent)))
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                // ── 3. Power Profile Selector ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Power Profile"
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeMd
                            color: Services.Theme.textPrimary
                            Layout.fillWidth: true
                        }
                        Text {
                            text: Services.PowerProfile.profile.toUpperCase()
                            font.family: Services.Theme.fontMono
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.accent
                        }
                    }

                    // 3 Mode Tiles
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // 1. Power Saver
                        Rectangle {
                            id: saverBtn
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: Services.Theme.radiusMd
                            readonly property bool isCurrent: Services.PowerProfile.profile === "power-saver"
                            color: isCurrent 
                                ? Qt.rgba(245/255, 158/255, 11/255, 0.18) 
                                : (saverMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                            border.color: isCurrent ? "#f59e0b" : (saverMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
                            border.width: isCurrent ? 1.5 : 1

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            MouseArea {
                                id: saverMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.PowerProfile.setProfile("power-saver")
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Services.Icons.leaf
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: saverBtn.isCurrent ? "#f59e0b" : Services.Theme.textSecondary
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Saver"
                                    font.bold: saverBtn.isCurrent
                                    font.pixelSize: 11
                                    color: saverBtn.isCurrent ? "#f59e0b" : Services.Theme.textPrimary
                                }
                            }
                        }

                        // 2. Balanced
                        Rectangle {
                            id: balancedBtn
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: Services.Theme.radiusMd
                            readonly property bool isCurrent: Services.PowerProfile.profile === "balanced"
                            color: isCurrent 
                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18) 
                                : (balancedMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                            border.color: isCurrent ? Services.Theme.accent : (balancedMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
                            border.width: isCurrent ? 1.5 : 1

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            MouseArea {
                                id: balancedMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.PowerProfile.setProfile("balanced")
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Services.Icons.balance
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: balancedBtn.isCurrent ? Services.Theme.accent : Services.Theme.textSecondary
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Balanced"
                                    font.bold: balancedBtn.isCurrent
                                    font.pixelSize: 11
                                    color: balancedBtn.isCurrent ? Services.Theme.accent : Services.Theme.textPrimary
                                }
                            }
                        }

                        // 3. Performance
                        Rectangle {
                            id: perfBtn
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: Services.Theme.radiusMd
                            readonly property bool isCurrent: Services.PowerProfile.profile === "performance"
                            color: isCurrent 
                                ? Qt.rgba(239/255, 68/255, 68/255, 0.18) 
                                : (perfMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                            border.color: isCurrent ? Services.Theme.danger : (perfMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle)
                            border.width: isCurrent ? 1.5 : 1

                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            MouseArea {
                                id: perfMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.PowerProfile.setProfile("performance")
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Services.Icons.speed
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: perfBtn.isCurrent ? Services.Theme.danger : Services.Theme.textSecondary
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Performance"
                                    font.bold: perfBtn.isCurrent
                                    font.pixelSize: 11
                                    color: perfBtn.isCurrent ? Services.Theme.danger : Services.Theme.textPrimary
                                }
                            }
                        }
                    }
                }

                // ── 4. Detailed Hardware Metrics Grid ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Battery Health & Stats"
                        font.bold: true
                        font.pixelSize: Services.Theme.fontSizeMd
                        color: Services.Theme.textPrimary
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        // Health / Capacity
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.borderSubtle
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Text {
                                    text: Services.Icons.heartPulse
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: Services.Theme.accent
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: "Health"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                    Text {
                                        text: Services.Power.health || "100%"
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: Services.Theme.textPrimary
                                    }
                                }
                            }
                        }

                        // Energy Rate / Power Draw
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.borderSubtle
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Text {
                                    text: Services.Icons.bolt
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: Services.Power.charging ? Services.Theme.success : Services.Theme.warning
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: Services.Power.charging ? "Charge Rate" : "Discharge Rate"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                    Text {
                                        text: Services.Power.energyRate || "0.0 W"
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: Services.Theme.textPrimary
                                    }
                                }
                            }
                        }

                        // Voltage
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.borderSubtle
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Text {
                                    text: Services.Icons.sliders
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: Services.Theme.textSecondary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: "Voltage"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                    Text {
                                        text: Services.Power.voltage || "--"
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: Services.Theme.textPrimary
                                    }
                                }
                            }
                        }

                        // Charge Cycles
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 52
                            radius: Services.Theme.radiusMd
                            color: Services.Theme.surfaceVariant
                            border.color: Services.Theme.borderSubtle
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                Text {
                                    text: Services.Icons.cycle
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 15
                                    color: Services.Theme.textSecondary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: "Charge Cycles"; font.pixelSize: 10; color: Services.Theme.textSecondary }
                                    Text {
                                        text: Services.Power.chargeCycles ? (Services.Power.chargeCycles + " cycles") : "N/A"
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: Services.Theme.textPrimary
                                    }
                                }
                            }
                        }
                    }

                    // Energy Capacity Info Line
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: Services.Icons.disk
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: Services.Theme.textSecondary
                            }

                            Text {
                                text: (Services.Power.model ? (Services.Power.model + " • ") : "") + (Services.Power.energyCurrent ? (Services.Power.energyCurrent + " / " + Services.Power.energyFull) : "Battery")
                                font.pixelSize: 11
                                color: Services.Theme.textSecondary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }
}
