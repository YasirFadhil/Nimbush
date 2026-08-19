import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

FloatingWindow {
    id: rootWindow
    title: "Settings - Quickshell Desktop"
    visible: false
    implicitWidth: 920
    implicitHeight: 660
    color: Services.Theme.bg

    property int currentTab: 0
    property string confirmResetMode: "" // "" | "settings" | "full"

    onVisibleChanged: {
        if (!visible) {
            confirmResetMode = ""
        } else {
            keyFocus.forceActiveFocus()
            if (Services.Compositor) {
                Services.Compositor.refreshState()
            }
        }
    }

    function show() {
        visible = false
        visible = true
        confirmResetMode = ""
        keyFocus.forceActiveFocus()
        if (Services.Wallpaper && Services.Config) {
            Services.Config.generateMatugen(Services.Wallpaper.currentWallpaper)
        }
        if (Services.Compositor) {
            Services.Compositor.refreshState()
        }
    }

    function hide() {
        visible = false
        confirmResetMode = ""
    }

    function toggle() {
        if (visible) {
            hide()
        } else {
            show()
        }
    }

    Item {
        id: keyFocus
        focus: rootWindow.visible
        Keys.onEscapePressed: rootWindow.hide()
        Keys.onTabPressed: (event) => {
            rootWindow.currentTab = (rootWindow.currentTab + 1) % 8
            event.accepted = true
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // REUSABLE MODERN SETTINGS CONTROLS & OVERVIEW SELECTORS
    // ═════════════════════════════════════════════════════════════════════════

    // ── 1. Settings Switch (Modern iOS / macOS Toggle with Fixed-Width Icon Box)
    component SettingsSwitch: Rectangle {
        id: switchRoot
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        signal toggled(bool newState)

        Layout.fillWidth: true
        implicitHeight: Math.max(50, switchRow.implicitHeight + 14)
        radius: Services.Theme.radiusSm
        color: switchMouse.containsMouse ? Services.Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

        RowLayout {
            id: switchRow
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 12

            // Uniform 32x32 Icon Container for aligned text starts
            Rectangle {
                visible: switchRoot.icon.length > 0
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: 8
                color: switchRoot.checked ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) : Services.Theme.bgElevated
                border.color: switchRoot.checked ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3) : Services.Theme.border
                border.width: 1
                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: switchRoot.icon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 14
                    color: switchRoot.checked ? Services.Theme.accent : Services.Theme.textSecondary
                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
            }

            // Title + Subtitle Column
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: switchRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.bold: true
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }
                Text {
                    visible: switchRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: switchRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            // Switch Toggle Capsule
            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                radius: 12
                color: switchRoot.checked ? Services.Theme.accent : Services.Theme.bgElevated
                border.color: switchRoot.checked ? Services.Theme.accent : Services.Theme.border
                border.width: 1
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    y: 2
                    x: switchRoot.checked ? 23 : 3
                    color: switchRoot.checked ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }

        MouseArea {
            id: switchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: switchRoot.toggled(!switchRoot.checked)
        }
    }

    // ── 2. Settings Slider (Continuous & Stepped with Live Thumb & Track) ──────
    component SettingsSlider: ColumnLayout {
        id: sliderRoot
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real value: 0
        property string valuePrefix: ""
        property string valueSuffix: ""
        property int decimals: 0
        signal moved(real newValue)

        Layout.fillWidth: true
        spacing: 8

        // Header Row: Uniform Icon + Title + Value Badge Pill
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                visible: sliderRoot.icon.length > 0
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: 8
                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: sliderRoot.icon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 14
                    color: Services.Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: sliderRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.bold: true
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }
                Text {
                    visible: sliderRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: sliderRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredHeight: 24
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: valText.implicitWidth + 18
                radius: 12
                color: Services.Theme.bgElevated
                border.color: Services.Theme.border
                border.width: 1

                Text {
                    id: valText
                    anchors.centerIn: parent
                    text: sliderRoot.valuePrefix + (sliderRoot.decimals > 0 ? Number(sliderRoot.value).toFixed(sliderRoot.decimals) : Math.round(sliderRoot.value)) + sliderRoot.valueSuffix
                    font.family: Services.Theme.fontMono
                    font.pixelSize: Services.Theme.fontSizeXs
                    font.bold: true
                    color: Services.Theme.accent
                }
            }
        }

        // Interactive Track & Thumb
        Item {
            id: trackContainer
            Layout.fillWidth: true
            height: 24

            Rectangle {
                id: bgTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 6
                radius: 3
                color: Services.Theme.bgDeep
                border.color: Services.Theme.border
                border.width: 1

                Rectangle {
                    id: activeTrack
                    height: parent.height
                    radius: parent.radius
                    color: Services.Theme.accent
                    width: Math.max(0, Math.min(parent.width, ((sliderRoot.value - sliderRoot.from) / Math.max(0.0001, sliderRoot.to - sliderRoot.from)) * parent.width))
                }
            }

            Rectangle {
                id: thumb
                width: 18
                height: 18
                radius: 9
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(trackContainer.width - width, ((sliderRoot.value - sliderRoot.from) / Math.max(0.0001, sliderRoot.to - sliderRoot.from)) * (trackContainer.width - width)))
                color: sliderDragArea.pressed ? Services.Theme.accent : Services.Theme.bgElevated
                border.color: Services.Theme.accent
                border.width: 2

                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: sliderDragArea.pressed ? Services.Theme.bgOnAccent : Services.Theme.accent
                }
            }

            MouseArea {
                id: sliderDragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function updateVal(mouseX) {
                    const ratio = Math.max(0, Math.min(1, mouseX / width))
                    let raw = sliderRoot.from + ratio * (sliderRoot.to - sliderRoot.from)
                    if (sliderRoot.stepSize > 0) {
                        raw = Math.round((raw - sliderRoot.from) / sliderRoot.stepSize) * sliderRoot.stepSize + sliderRoot.from
                    }
                    raw = Math.max(sliderRoot.from, Math.min(sliderRoot.to, raw))
                    sliderRoot.moved(raw)
                }

                onPressed: (mouse) => updateVal(mouse.x)
                onPositionChanged: (mouse) => {
                    if (pressed) updateVal(mouse.x)
                }
            }
        }
    }

    // ── 3. Settings Segmented Overview (Visual Card Switcher) ─────────────────
    component SettingsSegmentedOverview: ColumnLayout {
        id: segRoot
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property var model: [] // [{ id, label, icon?, desc? }]
        property var currentValue: null
        signal selected(var val)

        Layout.fillWidth: true
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                visible: segRoot.icon.length > 0
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                radius: 8
                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: segRoot.icon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 14
                    color: Services.Theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: segRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.bold: true
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }
                Text {
                    visible: segRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: segRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }
        }

        // Horizontal Overview Cards
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: segRoot.model
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: modelData.desc ? 58 : 44
                    radius: Services.Theme.radiusSm
                    readonly property bool isCur: segRoot.currentValue === modelData.id

                    color: isCur 
                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) 
                        : (cardHover.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated)
                    border.color: isCur 
                        ? Services.Theme.accent 
                        : (cardHover.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                    border.width: isCur ? 2 : 1
                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        // Icon badge
                        Rectangle {
                            visible: Boolean(modelData.icon)
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter
                            radius: 6
                            color: isCur ? Services.Theme.accent : (cardHover.containsMouse ? Services.Theme.bgHover : Services.Theme.bgDeep)
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon || ""
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: isCur ? Services.Theme.bgOnAccent : (cardHover.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label || ""
                                font.pixelSize: Services.Theme.fontSizeSm
                                font.bold: isCur
                                color: isCur ? Services.Theme.textPrimary : (cardHover.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                visible: Boolean(modelData.desc)
                                Layout.fillWidth: true
                                text: modelData.desc || ""
                                font.pixelSize: 9
                                color: Services.Theme.textDisabled
                                elide: Text.ElideRight
                            }
                        }

                        // Check indicator
                        Rectangle {
                            opacity: isCur ? 1.0 : 0.0
                            scale: isCur ? 1.0 : 0.6
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            radius: 10
                            color: Services.Theme.accent
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.check
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 9
                                color: Services.Theme.bgOnAccent
                            }
                        }
                    }

                    MouseArea {
                        id: cardHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: segRoot.selected(modelData.id)
                    }
                }
            }
        }
    }

    // ── 4. Card Container Component ──────────────────────────────────────────
    component SettingsCard: Rectangle {
        Layout.fillWidth: true
        radius: Services.Theme.radiusMd
        color: Services.Theme.surfaceVariant
        border.color: Services.Theme.border
        border.width: 1
    }

    // ── 5. Clean Card Item Divider ───────────────────────────────────────────
    component SettingsDivider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Qt.rgba(1, 1, 1, 0.05)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // MAIN SETTINGS WINDOW LAYOUT
    // ═════════════════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        color: Services.Theme.bg
        radius: Services.Theme.radiusLg
        clip: true
        border.color: Services.Theme.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── TOP TITLE BAR ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: Services.Theme.surfaceVariant
                border.color: Services.Theme.border
                border.width: 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Services.Theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Traffic Light Window Buttons
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: "#ff5f56"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootWindow.hide()
                            }
                        }
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: "#ffbd2e"
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootWindow.hide()
                            }
                        }
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: "#27c93f"
                        }
                    }

                    Item { Layout.preferredWidth: 12 }

                    Text {
                        text: Services.Icons.settings
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 14
                        color: Services.Theme.accent
                    }

                    Text {
                        text: "System Settings"
                        font.family: Services.Theme.fontDisplay
                        font.pixelSize: Services.Theme.fontSizeMd
                        font.bold: true
                        color: Services.Theme.textPrimary
                    }

                    Text {
                        text: "•"
                        font.pixelSize: 10
                        color: Services.Theme.textDisabled
                    }

                    Text {
                        text: {
                            const tabs = ["Appearance", "Bar & Island", "Notifications", "Sound & Audio", "Lock & Power", "Compositor", "Backup & Reset", "About & Keys"]
                            return tabs[rootWindow.currentTab] || "Overview"
                        }
                        font.pixelSize: Services.Theme.fontSizeSm
                        color: Services.Theme.accent
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    // Close Button Icon
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: closeMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: closeMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootWindow.hide()
                        }
                    }
                }
            }

            // ── MAIN BODY (SIDEBAR + CONTENT) ────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ── SIDEBAR NAVIGATION ───────────────────────────────────────
                Rectangle {
                    Layout.preferredWidth: 230
                    Layout.fillHeight: true
                    color: Services.Theme.surfaceVariant

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Services.Theme.border
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        ListView {
                            id: tabList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4
                            clip: true
                            interactive: false

                            model: [
                                { id: 0, title: "Appearance",  sub: "Wallpaper & Colors", icon: Services.Icons.palette },
                                { id: 1, title: "Bar & Island", sub: "Widgets & HUD",    icon: Services.Icons.controlcenter },
                                { id: 2, title: "Notifications",sub: "Alerts & Timing",  icon: Services.Icons.bell },
                                { id: 3, title: "Sound & Audio",sub: "Feedback sounds",  icon: Services.Icons.speaker },
                                { id: 4, title: "Lock & Power", sub: "Screen & battery", icon: Services.Icons.power },
                                { id: 5, title: "Compositor",   sub: "Hyprland & Window",icon: Services.Icons.display },
                                { id: 6, title: "Backup & Reset",sub: "Restore defaults", icon: Services.Icons.undo },
                                { id: 7, title: "About & Keys", sub: "System & guide",   icon: Services.Icons.info }
                            ]

                            delegate: Rectangle {
                                width: tabList.width
                                height: 44
                                radius: Services.Theme.radiusSm
                                readonly property bool isSelected: rootWindow.currentTab === modelData.id

                                color: isSelected 
                                    ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                    : (itemMouse.containsMouse ? Services.Theme.bgHover : "transparent")
                                border.color: isSelected ? Services.Theme.accent : (itemMouse.containsMouse ? Services.Theme.borderSubtle : "transparent")
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 6
                                        color: isSelected ? Services.Theme.accent : (itemMouse.containsMouse ? Services.Theme.bgElevated : Services.Theme.surfaced)
                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 12
                                            color: isSelected ? Services.Theme.bgOnAccent : (itemMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            font.bold: isSelected
                                            color: isSelected ? Services.Theme.textPrimary : (itemMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                            elide: Text.ElideRight
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.sub
                                            font.pixelSize: 9
                                            color: Services.Theme.textDisabled
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        opacity: isSelected ? 1.0 : 0.0
                                        scale: isSelected ? 1.0 : 0.4
                                        Layout.preferredWidth: 3
                                        Layout.preferredHeight: 14
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 2
                                        color: Services.Theme.accent
                                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rootWindow.currentTab = modelData.id
                                }
                            }
                        }
                    }
                }

                // ── RIGHT CONTENT VIEW ───────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Services.Theme.bg
                    clip: true

                    Flickable {
                        id: contentFlick
                        anchors.fill: parent
                        anchors.margins: 18
                        contentHeight: contentCol.implicitHeight + 40
                        contentWidth: width
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        ColumnLayout {
                            id: contentCol
                            width: contentFlick.width - 12
                            spacing: 16

                            // ─────────────────────────────────────────────────
                            // PAGE 0: APPEARANCE, WALLPAPER & THEMING
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 0
                                Layout.fillWidth: true
                                spacing: 14

                                // Wallpaper Gallery Card
                                SettingsCard {
                                    implicitHeight: wallCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: wallCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 2
                                                Text {
                                                    text: "Wallpaper & Background"
                                                    font.pixelSize: Services.Theme.fontSizeLg
                                                    font.bold: true
                                                    color: Services.Theme.textPrimary
                                                }
                                                Text {
                                                    text: "Select desktop wallpaper or add custom images"
                                                    font.pixelSize: Services.Theme.fontSizeXs
                                                    color: Services.Theme.textSecondary
                                                }
                                            }

                                            // + Add Wallpaper Button
                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                height: 32
                                                implicitWidth: addWpText.implicitWidth + 24
                                                radius: Services.Theme.radiusSm
                                                color: addWpMouse.containsMouse ? Services.Theme.accent : Services.Theme.bgElevated
                                                border.color: addWpMouse.containsMouse ? Services.Theme.accent : Services.Theme.border
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text {
                                                        text: Services.Icons.plus
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 11
                                                        color: addWpMouse.containsMouse ? Services.Theme.bgOnAccent : Services.Theme.accent
                                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    }
                                                    Text {
                                                        id: addWpText
                                                        text: "Add Image..."
                                                        font.pixelSize: Services.Theme.fontSizeSm
                                                        font.bold: true
                                                        color: addWpMouse.containsMouse ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    }
                                                }

                                                MouseArea {
                                                    id: addWpMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (Services.Wallpaper) {
                                                            Services.Wallpaper.pickCustomWallpaper()
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Wallpaper Horizontal Carousel
                                        Flickable {
                                            Layout.fillWidth: true
                                            height: 84
                                            contentWidth: wpRow.implicitWidth + 20
                                            contentHeight: 84
                                            clip: true
                                            boundsBehavior: Flickable.StopAtBounds

                                            RowLayout {
                                                id: wpRow
                                                spacing: 12
                                                anchors.verticalCenter: parent.verticalCenter

                                                Repeater {
                                                    model: Services.Wallpaper ? Services.Wallpaper.allWallpapers : []
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: 124; height: 76
                                                        radius: 8
                                                        clip: true
                                                        readonly property bool isCurrent: modelData.isDynamic 
                                                            ? (Services.Wallpaper && Services.Wallpaper.isWallblerActive)
                                                            : (Services.Wallpaper && Services.Wallpaper.currentWallpaper === modelData.path)
                                                        border.color: isCurrent ? Services.Theme.accent : (wpCardMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                        border.width: isCurrent ? 2 : 1
                                                        color: Services.Theme.bgElevated
                                                        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                        Image {
                                                            anchors.fill: parent
                                                            source: modelData.path.startsWith("/") ? ("file://" + modelData.path) : modelData.path
                                                            fillMode: Image.PreserveAspectCrop
                                                            asynchronous: true
                                                            smooth: true
                                                        }

                                                        Rectangle {
                                                            opacity: isCurrent ? 1.0 : 0.0
                                                            scale: isCurrent ? 1.0 : 0.6
                                                            anchors.top: parent.top; anchors.left: parent.left
                                                            anchors.margins: 5
                                                            width: 20; height: 20; radius: 10
                                                            color: Services.Theme.accent
                                                            z: 5
                                                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                            Text { anchors.centerIn: parent; text: Services.Icons.check; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.bgOnAccent }
                                                        }

                                                        // Dynamic Badge (for Wallbler)
                                                        Rectangle {
                                                            visible: Boolean(modelData.isDynamic)
                                                            anchors.bottom: parent.bottom; anchors.right: parent.right
                                                            anchors.margins: 5
                                                            height: 18
                                                            implicitWidth: dynRow.implicitWidth + 10
                                                            radius: 9
                                                            color: Qt.rgba(0, 0, 0, 0.75)
                                                            border.color: Qt.rgba(255, 255, 255, 0.25)
                                                            border.width: 1
                                                            z: 5

                                                            RowLayout {
                                                                id: dynRow
                                                                anchors.centerIn: parent
                                                                spacing: 3
                                                                Text {
                                                                    text: Services.Icons.sun
                                                                    font.family: Services.Theme.fontSymbols
                                                                    font.pixelSize: 8
                                                                    color: "#ffbd2e"
                                                                }
                                                                Text {
                                                                    text: "Dynamic"
                                                                    font.pixelSize: 8
                                                                    font.bold: true
                                                                    color: "#ffffff"
                                                                }
                                                            }
                                                        }

                                                        Rectangle {
                                                            visible: Boolean(modelData.isCustom)
                                                            anchors.top: parent.top; anchors.right: parent.right
                                                            anchors.margins: 5
                                                            width: 22; height: 22; radius: 11
                                                            color: delMouse.containsMouse ? Services.Theme.danger : Qt.rgba(0, 0, 0, 0.75)
                                                            border.color: Services.Theme.danger
                                                            border.width: 1
                                                            z: 10
                                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: Services.Icons.trash
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 10
                                                                color: "#ffffff"
                                                            }

                                                            MouseArea {
                                                                id: delMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (Services.Wallpaper) {
                                                                        Services.Wallpaper.deleteCustomWallpaper(modelData.path)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: wpCardMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.Wallpaper) {
                                                                    Services.Wallpaper.setWallpaper(modelData.path)
                                                                    if (Services.Config && Services.Config.useMatugen) {
                                                                        Services.Config.generateMatugen(Services.Wallpaper.currentWallpaper)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Theme & Color Scheme Overview Card
                                SettingsCard {
                                    implicitHeight: themeCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: themeCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        // Theme Mode Overview
                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.moon
                                            title: "Theme Mode"
                                            subtitle: "Switch between Dark and Light color schemes"
                                            currentValue: Services.Config ? Services.Config.themeMode : "dark"
                                            model: [
                                                { id: "dark",  label: "Dark Mode",  desc: "High contrast dark surfaces", icon: Services.Icons.moon },
                                                { id: "light", label: "Light Mode", desc: "Clean bright elevated surfaces", icon: Services.Icons.sun }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Config) Services.Config.setThemeMode(val)
                                            }
                                        }

                                        SettingsDivider {}

                                        // Color Palette Preset Overview Grid
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 10

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 12

                                                Rectangle {
                                                    Layout.preferredWidth: 32
                                                    Layout.preferredHeight: 32
                                                    Layout.alignment: Qt.AlignVCenter
                                                    radius: 8
                                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.palette
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 14
                                                        color: Services.Theme.accent
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 2

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: "Color Palette & Accent Presets"
                                                        font.pixelSize: Services.Theme.fontSizeMd
                                                        font.bold: true
                                                        color: Services.Theme.textPrimary
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: "Curated system palettes or wallpaper-adaptive Matugen theme"
                                                        font.pixelSize: Services.Theme.fontSizeXs
                                                        color: Services.Theme.textSecondary
                                                    }
                                                }
                                            }

                                            // Grid of Palettes
                                            GridLayout {
                                                Layout.fillWidth: true
                                                columns: 3
                                                columnSpacing: 8
                                                rowSpacing: 8

                                                Repeater {
                                                    model: Services.Config ? Services.Config.accentPresets : []
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        height: 44
                                                        radius: Services.Theme.radiusSm
                                                        readonly property bool isCur: Services.Config && Services.Config.accentName === modelData.name

                                                        color: isCur 
                                                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) 
                                                            : (palMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated)
                                                        border.color: isCur 
                                                            ? Services.Theme.accent 
                                                            : (palMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                        border.width: isCur ? 2 : 1
                                                        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 10
                                                            anchors.rightMargin: 10
                                                            spacing: 8

                                                            Rectangle {
                                                                Layout.preferredWidth: 20
                                                                Layout.preferredHeight: 20
                                                                Layout.alignment: Qt.AlignVCenter
                                                                radius: 10
                                                                color: modelData.preview || Services.Theme.accent
                                                                border.color: Qt.rgba(1, 1, 1, 0.2)
                                                                border.width: 1
                                                            }

                                                            Text {
                                                                Layout.fillWidth: true
                                                                Layout.alignment: Qt.AlignVCenter
                                                                text: modelData.name
                                                                font.pixelSize: Services.Theme.fontSizeSm
                                                                font.bold: isCur
                                                                color: isCur ? Services.Theme.textPrimary : (palMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                                elide: Text.ElideRight
                                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            }

                                                            Rectangle {
                                                                opacity: isCur ? 1.0 : 0.0
                                                                scale: isCur ? 1.0 : 0.6
                                                                Layout.preferredWidth: 18
                                                                Layout.preferredHeight: 18
                                                                Layout.alignment: Qt.AlignVCenter
                                                                radius: 9
                                                                color: Services.Theme.accent
                                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: Services.Icons.check
                                                                    font.family: Services.Theme.fontSymbols
                                                                    font.pixelSize: 8
                                                                    color: Services.Theme.bgOnAccent
                                                                }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: palMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.Config) {
                                                                    const hex = (Services.Config.themeMode === "light") ? modelData.lightHex : modelData.darkHex
                                                                    Services.Config.setAccent(hex, modelData.name, modelData.isMatugen)
                                                                    if (modelData.isMatugen && Services.Wallpaper) {
                                                                        Services.Config.generateMatugen(Services.Wallpaper.currentWallpaper)
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Typography & Geometry Card
                                SettingsCard {
                                    implicitHeight: geomCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: geomCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Text {
                                            text: "Typography & Shell Geometry"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        // UI Corner Radius Slider
                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Shell Corner Radius"
                                            subtitle: "Corner rounding for panels, popups, and dialogs"
                                            from: 0
                                            to: 28
                                            stepSize: 1
                                            valueSuffix: "px"
                                            value: Services.Config ? Services.Config.cornerRadius : 16
                                            onMoved: (v) => {
                                                if (Services.Config) Services.Config.setCornerRadius(Math.round(v))
                                            }
                                        }

                                        SettingsDivider {}

                                        // Font Family Overview
                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.font
                                            title: "UI Font Family"
                                            subtitle: "Global monospace & display typography"
                                            currentValue: {
                                                const f = Services.Config ? Services.Config.fontFamily : ""
                                                if (f.indexOf("JetBrains") !== -1) return "jetbrains"
                                                if (f.indexOf("SFMono") !== -1) return "sfmono"
                                                if (f.indexOf("Inter") !== -1) return "inter"
                                                return "firacode"
                                            }
                                            model: [
                                                { id: "sfmono",    label: "SFMono Nerd",  desc: "Apple Monospace" },
                                                { id: "jetbrains", label: "JetBrains",    desc: "Developer Mono" },
                                                { id: "inter",     label: "Inter UI",     desc: "Clean Sans-Serif" },
                                                { id: "firacode",  label: "FiraCode",     desc: "Ligature Mono" }
                                            ]
                                            onSelected: (val) => {
                                                if (!Services.Config) return
                                                if (val === "sfmono") Services.Config.setFontFamily("Liga SFMono Nerd Font, monospace")
                                                else if (val === "jetbrains") Services.Config.setFontFamily("JetBrainsMono Nerd Font, monospace")
                                                else if (val === "inter") Services.Config.setFontFamily("Inter, Sans-Serif")
                                                else Services.Config.setFontFamily("FiraCode Nerd Font, monospace")
                                            }
                                        }

                                        SettingsDivider {}

                                        // UI Scale Slider
                                        SettingsSlider {
                                            icon: Services.Icons.display
                                            title: "Global UI Scale Factor"
                                            subtitle: "Proportional scaling for quickshell panels and widgets"
                                            from: 75
                                            to: 135
                                            stepSize: 5
                                            valueSuffix: "%"
                                            value: Services.Config ? Math.round(Services.Config.uiScale * 100) : 100
                                            onMoved: (v) => {
                                                if (Services.Config) Services.Config.setUiScale(v / 100)
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 1: BAR & DYNAMIC ISLAND
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 1
                                Layout.fillWidth: true
                                spacing: 14

                                // ── 1. BAR LAYOUT & DESIGN PRESET CARD ──
                                SettingsCard {
                                    implicitHeight: barStyleCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: barStyleCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 12

                                            Rectangle {
                                                Layout.preferredWidth: 32
                                                Layout.preferredHeight: 32
                                                Layout.alignment: Qt.AlignVCenter
                                                radius: 8
                                                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                                                border.width: 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Services.Icons.palette
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 14
                                                    color: Services.Theme.accent
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Bar Layout & Design Preset"
                                                    font.pixelSize: Services.Theme.fontSizeMd
                                                    font.bold: true
                                                    color: Services.Theme.textPrimary
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Choose the overall visual architecture and surface styling for your status bar"
                                                    font.pixelSize: Services.Theme.fontSizeXs
                                                    color: Services.Theme.textSecondary
                                                }
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 2
                                            columnSpacing: 10
                                            rowSpacing: 10

                                            Repeater {
                                                model: [
                                                    { id: "islands",  label: "Islands (Discrete)",    desc: "Floating capsules with dynamic island & clear backdrop", icon: Services.Icons.palette },
                                                    { id: "floating", label: "Floating Glass",        desc: "Continuous floating glass bar with screen edge margins",   icon: Services.Icons.display },
                                                    { id: "unified",  label: "Unified Edge-to-Edge",  desc: "Classic full-width continuous dock status bar",          icon: Services.Icons.sliders },
                                                    { id: "minimal",  label: "Minimalist Flat",       desc: "Ultra-slim low-profile bar with borderless flat styling", icon: Services.Icons.sparkles }
                                                ]

                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    implicitHeight: 64
                                                    radius: Services.Theme.radiusSm
                                                    readonly property bool isCur: (Services.Config ? Services.Config.barStyle : "islands") === modelData.id

                                                    color: isCur 
                                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) 
                                                        : (styleMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated)
                                                    border.color: isCur 
                                                        ? Services.Theme.accent 
                                                        : (styleMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                    border.width: isCur ? 2 : 1
                                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 12
                                                        anchors.rightMargin: 12
                                                        spacing: 10

                                                        Rectangle {
                                                            Layout.preferredWidth: 34
                                                            Layout.preferredHeight: 34
                                                            Layout.alignment: Qt.AlignVCenter
                                                            radius: 8
                                                            color: isCur ? Services.Theme.accent : (styleMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgDeep)
                                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.icon || ""
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 14
                                                                color: isCur ? Services.Theme.bgOnAccent : (styleMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            Layout.alignment: Qt.AlignVCenter
                                                            spacing: 2

                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: modelData.label
                                                                font.pixelSize: Services.Theme.fontSizeSm
                                                                font.bold: isCur
                                                                color: isCur ? Services.Theme.textPrimary : (styleMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                                elide: Text.ElideRight
                                                            }
                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: modelData.desc
                                                                font.pixelSize: 10
                                                                color: Services.Theme.textDisabled
                                                                wrapMode: Text.WordWrap
                                                                maximumLineCount: 2
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        Rectangle {
                                                            opacity: isCur ? 1.0 : 0.0
                                                            scale: isCur ? 1.0 : 0.6
                                                            Layout.preferredWidth: 20
                                                            Layout.preferredHeight: 20
                                                            Layout.alignment: Qt.AlignVCenter
                                                            radius: 10
                                                            color: Services.Theme.accent
                                                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: Services.Icons.check
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 9
                                                                color: Services.Theme.bgOnAccent
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: styleMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Config) Services.Config.setBarStyle(modelData.id)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── 2. BAR SCREEN POSITION CARD ──
                                SettingsCard {
                                    implicitHeight: barPlaceCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: barPlaceCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.controlcenter
                                            title: "Bar Screen Position"
                                            subtitle: "Dock the system status bar at the top or bottom of your display"
                                            currentValue: Services.Config ? Services.Config.barPosition : "top"
                                            model: [
                                                { id: "top",    label: "Top Status Bar",  desc: "Docked to top edge with downward drop panels", icon: Services.Icons.sun },
                                                { id: "bottom", label: "Bottom Dock Bar", desc: "Docked to bottom edge with upward drop panels", icon: Services.Icons.moon }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Config) Services.Config.setBarPosition(val)
                                            }
                                        }
                                    }
                                }

                                // ── 3. WORKSPACE PAGER STYLE CARD ──
                                SettingsCard {
                                    implicitHeight: wsStyleCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: wsStyleCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.display
                                            title: "Workspace Pager Appearance"
                                            subtitle: "Choose how virtual desktop workspaces are visually displayed"
                                            currentValue: Services.Config ? Services.Config.workspaceStyle : "pills"
                                            model: [
                                                { id: "pills",   label: "Dynamic Pills", desc: "Expanding capsules", icon: Services.Icons.display },
                                                { id: "numbers", label: "Numbered",      desc: "Digits 1, 2, 3...",  icon: Services.Icons.terminal },
                                                { id: "dots",    label: "Minimal Dots",  desc: "Compact dots",       icon: Services.Icons.checkCircle },
                                                { id: "icons",   label: "Context Icons", desc: "Task glyphs",        icon: Services.Icons.folder }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Config) Services.Config.setWorkspaceStyle(val)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.check
                                            title: "Always Show Primary Workspaces (1–5)"
                                            subtitle: "Keep primary workspaces visible even when inactive or empty"
                                            checked: Services.Config ? Services.Config.workspaceShowAll : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setWorkspaceShowAll(st)
                                            }
                                        }
                                    }
                                }

                                // ── 4. DYNAMIC ISLAND HUD MODE CARD ──
                                SettingsCard {
                                    implicitHeight: islandCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: islandCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.sparkles
                                            title: "Dynamic Island HUD Mode"
                                            subtitle: (Services.Config && Services.Config.barStyle === "islands")
                                                ? "Interactive central notch for media controls, system status & notifications"
                                                : "Dynamic Island is active in 'Islands' bar mode (in floating/unified/minimal, bar uses a centered clock)"
                                            currentValue: Services.Config ? Services.Config.islandStyle : "expanded"
                                            model: [
                                                { id: "expanded", label: "Full Dynamic Island", desc: "Full media controls & system HUD", icon: Services.Icons.sparkles },
                                                { id: "compact",  label: "Compact HUD",         desc: "Essential alerts & status badge",  icon: Services.Icons.sliders },
                                                { id: "hidden",   label: "Hidden / Off",        desc: "Disable island for clean center",   icon: Services.Icons.close }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Config) Services.Config.setIslandStyle(val)
                                            }
                                        }
                                    }
                                }

                                // ── 5. STATUS BAR MODULES & WIDGETS CARD ──
                                SettingsCard {
                                    implicitHeight: barWidgetsCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: barWidgetsCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 4

                                        Text {
                                            text: "Status Bar Modules & Widgets"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }
                                        Text {
                                            text: "Toggle individual status indicators and modules visible on the bar"
                                            font.pixelSize: Services.Theme.fontSizeXs
                                            color: Services.Theme.textSecondary
                                        }

                                        Item { Layout.preferredHeight: 4 }

                                        SettingsSwitch {
                                            icon: Services.Icons.display
                                            title: "Workspaces Pager"
                                            subtitle: "Show virtual workspace tags and active indicators"
                                            checked: Services.Config ? Services.Config.showWorkspaces : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowWorkspaces(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.tray
                                            title: "System Tray"
                                            subtitle: "Show background running application icons (SNI)"
                                            checked: Services.Config ? Services.Config.showSysTray : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowSysTray(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.cpu
                                            title: "System Monitor"
                                            subtitle: "Show real-time CPU, RAM, and thermals meter"
                                            checked: Services.Config ? Services.Config.showSysmonTray : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowSysmonTray(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.speaker
                                            title: "Volume & Brightness"
                                            subtitle: "Show speaker volume level and slider module"
                                            checked: Services.Config ? Services.Config.showVolumeTray : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowVolumeTray(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.tree
                                            title: "Battery & Power Indicator"
                                            subtitle: "Show battery level percentage and charging state"
                                            checked: Services.Config ? Services.Config.showBatteryTray : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowBatteryTray(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.sliders
                                            title: "Control Center Trigger"
                                            subtitle: "Show quick settings and toggles trigger pill"
                                            checked: Services.Config ? Services.Config.showControlCenterTray : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowControlCenterTray(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.uptime
                                            title: "Digital Clock & Calendar"
                                            subtitle: "Show current time with calendar popup integration"
                                            checked: Services.Config ? Services.Config.showClockTray : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setShowClockTray(st) }
                                        }
                                    }
                                }

                                // ── 6. CLOCK & TIME FORMAT CARD ──
                                SettingsCard {
                                    implicitHeight: clockFmtCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: clockFmtCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 4

                                        Text {
                                            text: "Clock & Time Format"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        Item { Layout.preferredHeight: 4 }

                                        SettingsSwitch {
                                            icon: Services.Icons.uptime
                                            title: "24-Hour Time Format"
                                            subtitle: "Use 24h military clock instead of 12h AM/PM"
                                            checked: Services.Config ? Services.Config.clock24h : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setClock24h(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.uptime
                                            title: "Display Live Seconds"
                                            subtitle: "Render real-time ticking seconds in bar clock"
                                            checked: Services.Config ? Services.Config.clockShowSeconds : false
                                            onToggled: (st) => { if (Services.Config) Services.Config.setClockShowSeconds(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.uptime
                                            title: "Display Date Text"
                                            subtitle: "Show current day and date prefix in the bar"
                                            checked: Services.Config ? Services.Config.clockShowDate : true
                                            onToggled: (st) => { if (Services.Config) Services.Config.setClockShowDate(st) }
                                        }
                                        SettingsDivider {}

                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.uptime
                                            title: "Date Format"
                                            subtitle: "Format style for date text"
                                            currentValue: Services.Config ? Services.Config.clockDateFormat : "short"
                                            model: [
                                                { id: "short", label: "Short (Mon, 19 Jan)", desc: "Abbreviated day and month", icon: Services.Icons.uptime },
                                                { id: "full",  label: "Full (Monday, 19 January)", desc: "Full weekday and month name", icon: Services.Icons.calendar || Services.Icons.uptime }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Config) Services.Config.setClockDateFormat(val)
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 2: NOTIFICATIONS
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 2
                                Layout.fillWidth: true
                                spacing: 14

                                SettingsCard {
                                    implicitHeight: notifCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: notifCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Text {
                                            text: "Notification Behavior & Alerts"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSwitch {
                                            icon: Services.Icons.bell
                                            title: "Do Not Disturb Mode"
                                            subtitle: "Mute all on-screen notification popups and sound alerts"
                                            checked: Services.Notifications.doNotDisturb
                                            onToggled: (st) => {
                                                Services.Notifications.doNotDisturb = st
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.uptime
                                            title: "Notification Popup Duration"
                                            subtitle: "How long bubble popups remain on screen before dismissing"
                                            from: 2
                                            to: 15
                                            stepSize: 1
                                            valueSuffix: "s"
                                            value: Services.Config ? Services.Config.notificationTimeout : 5
                                            onMoved: (v) => {
                                                if (Services.Config) Services.Config.setNotificationTimeout(Math.round(v))
                                            }
                                        }

                                        SettingsDivider {}

                                        // Action Buttons
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 38
                                                radius: Services.Theme.radiusSm
                                                color: testNotifMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated
                                                border.color: testNotifMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: Services.Icons.bell; font.family: Services.Theme.fontSymbols; font.pixelSize: 12; color: Services.Theme.accent }
                                                    Text { text: "Send Test Notification"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                                }

                                                MouseArea {
                                                    id: testNotifMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: testNotifProc.running = true
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 38
                                                radius: Services.Theme.radiusSm
                                                color: clearNotifMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.15) : Services.Theme.bgElevated
                                                border.color: clearNotifMouse.containsMouse ? Services.Theme.danger : Services.Theme.border
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: Services.Icons.trash; font.family: Services.Theme.fontSymbols; font.pixelSize: 12; color: Services.Theme.danger }
                                                    Text { text: "Clear History"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                                }

                                                MouseArea {
                                                    id: clearNotifMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (Services.Notifications) Services.Notifications.clearHistory()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 3: SOUND & AUDIO EFFECTS
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 3
                                Layout.fillWidth: true
                                spacing: 14

                                SettingsCard {
                                    implicitHeight: sndCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: sndCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Text {
                                            text: "System Sound Feedback"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSwitch {
                                            icon: Services.Icons.speaker
                                            title: "Enable UI Sound Effects"
                                            subtitle: "Play audible feedback on volume adjustments and alerts"
                                            checked: Services.Config ? Services.Config.soundFeedback : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setSoundFeedback(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        Text { text: "Audition System Sound Effects:"; font.pixelSize: Services.Theme.fontSizeSm; font.bold: true; color: Services.Theme.textSecondary }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Repeater {
                                                model: [
                                                    { label: "Notification", sound: "playNotification" },
                                                    { label: "Volume Step",  sound: "playVolumeChange" },
                                                    { label: "Device Added", sound: "playDeviceAdded" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    height: 36
                                                    radius: Services.Theme.radiusSm
                                                    color: sHover.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated
                                                    border.color: sHover.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                                                    border.width: 1
                                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                    RowLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 6
                                                        Text { text: Services.Icons.speaker; font.family: Services.Theme.fontSymbols; font.pixelSize: 11; color: Services.Theme.accent }
                                                        Text { text: modelData.label; font.pixelSize: Services.Theme.fontSizeSm; font.bold: true; color: Services.Theme.textPrimary }
                                                    }

                                                    MouseArea {
                                                        id: sHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.SoundFeedback && typeof Services.SoundFeedback[modelData.sound] === "function") {
                                                                Services.SoundFeedback[modelData.sound]()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 4: LOCKSCREEN & POWER
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 4
                                Layout.fillWidth: true
                                spacing: 14

                                // ── Card 1: Lockscreen Visual Style & Clock ──
                                SettingsCard {
                                    implicitHeight: lockVisualCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: lockVisualCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Text {
                                            text: "Lockscreen Style & Typography"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.clock
                                            title: "Lock Clock Typography Style"
                                            subtitle: "Choose visual time and date presentation on the lockscreen"
                                            currentValue: Services.Config ? Services.Config.lockscreenClockStyle : "hero"
                                            model: [
                                                { id: "hero",    label: "Hero Display", desc: "Huge Apple-style bold clock", icon: Services.Icons.clock },
                                                { id: "modern",  label: "Modern Stack", desc: "Two-tone stacked Hour/Minute", icon: Services.Icons.dashboard },
                                                { id: "compact", label: "Compact Pill", desc: "Discrete minimal capsule pill", icon: Services.Icons.controlcenter }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Config) Services.Config.setLockscreenClockStyle(val)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.clock
                                            title: "24-Hour Time Format"
                                            subtitle: "Display 00:00 to 23:59 time on lockscreen instead of 12-hour format"
                                            checked: Services.Config ? Services.Config.lockscreen24h : false
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setLockscreen24h(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.sun
                                            title: "Ambient Greeting & Username"
                                            subtitle: "Show time-of-day greeting (Good Morning / Afternoon) and user info"
                                            checked: Services.Config ? Services.Config.lockscreenShowWeather : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setLockscreenShowWeather(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.musicNote
                                            title: "Now Playing Media Pill"
                                            subtitle: "Show active media controls and track info on lockscreen"
                                            checked: Services.Config ? Services.Config.lockscreenShowMedia : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setLockscreenShowMedia(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.bell
                                            title: "Show Notification Previews"
                                            subtitle: "Display stacked recent notifications below authentication pill"
                                            checked: Services.Config ? Services.Config.lockscreenShowNotifs : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setLockscreenShowNotifs(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.palette
                                            title: "Ken Burns Wallpaper Zoom"
                                            subtitle: "Smooth subtle wallpaper zoom effect when unlocking or revealing"
                                            checked: Services.Config ? Services.Config.lockscreenWallpaperZoom : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setLockscreenWallpaperZoom(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.moon
                                            title: "Lockscreen Backdrop Dimming"
                                            subtitle: "Dark vignette opacity over lockscreen background wallpaper"
                                            from: 10
                                            to: 85
                                            stepSize: 5
                                            valueSuffix: "%"
                                            value: Math.round((Services.Config ? Services.Config.lockscreenDim : 0.45) * 100)
                                            onMoved: (v) => {
                                                if (Services.Config) Services.Config.setLockscreenDim(Number((v / 100).toFixed(2)))
                                            }
                                        }
                                    }
                                }

                                // ── Card 2: Power Profile & Battery Management ──
                                SettingsCard {
                                    implicitHeight: pwrCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: pwrCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Text {
                                            text: "System Power Profile & Battery"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.power
                                            title: "CPU Governor Power Profile"
                                            subtitle: "Select CPU frequency scaling & battery consumption mode"
                                            currentValue: Services.PowerProfile ? Services.PowerProfile.currentProfile : "balanced"
                                            model: [
                                                { id: "power-saver", label: "Power Saver", desc: "Throttles CPU to maximize battery", icon: Services.Icons.tree },
                                                { id: "balanced",    label: "Balanced",    desc: "Dynamic balance of speed & power", icon: Services.Icons.sliders },
                                                { id: "performance", label: "Performance", desc: "Max clocks for gaming & rendering", icon: Services.Icons.cpu }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.PowerProfile) Services.PowerProfile.setProfile(val)
                                            }
                                        }

                                        SettingsDivider {}

                                        // Live Battery Telemetry Gauge Card
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: battGaugeCol.implicitHeight + 24
                                            radius: Services.Theme.radiusSm
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            ColumnLayout {
                                                id: battGaugeCol
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 10

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 10

                                                    Rectangle {
                                                        Layout.preferredWidth: 36
                                                        Layout.preferredHeight: 36
                                                        Layout.alignment: Qt.AlignVCenter
                                                        radius: 8
                                                        color: Services.Power.charging 
                                                            ? Qt.rgba(Services.Theme.success.r, Services.Theme.success.g, Services.Theme.success.b, 0.15) 
                                                            : (Services.Power.isLow ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.15) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15))

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Services.Icons.powerIcon(Services.Power.charging, Math.round((Services.Power.percentage || 0) * 100))
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 18
                                                            color: Services.Power.charging 
                                                                ? Services.Theme.success 
                                                                : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.accent))
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        spacing: 2

                                                        RowLayout {
                                                            spacing: 8
                                                            Text {
                                                                text: Services.Power.hasBattery ? (Math.round((Services.Power.percentage || 0) * 100) + "% Battery Available") : "AC Power Connected"
                                                                font.pixelSize: Services.Theme.fontSizeMd
                                                                font.bold: true
                                                                color: Services.Theme.textPrimary
                                                            }
                                                            Rectangle {
                                                                height: 16; radius: 4
                                                                implicitWidth: bStateTxt.implicitWidth + 8
                                                                color: Services.Power.charging ? Qt.rgba(Services.Theme.success.r, Services.Theme.success.g, Services.Theme.success.b, 0.15) : Services.Theme.bgHover
                                                                border.color: Services.Power.charging ? Services.Theme.success : Services.Theme.border
                                                                border.width: 1
                                                                Text {
                                                                    id: bStateTxt
                                                                    anchors.centerIn: parent
                                                                    text: Services.Power.stateString || "Normal"
                                                                    font.pixelSize: 8
                                                                    font.bold: true
                                                                    color: Services.Power.charging ? Services.Theme.success : Services.Theme.textSecondary
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            text: Services.Power.charging ? "Device is actively charging" : (Services.Power.isLow ? "Battery low! Connect AC adapter" : "Operating on battery power")
                                                            font.pixelSize: Services.Theme.fontSizeXs
                                                            color: Services.Theme.textSecondary
                                                        }
                                                    }
                                                }

                                                // Progress bar
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 8
                                                    radius: 4
                                                    color: Services.Theme.bgDeep

                                                    Rectangle {
                                                        width: Math.max(8, parent.width * Math.min(1.0, Math.max(0.0, Services.Power.percentage || 0)))
                                                        height: parent.height
                                                        radius: 4
                                                        color: Services.Power.charging 
                                                            ? Services.Theme.success 
                                                            : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.accent))
                                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                                        Behavior on color { ColorAnimation { duration: 200 } }
                                                    }
                                                }
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.speaker
                                            title: "Low Battery Warning Alerts"
                                            subtitle: "Play sound and show notifications when battery level is critically low"
                                            checked: Services.Config ? Services.Config.batteryShowWarnings : true
                                            onToggled: (st) => {
                                                if (Services.Config) Services.Config.setBatteryShowWarnings(st)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Battery Warning Threshold"
                                            subtitle: "Trigger low battery alerts when remaining charge drops below"
                                            from: 10
                                            to: 35
                                            stepSize: 5
                                            valueSuffix: "%"
                                            value: Services.Config ? Services.Config.batteryLowThreshold : 20
                                            onMoved: (v) => {
                                                if (Services.Config) Services.Config.setBatteryLowThreshold(Math.round(v))
                                            }
                                        }
                                    }
                                }

                                // ── Card 3: Session & Quick Power Actions ──
                                SettingsCard {
                                    implicitHeight: quickPwrCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: quickPwrCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Text {
                                            text: "Quick Session & Power Controls"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 40
                                                radius: Services.Theme.radiusSm
                                                color: btnLockMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated
                                                border.color: btnLockMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: "󰌾"; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.accent }
                                                    Text { text: "Lock Screen Now"; font.pixelSize: Services.Theme.fontSizeSm; font.bold: true; color: Services.Theme.textPrimary }
                                                }

                                                MouseArea {
                                                    id: btnLockMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        rootWindow.hide()
                                                        lockSessionProc.running = true
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 40
                                                radius: Services.Theme.radiusSm
                                                color: btnSleepMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.bgElevated
                                                border.color: btnSleepMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text { text: Services.Icons.pmSleep; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.accent }
                                                    Text { text: "Suspend System"; font.pixelSize: Services.Theme.fontSizeSm; font.bold: true; color: Services.Theme.textPrimary }
                                                }

                                                MouseArea {
                                                    id: btnSleepMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: suspendProc.running = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 5: COMPOSITOR & CONFIG EDITOR
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 5
                                Layout.fillWidth: true
                                spacing: 14

                                // Compositor Status Banner
                                SettingsCard {
                                    implicitHeight: compStatusCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: compStatusCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 14

                                            Rectangle {
                                                Layout.preferredWidth: 44
                                                Layout.preferredHeight: 44
                                                Layout.alignment: Qt.AlignVCenter
                                                radius: 10
                                                color: Services.Theme.accent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Services.Icons.display
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 20
                                                    color: Services.Theme.bgOnAccent
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 2

                                                RowLayout {
                                                    spacing: 8
                                                    Text {
                                                        text: Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland Compositor"
                                                        font.pixelSize: Services.Theme.fontSizeLg
                                                        font.bold: true
                                                        color: Services.Theme.textPrimary
                                                    }
                                                    Rectangle {
                                                        height: 18; radius: 4
                                                        implicitWidth: statTxt.implicitWidth + 10
                                                        color: Qt.rgba(0.2, 0.8, 0.4, 0.2)
                                                        border.color: Services.Theme.success
                                                        border.width: 1
                                                        Text {
                                                            id: statTxt
                                                            anchors.centerIn: parent
                                                            text: "ACTIVE"
                                                            font.pixelSize: 8
                                                            font.bold: true
                                                            color: Services.Theme.success
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: "Live Hyprland IPC connected • Real-time decoration & geometry control"
                                                    font.pixelSize: Services.Theme.fontSizeXs
                                                    color: Services.Theme.textSecondary
                                                }
                                            }
                                        }
                                    }
                                }

                                // Visual Effects Card
                                SettingsCard {
                                    visible: Services.Compositor && Services.Compositor.activeCompositor === "hyprland"
                                    implicitHeight: hyprCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: hyprCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Text {
                                            text: "Live Visual Effects & Decoration"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSwitch {
                                            icon: Services.Icons.wand
                                            title: "Compositor Animations"
                                            subtitle: "Enable smooth window transitions & popups"
                                            checked: Services.Compositor ? Services.Compositor.hyprAnim : true
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprAnim() }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.brush
                                            title: "Dual Kawase Blur"
                                            subtitle: "Background glass blur for windows & panels"
                                            checked: Services.Compositor ? Services.Compositor.hyprBlur : true
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprBlur() }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.moon
                                            title: "Window Drop Shadows"
                                            subtitle: "Floating window drop shadow rendering"
                                            checked: Services.Compositor ? Services.Compositor.hyprShadow : true
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprShadow() }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.eyeClosed
                                            title: "Dim Inactive Windows"
                                            subtitle: "Darken unfocused background windows"
                                            checked: Services.Compositor ? Services.Compositor.hyprDimInactive : false
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprDimInactive() }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.brush
                                            title: "Blur Size"
                                            subtitle: "Radius of the gaussian/kawase blur convolution kernel"
                                            from: 1; to: 16; stepSize: 1; valueSuffix: "px"
                                            value: Services.Compositor ? Services.Compositor.hyprBlurSize : 4
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurSize(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Blur Passes"
                                            subtitle: "Number of sampling passes (smoother glass effect)"
                                            from: 1; to: 5; stepSize: 1; valueSuffix: "x"
                                            value: Services.Compositor ? Services.Compositor.hyprBlurPasses : 2
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurPasses(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.moon
                                            title: "Shadow Range"
                                            subtitle: "Shadow spread distance in pixels"
                                            from: 0; to: 36; stepSize: 1; valueSuffix: "px"
                                            value: Services.Compositor ? Services.Compositor.hyprShadowRange : 12
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprShadowRange(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.display
                                            title: "Active Window Opacity"
                                            subtitle: "Opacity multiplier for currently focused application"
                                            from: 0.50; to: 1.00; stepSize: 0.01; decimals: 2
                                            value: Services.Compositor ? Services.Compositor.hyprActiveOpacity : 0.9
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprActiveOpacity(Number(v.toFixed(2))) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.display
                                            title: "Inactive Window Opacity"
                                            subtitle: "Opacity multiplier for unfocused background windows"
                                            from: 0.50; to: 1.00; stepSize: 0.01; decimals: 2
                                            value: Services.Compositor ? Services.Compositor.hyprInactiveOpacity : 0.95
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprInactiveOpacity(Number(v.toFixed(2))) }
                                        }
                                    }
                                }

                                // Geometry, Layout & Gaps Card
                                SettingsCard {
                                    visible: Services.Compositor && Services.Compositor.activeCompositor === "hyprland"
                                    implicitHeight: hyprGeomCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: hyprGeomCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Text {
                                            text: "Window Geometry, Spacing & Layout"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Window Corner Rounding"
                                            subtitle: "Corner radius applied to all client windows"
                                            from: 0; to: 28; stepSize: 1; valueSuffix: "px"
                                            value: Services.Compositor ? Services.Compositor.hyprRounding : 10
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprRounding(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Window Border Size"
                                            subtitle: "Outline border thickness in pixels"
                                            from: 0; to: 6; stepSize: 1; valueSuffix: "px"
                                            value: Services.Compositor ? Services.Compositor.hyprBorderSize : 0
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBorderSize(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Gaps In (Window Spacing)"
                                            subtitle: "Inner padding distance between tiled windows"
                                            from: 0; to: 24; stepSize: 1; valueSuffix: "px"
                                            value: Services.Compositor ? Services.Compositor.hyprGapsIn : 5
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsIn(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Gaps Out (Screen Margin)"
                                            subtitle: "Outer margin distance from screen edges and desktop bar"
                                            from: 0; to: 36; stepSize: 1; valueSuffix: "px"
                                            value: Services.Compositor ? Services.Compositor.hyprGapsOut : 10
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsOut(Math.round(v)) }
                                        }

                                        SettingsDivider {}

                                        // Tiling Layout Overview
                                        SettingsSegmentedOverview {
                                            icon: Services.Icons.display
                                            title: "Tiling Layout Engine"
                                            subtitle: "Window management layout strategy"
                                            currentValue: Services.Compositor ? Services.Compositor.hyprLayout : "dwindle"
                                            model: [
                                                { id: "scrolling", label: "Scrolling", desc: "Niri / PaperWM tape", icon: Services.Icons.sliders },
                                                { id: "dwindle",   label: "Dwindle",   desc: "BSP dynamic split", icon: Services.Icons.display },
                                                { id: "master",    label: "Master",    desc: "Master & vertical stack", icon: Services.Icons.terminal }
                                            ]
                                            onSelected: (val) => {
                                                if (Services.Compositor) Services.Compositor.setHyprLayout(val)
                                            }
                                        }

                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.sliders
                                            title: "Resize on Border"
                                            subtitle: "Allow dragging window borders directly with the mouse"
                                            checked: Services.Compositor ? Services.Compositor.hyprResizeOnBorder : false
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprResizeBorder() }
                                        }
                                    }
                                }

                                // Input & Touchpad Card
                                SettingsCard {
                                    visible: Services.Compositor && Services.Compositor.activeCompositor === "hyprland"
                                    implicitHeight: inputCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: inputCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Text {
                                            text: "Input & Touchpad Behavior"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        SettingsSwitch {
                                            icon: Services.Icons.sliders
                                            title: "Natural Scrolling"
                                            subtitle: "Reverse touchpad scroll direction"
                                            checked: Services.Compositor ? Services.Compositor.hyprTouchpadNatural : true
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTouchpadNatural() }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.checkCircle
                                            title: "Tap-to-Click"
                                            subtitle: "Single finger tap on touchpad simulates click"
                                            checked: Services.Compositor ? Services.Compositor.hyprTouchpadTap : true
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTouchpadTap() }
                                        }
                                        SettingsDivider {}

                                        SettingsSwitch {
                                            icon: Services.Icons.keyboard
                                            title: "Disable While Typing (DWT)"
                                            subtitle: "Freeze touchpad clicks while typing on keyboard"
                                            checked: Services.Compositor ? Services.Compositor.hyprTouchpadDwt : false
                                            onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTouchpadDwt() }
                                        }
                                        SettingsDivider {}

                                        SettingsSlider {
                                            icon: Services.Icons.sliders
                                            title: "Pointer / Cursor Sensitivity"
                                            subtitle: "Compositor cursor acceleration multiplier (-1.00 slow to +1.00 fast)"
                                            from: -1.00; to: 1.00; stepSize: 0.05; decimals: 2
                                            valuePrefix: (Services.Compositor && Services.Compositor.hyprSensitivity > 0) ? "+" : ""
                                            value: Services.Compositor ? Services.Compositor.hyprSensitivity : 0.0
                                            onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprSensitivity(Number(v.toFixed(2))) }
                                        }
                                    }
                                }

                                // Detected Compositors List Card
                                SettingsCard {
                                    implicitHeight: instCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: instCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 10

                                        Text {
                                            text: "Detected Wayland Compositors"
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        Repeater {
                                            model: Services.Compositor ? Services.Compositor.installedCompositors : []
                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: 10

                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28
                                                    Layout.alignment: Qt.AlignVCenter
                                                    radius: 6
                                                    readonly property bool isCur: modelData.id === (Services.Compositor ? Services.Compositor.activeCompositor : "")
                                                    color: isCur ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15) : Services.Theme.bgElevated

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.terminal
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 12
                                                        color: parent.isCur ? Services.Theme.accent : Services.Theme.textDisabled
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    text: modelData.name
                                                    font.pixelSize: Services.Theme.fontSizeSm
                                                    font.bold: true
                                                    color: Services.Theme.textPrimary
                                                }

                                                Rectangle {
                                                    Layout.preferredHeight: 20
                                                    Layout.alignment: Qt.AlignVCenter
                                                    implicitWidth: statusBadgeTxt.implicitWidth + 12
                                                    radius: 4
                                                    readonly property bool isActive: modelData.id === (Services.Compositor ? Services.Compositor.activeCompositor : "")
                                                    color: isActive 
                                                        ? Qt.rgba(0.2, 0.8, 0.4, 0.2) 
                                                        : (modelData.isInstalled ? Qt.rgba(0.3, 0.6, 0.9, 0.15) : Qt.rgba(0.5, 0.5, 0.5, 0.1))
                                                    border.color: isActive ? Services.Theme.success : (modelData.isInstalled ? Services.Theme.accent : Services.Theme.border)
                                                    border.width: 1

                                                    Text {
                                                        id: statusBadgeTxt
                                                        anchors.centerIn: parent
                                                        text: parent.isActive ? "RUNNING" : (modelData.isInstalled ? "INSTALLED" : "NOT FOUND")
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: parent.isActive ? Services.Theme.success : (modelData.isInstalled ? Services.Theme.accent : Services.Theme.textDisabled)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 6: BACKUP, RESTORE & RESET
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 6
                                Layout.fillWidth: true
                                spacing: 14

                                SettingsCard {
                                    implicitHeight: backupNoticeCol.implicitHeight + 24
                                    color: Qt.rgba(0.2, 0.5, 0.8, 0.12)
                                    border.color: Services.Theme.accent

                                    RowLayout {
                                        id: backupNoticeCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Rectangle {
                                            Layout.preferredWidth: 36
                                            Layout.preferredHeight: 36
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 8
                                            color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.2)

                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.info
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 18
                                                color: Services.Theme.accent
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2
                                            Text {
                                                text: "Original File Snapshot Preserved"
                                                font.pixelSize: Services.Theme.fontSizeMd
                                                font.bold: true
                                                color: Services.Theme.textPrimary
                                            }
                                            Text {
                                                text: "All factory original configuration and component files are archived in .backup_original and defaults/. You can safely experiment and reset anytime."
                                                font.pixelSize: Services.Theme.fontSizeXs
                                                color: Services.Theme.textSecondary
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }
                                }

                                SettingsCard {
                                    implicitHeight: rstCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: rstCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        Text {
                                            text: "Reset & Restore Controls"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 42
                                            radius: Services.Theme.radiusSm
                                            color: rstSetMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.12) : Services.Theme.bgElevated
                                            border.color: rstSetMouse.containsMouse ? Services.Theme.danger : Services.Theme.border
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 8
                                                Text {
                                                    text: Services.Icons.undo
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 13
                                                    color: rstSetMouse.containsMouse ? Services.Theme.danger : Services.Theme.accent
                                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                }
                                                Text { text: "Reset Preferences to Default"; font.pixelSize: Services.Theme.fontSizeMd; font.bold: true; color: Services.Theme.textPrimary }
                                            }

                                            MouseArea {
                                                id: rstSetMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.Config) Services.Config.resetToDefaults()
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────
                            // PAGE 7: ABOUT & KEYS
                            // ─────────────────────────────────────────────────
                            ColumnLayout {
                                visible: rootWindow.currentTab === 7
                                Layout.fillWidth: true
                                spacing: 14

                                SettingsCard {
                                    implicitHeight: sysCol.implicitHeight + 28

                                    RowLayout {
                                        id: sysCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 14

                                        Rectangle {
                                            Layout.preferredWidth: 52
                                            Layout.preferredHeight: 52
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 12
                                            color: Services.Theme.accent
                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.OsInfo.logoGlyph || Services.Icons.shell
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 26
                                                color: Services.Theme.bgOnAccent
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2
                                            Text {
                                                text: (Services.OsInfo.distroName || "Linux Desktop")
                                                font.pixelSize: Services.Theme.fontSize2xl
                                                font.bold: true
                                                color: Services.Theme.textPrimary
                                            }
                                            Text {
                                                text: "Host: " + (Services.OsInfo.hostname || "localhost") + "  •  Kernel: " + (Services.OsInfo.kernel || "Linux")
                                                font.pixelSize: Services.Theme.fontSizeXs
                                                color: Services.Theme.textSecondary
                                            }
                                            Text {
                                                text: "User: " + (Services.OsInfo.username || "user") + "  •  Compositor: " + (Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland")
                                                font.pixelSize: Services.Theme.fontSizeXs
                                                color: Services.Theme.textSecondary
                                            }
                                        }
                                    }
                                }

                                SettingsCard {
                                    implicitHeight: scCol.implicitHeight + 28

                                    ColumnLayout {
                                        id: scCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 10

                                        Text {
                                            text: "Desktop Keyboard Shortcuts"
                                            font.pixelSize: Services.Theme.fontSizeLg
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }

                                        Repeater {
                                            model: [
                                                { key: "Super + D", desc: "Application Launcher" },
                                                { key: "Super + A", desc: "System Dashboard" },
                                                { key: "Super + C", desc: "Control Center" },
                                                { key: "Super + V", desc: "Clipboard Manager" },
                                                { key: "Super + L", desc: "Lock Screen" },
                                                { key: "Super + Esc", desc: "Power Menu" }
                                            ]
                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: 12

                                                Rectangle {
                                                    Layout.preferredWidth: 120
                                                    Layout.preferredHeight: 26
                                                    Layout.alignment: Qt.AlignVCenter
                                                    radius: 4
                                                    color: Services.Theme.bgElevated
                                                    border.color: Services.Theme.border
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.key
                                                        font.family: Services.Theme.fontMono
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: Services.Theme.accent
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    text: modelData.desc
                                                    font.pixelSize: Services.Theme.fontSizeSm
                                                    color: Services.Theme.textPrimary
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Helper Processes ─────────────────────────────────────────────────────
    Process {
        id: testNotifProc
        command: ["notify-send", "-a", "Quickshell Settings", "Settings Preview", "Your theme & notification settings are working beautifully!"]
    }
    Process {
        id: lockSessionProc
        command: ["loginctl", "lock-session"]
    }
    Process {
        id: suspendProc
        command: ["systemctl", "suspend"]
    }
}
