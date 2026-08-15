import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../../services" as Services

PanelWindow {
    id: root

    property string overlayId: "dashboard"
    property bool isOpen: false

    visible: false

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "quickshell:dashboard"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }

    Component.onCompleted: Services.OverlayManager.register(root)

    function show() {
        Services.OverlayManager.closeAllExcept(root)
        hideTimer.stop()
        visible = true
        isOpen = true
        keyFocus.forceActiveFocus()
    }

    function hide() {
        if (!isOpen) return
        isOpen = false
        hideTimer.restart()
    }

    function toggle() { isOpen ? hide() : show() }
    function open() { show() }
    function close() { hide() }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: root.visible = false
    }

    Item {
        id: keyFocus
        focus: root.isOpen
        Keys.onEscapePressed: root.close()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        // ── Panel ──────────────────────────────────────────────────────────
        Rectangle {
            id: panel
            anchors { top: parent.top; left: parent.left }
            anchors.leftMargin: 12
            anchors.topMargin: 12
            width: 360
            implicitHeight: mainCol.implicitHeight + 32

            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -16
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            // Reusable metric card component (2-col grid)
            component MetricCard: Rectangle {
                id: card
                property string iconGlyph: ""
                property string label: ""
                property string valueText: ""
                property real progress: 0.0
                property bool critical: false
                property string iconFont: Services.Theme.fontSymbols

                Layout.fillWidth: true
                implicitHeight: 58
                radius: Services.Theme.radiusMd
                color: Services.Theme.surfaceVariant

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 7

                    // Row: icon + label + value
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        // Icon bubble
                        Rectangle {
                            width: 22; height: 22; radius: 6
                            color: card.critical ? Qt.rgba(0.54, 0.32, 0.32, 0.25) : Qt.rgba(0.83, 0.83, 0.83, 0.1)
                            Behavior on color { ColorAnimation { duration: 300 } }

                            Text {
                                anchors.centerIn: parent
                                text: card.iconGlyph
                                font.family: card.iconFont
                                font.pixelSize: 11
                                color: card.critical ? Services.Theme.danger : Services.Theme.accent
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }

                        Text {
                            text: card.label
                            font.pixelSize: 10
                            font.bold: true
                            color: Services.Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: card.valueText
                            font.pixelSize: 10
                            font.bold: true
                            color: card.critical ? Services.Theme.danger : Services.Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }

                    // Progress bar track
                    Rectangle {
                        Layout.fillWidth: true
                        height: 5
                        radius: 3
                        color: Qt.rgba(0.1, 0.1, 0.1, 0.6)
                        clip: true

                        // Fill
                        Rectangle {
                            height: parent.height
                            width: Math.max(0, Math.min(parent.width, parent.width * card.progress))
                            radius: parent.radius
                            color: card.critical ? Services.Theme.danger : Services.Theme.accent
                            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }
                }
            }

            // ── Main Column ────────────────────────────────────────────────
            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // ── Header ──────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Avatar
                    Rectangle {
                        width: 46; height: 46
                        radius: 23
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderHighlight
                        border.width: 1
                        antialiasing: true
                        smooth: true

                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            anchors.margins: 1
                            source: Services.OsInfo.avatarPath
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            smooth: true
                            mipmap: true
                        }

                        MultiEffect {
                            anchors.fill: avatarImg
                            source: avatarImg
                            maskEnabled: true
                            maskSource: avatarMask
                            visible: avatarImg.status === Image.Ready
                        }

                        Item {
                            id: avatarMask
                            anchors.fill: avatarImg
                            visible: false
                            layer.enabled: true
                            layer.smooth: true
                            layer.samples: 8
                            Rectangle {
                                anchors.fill: parent
                                radius: 22
                                color: "black"
                                antialiasing: true
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImg.status !== Image.Ready
                            text: Services.OsInfo.logoGlyph !== "" ? Services.OsInfo.logoGlyph : "\uf007"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 20
                            color: Services.Theme.accent
                        }
                    }

                    // User info
                    ColumnLayout {
                        spacing: 3
                        Layout.fillWidth: true

                        Text {
                            text: Services.OsInfo.username.length > 0 ? Services.OsInfo.username : "User"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: Services.Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            spacing: 5

                            Text {
                                text: Services.OsInfo.hostname.length > 0 ? "@" + Services.OsInfo.hostname : ""
                                font.pixelSize: 10
                                color: Services.Theme.textSecondary
                            }

                            Text {
                                visible: Services.OsInfo.hostname.length > 0 && Services.OsInfo.distroName.length > 0
                                text: "·"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                            }

                            Text {
                                text: Services.OsInfo.distroName.length > 0 ? Services.OsInfo.distroName : "Linux"
                                font.pixelSize: 10
                                color: Services.Theme.accent
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Close button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: closeMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        border.color: closeMouse.containsMouse ? Services.Theme.border : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: closeMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                            Behavior on color { ColorAnimation { duration: 100 } }
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

                // ── Divider ──────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.7
                }

                // ── System Performance Section ────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Section label
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "System Performance"
                            font.pixelSize: 10
                            font.bold: true
                            font.letterSpacing: 0.5
                            color: Services.Theme.textDisabled
                        }

                        Item { Layout.fillWidth: true }

                        // Live indicator dot
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: Services.Theme.success
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    // Row 1: CPU + RAM
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MetricCard {
                            iconGlyph: Services.Icons.cpu
                            label: "CPU"
                            valueText: Math.round(Services.Sysmon.cpuUsage) + "%"
                            progress: Services.Sysmon.cpuUsage / 100.0
                            critical: Services.Sysmon.cpuUsage > 85
                        }

                        MetricCard {
                            iconGlyph: Services.Icons.ram
                            iconFont: Services.Theme.fontMono
                            label: "RAM"
                            valueText: Services.Sysmon.ramUsedStr.length > 0
                                       ? Services.Sysmon.ramUsedStr + "/" + Services.Sysmon.ramTotalStr
                                       : Math.round(Services.Sysmon.ramUsage) + "%"
                            progress: Services.Sysmon.ramUsage / 100.0
                            critical: Services.Sysmon.ramUsage > 85
                        }
                    }

                    // Row 2: Disk + Temp
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MetricCard {
                            iconGlyph: Services.Icons.disk
                            label: "Disk"
                            valueText: Services.Sysmon.diskUsedStr.length > 0
                                       ? Services.Sysmon.diskUsedStr + "/" + Services.Sysmon.diskTotalStr
                                       : Math.round(Services.Sysmon.diskUsage) + "%"
                            progress: Services.Sysmon.diskUsage / 100.0
                            critical: Services.Sysmon.diskUsage > 90
                        }

                        MetricCard {
                            iconGlyph: Services.Icons.temp
                            label: "Temp"
                            valueText: Math.round(Services.Sysmon.cpuTemp) + "°C"
                            progress: Math.min(1.0, Services.Sysmon.cpuTemp / 100.0)
                            critical: Services.Sysmon.cpuTemp > 75
                        }
                    }
                }

                // ── System Details Card ───────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: detailGrid.implicitHeight + 20
                    radius: Services.Theme.radiusMd
                    color: Services.Theme.surfaceVariant

                    GridLayout {
                        id: detailGrid
                        anchors.fill: parent
                        anchors.margins: 10
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                        // Kernel
                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.Icons.kernel
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: Services.Theme.accent
                            }
                            Text {
                                text: "Kernel"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                                font.bold: true
                            }
                            Text {
                                text: Services.OsInfo.kernel.length > 0 ? Services.OsInfo.kernel : "-"
                                font.pixelSize: 10
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Uptime
                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.Icons.uptime
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: Services.Theme.accent
                            }
                            Text {
                                text: "Uptime"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                                font.bold: true
                            }
                            Text {
                                text: Services.Sysmon.uptimeStr.length > 0 ? Services.Sysmon.uptimeStr : "-"
                                font.pixelSize: 10
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Shell
                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.Icons.shell
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: Services.Theme.accent
                            }
                            Text {
                                text: "Shell"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                                font.bold: true
                            }
                            Text {
                                text: Services.OsInfo.shellName.length > 0 ? Services.OsInfo.shellName : "-"
                                font.pixelSize: 10
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Power / Battery
                        RowLayout {
                            visible: Services.Power.ready && !isNaN(Services.Power.percentage) && Services.Power.percentage > 0
                            spacing: 6
                            Text {
                                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : Services.Theme.accent)
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }
                            Text {
                                text: "Power"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                                font.bold: true
                            }
                            Text {
                                text: Math.round(Services.Power.percentage * 100) + "%"
                                font.pixelSize: 10
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                // ── Wallpaper Picker Section ──────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Section header
                    RowLayout {
                        Layout.fillWidth: true

                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.Icons.image
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: Services.Theme.accent
                            }
                            Text {
                                text: "Wallpaper"
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.5
                                color: Services.Theme.textDisabled
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Upload custom button
                        Rectangle {
                            height: 24
                            implicitWidth: customBtnRow.implicitWidth + 14
                            radius: 12
                            color: customBtnMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                            border.color: customBtnMouse.containsMouse ? Services.Theme.borderHighlight : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                id: customBtnRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: Services.Wallpaper.isPicking ? Services.Icons.spinner : Services.Icons.plus
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: "Custom..."
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                            }

                            MouseArea {
                                id: customBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Wallpaper.pickCustomWallpaper()
                            }
                        }
                    }

                    // Wallpapers Carousel / Horizontal Scroll
                    Flickable {
                        Layout.fillWidth: true
                        implicitHeight: 68
                        contentWidth: wallRow.implicitWidth
                        contentHeight: 68
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        RowLayout {
                            id: wallRow
                            spacing: 8

                            Repeater {
                                model: Services.Wallpaper.allWallpapers

                                delegate: Rectangle {
                                    id: wallCard
                                    property var itemData: modelData
                                    property bool isActive: Services.Wallpaper.currentWallpaper === itemData.path

                                    width: 96
                                    height: 64
                                    radius: Services.Theme.radiusSm
                                    color: Services.Theme.surfaceVariant
                                    border.color: isActive ? Services.Theme.accent : (cardMouse.containsMouse ? Services.Theme.borderHighlight : Qt.rgba(1, 1, 1, 0.1))
                                    border.width: isActive ? 2 : 1
                                    clip: true

                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    // Wallpaper Image Preview
                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + itemData.path
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        mipmap: true
                                        opacity: cardMouse.containsMouse || isActive ? 1.0 : 0.82
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    // Dark gradient overlay for text readability
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                                        }
                                    }

                                    // Active Checkmark Badge
                                    Rectangle {
                                        visible: isActive
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 4
                                        width: 18; height: 18; radius: 9
                                        color: Services.Theme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.check
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 9
                                            color: "#ffffff"
                                        }
                                    }

                                    // Delete custom wallpaper button (on hover)
                                    Rectangle {
                                        visible: itemData.isCustom && cardMouse.containsMouse && !isActive
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 4
                                        width: 18; height: 18; radius: 9
                                        color: Qt.rgba(0, 0, 0, 0.7)

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.trash
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 9
                                            color: Services.Theme.danger
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Wallpaper.removeCustomWallpaper(itemData.path)
                                        }
                                    }

                                    // Wallpaper Name
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 6
                                        text: itemData.name
                                        font.pixelSize: 9
                                        font.bold: isActive
                                        color: isActive ? "#ffffff" : Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                    }

                                    MouseArea {
                                        id: cardMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Wallpaper.setWallpaper(itemData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Action Buttons ────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Lock Screen
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Services.Theme.radiusMd
                        color: lockMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: lockMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 7

                            Text {
                                text: Services.Icons.lock
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: lockMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Text {
                                text: "Lock Screen"
                                font.pixelSize: 11
                                font.bold: true
                                color: lockMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        MouseArea {
                            id: lockMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                lockProc.running = true
                            }
                        }
                    }

                    // Power Menu
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Services.Theme.radiusMd
                        color: pwrMouse.containsMouse ? Qt.rgba(0.54, 0.32, 0.32, 0.35) : Services.Theme.surfaceVariant
                        border.color: pwrMouse.containsMouse ? Services.Theme.danger : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 7

                            Text {
                                text: Services.Icons.power
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: Services.Theme.danger
                            }

                            Text {
                                text: "Power Menu"
                                font.pixelSize: 11
                                font.bold: true
                                color: pwrMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                        }

                        MouseArea {
                            id: pwrMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                pwrProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }

    Process { id: lockProc; command: ["sh", "-c", "qs ipc call lockscreen lock || hyprlock || swaylock"] }
    Process { id: pwrProc; command: ["quickshell", "ipc", "call", "powermenu", "open"] }
}
