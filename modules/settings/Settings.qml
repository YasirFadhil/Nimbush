import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../../services" as Services

FloatingWindow {
    id: rootWindow

    title: "Settings"
    visible: false
    implicitWidth: 960
    implicitHeight: 660
    color: Services.Theme.bgElevated

    property string overlayId: "settings"
    property int currentTab: 0
    property int compSubTab: 0
    property string keySearchQuery: ""
    property string keyCategory: "all"
    property bool isAddingKeybind: false
    property int editingBindLine: -1
    property string formKeys: ""
    property string formAction: ""
    property string formDesc: ""

    Component.onCompleted: {
        Services.OverlayManager.register(rootWindow)
        if (Services.Compositor) {
            Services.Compositor.refreshState()
            Services.Compositor.loadKeybinds()
        }
    }

    function show() {
        visible = true
        keyFocus.forceActiveFocus()
        if (Services.Compositor) {
            Services.Compositor.refreshState()
            Services.Compositor.loadKeybinds()
        }
    }

    function hide() {
        visible = false
    }

    function toggle() {
        visible ? hide() : show()
    }

    function open() { show() }
    function close() { hide() }

    onVisibleChanged: {
        if (visible) {
            keyFocus.forceActiveFocus()
        }
    }

    Item {
        id: keyFocus
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: (event) => {
            rootWindow.close()
            event.accepted = true
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // REUSABLE BALANCED "MEDIUM" SETTINGS COMPONENTS
    // ═════════════════════════════════════════════════════════════════════════

    // ── 1. Section Header & Inset Grouped Card ───────────────────────────────
    component SettingsSection: ColumnLayout {
        id: secRoot
        property string title: ""
        property string icon: ""
        default property alias content: cardContent.data

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            visible: secRoot.title.length > 0
            spacing: 6
            Layout.leftMargin: 2

            Text {
                visible: secRoot.icon.length > 0
                text: secRoot.icon
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 11
                color: Services.Theme.accent
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: secRoot.title.toUpperCase()
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
                color: Services.Theme.textSecondary
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: cardContent.implicitHeight + 4
            radius: Services.Theme.radiusMd
            color: Services.Theme.surfaceVariant
            border.color: Services.Theme.border
            border.width: 1

            ColumnLayout {
                id: cardContent
                anchors.fill: parent
                anchors.margins: 4
                spacing: 0
            }
        }
    }

    // ── 2. Settings Row (Clean Typography on Left, Control on Right) ──────────
    component SettingsRow: Rectangle {
        id: rowRoot
        property string title: ""
        property string subtitle: ""
        default property alias control: controlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(42, textCol.implicitHeight + 16)
        radius: Services.Theme.radiusSm
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 12

            ColumnLayout {
                id: textCol
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: rowRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.weight: Font.Medium
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }

                Text {
                    visible: rowRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: rowRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Item {
                id: controlSlot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    // ── 3. Settings Dropdown / ComboBox (Clean Modern Popover) ────────────────
    component SettingsDropdown: Item {
        id: dropRoot
        property var model: [] // [{ id, label }]
        property var currentValue: null
        signal selected(var val)

        readonly property var currentItem: {
            for (let i = 0; i < model.length; i++) {
                if (model[i].id === currentValue) return model[i]
            }
            return model.length > 0 ? model[0] : { label: "Select..." }
        }

        implicitHeight: 28
        implicitWidth: Math.max(140, dropBtnText.implicitWidth + 36)

        Rectangle {
            id: dropBtn
            anchors.fill: parent
            radius: 6
            color: dropArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Services.Theme.bgElevated
            border.color: dropMenu.visible ? Services.Theme.accent : Services.Theme.border
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    id: dropBtnText
                    Layout.fillWidth: true
                    text: dropRoot.currentItem ? dropRoot.currentItem.label : ""
                    font.pixelSize: Services.Theme.fontSizeSm
                    font.weight: Font.Medium
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }

                Text {
                    text: "▾"
                    font.pixelSize: 8
                    color: Services.Theme.textSecondary
                }
            }

            MouseArea {
                id: dropArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (dropMenu.visible) dropMenu.close()
                    else dropMenu.open()
                }
            }

            Popup {
                id: dropMenu
                y: dropBtn.height + 4
                x: Math.min(0, dropBtn.width - width)
                width: Math.max(dropBtn.width, 175)
                height: Math.min(240, menuCol.implicitHeight + 8)
                padding: 4
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                modal: false
                focus: true

                background: Rectangle {
                    radius: 8
                    color: Services.Theme.bgElevated
                    border.color: Services.Theme.borderHighlight
                    border.width: 1
                }

                contentItem: Flickable {
                    contentHeight: menuCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: menuCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: dropRoot.model
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                height: 28
                                radius: 5
                                readonly property bool isSelected: dropRoot.currentValue === modelData.id

                                color: isSelected 
                                    ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12)
                                    : (itemArea.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        font.weight: isSelected ? Font.DemiBold : Font.Normal
                                        color: isSelected ? Services.Theme.accent : (itemArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: isSelected
                                        text: Services.Icons.check
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 9
                                        color: Services.Theme.accent
                                    }
                                }

                                MouseArea {
                                    id: itemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        dropRoot.selected(modelData.id)
                                        dropMenu.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── 4. Settings Switch (Modern Minimal Capsule Toggle) ────────────────────
    component SettingsSwitch: Rectangle {
        id: switchRoot
        property string title: ""
        property string subtitle: ""
        property bool checked: false
        signal toggled(bool newState)

        Layout.fillWidth: true
        implicitHeight: Math.max(42, switchTextCol.implicitHeight + 16)
        radius: Services.Theme.radiusSm
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 12

            ColumnLayout {
                id: switchTextCol
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: switchRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.weight: Font.Medium
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

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                radius: 10
                color: switchRoot.checked ? Services.Theme.accent : (switchMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Services.Theme.bgElevated)
                border.color: switchRoot.checked ? Services.Theme.accent : Services.Theme.border
                border.width: 1

                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    y: 2
                    x: switchRoot.checked ? 20 : 2
                    color: switchRoot.checked ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
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

    // ── 5. Settings Slider (Ultra-Clean Track with Live Badge) ────────────────
    component SettingsSlider: ColumnLayout {
        id: sliderRoot
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
        spacing: 4
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.topMargin: 6
        Layout.bottomMargin: 6

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: sliderRoot.title
                    font.pixelSize: Services.Theme.fontSizeMd
                    font.weight: Font.Medium
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }
                Text {
                    visible: sliderRoot.subtitle.length > 0
                    text: sliderRoot.subtitle
                    font.pixelSize: Services.Theme.fontSizeXs
                    color: Services.Theme.textSecondary
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: valBadgeText.implicitWidth + 12
                radius: 4
                color: Services.Theme.bgElevated
                border.color: Services.Theme.border
                border.width: 1

                Text {
                    id: valBadgeText
                    anchors.centerIn: parent
                    text: sliderRoot.valuePrefix + (sliderRoot.decimals > 0 ? Number(sliderRoot.value).toFixed(sliderRoot.decimals) : Math.round(sliderRoot.value)) + sliderRoot.valueSuffix
                    font.family: Services.Theme.fontMono
                    font.pixelSize: 10
                    font.bold: true
                    color: Services.Theme.accent
                }
            }
        }

        Item {
            id: trackContainer
            Layout.fillWidth: true
            height: 16

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                radius: 2
                color: Services.Theme.bgDeep

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: Services.Theme.accent
                    width: Math.max(0, Math.min(parent.width, ((sliderRoot.value - sliderRoot.from) / Math.max(0.0001, sliderRoot.to - sliderRoot.from)) * parent.width))
                }
            }

            Rectangle {
                width: 14
                height: 14
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(trackContainer.width - width, ((sliderRoot.value - sliderRoot.from) / Math.max(0.0001, sliderRoot.to - sliderRoot.from)) * (trackContainer.width - width)))
                color: sDrag.pressed ? Services.Theme.accent : Services.Theme.bgElevated
                border.color: Services.Theme.accent
                border.width: 2
            }

            MouseArea {
                id: sDrag
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
                onPositionChanged: (mouse) => { if (pressed) updateVal(mouse.x) }
            }
        }
    }

    // ── 6. Hairline Divider ──────────────────────────────────────────────────
    component SettingsDivider: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Qt.rgba(1, 1, 1, 0.04)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // WINDOW ROOT LAYOUT
    // ═════════════════════════════════════════════════════════════════════════

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── WINDOW TITLEBAR ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 46
            color: Services.Theme.surfaceVariant

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

                // Window Title & Tab Breadcrumb
                RowLayout {
                    spacing: 8

                    Text {
                        text: Services.Icons.settings || ""
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 13
                        color: Services.Theme.accent
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: "Settings"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Services.Theme.textPrimary
                    }

                    Text {
                        text: "/"
                        font.pixelSize: 12
                        color: Services.Theme.textDisabled
                    }

                    Text {
                        text: {
                            const tabs = ["Appearance", "Bar & Island", "Notifications", "Sound & Audio", "Lock & Power", "Compositor", "Keybindings", "Backup & Reset", "About"]
                            return tabs[rootWindow.currentTab] || "Preferences"
                        }
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Services.Theme.accent
                    }
                }

                Item { Layout.fillWidth: true }

                // Esc key badge
                Rectangle {
                    implicitHeight: 20
                    implicitWidth: escText.implicitWidth + 12
                    radius: 4
                    color: Services.Theme.bgElevated
                    border.color: Services.Theme.border
                    border.width: 1
                    Text {
                        id: escText
                        anchors.centerIn: parent
                        text: "Esc"
                        font.family: Services.Theme.fontMono
                        font.pixelSize: 9
                        color: Services.Theme.textDisabled
                    }
                }

                // Close button
                Rectangle {
                    width: 24; height: 24; radius: 5
                    color: closeMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: Services.Icons.close || "✕"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 12
                        color: closeMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootWindow.close()
                    }
                }
            }
        }

        // ── MAIN BODY: SIDEBAR + CONTENT PANE ─────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── LEFT SIDEBAR (210px) ─────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 210
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
                    anchors.margins: 8
                    spacing: 4

                    ListView {
                        id: navList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        clip: true
                        interactive: false

                        model: [
                            { id: 0, title: "Appearance",    icon: Services.Icons.palette },
                            { id: 1, title: "Bar & Island",   icon: Services.Icons.controlcenter },
                            { id: 2, title: "Notifications",  icon: Services.Icons.bell },
                            { id: 3, title: "Sound & Audio",  icon: Services.Icons.speaker },
                            { id: 4, title: "Lock & Power",   icon: Services.Icons.power },
                            { id: 5, title: "Compositor",     icon: Services.Icons.display },
                            { id: 6, title: "Keybindings",    icon: Services.Icons.keyboard },
                            { id: 7, title: "Backup & Reset", icon: Services.Icons.undo },
                            { id: 8, title: "About",          icon: Services.Icons.info }
                        ]

                        delegate: Rectangle {
                            width: navList.width
                            height: 36
                            radius: 6
                            readonly property bool isCur: rootWindow.currentTab === modelData.id

                            color: isCur 
                                ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12)
                                : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                            border.color: isCur ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.25) : "transparent"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    text: modelData.icon
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 12
                                    color: isCur ? Services.Theme.accent : (tabMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.title
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.weight: isCur ? Font.Medium : Font.Normal
                                    color: isCur ? Services.Theme.textPrimary : (tabMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    opacity: isCur ? 1.0 : 0.0
                                    Layout.preferredWidth: 3
                                    Layout.preferredHeight: 12
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 1.5
                                    color: Services.Theme.accent
                                }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    rootWindow.currentTab = modelData.id
                                    if (modelData.id === 5 && Services.Compositor) Services.Compositor.refreshState()
                                    if (modelData.id === 6 && Services.Compositor) Services.Compositor.loadKeybinds()
                                }
                            }
                        }
                    }

                    // Sidebar Footer: Distro info
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 6
                        color: Services.Theme.bgElevated
                        border.color: Services.Theme.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: Services.OsInfo.logoGlyph || Services.Icons.kernel || "󰌽"
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: Services.Theme.accent
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Services.OsInfo.distroName || "Linux"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Services.Theme.textSecondary
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ── RIGHT SETTINGS CONTENT PANE ──────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Services.Theme.bg
                clip: true

                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.margins: 16
                    contentHeight: contentCol.implicitHeight + 24
                    contentWidth: width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: contentCol
                        width: contentFlick.width - 10
                        spacing: 14

                        // ═════════════════════════════════════════════
                        // TAB 0: APPEARANCE & THEMING
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 0
                            Layout.fillWidth: true
                            spacing: 14

                            // Wallpaper Section
                            SettingsSection {
                                title: "Desktop Wallpaper"
                                icon: Services.Icons.image

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 88
                                    Layout.margins: 8

                                    Flickable {
                                        anchors.fill: parent
                                        contentWidth: wpListRow.implicitWidth
                                        contentHeight: parent.height
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        RowLayout {
                                            id: wpListRow
                                            spacing: 8

                                            Repeater {
                                                model: Services.Wallpaper ? Services.Wallpaper.allWallpapers : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: 108; height: 72
                                                    radius: 6
                                                    clip: true
                                                    readonly property bool isCur: Services.Wallpaper && Services.Wallpaper.currentWallpaper === modelData.path
                                                    border.color: isCur ? Services.Theme.accent : (wCardMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                                                    border.width: isCur ? 2 : 1
                                                    color: Services.Theme.bgDeep

                                                    Image {
                                                        anchors.fill: parent
                                                        source: modelData.path.startsWith("/") ? ("file://" + modelData.path) : modelData.path
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        smooth: true
                                                        opacity: isCur || wCardMouse.containsMouse ? 1.0 : 0.75
                                                    }

                                                    Rectangle {
                                                        visible: isCur
                                                        anchors.top: parent.top; anchors.right: parent.right
                                                        anchors.margins: 4
                                                        width: 16; height: 16; radius: 8
                                                        color: Services.Theme.accent
                                                        Text { anchors.centerIn: parent; text: Services.Icons.check; font.family: Services.Theme.fontSymbols; font.pixelSize: 8; color: Services.Theme.bgOnAccent }
                                                    }

                                                    Rectangle {
                                                        visible: (modelData.isCustom === true) && (wCardMouse.containsMouse || delMouse.containsMouse)
                                                        anchors.top: parent.top; anchors.left: parent.left
                                                        anchors.margins: 4
                                                        width: 18; height: 18; radius: 9
                                                        color: delMouse.containsMouse ? Services.Theme.danger : Qt.rgba(0, 0, 0, 0.65)
                                                        border.color: Qt.rgba(1, 1, 1, 0.2)
                                                        border.width: 1
                                                        z: 2

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Services.Icons.trash || ""
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 9
                                                            color: "#ffffff"
                                                        }

                                                        MouseArea {
                                                            id: delMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (Services.Wallpaper) {
                                                                    Services.Wallpaper.removeCustomWallpaper(modelData.path)
                                                                }
                                                            }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: wCardMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Wallpaper) {
                                                                Services.Wallpaper.setWallpaper(modelData.path)
                                                                if (Services.Config && Services.Config.useMatugen) Services.Config.generateMatugen(modelData.path)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Custom Wallpaper"
                                    subtitle: "Add image file from local storage"

                                    Rectangle {
                                        implicitHeight: 26
                                        implicitWidth: addBtnText.implicitWidth + 14
                                        radius: 4
                                        color: addWpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border
                                        border.width: 1

                                        Text {
                                            id: addBtnText
                                            anchors.centerIn: parent
                                            text: "+ Add Image..."
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: Services.Theme.textPrimary
                                        }

                                        MouseArea {
                                            id: addWpMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper() }
                                        }
                                    }
                                }
                            }

                            // Theme Mode Section
                            SettingsSection {
                                title: "Theme & Palette Strategy"
                                icon: Services.Icons.palette || "*"

                                SettingsRow {
                                    title: "Theme Mode"
                                    subtitle: "Global color scheme"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.themeMode : "light"
                                        model: [
                                            { id: "dark",  label: "Dark Mode" },
                                            { id: "light", label: "Light Mode" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setThemeMode(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Matugen Dynamic Theme"
                                    subtitle: "Extract harmonious color palette directly from wallpaper"
                                    checked: Services.Config ? Services.Config.useMatugen : false
                                    onToggled: (st) => {
                                        if (Services.Config) {
                                            Services.Config.setUseMatugen(st, Services.Wallpaper ? Services.Wallpaper.currentWallpaper : "")
                                        }
                                    }
                                }
                            }

                            // Accent Color Presets
                            SettingsSection {
                                title: "Accent Color Swatches"
                                icon: Services.Icons.brush

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: palGrid.implicitHeight + 12
                                    Layout.margins: 6

                                    GridLayout {
                                        id: palGrid
                                        anchors.fill: parent
                                        columns: 3
                                        columnSpacing: 6
                                        rowSpacing: 6

                                        Repeater {
                                            model: Services.Config ? Services.Config.accentPresets : []
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                height: 32
                                                radius: 6
                                                readonly property bool isCur: Services.Config && Services.Config.accentName === modelData.name

                                                color: isCur ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12) : (palItemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Services.Theme.bgElevated)
                                                border.color: isCur ? Services.Theme.accent : Services.Theme.border
                                                border.width: isCur ? 1.5 : 1

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6

                                                    Rectangle {
                                                        width: 12; height: 12; radius: 6
                                                        color: modelData.preview || Services.Theme.accent
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.name
                                                        font.pixelSize: 11
                                                        font.weight: isCur ? Font.DemiBold : Font.Normal
                                                        color: isCur ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        visible: isCur
                                                        text: Services.Icons.check
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 9
                                                        color: Services.Theme.accent
                                                    }
                                                }

                                                MouseArea {
                                                    id: palItemMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (Services.Config) {
                                                            const hex = (Services.Config.themeMode === "light") ? modelData.lightHex : modelData.darkHex
                                                            Services.Config.setAccent(hex, modelData.name, modelData.isMatugen)
                                                            if (modelData.isMatugen && Services.Wallpaper) Services.Config.generateMatugen(Services.Wallpaper.currentWallpaper)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Typography & UI Scale Section
                            SettingsSection {
                                title: "Typography & Geometry"
                                icon: Services.Icons.font

                                SettingsRow {
                                    title: "UI Font Family"
                                    subtitle: "Global font for labels, widgets, and clock"

                                    SettingsDropdown {
                                        currentValue: {
                                            const f = Services.Config ? Services.Config.fontFamily : ""
                                            if (f.indexOf("JetBrains") !== -1) return "jetbrains"
                                            if (f.indexOf("SFMono") !== -1) return "sfmono"
                                            if (f.indexOf("Inter") !== -1) return "inter"
                                            if (f.indexOf("Fira") !== -1) return "firacode"
                                            return "default"
                                        }
                                        model: [
                                            { id: "sfmono",    label: "SFMono Nerd Font" },
                                            { id: "jetbrains", label: "JetBrains Mono" },
                                            { id: "inter",     label: "Inter UI" },
                                            { id: "firacode",  label: "FiraCode Mono" }
                                        ]
                                        onSelected: (val) => {
                                            if (!Services.Config) return
                                            if (val === "sfmono") Services.Config.setFontFamily("Liga SFMono Nerd Font, monospace")
                                            else if (val === "jetbrains") Services.Config.setFontFamily("JetBrainsMono Nerd Font, monospace")
                                            else if (val === "inter") Services.Config.setFontFamily("Inter, Sans-Serif")
                                            else if (val === "firacode") Services.Config.setFontFamily("FiraCode Nerd Font, monospace")
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Corner Rounding"
                                    subtitle: "Radius for panels, widgets, and popup overlays"
                                    from: 0; to: 28; stepSize: 1; valueSuffix: "px"
                                    value: Services.Config ? Services.Config.cornerRadius : 16
                                    onMoved: (v) => { if (Services.Config) Services.Config.setCornerRadius(Math.round(v)) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "UI Scale"
                                    subtitle: "Proportional scaling factor for all overlays"
                                    from: 75; to: 135; stepSize: 5; valueSuffix: "%"
                                    value: Services.Config ? Math.round(Services.Config.uiScale * 100) : 100
                                    onMoved: (v) => { if (Services.Config) Services.Config.setUiScale(v / 100) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Surface Glass Opacity"
                                    subtitle: "Transparency level of quickshell overlay cards"
                                    from: 0.50; to: 1.00; stepSize: 0.05; decimals: 2
                                    value: Services.Config ? Services.Config.glassOpacity : 0.85
                                    onMoved: (v) => { if (Services.Config) Services.Config.setGlassOpacity(Number(v.toFixed(2))) }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 1: BAR & DYNAMIC ISLAND
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 1
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Bar Architecture & Position"
                                icon: Services.Icons.controlcenter

                                SettingsRow {
                                    title: "Bar Architecture Preset"
                                    subtitle: "Overall layout and visual style"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.barStyle : "islands"
                                        model: [
                                            { id: "islands",  label: "Islands (Capsules)" },
                                            { id: "floating", label: "Floating Glass Bar" },
                                            { id: "unified",  label: "Unified Edge-to-Edge" },
                                            { id: "minimal",  label: "Minimalist Low-Profile" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setBarStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Screen Placement"
                                    subtitle: "Dock to top or bottom edge"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.barPosition : "top"
                                        model: [
                                            { id: "top",    label: "Top Status Bar" },
                                            { id: "bottom", label: "Bottom Dock Bar" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setBarPosition(val) }
                                    }
                                }
                            }

                            SettingsSection {
                                title: "Dynamic Island HUD"
                                icon: Services.Icons.bell

                                SettingsRow {
                                    title: "Notch Display Mode"
                                    subtitle: "Interactive media & status pill in bar center"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.islandStyle : "expanded"
                                        model: [
                                            { id: "expanded", label: "Full Dynamic Island" },
                                            { id: "compact",  label: "Compact HUD Notch" },
                                            { id: "hidden",   label: "Hidden / Off" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setIslandStyle(val) }
                                    }
                                }
                            }

                            SettingsSection {
                                title: "Workspaces Pager"
                                icon: Services.Icons.grid

                                SettingsRow {
                                    title: "Pager Style"
                                    subtitle: "Visual representation of workspaces"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.workspaceStyle : "pills"
                                        model: [
                                            { id: "pills",   label: "Dynamic Pills" },
                                            { id: "numbers", label: "Numbered (1, 2, 3...)" },
                                            { id: "dots",    label: "Minimal Dots" },
                                            { id: "icons",   label: "Context Icons" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setWorkspaceStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Always Show Primary Workspaces (1–5)"
                                    subtitle: "Keep primary workspaces visible even when inactive"
                                    checked: Services.Config ? Services.Config.workspaceShowAll : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setWorkspaceShowAll(st) }
                                }
                            }

                            SettingsSection {
                                title: "Clock & Date Typography"
                                icon: Services.Icons.clock

                                SettingsRow {
                                    title: "Date Format"
                                    subtitle: "Display format for calendar date"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.clockDateFormat : "short"
                                        model: [
                                            { id: "short", label: "Short (Kam, 20 Agt)" },
                                            { id: "full",  label: "Full (Kamis, 20 Agustus)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setClockDateFormat(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "24-Hour Time Format"
                                    subtitle: "Use 24h clock instead of 12h AM/PM"
                                    checked: Services.Config ? Services.Config.clock24h : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setClock24h(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Display Live Seconds"
                                    subtitle: "Render real-time ticking seconds"
                                    checked: Services.Config ? Services.Config.clockShowSeconds : false
                                    onToggled: (st) => { if (Services.Config) Services.Config.setClockShowSeconds(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Display Date Text"
                                    subtitle: "Show current day and date prefix in the bar"
                                    checked: Services.Config ? Services.Config.clockShowDate : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setClockShowDate(st) }
                                }
                            }

                            SettingsSection {
                                title: "Bar Modules Visibility"
                                icon: Services.Icons.eyeOpen || Services.Icons.eye

                                SettingsSwitch {
                                    title: "Workspaces Pager"
                                    checked: Services.Config ? Services.Config.showWorkspaces : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowWorkspaces(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "System Tray (SNI)"
                                    checked: Services.Config ? Services.Config.showSysTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowSysTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "System Resource Monitor"
                                    checked: Services.Config ? Services.Config.showSysmonTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowSysmonTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Volume & Audio Pill"
                                    checked: Services.Config ? Services.Config.showVolumeTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowVolumeTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Battery & Power Indicator"
                                    checked: Services.Config ? Services.Config.showBatteryTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowBatteryTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Control Center Trigger Pill"
                                    checked: Services.Config ? Services.Config.showControlCenterTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowControlCenterTray(st) }
                                }
                                SettingsDivider {}
                                SettingsSwitch {
                                    title: "Clock & Calendar Pill"
                                    checked: Services.Config ? Services.Config.showClockTray : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setShowClockTray(st) }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 2: NOTIFICATIONS
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 2
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Notification Alerts"
                                icon: Services.Icons.bell

                                SettingsSwitch {
                                    title: "Do Not Disturb"
                                    subtitle: "Mute all popups and banner alerts"
                                    checked: Services.Notifications.doNotDisturb
                                    onToggled: (st) => { Services.Notifications.doNotDisturb = st }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Popup Placement"
                                    subtitle: "Screen corner for notification toasts"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.notificationPosition : "top_right"
                                        model: [
                                            { id: "top_right",    label: "Top Right Corner" },
                                            { id: "top_center",   label: "Top Center (Notch)" },
                                            { id: "top_left",     label: "Top Left Corner" },
                                            { id: "bottom_right", label: "Bottom Right Corner" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setNotificationPosition(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Popup Duration"
                                    subtitle: "How long bubble popups remain on screen"
                                    from: 2; to: 15; stepSize: 1; valueSuffix: "s"
                                    value: Services.Config ? Services.Config.notificationTimeout : 5
                                    onMoved: (v) => { if (Services.Config) Services.Config.setNotificationTimeout(Math.round(v)) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "History Retention"
                                    subtitle: "Days before history entries expire"
                                    from: 1; to: 7; stepSize: 1; valueSuffix: " days"
                                    value: Services.Config ? Services.Config.notificationRetentionDays : 7
                                    onMoved: (v) => { if (Services.Config) Services.Config.setNotificationRetentionDays(Math.round(v)) }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Test & Actions"

                                    RowLayout {
                                        spacing: 8

                                        Rectangle {
                                            height: 28
                                            implicitWidth: testNotifTxt.implicitWidth + 16
                                            radius: 5
                                            color: tNotifMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { id: testNotifTxt; anchors.centerIn: parent; text: "Send Test"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                            MouseArea {
                                                id: tNotifMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: testNotifProc.running = true
                                            }
                                        }

                                        Rectangle {
                                            height: 28
                                            implicitWidth: clrNotifTxt.implicitWidth + 16
                                            radius: 5
                                            color: clrNotifMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            Text { id: clrNotifTxt; anchors.centerIn: parent; text: "Clear History"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.danger }
                                            MouseArea {
                                                id: clrNotifMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.Notifications) Services.Notifications.clearHistory() }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 3: SOUND & AUDIO
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 3
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Audio Feedback"
                                icon: Services.Icons.speaker

                                SettingsSwitch {
                                    title: "UI Sound Effects"
                                    subtitle: "Audible feedback for volume adjustments and alerts"
                                    checked: Services.Config ? Services.Config.soundFeedback : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setSoundFeedback(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Volume Adjustment Feedback"
                                    subtitle: "Tick chime on volume step change"
                                    checked: Services.Config ? Services.Config.soundVolumeFeedback : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setSoundVolumeFeedback(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Notification Chime Sound"
                                    subtitle: "Audible alert on incoming notification"
                                    checked: Services.Config ? Services.Config.soundNotifFeedback : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setSoundNotifFeedback(st) }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Audition Sounds"

                                    RowLayout {
                                        spacing: 6

                                        Rectangle {
                                            height: 26
                                            implicitWidth: s1Txt.implicitWidth + 12
                                            radius: 4
                                            color: s1Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { id: s1Txt; anchors.centerIn: parent; text: "Notification"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                            MouseArea {
                                                id: s1Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.SoundFeedback && typeof Services.SoundFeedback.playNotification === "function") Services.SoundFeedback.playNotification() }
                                            }
                                        }

                                        Rectangle {
                                            height: 26
                                            implicitWidth: s2Txt.implicitWidth + 12
                                            radius: 4
                                            color: s2Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { id: s2Txt; anchors.centerIn: parent; text: "Volume Step"; font.pixelSize: 10; color: Services.Theme.textPrimary }
                                            MouseArea {
                                                id: s2Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { if (Services.SoundFeedback && typeof Services.SoundFeedback.playVolumeChange === "function") Services.SoundFeedback.playVolumeChange() }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 4: LOCKSCREEN & POWER
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 4
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Lockscreen Display"
                                icon: Services.Icons.lock

                                SettingsRow {
                                    title: "Lockscreen Layout Mode"
                                    subtitle: "Overall layout style (Default, Compact Card, or Minimalist)"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenLayout : "default"
                                        model: [
                                            { id: "default", label: "Default (Spacious Spread)" },
                                            { id: "compact", label: "Compact (Centered Glass Card)" },
                                            { id: "minimal", label: "Minimal (Clean Typography)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenLayout(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Clock Presentation Style"
                                    subtitle: "Visual typography layout of lockscreen clock"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenClockStyle : "hero"
                                        model: [
                                            { id: "hero",        label: "Hero Large (96px)" },
                                            { id: "modern",      label: "Modern Stacked (HH / MM)" },
                                            { id: "minimal",     label: "Minimal Thin" },
                                            { id: "compact",     label: "Compact Capsule" },
                                            { id: "vertical",    label: "Vertical Split" },
                                            { id: "typographic", label: "Typographic Words" },
                                            { id: "radial",      label: "Radial Ring Gauge" },
                                            { id: "cyber",       label: "Cyberpunk HUD" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenClockStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Wallpaper Backdrop Source"
                                    subtitle: "Sync with active desktop or choose custom image"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenWallpaperMode : "sync"
                                        model: [
                                            { id: "sync",   label: "Sync Desktop Wallpaper" },
                                            { id: "custom", label: "Custom Dedicated Image" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenWallpaperMode(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Blur Wallpaper on Lockscreen"
                                    subtitle: "Gaussian blur backdrop on locked screen"
                                    checked: Services.Config ? Services.Config.lockscreenBlur : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenBlur(st) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Dimming Level"
                                    subtitle: "Backdrop darkness percentage"
                                    from: 0.10; to: 0.85; stepSize: 0.05; decimals: 2
                                    value: Services.Config ? Services.Config.lockscreenDim : 0.45
                                    onMoved: (v) => { if (Services.Config) Services.Config.setLockscreenDim(Number(v.toFixed(2))) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show Status Pill (Battery, Wi-Fi)"
                                    checked: Services.Config ? Services.Config.lockscreenShowStatusPill : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowStatusPill(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show System Uptime Tag"
                                    checked: Services.Config ? Services.Config.lockscreenShowUptime : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowUptime(st) }
                                }
                            }

                            // User Profile & Avatar Styling Section
                            SettingsSection {
                                title: "User Profile & Avatar"
                                icon: Services.Icons.user

                                SettingsRow {
                                    title: "Avatar Profile Shape"
                                    subtitle: "Geometry and curvature of avatar frame"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenAvatarShape : "circle"
                                        model: [
                                            { id: "circle",   label: "Circular (Round 360°)" },
                                            { id: "squircle", label: "Squircle (Smooth Curvature)" },
                                            { id: "rounded",  label: "Rounded Square (Radius 16)" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenAvatarShape(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Accent Glow Focus Ring"
                                    subtitle: "Outer breathing glow ring around avatar picture"
                                    checked: Services.Config ? Services.Config.lockscreenAvatarRing : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenAvatarRing(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Display Profile Picture"
                                    subtitle: "Show user avatar or initials monogram"
                                    checked: Services.Config ? Services.Config.lockscreenShowAvatar : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowAvatar(st) }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Display Greeting Subtitle"
                                    subtitle: "Show greeting and user@hostname tag"
                                    checked: Services.Config ? Services.Config.lockscreenShowGreeting : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowGreeting(st) }
                                }
                            }

                            // Password Input & Authentication Styling Section
                            SettingsSection {
                                title: "Password Authentication & Media"
                                icon: Services.Icons.keyboard

                                SettingsRow {
                                    title: "Input Field Design"
                                    subtitle: "Visual style of password entry field"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenInputStyle : "pill"
                                        model: [
                                            { id: "pill",      label: "Capsule Glass Pill" },
                                            { id: "underline", label: "Minimalist Underline" },
                                            { id: "box",       label: "Modern Inset Box" },
                                            { id: "dots",      label: "Discrete Dot Slots" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenInputStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Media Player Layout"
                                    subtitle: "Appearance of music and media widget on lockscreen"

                                    SettingsDropdown {
                                        currentValue: Services.Config ? Services.Config.lockscreenMediaStyle : "pill"
                                        model: [
                                            { id: "pill", label: "Floating Mini Capsule" },
                                            { id: "card", label: "Full Glass Album Card" }
                                        ]
                                        onSelected: (val) => { if (Services.Config) Services.Config.setLockscreenMediaStyle(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Show Media Player"
                                    subtitle: "Display media playback controls when audio is playing"
                                    checked: Services.Config ? Services.Config.lockscreenShowMedia : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setLockscreenShowMedia(st) }
                                }
                            }

                            SettingsSection {
                                title: "Power Profile & Battery"
                                icon: Services.Icons.power

                                SettingsRow {
                                    title: "CPU Governor Profile"
                                    subtitle: "Performance vs battery consumption strategy"

                                    SettingsDropdown {
                                        currentValue: Services.PowerProfile ? Services.PowerProfile.currentProfile : "balanced"
                                        model: [
                                            { id: "power-saver", label: "Power Saver (Battery)" },
                                            { id: "balanced",    label: "Balanced (Dynamic)" },
                                            { id: "performance", label: "Performance (Max Clocks)" }
                                        ]
                                        onSelected: (val) => { if (Services.PowerProfile) Services.PowerProfile.setProfile(val) }
                                    }
                                }

                                SettingsDivider {}

                                SettingsSwitch {
                                    title: "Low Battery Warning Alerts"
                                    subtitle: "Notify when charge level drops critically low"
                                    checked: Services.Config ? Services.Config.batteryShowWarnings : true
                                    onToggled: (st) => { if (Services.Config) Services.Config.setBatteryShowWarnings(st) }
                                }

                                SettingsDivider {}

                                SettingsSlider {
                                    title: "Low Battery Alert Threshold"
                                    from: 10; to: 35; stepSize: 5; valueSuffix: "%"
                                    value: Services.Config ? Services.Config.batteryLowThreshold : 20
                                    onMoved: (v) => { if (Services.Config) Services.Config.setBatteryLowThreshold(Math.round(v)) }
                                }
                            }

                            SettingsSection {
                                title: "Quick Power Actions"
                                icon: Services.Icons.refresh || Services.Icons.reboot

                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    Layout.margins: 6

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p1Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Lock Screen"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                            MouseArea { id: p1Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { rootWindow.close(); lockSessionProc.running = true } }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p2Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Suspend"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.textPrimary }
                                            MouseArea { id: p2Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: suspendProc.running = true }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p3Mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Reboot"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.warning }
                                            MouseArea { id: p3Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rebootProc.running = true }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 4
                                            color: p4Mouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                            border.color: Services.Theme.border; border.width: 1
                                            Text { anchors.centerIn: parent; text: "Power Off"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.danger }
                                            MouseArea { id: p4Mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: poweroffProc.running = true }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 5: COMPOSITOR & DISPLAYS (REDESIGNED: MINIMAL & RICH)
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 5
                            Layout.fillWidth: true
                            spacing: 12

                            // ── Hero / Status Header Card ────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 54
                                radius: Services.Theme.radiusMd
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    // Compositor Icon + Name + Version
                                    RowLayout {
                                        spacing: 8
                                        Text {
                                            text: Services.Icons.display
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 15
                                            color: Services.Theme.accent
                                        }

                                        ColumnLayout {
                                            spacing: 1
                                            Text {
                                                text: Services.Compositor ? Services.Compositor.activeDisplayName : "Compositor"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                color: Services.Theme.textPrimary
                                            }
                                            Text {
                                                text: Services.Compositor ? (Services.Compositor.activeVersion.split(" built")[0] || "Wayland Compositor") : "Wayland"
                                                font.pixelSize: 9
                                                color: Services.Theme.textDisabled
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: 260
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Quick Stats Badges
                                    RowLayout {
                                        spacing: 6

                                        Rectangle {
                                            height: 22
                                            implicitWidth: mTxt.implicitWidth + 12
                                            radius: 4
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: 4
                                                Text { text: Services.Icons.display; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: Services.Theme.accent }
                                                Text { id: mTxt; text: (Services.Compositor ? Services.Compositor.monitorsCount : 1) + " Display"; font.pixelSize: 9; font.weight: Font.Medium; color: Services.Theme.textSecondary }
                                            }
                                        }

                                        Rectangle {
                                            height: 22
                                            implicitWidth: wsTxt.implicitWidth + 12
                                            radius: 4
                                            color: Services.Theme.bgElevated
                                            border.color: Services.Theme.border
                                            border.width: 1
                                            RowLayout {
                                                anchors.centerIn: parent; spacing: 4
                                                Text { text: Services.Icons.grid; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: Services.Theme.accent }
                                                Text { id: wsTxt; text: (Services.Compositor ? Services.Compositor.workspacesCount : 1) + " Workspaces"; font.pixelSize: 9; font.weight: Font.Medium; color: Services.Theme.textSecondary }
                                            }
                                        }
                                    }

                                    // Action: Reload Compositor
                                    Rectangle {
                                        height: 26
                                        implicitWidth: rlTxt.implicitWidth + 16
                                        radius: 5
                                        color: rlMouse.containsMouse ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18) : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.08)
                                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                                        border.width: 1

                                        RowLayout {
                                            anchors.centerIn: parent; spacing: 6
                                            Text {
                                                text: Services.Icons.refresh
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 10
                                                color: Services.Theme.accent
                                            }
                                            Text {
                                                id: rlTxt
                                                text: "Reload"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                                color: Services.Theme.accent
                                            }
                                        }

                                        MouseArea {
                                            id: rlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Compositor) Services.Compositor.reloadCompositor() }
                                        }
                                    }
                                }
                            }

                            // ── 1-Click Aesthetic Profiles ─────────────────────────
                            SettingsSection {
                                title: "Quick Aesthetic Profiles (1-Click Presets)"
                                icon: Services.Icons.wand

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: profileGrid.implicitHeight + 8
                                    color: "transparent"

                                    GridLayout {
                                        id: profileGrid
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        columns: 4
                                        rowSpacing: 8
                                        columnSpacing: 8

                                        Repeater {
                                            model: [
                                                { id: "glass",    title: "Glass Elegance", icon: Services.Icons.sparkle, desc: "Dual Kawase blur, soft shadow, 88% opacity, 14px rounding" },
                                                { id: "gaming",   title: "Gaming & Fast",  icon: Services.Icons.speed,   desc: "0 blur, 0 anim, tearing allowed, low latency, snappy" },
                                                { id: "minimal",  title: "Clean Minimal",  icon: Services.Icons.layout,  desc: "0 gaps, 0 border, 100% solid, distraction-free" },
                                                { id: "material", title: "Material You",   icon: Services.Icons.palette, desc: "Wallpaper dynamic palette, 12px rounding, 10px gaps" }
                                            ]

                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 70
                                                radius: Services.Theme.radiusSm
                                                readonly property bool isAct: Services.Compositor && Services.Compositor.activePreset === modelData.id
                                                color: isAct ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12) : (pMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Services.Theme.bgElevated)
                                                border.color: isAct ? Services.Theme.accent : (pMouse.containsMouse ? Services.Theme.textDisabled : Services.Theme.border)
                                                border.width: isAct ? 1.5 : 1

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 4

                                                    RowLayout {
                                                        spacing: 6
                                                        Text {
                                                            text: modelData.icon
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 11
                                                            color: isAct ? Services.Theme.accent : Services.Theme.textPrimary
                                                        }
                                                        Text {
                                                            text: modelData.title
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                            color: isAct ? Services.Theme.accent : Services.Theme.textPrimary
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.desc
                                                        font.pixelSize: 9
                                                        color: Services.Theme.textSecondary
                                                        wrapMode: Text.WordWrap
                                                        elide: Text.ElideRight
                                                        maximumLineCount: 2
                                                    }
                                                }

                                                MouseArea {
                                                    id: pMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { if (Services.Compositor) Services.Compositor.applyPreset(modelData.id) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Segment Switcher Pill Bar ──────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: Services.Theme.radiusSm
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    spacing: 3

                                    Repeater {
                                        model: [
                                            { id: 0, label: "Window Styling", icon: Services.Icons.sparkles },
                                            { id: 1, label: "Displays & Monitors", icon: Services.Icons.display },
                                            { id: 2, label: "Input & Gestures", icon: Services.Icons.sliders },
                                            { id: 3, label: "Power & Gaming", icon: Services.Icons.speed }
                                        ]

                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 4
                                            readonly property bool isCur: rootWindow.compSubTab === modelData.id
                                            color: isCur ? Services.Theme.accent : (subMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

                                            RowLayout {
                                                anchors.centerIn: parent; spacing: 5
                                                Text {
                                                    text: modelData.icon
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 10
                                                    color: isCur ? "#ffffff" : (subMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                }
                                                Text {
                                                    text: modelData.label
                                                    font.pixelSize: 10
                                                    font.weight: isCur ? Font.DemiBold : Font.Normal
                                                    color: isCur ? "#ffffff" : (subMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                                }
                                            }

                                            MouseArea {
                                                id: subMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: rootWindow.compSubTab = modelData.id
                                            }
                                        }
                                    }
                                }
                            }

                            // ── SUB-TAB 0: WINDOW STYLING & GLASS ──────────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 0
                                Layout.fillWidth: true
                                spacing: 10

                                SettingsSection {
                                    title: "Glass Blur & Animations"
                                    icon: Services.Icons.sparkle

                                    SettingsSwitch {
                                        title: "Window Animations"
                                        subtitle: "Smooth window open/close and workspace transitions"
                                        checked: Services.Compositor ? Services.Compositor.hyprAnim : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprAnim() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Dual Kawase Glass Blur"
                                        subtitle: "Background blur for translucent windows and quickshell panels"
                                        checked: Services.Compositor ? Services.Compositor.hyprBlur : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprBlur() }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Blur Radius (Size)"
                                        from: 1; to: 16; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprBlurSize : 4
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurSize(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Blur Iterations (Passes)"
                                        from: 1; to: 5; stepSize: 1; valueSuffix: "x"
                                        value: Services.Compositor ? Services.Compositor.hyprBlurPasses : 2
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBlurPasses(Math.round(v)) }
                                    }
                                }

                                SettingsSection {
                                    title: "Window Opacity & Dimming"
                                    icon: Services.Icons.contrast

                                    SettingsSlider {
                                        title: "Active Window Opacity"
                                        from: 0.50; to: 1.00; stepSize: 0.01; decimals: 2
                                        value: Services.Compositor ? Services.Compositor.hyprActiveOpacity : 0.90
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprActiveOpacity(Number(v.toFixed(2))) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Inactive Window Opacity"
                                        from: 0.50; to: 1.00; stepSize: 0.01; decimals: 2
                                        value: Services.Compositor ? Services.Compositor.hyprInactiveOpacity : 0.95
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprInactiveOpacity(Number(v.toFixed(2))) }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Dim Inactive Windows"
                                        subtitle: "Darken background windows to emphasize active focus"
                                        checked: Services.Compositor ? Services.Compositor.hyprDimInactive : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprDimInactive() }
                                    }
                                }

                                SettingsSection {
                                    title: "Window Geometry & Gaps"
                                    icon: Services.Icons.layout

                                    SettingsSlider {
                                        title: "Window Corner Radius"
                                        from: 0; to: 28; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprRounding : 10
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprRounding(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Border Thickness"
                                        from: 0; to: 6; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprBorderSize : 0
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprBorderSize(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Gaps In (Between Windows)"
                                        from: 0; to: 24; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprGapsIn : 5
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsIn(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Gaps Out (Screen Margins)"
                                        from: 0; to: 36; stepSize: 1; valueSuffix: "px"
                                        value: Services.Compositor ? Services.Compositor.hyprGapsOut : 10
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprGapsOut(Math.round(v)) }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Smart Gaps (No Gaps When Only)"
                                        subtitle: "Automatically remove gaps and borders if only one window is open"
                                        checked: Services.Compositor ? Services.Compositor.hyprSmartGaps : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprSmartGaps() }
                                    }
                                }
                            }

                            // ── SUB-TAB 1: DISPLAYS & MONITORS ─────────────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 1
                                Layout.fillWidth: true
                                spacing: 10

                                SettingsSection {
                                    title: "Connected Displays (" + (Services.Compositor ? Services.Compositor.monitorsCount : 1) + ")"
                                    icon: Services.Icons.display

                                    Repeater {
                                        model: Services.Compositor ? Services.Compositor.monitorsList : []

                                        delegate: ColumnLayout {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: monCol.implicitHeight + 20
                                                radius: Services.Theme.radiusSm
                                                color: Services.Theme.bgElevated
                                                border.color: modelData.focused ? Services.Theme.accent : Services.Theme.border
                                                border.width: modelData.focused ? 1.5 : 1

                                                ColumnLayout {
                                                    id: monCol
                                                    anchors.fill: parent
                                                    anchors.margins: 12
                                                    spacing: 10

                                                    // Monitor Header
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 8

                                                        Text { text: Services.Icons.display; font.family: Services.Theme.fontSymbols; font.pixelSize: 14; color: Services.Theme.accent }

                                                        ColumnLayout {
                                                            spacing: 1
                                                            RowLayout {
                                                                spacing: 6
                                                                Text { text: modelData.name || "Display"; font.pixelSize: 12; font.weight: Font.DemiBold; color: Services.Theme.textPrimary }
                                                                Rectangle {
                                                                    visible: modelData.focused
                                                                    height: 16; implicitWidth: fTxt.implicitWidth + 8; radius: 3
                                                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                                                                    Text { id: fTxt; anchors.centerIn: parent; text: "PRIMARY / FOCUSED"; font.pixelSize: 8; font.weight: Font.Bold; color: Services.Theme.accent }
                                                                }
                                                            }
                                                            Text { text: (modelData.description || "Internal Screen") + " • " + modelData.width + "×" + modelData.height + " @" + modelData.refreshRate + "Hz"; font.pixelSize: 9; color: Services.Theme.textSecondary }
                                                        }

                                                        Item { Layout.fillWidth: true }

                                                        // Resolution badge
                                                        Rectangle {
                                                            height: 22
                                                            implicitWidth: resTxt.implicitWidth + 10
                                                            radius: 4
                                                            color: Services.Theme.surfaceVariant
                                                            border.color: Services.Theme.border; border.width: 1
                                                            Text { id: resTxt; anchors.centerIn: parent; text: modelData.width + "×" + modelData.height; font.pixelSize: 9; font.family: Services.Theme.fontMono; color: Services.Theme.textPrimary }
                                                        }
                                                    }

                                                    // Live Scaling Slider & Preset Buttons
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            Text { text: "Display Scale Factor"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                            Item { Layout.fillWidth: true }
                                                            Text { text: (Number(modelData.scale || 1.0) * 100).toFixed(0) + "% (" + Number(modelData.scale || 1.0).toFixed(2) + "x)"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.accent }
                                                        }

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 8

                                                            Slider {
                                                                Layout.fillWidth: true
                                                                from: 0.75; to: 2.00; stepSize: 0.05
                                                                value: Number(modelData.scale || 1.0)
                                                                onMoved: () => { if (Services.Compositor) Services.Compositor.setMonitorScale(modelData.name, value) }
                                                            }

                                                            // Quick Scale presets
                                                            Repeater {
                                                                model: [1.0, 1.25, 1.5, 1.75, 2.0]
                                                                delegate: Rectangle {
                                                                    width: 36; height: 22; radius: 3
                                                                    readonly property bool isSel: Math.abs(Number(modelData.scale || 1.0) - Number(modelData)) < 0.01
                                                                    color: isSel ? Services.Theme.accent : (scMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.surfaceVariant)
                                                                    border.color: isSel ? Services.Theme.accent : Services.Theme.border; border.width: 1
                                                                    Text { anchors.centerIn: parent; text: (Number(modelData) * 100).toFixed(0) + "%"; font.pixelSize: 8; font.weight: Font.Medium; color: isSel ? "#ffffff" : Services.Theme.textSecondary }
                                                                    MouseArea {
                                                                        id: scMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                        onClicked: { if (Services.Compositor) Services.Compositor.setMonitorScale(modelData.name, modelData) }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // VRR Adaptive Sync Switch
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: "Variable Refresh Rate (VRR / FreeSync / G-Sync)"; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                                        Item { Layout.fillWidth: true }
                                                        Switch {
                                                            checked: Boolean(modelData.vrr)
                                                            onToggled: { if (Services.Compositor) Services.Compositor.setMonitorVRR(modelData.name, checked) }
                                                        }
                                                    }
                                                }
                                            }

                                            SettingsDivider { visible: index < (Services.Compositor.monitorsList.length - 1) }
                                        }
                                    }
                                }
                            }

                            // ── SUB-TAB 2: INPUT & TOUCHPAD GESTURES ───────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 2
                                Layout.fillWidth: true
                                spacing: 10

                                SettingsSection {
                                    title: "Window Focus Behavior"
                                    icon: Services.Icons.sliders

                                    SettingsRow {
                                        title: "Focus Follows Mouse"
                                        subtitle: "How window focus is shifted when moving the cursor"

                                        SettingsDropdown {
                                            currentValue: Services.Compositor ? String(Services.Compositor.hyprFollowMouse) : "1"
                                            model: [
                                                { id: "1", label: "Hover Focus (Continuous)" },
                                                { id: "0", label: "Click to Focus (Strict)" },
                                                { id: "2", label: "Click on Tiled, Hover on Floating" }
                                            ]
                                            onSelected: (val) => { if (Services.Compositor) Services.Compositor.setHyprFollowMouse(val) }
                                        }
                                    }
                                }

                                SettingsSection {
                                    title: "Touchpad & Gestures"
                                    icon: Services.Icons.touchpad || Services.Icons.sliders

                                    SettingsSwitch {
                                        title: "Natural Scrolling"
                                        subtitle: "Reverse scrolling direction (swipe up scrolls content up)"
                                        checked: Services.Compositor ? Services.Compositor.hyprTouchpadNatural : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTouchpadNatural() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Tap to Click"
                                        subtitle: "Tap touchpad surface to trigger primary click"
                                        checked: Services.Compositor ? Services.Compositor.hyprTouchpadTap : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTouchpadTap() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Disable While Typing (DWT)"
                                        subtitle: "Prevent accidental palm clicks when typing on the keyboard"
                                        checked: Services.Compositor ? Services.Compositor.hyprTouchpadDwt : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTouchpadDwt() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Touchpad 3-Finger Workspace Swipe"
                                        subtitle: "Smooth 1:1 trackpad swipe gesture to switch active workspace"
                                        checked: Services.Compositor ? Services.Compositor.hyprWorkspaceSwipe : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprWorkspaceSwipe() }
                                    }

                                    SettingsDivider {}

                                    SettingsSlider {
                                        title: "Touchpad Pointer Sensitivity"
                                        from: -1.0; to: 1.0; stepSize: 0.05; decimals: 2
                                        value: Services.Compositor ? Services.Compositor.hyprSensitivity : 0.0
                                        onMoved: (v) => { if (Services.Compositor) Services.Compositor.setHyprSensitivity(Number(v.toFixed(2))) }
                                    }
                                }
                            }

                            // ── SUB-TAB 3: POWER & GAMING ──────────────────────────
                            ColumnLayout {
                                visible: rootWindow.compSubTab === 3
                                Layout.fillWidth: true
                                spacing: 10

                                SettingsSection {
                                    title: "Battery & Performance Optimizations"
                                    icon: Services.Icons.speed

                                    SettingsSwitch {
                                        title: "Variable Frame Rate (VFR)"
                                        subtitle: "Lower rendering refresh rate when the screen is static to conserve laptop battery"
                                        checked: Services.Compositor ? Services.Compositor.hyprVFR : true
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprVFR() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Allow Screen Tearing (Gaming Low-Latency)"
                                        subtitle: "Enable direct scanout tearing for competitive games to reduce input lag"
                                        checked: Services.Compositor ? Services.Compositor.hyprAllowTearing : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprTearing() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Resize Windows on Border"
                                        subtitle: "Allow dragging window borders directly to resize tiled windows"
                                        checked: Services.Compositor ? Services.Compositor.hyprResizeOnBorder : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprResizeBorder() }
                                    }

                                    SettingsDivider {}

                                    SettingsSwitch {
                                        title: "Disable Hyprland Default Splash & Logo"
                                        subtitle: "Suppress anime mascot splash screen on session start"
                                        checked: Services.Compositor ? Services.Compositor.hyprDisableLogo : false
                                        onToggled: () => { if (Services.Compositor) Services.Compositor.toggleHyprDisableLogo() }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 6: KEYBINDINGS (LIVE FROM COMPOSITOR CONFIG)
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 6
                            Layout.fillWidth: true
                            spacing: 12

                            // ── Search & Filter & Add Bar ──────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: Services.Theme.radiusMd
                                color: Services.Theme.surfaceVariant
                                border.color: Services.Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Text {
                                        text: Services.Icons.search
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 12
                                        color: Services.Theme.textSecondary
                                    }

                                    TextField {
                                        id: keySearchInput
                                        Layout.fillWidth: true
                                        placeholderText: "Search shortcuts by keys, command, or category..."
                                        placeholderTextColor: Services.Theme.textDisabled
                                        text: rootWindow.keySearchQuery
                                        onTextChanged: rootWindow.keySearchQuery = text
                                        font.pixelSize: 11
                                        color: Services.Theme.textPrimary
                                        background: null
                                    }

                                    // Category Filter Pills
                                    RowLayout {
                                        spacing: 4

                                        Repeater {
                                            model: [
                                                { id: "all",        label: "All" },
                                                { id: "quickshell", label: "Quickshell" },
                                                { id: "nav",        label: "Window / Nav" },
                                                { id: "apps",       label: "Apps" },
                                                { id: "screenshot", label: "Screenshot" },
                                                { id: "media",      label: "Media" }
                                            ]

                                            delegate: Rectangle {
                                                height: 24
                                                implicitWidth: cTxt.implicitWidth + 12
                                                radius: 4
                                                readonly property bool isCur: rootWindow.keyCategory === modelData.id
                                                color: isCur ? Services.Theme.accent : (catMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated)
                                                border.color: isCur ? Services.Theme.accent : Services.Theme.border
                                                border.width: 1

                                                Text {
                                                    id: cTxt
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    font.pixelSize: 9
                                                    font.weight: isCur ? Font.Bold : Font.Medium
                                                    color: isCur ? "#ffffff" : Services.Theme.textSecondary
                                                }

                                                MouseArea {
                                                    id: catMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: rootWindow.keyCategory = modelData.id
                                                }
                                            }
                                        }
                                    }

                                    // Add Keybind Button
                                    Rectangle {
                                        height: 26
                                        implicitWidth: addTxt.implicitWidth + 16
                                        radius: 4
                                        color: Services.Theme.accent
                                        RowLayout {
                                            anchors.centerIn: parent; spacing: 4
                                            Text { text: Services.Icons.plus || "+"; font.family: Services.Theme.fontSymbols; font.pixelSize: 9; color: "#ffffff" }
                                            Text { id: addTxt; text: "Add Shortcut"; font.pixelSize: 9; font.weight: Font.DemiBold; color: "#ffffff" }
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                rootWindow.isAddingKeybind = !rootWindow.isAddingKeybind
                                                rootWindow.formKeys = ""
                                                rootWindow.formAction = ""
                                                rootWindow.formDesc = ""
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Add Keybinding Form Card (Collapsible) ──────────────
                            Rectangle {
                                visible: rootWindow.isAddingKeybind
                                Layout.fillWidth: true
                                implicitHeight: addFormCol.implicitHeight + 20
                                radius: Services.Theme.radiusSm
                                color: Services.Theme.bgElevated
                                border.color: Services.Theme.accent
                                border.width: 1.5

                                ColumnLayout {
                                    id: addFormCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    RowLayout {
                                        Text { text: "Add New Shortcut to Compositor Config"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Services.Theme.accent }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Services.Icons.close || "✕"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Theme.textDisabled
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: rootWindow.isAddingKeybind = false
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.preferredWidth: 180
                                            spacing: 2
                                            Text { text: "Key Combination"; font.pixelSize: 9; color: Services.Theme.textSecondary }
                                            Rectangle {
                                                Layout.fillWidth: true; height: 28; radius: 4
                                                color: Services.Theme.surfaceVariant; border.color: Services.Theme.border; border.width: 1
                                                TextField {
                                                    anchors.fill: parent; anchors.margins: 4
                                                    placeholderText: "SUPER + K"
                                                    placeholderTextColor: Services.Theme.textDisabled
                                                    text: rootWindow.formKeys
                                                    onTextChanged: rootWindow.formKeys = text
                                                    font.family: Services.Theme.fontMono; font.pixelSize: 10; color: Services.Theme.textPrimary
                                                    background: null
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Text { text: "Command / Dispatcher Action"; font.pixelSize: 9; color: Services.Theme.textSecondary }
                                            Rectangle {
                                                Layout.fillWidth: true; height: 28; radius: 4
                                                color: Services.Theme.surfaceVariant; border.color: Services.Theme.border; border.width: 1
                                                TextField {
                                                    anchors.fill: parent; anchors.margins: 4
                                                    placeholderText: "kitty  or  qs ipc call powermenu toggle"
                                                    placeholderTextColor: Services.Theme.textDisabled
                                                    text: rootWindow.formAction
                                                    onTextChanged: rootWindow.formAction = text
                                                    font.family: Services.Theme.fontMono; font.pixelSize: 10; color: Services.Theme.textPrimary
                                                    background: null
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.alignment: Qt.AlignBottom
                                            height: 28; implicitWidth: saveAddTxt.implicitWidth + 16; radius: 4
                                            color: Services.Theme.accent
                                            Text { id: saveAddTxt; anchors.centerIn: parent; text: "Save"; font.pixelSize: 10; font.weight: Font.DemiBold; color: "#ffffff" }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (Services.Compositor && rootWindow.formKeys && rootWindow.formAction) {
                                                        Services.Compositor.addKeybind(rootWindow.formKeys, rootWindow.formAction, rootWindow.formDesc)
                                                        rootWindow.isAddingKeybind = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Live Keybindings List ──────────────────────────────
                            SettingsSection {
                                title: "Configured Shortcuts (" + (Services.Compositor ? Services.Compositor.keybindsList.length : 0) + ")"
                                icon: Services.Icons.keyboard

                                readonly property var filteredBinds: {
                                    const q = (rootWindow.keySearchQuery || "").toLowerCase().trim()
                                    const cat = rootWindow.keyCategory
                                    const list = (Services.Compositor ? Services.Compositor.keybindsList : []) || []
                                    return list.filter(k => {
                                        if (cat !== "all" && k.category !== cat) return false
                                        if (q.length === 0) return true
                                        const ks = (k.keys || "").toLowerCase()
                                        const act = (k.action || "").toLowerCase()
                                        return ks.includes(q) || act.includes(q)
                                    })
                                }

                                Repeater {
                                    model: parent.filteredBinds

                                    delegate: ColumnLayout {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        spacing: 0

                                        readonly property bool isEditingThis: rootWindow.editingBindLine === modelData.startLine

                                        // Regular Display Row
                                        RowLayout {
                                            visible: !isEditingThis
                                            Layout.fillWidth: true
                                            Layout.topMargin: 8
                                            Layout.bottomMargin: 8
                                            spacing: 10

                                            // Action command and category
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2

                                                RowLayout {
                                                    spacing: 6
                                                    Text {
                                                        text: modelData.action || "No action"
                                                        font.family: Services.Theme.fontMono
                                                        font.pixelSize: 11
                                                        font.weight: Font.Medium
                                                        color: Services.Theme.textPrimary
                                                        elide: Text.ElideMiddle
                                                        Layout.maximumWidth: 380
                                                    }

                                                    Rectangle {
                                                        height: 16; implicitWidth: catTxt.implicitWidth + 8; radius: 3
                                                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.1)
                                                        Text { id: catTxt; anchors.centerIn: parent; text: modelData.category || "custom"; font.pixelSize: 8; font.weight: Font.DemiBold; color: Services.Theme.accent }
                                                    }
                                                }

                                                Text {
                                                    text: "Line " + modelData.startLine + (modelData.opts ? " • " + modelData.opts : "")
                                                    font.pixelSize: 8
                                                    color: Services.Theme.textDisabled
                                                }
                                            }

                                            // Shortcut Key Badges
                                            RowLayout {
                                                spacing: 4

                                                Repeater {
                                                    model: modelData.keyTokens || [modelData.keys]
                                                    delegate: RowLayout {
                                                        required property string modelData
                                                        required property int index
                                                        spacing: 4

                                                        Rectangle {
                                                            height: 22
                                                            implicitWidth: kbTxt.implicitWidth + 12
                                                            radius: 4
                                                            color: Services.Theme.bgElevated
                                                            border.color: Services.Theme.border
                                                            border.width: 1

                                                            Text {
                                                                id: kbTxt
                                                                anchors.centerIn: parent
                                                                text: parent.parent.modelData
                                                                font.family: Services.Theme.fontMono
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                                color: Services.Theme.accent
                                                            }
                                                        }

                                                        Text {
                                                            visible: parent.parent.index < (parent.parent.parent.count - 1)
                                                            text: "+"
                                                            font.pixelSize: 10
                                                            font.weight: Font.Bold
                                                            color: Services.Theme.textDisabled
                                                        }
                                                    }
                                                }
                                            }

                                            // Actions: Copy, Edit, Delete
                                            RowLayout {
                                                spacing: 4

                                                // Copy Button
                                                Rectangle {
                                                    width: 24; height: 24; radius: 4
                                                    color: cpMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.clipboard
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 10
                                                        color: cpMouse.containsMouse ? Services.Theme.accent : Services.Theme.textDisabled
                                                    }
                                                    MouseArea {
                                                        id: cpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Clipboard) Services.Clipboard.copyText(modelData.action)
                                                        }
                                                    }
                                                }

                                                // Edit Button
                                                Rectangle {
                                                    width: 24; height: 24; radius: 4
                                                    color: edMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.sliders || "✎"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 10
                                                        color: edMouse.containsMouse ? Services.Theme.accent : Services.Theme.textDisabled
                                                    }
                                                    MouseArea {
                                                        id: edMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            rootWindow.editingBindLine = modelData.startLine
                                                            rootWindow.formKeys = modelData.keys
                                                            rootWindow.formAction = modelData.action
                                                        }
                                                    }
                                                }

                                                // Delete Button
                                                Rectangle {
                                                    width: 24; height: 24; radius: 4
                                                    color: delMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.trash
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 10
                                                        color: delMouse.containsMouse ? Services.Theme.danger : Services.Theme.textDisabled
                                                    }
                                                    MouseArea {
                                                        id: delMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Compositor) Services.Compositor.deleteKeybind(modelData.startLine)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Inline Edit Row (when active)
                                        Rectangle {
                                            visible: isEditingThis
                                            Layout.fillWidth: true
                                            implicitHeight: editRow.implicitHeight + 14
                                            radius: Services.Theme.radiusSm
                                            color: Services.Theme.surfaceVariant
                                            border.color: Services.Theme.accent
                                            border.width: 1

                                            RowLayout {
                                                id: editRow
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 8

                                                TextField {
                                                    Layout.preferredWidth: 160
                                                    text: rootWindow.formKeys
                                                    onTextChanged: rootWindow.formKeys = text
                                                    font.family: Services.Theme.fontMono; font.pixelSize: 10; color: Services.Theme.textPrimary
                                                    placeholderText: "Keys (e.g. SUPER + K)"
                                                }

                                                TextField {
                                                    Layout.fillWidth: true
                                                    text: rootWindow.formAction
                                                    onTextChanged: rootWindow.formAction = text
                                                    font.family: Services.Theme.fontMono; font.pixelSize: 10; color: Services.Theme.textPrimary
                                                    placeholderText: "Action (e.g. kitty)"
                                                }

                                                Rectangle {
                                                    height: 24; implicitWidth: svEdTxt.implicitWidth + 12; radius: 4
                                                    color: Services.Theme.accent
                                                    Text { id: svEdTxt; anchors.centerIn: parent; text: "Save"; font.pixelSize: 9; font.weight: Font.DemiBold; color: "#ffffff" }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (Services.Compositor && rootWindow.formKeys && rootWindow.formAction) {
                                                                Services.Compositor.updateKeybind(modelData.startLine, rootWindow.formKeys, rootWindow.formAction, "")
                                                                rootWindow.editingBindLine = -1
                                                            }
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    height: 24; implicitWidth: cnEdTxt.implicitWidth + 12; radius: 4
                                                    color: Services.Theme.bgElevated; border.color: Services.Theme.border; border.width: 1
                                                    Text { id: cnEdTxt; anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 9; color: Services.Theme.textSecondary }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: rootWindow.editingBindLine = -1
                                                    }
                                                }
                                            }
                                        }

                                        SettingsDivider { visible: index < (parent.filteredBinds.length - 1) }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 7: BACKUP & RESET
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 7
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "Configuration Management"
                                icon: Services.Icons.undo

                                SettingsRow {
                                    title: "Export Configuration"
                                    subtitle: "Save a backup snapshot of your current settings"

                                    Rectangle {
                                        height: 26
                                        implicitWidth: expTxt.implicitWidth + 14
                                        radius: 4
                                        color: expMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1
                                        Text { id: expTxt; anchors.centerIn: parent; text: "Backup..."; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                        MouseArea {
                                            id: expMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Config) Services.Config.exportConfig() }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Import Configuration"
                                    subtitle: "Restore previously exported settings snapshot"

                                    Rectangle {
                                        height: 26
                                        implicitWidth: impTxt.implicitWidth + 14
                                        radius: 4
                                        color: impMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1
                                        Text { id: impTxt; anchors.centerIn: parent; text: "Restore..."; font.pixelSize: 11; color: Services.Theme.textPrimary }
                                        MouseArea {
                                            id: impMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Config) Services.Config.importConfig() }
                                        }
                                    }
                                }

                                SettingsDivider {}

                                SettingsRow {
                                    title: "Reset to Defaults"
                                    subtitle: "Restore factory theme, layout, and configuration"

                                    Rectangle {
                                        height: 26
                                        implicitWidth: rstTxt.implicitWidth + 14
                                        radius: 4
                                        color: rstMouse.containsMouse ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Services.Theme.bgElevated
                                        border.color: Services.Theme.border; border.width: 1
                                        Text { id: rstTxt; anchors.centerIn: parent; text: "Reset All"; font.pixelSize: 11; color: Services.Theme.danger }
                                        MouseArea {
                                            id: rstMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { if (Services.Config) Services.Config.resetToDefaults() }
                                        }
                                    }
                                }
                            }
                        }

                        // ═════════════════════════════════════════════
                        // TAB 8: ABOUT & SYSTEM INFORMATION
                        // ═════════════════════════════════════════════
                        ColumnLayout {
                            visible: rootWindow.currentTab === 8
                            Layout.fillWidth: true
                            spacing: 14

                            SettingsSection {
                                title: "System Information"
                                icon: Services.Icons.info

                                SettingsRow {
                                    title: "OS Distribution"
                                    Text { text: Services.OsInfo.distroName || "Linux"; font.pixelSize: 11; font.weight: Font.Medium; color: Services.Theme.accent }
                                }
                                SettingsDivider {}
                                SettingsRow {
                                    title: "Kernel Version"
                                    Text { text: Services.OsInfo.kernel || "-"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }
                                SettingsDivider {}
                                SettingsRow {
                                    title: "Host Machine"
                                    Text { text: Services.OsInfo.hostname || "local"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }
                                SettingsDivider {}
                                SettingsRow {
                                    title: "User Shell"
                                    Text { text: Services.OsInfo.shellName || "sh"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                }
                                SettingsDivider {}
                                SettingsRow {
                                    title: "Compositor Protocol"
                                    Text { text: (Services.Compositor ? Services.Compositor.activeDisplayName : "Wayland") + " (Wayland LayerShell v1)"; font.pixelSize: 11; color: Services.Theme.textSecondary }
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
        command: ["notify-send", "-a", "Quickshell Settings", "Settings Test", "Your notification preferences are working!"]
    }
    Process {
        id: lockSessionProc
        command: ["sh", "-c", "qs ipc call lockscreen lock || loginctl lock-session"]
    }
    Process {
        id: suspendProc
        command: ["systemctl", "suspend"]
    }
    Process {
        id: rebootProc
        command: ["systemctl", "reboot"]
    }
    Process {
        id: poweroffProc
        command: ["systemctl", "poweroff"]
    }
}