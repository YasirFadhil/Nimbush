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
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    // Tab state if user enabled "both" widgets
    property int currentWidgetTab: 0 // 0 = Weather, 1 = Wallpaper

    visible: false

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell:dashboard"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    Component.onCompleted: Services.OverlayManager.register(root)

    function show() {
        Services.OverlayManager.closeAllExcept(root)
        hideTimer.stop()
        visible = true
        isOpen = true
        keyFocus.forceActiveFocus()
        if (Services.Weather) {
            // If weather data is older or empty, refresh
            if (!Services.Weather.isReady || !Services.Weather.lastUpdated) {
                Services.Weather.refresh()
            }
        }
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

    // Dynamic greeting calculation
    function getGreeting() {
        const hour = new Date().getHours()
        if (hour >= 5 && hour < 12) return "Good morning"
        if (hour >= 12 && hour < 17) return "Good afternoon"
        if (hour >= 17 && hour < 22) return "Good evening"
        return "Good night"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        // ── Main Dashboard Floating Window ───────────────────────────────────
        Rectangle {
            id: panel
            anchors.left: parent.left
            anchors.leftMargin: 16
            y: root.isBottom ? (parent.height - height - 12) : 12
            width: 375
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

                // ── 1. Modern Profile & Greeting Header ──────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // User Profile Avatar with shape & online status dot
                    Item {
                        id: dashboardAvatarItem
                        width: 44
                        height: 44

                        readonly property string avatarShape: Services.Config ? Services.Config.lockscreenAvatarShape : "squircle"
                        readonly property real avatarRadius: {
                            if (avatarShape === "circle") return width / 2
                            if (avatarShape === "squircle") return 12
                            return 8
                        }

                        Services.AvatarFrame {
                            anchors.fill: parent
                            source: Services.OsInfo.avatarPath
                            shapeRadius: dashboardAvatarItem.avatarRadius
                            backgroundColor: Services.Theme.surfaceVariant
                            borderColor: (Services.Config && Services.Config.lockscreenAvatarRing) ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4) : Services.Theme.border
                            borderWidth: 1.5
                            fallbackText: {
                                const u = (Services.OsInfo.username || Quickshell.env("USER") || "user").toUpperCase()
                                return u.length > 0 ? u.charAt(0) : "󰌽"
                            }
                            fallbackFontFamily: Services.Theme.fontDisplay || Services.Theme.fontSymbols
                            fallbackFontSize: 18
                            fallbackColor: Services.Theme.accent
                        }

                        // Live status dot
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 1
                            width: 10
                            height: 10
                            radius: 5
                            color: Services.Theme.success
                            border.color: Services.Theme.bgElevated
                            border.width: 1.5
                        }
                    }

                    // User Identity & Dynamic Greeting
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: root.getGreeting() + ", " + (Services.OsInfo.username ? (Services.OsInfo.username.charAt(0).toUpperCase() + Services.OsInfo.username.slice(1)) : "User")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Services.Theme.textPrimary
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            spacing: 6

                            // Distro Badge
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: distroBadgeRow.implicitWidth + 10
                                radius: 9
                                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12)
                                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25)
                                border.width: 1

                                RowLayout {
                                    id: distroBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: Services.OsInfo.distroName || "Linux"
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                        color: Services.Theme.accent
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Text {
                                text: "@" + (Services.OsInfo.hostname || "local")
                                font.pixelSize: 10
                                color: Services.Theme.textSecondary
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Header Action Buttons
                    RowLayout {
                        spacing: 4

                        // Refresh Button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 7
                            color: refBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 180 } }

                            Text {
                                id: refIcon
                                anchors.centerIn: parent
                                text: Services.Icons.refresh
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: refBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                                transformOrigin: Item.Center
                                RotationAnimation on rotation {
                                    running: Services.Weather ? Services.Weather.isLoading : false
                                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                }
                            }

                            MouseArea {
                                id: refBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Services.Weather) Services.Weather.refresh()
                                }
                            }
                        }

                        // Settings Button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 7
                            color: setBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 180 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.settings
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
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

                        // Close Button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 7
                            color: closeBtnArea.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"
                            Behavior on color { ColorAnimation { duration: 180 } }

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
                    opacity: 0.5
                }

                // ── 2. Hardware Metrics Grid (2x2) ───────────────────────────
                GridLayout {
                    visible: Services.Config ? Services.Config.dashboardShowMetrics : true
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    component ModernMetricCard: Rectangle {
                        id: cardRoot
                        property string icon: ""
                        property string name: ""
                        property string value: ""
                        property real ratio: 0.0
                        property color barColor: Services.Theme.accent

                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: Services.Theme.radiusSm
                        color: metricMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: metricMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 180 } }

                        MouseArea {
                            id: metricMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Icon Pill
                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 5
                                    color: Qt.rgba(cardRoot.barColor.r, cardRoot.barColor.g, cardRoot.barColor.b, 0.15)

                                    Text {
                                        anchors.centerIn: parent
                                        text: cardRoot.icon
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 10
                                        color: cardRoot.barColor
                                    }
                                }

                                Text {
                                    text: cardRoot.name
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: Services.Theme.textSecondary
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: cardRoot.value
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Services.Theme.textPrimary
                                }
                            }

                            // Meter Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 4
                                radius: 2
                                color: Qt.rgba(Services.Theme.textPrimary.r, Services.Theme.textPrimary.g, Services.Theme.textPrimary.b, 0.08)
                                clip: true

                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * cardRoot.ratio))
                                    radius: parent.radius
                                    color: cardRoot.barColor
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    ModernMetricCard {
                        icon: Services.Icons.cpu
                        name: "CPU"
                        value: Math.round(Services.Sysmon.cpuUsage) + "%"
                        ratio: Services.Sysmon.cpuUsage / 100.0
                        barColor: Services.Sysmon.cpuUsage > 80 ? Services.Theme.danger : Services.Theme.accent
                    }

                    ModernMetricCard {
                        icon: Services.Icons.ram
                        name: "RAM"
                        value: Services.Sysmon.ramDetailStr || Services.Sysmon.ramUsedStr || (Math.round(Services.Sysmon.ramUsage) + "%")
                        ratio: Services.Sysmon.ramUsage / 100.0
                        barColor: Services.Sysmon.ramUsage > 85 ? Services.Theme.danger : Services.Theme.accent
                    }

                    ModernMetricCard {
                        icon: Services.Icons.disk
                        name: "Disk"
                        value: Services.Sysmon.diskDetailStr || Services.Sysmon.diskUsedStr || (Math.round(Services.Sysmon.diskUsage) + "%")
                        ratio: Services.Sysmon.diskUsage / 100.0
                        barColor: Services.Sysmon.diskUsage > 90 ? Services.Theme.danger : Services.Theme.accent
                    }

                    ModernMetricCard {
                        icon: Services.Icons.temp
                        name: "Temp"
                        value: Math.round(Services.Sysmon.cpuTemp) + "°C"
                        ratio: Math.min(1.0, Services.Sysmon.cpuTemp / 100.0)
                        barColor: Services.Sysmon.cpuTemp > 75 ? Services.Theme.danger : Services.Theme.accent
                    }
                }

                // ── 3. Minimal Specs Bar ─────────────────────────────────────
                Rectangle {
                    visible: Services.Config ? Services.Config.dashboardShowSpecs : true
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Services.Theme.radiusSm
                    color: Services.Theme.surfaceVariant
                    border.color: Services.Theme.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
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

                // ── 4. Main Widget Section: Weather / Wallpaper Switcher ─────
                // Tab bar if mode is "both"
                RowLayout {
                    visible: Services.Config && Services.Config.dashboardWidget === "both"
                    Layout.fillWidth: true
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 6
                        color: root.currentWidgetTab === 0 ? Services.Theme.accent : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "Weather"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: root.currentWidgetTab === 0 ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentWidgetTab = 0
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 6
                        color: root.currentWidgetTab === 1 ? Services.Theme.accent : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "Wallpaper"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: root.currentWidgetTab === 1 ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentWidgetTab = 1
                        }
                    }
                }

                // ── 4A. Weather Widget Card ───────────────────────────────────
                Rectangle {
                    id: weatherCard
                    visible: (Services.Config && Services.Config.dashboardWidget === "wallpaper")
                             ? false
                             : (Services.Config && Services.Config.dashboardWidget === "both" ? (root.currentWidgetTab === 0) : true)

                    Layout.fillWidth: true
                    implicitHeight: weatherCol.implicitHeight + 18
                    radius: Services.Theme.radiusMd
                    color: Services.Theme.surfaceVariant
                    border.color: Services.Theme.border
                    border.width: 1

                    ColumnLayout {
                        id: weatherCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Top Row: Location & Condition Pill
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // Location Icon & City
                            Text {
                                text: Services.Icons.location
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                                color: Services.Theme.accent
                            }

                            Text {
                                text: (Services.Weather ? Services.Weather.city : "Local City") + (Services.Weather && Services.Weather.country ? (", " + Services.Weather.country) : "")
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            // Condition Badge
                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: condTxt.implicitWidth + 12
                                radius: 9
                                color: Qt.rgba(
                                    Services.Weather ? Services.Weather.weatherColor.r : 0.2,
                                    Services.Weather ? Services.Weather.weatherColor.g : 0.6,
                                    Services.Weather ? Services.Weather.weatherColor.b : 0.9,
                                    0.15
                                )
                                border.color: Qt.rgba(
                                    Services.Weather ? Services.Weather.weatherColor.r : 0.2,
                                    Services.Weather ? Services.Weather.weatherColor.g : 0.6,
                                    Services.Weather ? Services.Weather.weatherColor.b : 0.9,
                                    0.3
                                )
                                border.width: 1

                                Text {
                                    id: condTxt
                                    anchors.centerIn: parent
                                    text: Services.Weather ? Services.Weather.condition : "Clear"
                                    font.pixelSize: 9
                                    font.weight: Font.Medium
                                    color: Services.Weather ? Services.Weather.weatherColor : Services.Theme.accent
                                }
                            }
                        }

                        // Middle Row: Big Temp Display + Animated Weather Icon + Feels Like
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            // Big Temp
                            ColumnLayout {
                                spacing: 0
                                RowLayout {
                                    spacing: 2
                                    Text {
                                        text: Services.Weather ? (Services.Weather.temp + "°") : "--°"
                                        font.pixelSize: 28
                                        font.weight: Font.Bold
                                        color: Services.Theme.textPrimary
                                    }
                                }

                                Text {
                                    text: "Feels like " + (Services.Weather ? Services.Weather.feelsLikeStr : "--°")
                                    font.pixelSize: 10
                                    color: Services.Theme.textSecondary
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Weather Icon Pill
                            Rectangle {
                                width: 44
                                height: 44
                                radius: 22
                                color: Qt.rgba(
                                    Services.Weather ? Services.Weather.weatherColor.r : 0.2,
                                    Services.Weather ? Services.Weather.weatherColor.g : 0.6,
                                    Services.Weather ? Services.Weather.weatherColor.b : 0.9,
                                    0.15
                                )
                                border.color: Qt.rgba(
                                    Services.Weather ? Services.Weather.weatherColor.r : 0.2,
                                    Services.Weather ? Services.Weather.weatherColor.g : 0.6,
                                    Services.Weather ? Services.Weather.weatherColor.b : 0.9,
                                    0.3
                                )
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Weather ? Services.Weather.icon : "󰖙"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 22
                                    color: Services.Weather ? Services.Weather.weatherColor : Services.Theme.accent
                                }
                            }
                        }

                        // Micro Stats Row (Humidity, Wind, High/Low)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: 6
                            color: Qt.rgba(Services.Theme.textPrimary.r, Services.Theme.textPrimary.g, Services.Theme.textPrimary.b, 0.04)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Humidity
                                RowLayout {
                                    spacing: 3
                                    Text {
                                        text: Services.Icons.droplet || "\uf043"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 9
                                        color: "#38bdf8"
                                    }
                                    Text {
                                        text: Services.Weather ? Services.Weather.humidityStr : "--%"
                                        font.pixelSize: 9
                                        color: Services.Theme.textPrimary
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Wind
                                RowLayout {
                                    spacing: 3
                                    Text {
                                        text: Services.Icons.wind || "󰖝"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 10
                                        color: "#a1a1aa"
                                    }
                                    Text {
                                        text: Services.Weather ? Services.Weather.windSpeedStr : "--"
                                        font.pixelSize: 9
                                        color: Services.Theme.textPrimary
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // High / Low
                                RowLayout {
                                    spacing: 3
                                    Text {
                                        text: "↕"
                                        font.pixelSize: 9
                                        color: Services.Theme.accent
                                    }
                                    Text {
                                        text: Services.Weather ? Services.Weather.tempMinMaxStr : "--° / --°"
                                        font.pixelSize: 9
                                        color: Services.Theme.textPrimary
                                    }
                                }
                            }
                        }

                        // 3-Day Forecast Mini Strip
                        RowLayout {
                            visible: Services.Weather && Services.Weather.forecast && Services.Weather.forecast.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: Services.Weather ? Services.Weather.forecast.slice(0, 3) : []

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: 6
                                    color: Qt.rgba(Services.Theme.textPrimary.r, Services.Theme.textPrimary.g, Services.Theme.textPrimary.b, 0.03)
                                    border.color: Services.Theme.borderSubtle
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            text: modelData.day
                                            font.pixelSize: 8
                                            font.weight: Font.Medium
                                            color: Services.Theme.textSecondary
                                        }

                                        Text {
                                            text: Services.Weather ? Services.Weather.getIcon(modelData.code, true) : "󰖙"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            color: Services.Weather ? Services.Weather.getColor(modelData.code, true) : Services.Theme.accent
                                        }

                                        Text {
                                            text: modelData.tempRange || (modelData.tempMin + "° / " + modelData.tempMax + "°")
                                            font.pixelSize: 8
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── 4B. Wallpaper Strip (if configured) ───────────────────────
                ColumnLayout {
                    id: wallpaperSection
                    visible: (Services.Config && Services.Config.dashboardWidget === "weather")
                             ? false
                             : (Services.Config && Services.Config.dashboardWidget === "both" ? (root.currentWidgetTab === 1) : true)

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
                    visible: Services.Config ? Services.Config.dashboardShowActions : true
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
                        Behavior on color { ColorAnimation { duration: 180 } }

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
                        Behavior on color { ColorAnimation { duration: 180 } }

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
                        Behavior on color { ColorAnimation { duration: 180 } }

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
