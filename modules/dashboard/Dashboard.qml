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
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false

    visible: false

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
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

        // ── Main Dashboard Floating Window ───────────────────────────────────
        Rectangle {
            id: panel
            anchors.left: parent.left
            anchors.leftMargin: 16
            y: root.isBottom ? (parent.height - height - 16) : 16
            width: 350
            implicitHeight: mainCol.implicitHeight + 28

            radius: Services.Theme.radiusLg
            color: Services.Theme.bgElevated
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : (root.isBottom ? 24 : -24)
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            scale: root.isOpen ? 1 : 0.97
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            // ── Main Content Column ──────────────────────────────────────────
            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // ── 1. Profile Header ─────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Avatar / Distro Glyph
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 19
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1
                        antialiasing: true
                        smooth: true

                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            anchors.margins: 1
                            source: Services.OsInfo.avatarPath
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(76, 76)
                            visible: false
                            smooth: true
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
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: "black"
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImg.status !== Image.Ready
                            text: Services.OsInfo.logoGlyph || "\uf17c"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 18
                            color: Services.Theme.accent
                        }
                    }

                    // User Identity
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        RowLayout {
                            spacing: 6
                            Text {
                                text: Services.OsInfo.username || "User"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "·"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                            }

                            Text {
                                text: Services.OsInfo.distroName || "Linux"
                                font.pixelSize: 10
                                color: Services.Theme.accent
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: "@" + (Services.OsInfo.hostname || "local")
                            font.pixelSize: 10
                            color: Services.Theme.textSecondary
                        }
                    }

                    // Settings & Close Actions
                    RowLayout {
                        spacing: 4

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 6
                            color: setBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.settings
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: setBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            }

                            MouseArea {
                                id: setBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.close()
                                    Services.OverlayManager.openSettings()
                                }
                            }
                        }

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 6
                            color: closeBtnArea.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.12) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                font.pixelSize: 16
                                font.bold: true
                                color: closeBtnArea.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
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
                }

                // ── Divider ──────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.6
                }

                // ── 2. Minimal Metrics Grid ──────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    component MinimalMetric: Rectangle {
                        id: mmRoot
                        property string icon: ""
                        property string name: ""
                        property string value: ""
                        property real ratio: 0.0
                        property color barColor: Services.Theme.accent

                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: Services.Theme.radiusSm
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    text: mmRoot.icon
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: mmRoot.barColor
                                }

                                Text {
                                    text: mmRoot.name
                                    font.pixelSize: 10
                                    color: Services.Theme.textSecondary
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: mmRoot.value
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 3
                                radius: 1.5
                                color: Qt.rgba(Services.Theme.textPrimary.r, Services.Theme.textPrimary.g, Services.Theme.textPrimary.b, 0.08)
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * mmRoot.ratio))
                                    radius: parent.radius
                                    color: mmRoot.barColor
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    MinimalMetric {
                        icon: Services.Icons.cpu
                        name: "CPU"
                        value: Math.round(Services.Sysmon.cpuUsage) + "%"
                        ratio: Services.Sysmon.cpuUsage / 100.0
                        barColor: Services.Sysmon.cpuUsage > 80 ? Services.Theme.danger : Services.Theme.accent
                    }

                    MinimalMetric {
                        icon: Services.Icons.ram
                        name: "RAM"
                        value: Services.Sysmon.ramUsedStr || (Math.round(Services.Sysmon.ramUsage) + "%")
                        ratio: Services.Sysmon.ramUsage / 100.0
                        barColor: Services.Sysmon.ramUsage > 85 ? Services.Theme.danger : Services.Theme.accent
                    }

                    MinimalMetric {
                        icon: Services.Icons.disk
                        name: "Disk"
                        value: Services.Sysmon.diskUsedStr || (Math.round(Services.Sysmon.diskUsage) + "%")
                        ratio: Services.Sysmon.diskUsage / 100.0
                        barColor: Services.Sysmon.diskUsage > 90 ? Services.Theme.danger : Services.Theme.accent
                    }

                    MinimalMetric {
                        icon: Services.Icons.temp
                        name: "Temp"
                        value: Math.round(Services.Sysmon.cpuTemp) + "°C"
                        ratio: Math.min(1.0, Services.Sysmon.cpuTemp / 100.0)
                        barColor: Services.Sysmon.cpuTemp > 75 ? Services.Theme.danger : Services.Theme.accent
                    }
                }

                // ── 3. Minimal Specs Bar ─────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: Services.Theme.radiusSm
                    color: Services.Theme.surfaceVariant
                    border.color: Services.Theme.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: Services.Icons.uptime
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: Services.Theme.accent
                        }
                        Text {
                            text: Services.Sysmon.uptimeStr || "0m"
                            font.pixelSize: 9
                            color: Services.Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }
                        Text { text: "·"; font.pixelSize: 9; color: Services.Theme.textDisabled }
                        Item { Layout.fillWidth: true }

                        Text {
                            text: Services.Icons.kernel
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: Services.Theme.accent
                        }
                        Text {
                            text: (Services.OsInfo.kernel ? Services.OsInfo.kernel.split("-")[0] : "Linux")
                            font.pixelSize: 9
                            color: Services.Theme.textPrimary
                        }

                        Item { Layout.fillWidth: true }
                        Text { text: "·"; font.pixelSize: 9; color: Services.Theme.textDisabled }
                        Item { Layout.fillWidth: true }

                        Text {
                            text: Services.Icons.shell
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: Services.Theme.accent
                        }
                        Text {
                            text: Services.OsInfo.shellName || "sh"
                            font.pixelSize: 9
                            color: Services.Theme.textPrimary
                        }

                        Item {
                            visible: Services.Power.ready && !isNaN(Services.Power.percentage)
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: Services.Power.ready && !isNaN(Services.Power.percentage)
                            text: "·"
                            font.pixelSize: 9
                            color: Services.Theme.textDisabled
                        }
                        Item {
                            visible: Services.Power.ready && !isNaN(Services.Power.percentage)
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: Services.Power.ready && !isNaN(Services.Power.percentage)
                            text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: Services.Power.charging ? Services.Theme.success : Services.Theme.accent
                        }
                        Text {
                            visible: Services.Power.ready && !isNaN(Services.Power.percentage)
                            text: Math.round(Services.Power.percentage * 100) + "%"
                            font.pixelSize: 9
                            color: Services.Theme.textPrimary
                        }
                    }
                }

                // ── 4. Wallpaper Strip ───────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Wallpaper"
                            font.pixelSize: 10
                            font.bold: true
                            color: Services.Theme.textSecondary
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitHeight: 18
                            implicitWidth: addTxt.implicitWidth + 10
                            radius: 4
                            color: addMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                            border.color: Services.Theme.border
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: "+"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Theme.accent
                                }
                                Text {
                                    id: addTxt
                                    text: "Custom"
                                    font.pixelSize: 9
                                    color: Services.Theme.textPrimary
                                }
                            }

                            MouseArea {
                                id: addMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Wallpaper.pickCustomWallpaper()
                            }
                        }
                    }

                    // Wallpapers Carousel
                    Flickable {
                        Layout.fillWidth: true
                        implicitHeight: 52
                        contentWidth: wallRow.implicitWidth
                        contentHeight: 52
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        RowLayout {
                            id: wallRow
                            spacing: 6

                            Repeater {
                                model: Services.Wallpaper.allWallpapers

                                delegate: Rectangle {
                                    id: wallCard
                                    property var itemData: modelData
                                    property bool isActive: Services.Wallpaper.currentWallpaper === itemData.path

                                    width: 78
                                    height: 50
                                    radius: Services.Theme.radiusSm
                                    color: Services.Theme.surfaceVariant
                                    border.color: isActive ? Services.Theme.accent : (wMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                    border.width: isActive ? 2 : 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + itemData.path
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize: Qt.size(140, 80)
                                        smooth: true
                                        opacity: isActive || wMouse.containsMouse ? 1.0 : 0.7
                                    }

                                    // Active checkmark badge
                                    Rectangle {
                                        visible: isActive
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 3
                                        width: 14; height: 14; radius: 7
                                        color: Services.Theme.accent

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.check
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 7
                                            color: Services.Theme.bgOnAccent
                                        }
                                    }

                                    // Name Label
                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 4
                                        text: itemData.name
                                        font.pixelSize: 8
                                        font.bold: isActive
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                        style: Text.Outline
                                        styleColor: Qt.rgba(0, 0, 0, 0.8)
                                    }

                                    MouseArea {
                                        id: wMouse
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

                // ── 5. Minimal Quick Session Actions ─────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Lock Button
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Services.Theme.radiusSm
                        color: lockActionMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: lockActionMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: Services.Icons.lock
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                text: "Lock"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Services.Theme.textPrimary
                            }
                        }

                        MouseArea {
                            id: lockActionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                lockProc.running = true
                            }
                        }
                    }

                    // Reload Shell Button
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Services.Theme.radiusSm
                        color: reloadActionMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: reloadActionMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: Services.Icons.refresh
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                                color: Services.Theme.textPrimary
                            }
                            Text {
                                text: "Reload"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Services.Theme.textPrimary
                            }
                        }

                        MouseArea {
                            id: reloadActionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                reloadProc.running = true
                            }
                        }
                    }

                    // Power Menu Button
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Services.Theme.radiusSm
                        color: pwrActionMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.12) : Services.Theme.surfaceVariant
                        border.color: pwrActionMouse.containsMouse ? Services.Theme.danger : Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: Services.Icons.power
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                                color: Services.Theme.danger
                            }
                            Text {
                                text: "Power"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Services.Theme.danger
                            }
                        }

                        MouseArea {
                            id: pwrActionMouse
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
    Process { id: reloadProc; command: ["quickshell", "ipc", "call", "shell", "reload"] }
}
