import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services" as Services
import "." as Local

PanelWindow {
    id: root
    property string overlayId: "controlCenter"

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.controlCenterVisible
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:controlcenter"
    WlrLayershell.keyboardFocus: Services.OverlayManager.isLocked ? WlrKeyboardFocus.Exclusive : (root.wifiPasswordTarget !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    property string wifiPasswordTarget: ""
    property string wifiPasswordInput: ""
    property bool audioSinkSelectorOpen: false

    Process {
        id: pwrProc
        command: ["quickshell", "ipc", "call", "powermenu", "open"]
    }
    Process {
        id: settingsProc
        command: ["quickshell", "ipc", "call", "settings", "show"]
    }
    Process {
        id: screenshotProc
        command: ["sh", "-c", "mkdir -p ~/Pictures/Screenshots && sleep 0.2 && (hyprshot -m region -o ~/Pictures/Screenshots || (GEOM=$(slurp) && [ -n \"$GEOM\" ] && FILE=\"$HOME/Pictures/Screenshots/Screenshot_$(date +'%Y%m%d_%H%M%S').png\" && grim -g \"$GEOM\" \"$FILE\" && wl-copy < \"$FILE\"))"]
    }

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        Services.OverlayManager.controlCenterVisible = true
    }
    function close() {
        Services.OverlayManager.controlCenterVisible = false
        Services.OverlayManager.wifiPanelVisible = false
        Services.OverlayManager.btPanelVisible = false
        Services.OverlayManager.audioPanelVisible = false
    }
    function hide() { close() }
    function show() { open() }
    function toggle() {
        if (Services.OverlayManager.controlCenterVisible) close()
        else open()
    }

    Component.onCompleted: Services.OverlayManager.register(root)

    Item {
        id: escFocus
        focus: Services.OverlayManager.controlCenterVisible
        Keys.onEscapePressed: root.close()
    }

    // Modern Capsule Slider (Height 38px, filled track, icon inside)
    component ControlSlider: Rectangle {
        id: sliderRoot
        property string icon: ""
        property real value: 0
        signal moved(real newValue)

        Layout.fillWidth: true
        implicitHeight: 38
        radius: Services.Theme.radiusMd
        color: sliderMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
        border.color: sliderMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
        border.width: 1
        clip: true

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

        // Active track fill
        Rectangle {
            id: fillBar
            height: parent.height
            radius: parent.radius
            color: sliderMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent
            width: Math.max(38, Math.min(parent.width, sliderRoot.value * parent.width))
            Behavior on width { NumberAnimation { duration: 80 } }
            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        RowLayout {
            id: sliderContentRow
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Text {
                id: iconText
                text: sliderRoot.icon
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 14
                color: (fillBar.width > (iconText.x + sliderContentRow.x + iconText.width / 2)) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }

            Item { Layout.fillWidth: true }

            Text {
                id: percentText
                text: Math.round(sliderRoot.value * 100) + "%"
                font.pixelSize: 11
                font.bold: true
                color: (fillBar.width > (percentText.x + sliderContentRow.x + percentText.width / 2)) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: sliderMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => sliderRoot.moved(Math.max(0, Math.min(1, mouse.x / width)))
            onPositionChanged: (mouse) => {
                if (pressed) sliderRoot.moved(Math.max(0, Math.min(1, mouse.x / width)))
            }
        }
    }

    component ControlCard: Rectangle {
        default property alias content: inner.data
        Layout.fillWidth: true
        radius: Services.Theme.radiusLg
        color: Services.Theme.surfaceVariant
        implicitHeight: inner.implicitHeight + 24

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
        }
    }

    // Signal strength macOS-style — 4 ascending bars filled according to percentage
    component SignalBars: Item {
        id: bars
        property int signal: 0   // 0-100
        implicitWidth: 18
        implicitHeight: 14
        readonly property int tier: signal <= 0 ? 0 : Math.min(4, Math.ceil(signal / 25))

        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                width: 3
                radius: 1
                height: 4 + index * 3
                x: index * 4
                y: bars.height - height
                color: (index < bars.tier) ? Services.Theme.accent : Services.Theme.border
                opacity: (index < bars.tier) ? 1 : 0.6
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: panel
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: root.isBottom ? (parent.height - height - 12) : 12
            width: 356
            height: Math.min(530, parent.height - 24)
            radius: Services.Theme.radiusMd
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.controlCenterVisible ? 1 : 0
            transform: Translate {
                y: Services.OverlayManager.controlCenterVisible ? 0 : (root.isBottom ? 32 : -32)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            }
            scale: Services.OverlayManager.controlCenterVisible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                anchors.margins: 16
                spacing: 12
                opacity: fullPanelOverlay.isOpen ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                // Header with title & Power quick action
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Control Center"
                        color: Services.Theme.textPrimary
                        font.bold: true
                        font.pixelSize: 15
                    }

                    Item { Layout.fillWidth: true }

                    // Battery Info Badge (Moved to top near power menu)
                    Rectangle {
                        implicitHeight: 24
                        implicitWidth: headerBatLayout.implicitWidth + 14
                        radius: 12
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.border
                        border.width: 1

                        RowLayout {
                            id: headerBatLayout
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                id: headerBatIcon
                                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : Services.Theme.textPrimary)))
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                SequentialAnimation {
                                    running: Services.Power.isLow
                                    loops: Animation.Infinite
                                    NumberAnimation { target: headerBatIcon; property: "opacity"; to: 0.2; duration: 500; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: headerBatIcon; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                                }
                            }
                            Text {
                                text: Math.round(Services.Power.percentage * 100) + "%"
                                font.family: Services.Theme.fontMono
                                font.pixelSize: 10
                                font.bold: true
                                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : Services.Theme.textSecondary))
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    // Shell Update Icon Button (Always visible)
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: updateBtnMouse.containsMouse 
                               ? Services.Theme.surfaceVariant 
                               : (Services.OverlayManager.updatePanelVisible || Services.ShellUpdate.hasUpdate ? Services.Theme.bgHover : "transparent")
                        border.color: Services.ShellUpdate.hasUpdate 
                                      ? Services.Theme.accent 
                                      : (Services.OverlayManager.updatePanelVisible ? Services.Theme.border : "transparent")
                        border.width: (Services.ShellUpdate.hasUpdate || Services.OverlayManager.updatePanelVisible) ? 1 : 0
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.updateIcon(Services.ShellUpdate.isPulling, Services.ShellUpdate.isChecking)
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: Services.ShellUpdate.hasUpdate ? Services.Theme.accent : (updateBtnMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                            rotation: Services.OverlayManager.updatePanelVisible ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                        }

                        // Notification Badge Dot if update available
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 2
                            color: Services.Theme.accent
                            visible: Services.ShellUpdate.hasUpdate
                        }

                        MouseArea {
                            id: updateBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.OverlayManager.updatePanelVisible = !Services.OverlayManager.updatePanelVisible
                                if (Services.OverlayManager.updatePanelVisible) {
                                    Services.ShellUpdate.checkUpdates()
                                    Services.OverlayManager.wifiPanelVisible = false
                                    Services.OverlayManager.btPanelVisible = false
                                    Services.OverlayManager.audioPanelVisible = false
                                }
                            }
                        }
                    }

                    // Settings Icon Button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: settingsHover.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.settings
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: settingsHover.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: settingsHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                Services.OverlayManager.openSettings()
                            }
                        }
                    }

                    // Power Menu Icon Button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: pwrHover.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.power
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: pwrHover.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: pwrHover
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

                // ── Dynamic Island Morphing Control Tiles Row ──
                RowLayout {
                    id: morphingTilesRow
                    Layout.fillWidth: true
                    spacing: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible) ? 0 : 10
                    Behavior on spacing { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    // ── Dynamic Island Wi-Fi Card ──
                    Rectangle {
                        id: wifiTile
                        Layout.fillWidth: !Services.OverlayManager.btPanelVisible
                        Layout.preferredWidth: Services.OverlayManager.btPanelVisible ? 0 : (Services.OverlayManager.wifiPanelVisible ? 324 : 157)
                        Layout.preferredHeight: Services.OverlayManager.wifiPanelVisible ? 248 : 72
                        radius: Services.Theme.radiusLg
                        color: Services.Wifi.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                        clip: true

                        visible: opacity > 0.01
                        opacity: Services.OverlayManager.btPanelVisible ? 0 : 1

                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            // Dynamic Island Header Bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Left Icon Circle (Click icon = Power Toggle On/Off)
                                Rectangle {
                                    id: wifiIconCircle
                                    width: 36; height: 36; radius: 18
                                    color: wifiIconMouse.containsMouse 
                                           ? (Services.Wifi.enabled ? "#35000000" : Services.Theme.bgHover) 
                                           : (Services.Wifi.enabled ? "#20000000" : "transparent")
                                    scale: wifiIconMouse.pressed ? 0.88 : (wifiIconMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    Text {
                                        id: wifiIcon
                                        anchors.centerIn: parent
                                        text: Services.Icons.wifi
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 18
                                        scale: Services.Wifi.enabled ? 1.08 : 1.0
                                        color: Services.Wifi.enabled ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }

                                    MouseArea {
                                        id: wifiIconMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Wifi.toggle()
                                    }
                                }

                                // Header Text Area (Clicking opens/collapses Dynamic Island)
                                MouseArea {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.OverlayManager.wifiPanelVisible = !Services.OverlayManager.wifiPanelVisible
                                        if (Services.OverlayManager.wifiPanelVisible) Services.Wifi.scan()
                                        Services.OverlayManager.btPanelVisible = false
                                        Services.OverlayManager.audioPanelVisible = false
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: Services.OverlayManager.wifiPanelVisible 
                                                      ? "Wi-Fi Networks" 
                                                      : (Services.Wifi.enabled ? (Services.Wifi.connected ? Services.Wifi.ssid : "Wi-Fi") : "Wi-Fi")
                                                font.pixelSize: 12
                                                font.bold: true
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                color: Services.Wifi.enabled ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                            }
                                            Text {
                                                text: Services.OverlayManager.wifiPanelVisible
                                                      ? (Services.Wifi.scanning ? "Scanning networks..." : (Services.Wifi.networks.length + " networks found"))
                                                      : (Services.Wifi.enabled ? (Services.Wifi.connected ? "Connected" : "On") : "Off")
                                                font.pixelSize: 10
                                                color: Services.Wifi.enabled ? Services.Theme.bgOnAccent : Services.Theme.textDisabled
                                            }
                                        }

                                        // Refresh Button (when expanded)
                                        Rectangle {
                                            width: 26; height: 26; radius: 13
                                            visible: Services.OverlayManager.wifiPanelVisible
                                            color: refreshWifiMouse.containsMouse ? "#30000000" : "transparent"
                                            scale: refreshWifiMouse.pressed ? 0.88 : (refreshWifiMouse.containsMouse ? 1.08 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.refreshOrSpinIcon(Services.Wifi.scanning)
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 11
                                                color: Services.Theme.bgDeep
                                            }
                                            MouseArea {
                                                id: refreshWifiMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.Wifi.scan()
                                            }
                                        }

                                        // Collapse / Chevron Icon
                                        Text {
                                            text: Services.Icons.chevDown
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                            rotation: Services.OverlayManager.wifiPanelVisible ? 180 : 0
                                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }
                            }

                            // Divider line when expanded
                            Rectangle {
                                visible: Services.OverlayManager.wifiPanelVisible
                                Layout.fillWidth: true
                                height: 1
                                color: Services.Wifi.enabled ? "#30000000" : Services.Theme.border
                                opacity: 0.5
                            }

                            // Morphing Scrollable Networks List
                            Flickable {
                                visible: Services.OverlayManager.wifiPanelVisible
                                opacity: Services.OverlayManager.wifiPanelVisible ? 1 : 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentHeight: wifiCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                ColumnLayout {
                                    id: wifiCol
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        visible: !Services.Wifi.enabled
                                        text: "Wi-Fi is turned off"
                                        font.pixelSize: 11
                                        color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Text {
                                        visible: Services.Wifi.enabled && Services.Wifi.networks.length === 0 && !Services.Wifi.scanning
                                        text: "No networks found"
                                        font.pixelSize: 11
                                        color: Services.Wifi.enabled ? "#333333" : Services.Theme.textDisabled
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Repeater {
                                        model: Services.Wifi.enabled ? Services.Wifi.networks : []
                                        delegate: Rectangle {
                                            id: netRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: netCol.implicitHeight + 12
                                            radius: Services.Theme.radiusSm
                                            color: Services.Wifi.enabled
                                                   ? (netRowArea.containsMouse ? "#25000000" : (netRow.modelData.inUse ? "#35000000" : "transparent"))
                                                   : (netRowArea.containsMouse ? Services.Theme.bgHover : "transparent")

                                            readonly property bool isSaved: Services.Wifi.isSaved(netRow.modelData.ssid)
                                            readonly property bool isPwOpen: root.wifiPasswordTarget === netRow.modelData.ssid

                                            ColumnLayout {
                                                id: netCol
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                anchors.margins: 6
                                                spacing: 4

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    MouseArea {
                                                        id: netRowArea
                                                        Layout.fillWidth: true
                                                        implicitHeight: 26
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (netRow.modelData.inUse) Services.Wifi.disconnectNetwork()
                                                            else if (netRow.isSaved || netRow.modelData.security.length === 0) Services.Wifi.connectNetwork(netRow.modelData.ssid, "")
                                                            else {
                                                                root.wifiPasswordTarget = netRow.isPwOpen ? "" : netRow.modelData.ssid
                                                                root.wifiPasswordInput = ""
                                                            }
                                                        }

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            spacing: 8

                                                            Text {
                                                                text: Services.Icons.wifiSecurityIcon(netRow.modelData.security.length > 0)
                                                                font.family: Services.Theme.fontSymbols
                                                                font.pixelSize: 11
                                                                color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textSecondary
                                                            }

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 1

                                                                Text {
                                                                    text: netRow.modelData.ssid
                                                                    font.pixelSize: 11
                                                                    font.bold: netRow.modelData.inUse
                                                                    color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                                    Layout.fillWidth: true
                                                                    elide: Text.ElideRight
                                                                }
                                                                Text {
                                                                    visible: netRow.modelData.inUse || netRow.isSaved
                                                                    text: netRow.modelData.inUse ? "Connected" : "Saved"
                                                                    font.pixelSize: 9
                                                                    color: Services.Wifi.enabled ? "#333333" : Services.Theme.textDisabled
                                                                }
                                                            }

                                                            SignalBars { signal: netRow.modelData.signal }
                                                        }
                                                    }

                                                    // Forget Button
                                                    Item {
                                                        visible: netRow.isSaved
                                                        Layout.preferredWidth: 22; Layout.preferredHeight: 22

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 6
                                                            color: forgetHover.containsMouse ? "#40ff0000" : "transparent"
                                                        }
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Services.Icons.trash
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 10
                                                            color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                                        }
                                                        MouseArea {
                                                            id: forgetHover
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: Services.Wifi.forgetNetwork(netRow.modelData.ssid)
                                                        }
                                                    }
                                                }

                                                // Password Input Box
                                                ColumnLayout {
                                                    visible: netRow.isPwOpen
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        height: 30
                                                        radius: 6
                                                        color: Services.Wifi.enabled ? "#35000000" : Services.Theme.surfaceVariant

                                                        TextInput {
                                                            anchors.fill: parent
                                                            anchors.margins: 6
                                                            text: root.wifiPasswordInput
                                                            echoMode: TextInput.Password
                                                            font.pixelSize: 11
                                                            color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                            verticalAlignment: TextInput.AlignVCenter
                                                            onTextChanged: root.wifiPasswordInput = text
                                                            Keys.onReturnPressed: {
                                                                Services.Wifi.connectNetwork(netRow.modelData.ssid, root.wifiPasswordInput)
                                                                root.wifiPasswordTarget = ""
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

                    // ── Dynamic Island Bluetooth Card ──
                    Rectangle {
                        id: btTile
                        Layout.fillWidth: !Services.OverlayManager.wifiPanelVisible
                        Layout.preferredWidth: Services.OverlayManager.wifiPanelVisible ? 0 : (Services.OverlayManager.btPanelVisible ? 324 : 157)
                        Layout.preferredHeight: Services.OverlayManager.btPanelVisible ? 248 : 72
                        radius: Services.Theme.radiusLg
                        color: Services.Bluetooth.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                        clip: true

                        visible: opacity > 0.01
                        opacity: Services.OverlayManager.wifiPanelVisible ? 0 : 1

                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            // Dynamic Island Header Bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Left Icon Circle (Click icon = Power Toggle On/Off)
                                Rectangle {
                                    id: btIconCircle
                                    width: 36; height: 36; radius: 18
                                    color: btIconMouse.containsMouse 
                                           ? (Services.Bluetooth.enabled ? "#35000000" : Services.Theme.bgHover) 
                                           : (Services.Bluetooth.enabled ? "#20000000" : "transparent")
                                    scale: btIconMouse.pressed ? 0.88 : (btIconMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    Text {
                                        id: btIcon
                                        anchors.centerIn: parent
                                        text: Services.Icons.bluetooth
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 18
                                        scale: Services.Bluetooth.enabled ? 1.08 : 1.0
                                        color: Services.Bluetooth.enabled ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }

                                    MouseArea {
                                        id: btIconMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Bluetooth.toggle()
                                    }
                                }

                                // Header Text Area (Clicking opens/collapses Dynamic Island)
                                MouseArea {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.OverlayManager.btPanelVisible = !Services.OverlayManager.btPanelVisible
                                        if (Services.OverlayManager.btPanelVisible) Services.Bluetooth.listDevices()
                                        Services.OverlayManager.wifiPanelVisible = false
                                        Services.OverlayManager.audioPanelVisible = false
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: Services.OverlayManager.btPanelVisible ? "Bluetooth Devices" : "Bluetooth"
                                                font.pixelSize: 12
                                                font.bold: true
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                                color: Services.Bluetooth.enabled ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
                                            }
                                            Text {
                                                text: Services.OverlayManager.btPanelVisible
                                                      ? (Services.Bluetooth.refreshing ? "Searching devices..." : (Services.Bluetooth.devices.length + " paired devices"))
                                                      : (Services.Bluetooth.enabled ? (Services.Bluetooth.devices.some(d => d.connected) ? "Connected" : "On") : "Off")
                                                font.pixelSize: 10
                                                color: Services.Bluetooth.enabled ? Services.Theme.bgOnAccent : Services.Theme.textDisabled
                                            }
                                        }

                                        // Refresh Button (when expanded)
                                        Rectangle {
                                            width: 26; height: 26; radius: 13
                                            visible: Services.OverlayManager.btPanelVisible
                                            color: refreshBtMouse.containsMouse ? "#30000000" : "transparent"
                                            scale: refreshBtMouse.pressed ? 0.88 : (refreshBtMouse.containsMouse ? 1.08 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.refreshOrSpinIcon(Services.Bluetooth.refreshing)
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 11
                                                color: Services.Theme.bgDeep
                                            }
                                            MouseArea {
                                                id: refreshBtMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.Bluetooth.listDevices()
                                            }
                                        }

                                        // Collapse / Chevron Icon
                                        Text {
                                            text: Services.Icons.chevDown
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                            rotation: Services.OverlayManager.btPanelVisible ? 180 : 0
                                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }
                            }

                            // Divider line when expanded
                            Rectangle {
                                visible: Services.OverlayManager.btPanelVisible
                                Layout.fillWidth: true
                                height: 1
                                color: Services.Bluetooth.enabled ? "#30000000" : Services.Theme.border
                                opacity: 0.5
                            }

                            // Morphing Scrollable Devices List
                            Flickable {
                                visible: Services.OverlayManager.btPanelVisible
                                opacity: Services.OverlayManager.btPanelVisible ? 1 : 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentHeight: btCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                ColumnLayout {
                                    id: btCol
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        visible: !Services.Bluetooth.enabled
                                        text: "Bluetooth is turned off"
                                        font.pixelSize: 11
                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Text {
                                        visible: Services.Bluetooth.enabled && Services.Bluetooth.devices.length === 0
                                        text: "No paired devices"
                                        font.pixelSize: 11
                                        color: Services.Bluetooth.enabled ? "#333333" : Services.Theme.textDisabled
                                        Layout.alignment: Qt.AlignHCenter
                                    }

                                    Repeater {
                                        model: Services.Bluetooth.enabled ? Services.Bluetooth.devices : []
                                        delegate: Rectangle {
                                            id: btItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            radius: Services.Theme.radiusSm
                                            color: Services.Bluetooth.enabled
                                                   ? (btItemArea.containsMouse ? "#25000000" : (btItem.modelData.connected ? "#35000000" : "transparent"))
                                                   : (btItemArea.containsMouse ? Services.Theme.bgHover : "transparent")

                                            MouseArea {
                                                id: btItemArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (btItem.modelData.connected) Services.Bluetooth.disconnectDevice(btItem.modelData.mac)
                                                    else Services.Bluetooth.connectDevice(btItem.modelData.mac)
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 8

                                                    Text {
                                                        text: Services.Icons.btIcon(btItem.modelData.connected)
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 12
                                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                    }

                                                    Text {
                                                        text: btItem.modelData.name
                                                        font.pixelSize: 11
                                                        font.bold: btItem.modelData.connected
                                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: btItem.modelData.connected ? "Disconnect" : "Connect"
                                                        font.pixelSize: 10
                                                        color: Services.Bluetooth.enabled ? "#333333" : Services.Theme.textDisabled
                                                    }

                                                    // Unpair / Forget button
                                                    Rectangle {
                                                        width: 20; height: 20; radius: 10
                                                        color: unpairBtMouse.containsMouse ? "#40000000" : "transparent"

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰆴"
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 10
                                                            color: unpairBtMouse.containsMouse ? Services.Theme.danger : (Services.Bluetooth.enabled ? "#444444" : Services.Theme.textDisabled)
                                                        }

                                                        MouseArea {
                                                            id: unpairBtMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: Services.Bluetooth.removeDevice(btItem.modelData.mac)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Scan New Devices Button ──
                                    Rectangle {
                                        visible: Services.Bluetooth.enabled
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        radius: Services.Theme.radiusSm
                                        color: scanBtnArea.containsMouse ? "#30000000" : "#15000000"
                                        Layout.topMargin: 4

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: Services.Icons.refreshOrSpinIcon(Services.Bluetooth.scanning)
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 11
                                                color: Services.Theme.bgDeep
                                            }

                                            Text {
                                                text: Services.Bluetooth.scanning ? "Scanning for devices..." : "Scan New Devices"
                                                font.pixelSize: 10
                                                font.bold: true
                                                color: Services.Theme.bgDeep
                                            }
                                        }

                                        MouseArea {
                                            id: scanBtnArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Bluetooth.toggleScan()
                                        }
                                    }

                                    // ── Available / Unpaired Devices Section ──
                                    Text {
                                        visible: Services.Bluetooth.enabled && Services.Bluetooth.unpairedDevices.length > 0
                                        text: "Available Devices"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Services.Bluetooth.enabled ? "#444444" : Services.Theme.textDisabled
                                        Layout.topMargin: 4
                                    }

                                    Repeater {
                                        model: Services.Bluetooth.enabled ? Services.Bluetooth.unpairedDevices : []
                                        delegate: Rectangle {
                                            id: unpItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            radius: Services.Theme.radiusSm
                                            color: unpItemArea.containsMouse ? "#25000000" : "transparent"

                                            MouseArea {
                                                id: unpItemArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.Bluetooth.pairAndConnect(unpItem.modelData.mac)

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 8

                                                    Text {
                                                        text: "󰂲"
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 12
                                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                    }

                                                    Text {
                                                        text: unpItem.modelData.name || unpItem.modelData.mac
                                                        font.pixelSize: 11
                                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: Services.Bluetooth.pairingMac === unpItem.modelData.mac ? "Pairing..." : "Pair & Connect"
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: Services.Bluetooth.enabled ? "#333333" : Services.Theme.textDisabled
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

                // ── Quick Actions & Media Player Container (Seamless height transition with zero layout push) ──
                Item {
                    id: quickActionsAndMediaCol
                    Layout.fillWidth: true
                    Layout.preferredHeight: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible) ? 0 : 160
                    visible: opacity > 0.01
                    opacity: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible) ? 0 : 1
                    clip: false

                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 12

                        // Quick Action Icon-Only Square Tiles (Focus, Saver, Theme, Mute)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // 1. Focus (DND)
                            Rectangle {
                                id: dndTile
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                radius: Services.Theme.radiusLg
                                readonly property bool isActive: Services.Notifications.doNotDisturb
                                color: isActive 
                                    ? Services.Theme.accent 
                                    : (dndMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                                border.color: isActive ? Services.Theme.accent : (dndMouse.containsMouse ? Services.Theme.borderHighlight : "transparent")
                                border.width: 1
                                scale: dndMouse.pressed ? 0.93 : 1.0
                                clip: true

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                // Active Pulse Wave
                                Rectangle {
                                    id: dndPulse
                                    anchors.centerIn: parent
                                    width: 44; height: 44; radius: 22
                                    color: Services.Theme.accent
                                    opacity: 0
                                    scale: 0.4
                                }

                                ParallelAnimation {
                                    id: dndAnim
                                    NumberAnimation { target: dndPulse; property: "scale"; from: 0.4; to: 2.2; duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: dndPulse; property: "opacity"; from: 0.5; to: 0.0; duration: 280 }
                                }

                                SequentialAnimation {
                                    id: bellRingAnim
                                    NumberAnimation { target: dndIcon; property: "rotation"; from: 0; to: -18; duration: 60; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: dndIcon; property: "rotation"; from: -18; to: 18; duration: 100; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: dndIcon; property: "rotation"; from: 18; to: -12; duration: 80; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: dndIcon; property: "rotation"; from: -12; to: 0; duration: 80; easing.type: Easing.OutQuad }
                                }

                                Text {
                                    id: dndIcon
                                    anchors.centerIn: parent
                                    text: dndTile.isActive ? Services.Icons.bellSlash : Services.Icons.bell
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 18
                                    scale: dndTile.isActive ? 1.15 : (dndMouse.containsMouse ? 1.08 : 1.0)
                                    color: dndTile.isActive 
                                        ? Services.Theme.bgOnAccent 
                                        : (dndMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }

                                MouseArea {
                                    id: dndMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Notifications.doNotDisturb = !Services.Notifications.doNotDisturb
                                        if (Services.Notifications.doNotDisturb) {
                                            dndAnim.restart()
                                            bellRingAnim.restart()
                                        }
                                    }
                                }
                            }

                            // 2. Saver (Battery Saver)
                            Rectangle {
                                id: saverTile
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                radius: Services.Theme.radiusLg
                                readonly property bool isActive: Services.PowerProfile.saverEnabled
                                color: isActive 
                                    ? Services.Theme.accent 
                                    : (saverMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                                border.color: isActive ? Services.Theme.accent : (saverMouse.containsMouse ? Services.Theme.borderHighlight : "transparent")
                                border.width: 1
                                scale: saverMouse.pressed ? 0.93 : 1.0
                                clip: true

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                // Active Pulse Wave
                                Rectangle {
                                    id: saverPulse
                                    anchors.centerIn: parent
                                    width: 44; height: 44; radius: 22
                                    color: Services.Theme.accent
                                    opacity: 0
                                    scale: 0.4
                                }

                                ParallelAnimation {
                                    id: saverAnim
                                    NumberAnimation { target: saverPulse; property: "scale"; from: 0.4; to: 2.2; duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: saverPulse; property: "opacity"; from: 0.5; to: 0.0; duration: 280 }
                                }

                                SequentialAnimation {
                                    id: saverPopAnim
                                    NumberAnimation { target: saverIcon; property: "scale"; from: 1.0; to: 1.3; duration: 120; easing.type: Easing.OutBack }
                                    NumberAnimation { target: saverIcon; property: "scale"; from: 1.3; to: 1.15; duration: 140; easing.type: Easing.OutQuad }
                                }

                                Text {
                                    id: saverIcon
                                    anchors.centerIn: parent
                                    text: Services.Icons.tree
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 18
                                    scale: saverTile.isActive ? 1.15 : (saverMouse.containsMouse ? 1.08 : 1.0)
                                    color: saverTile.isActive 
                                        ? Services.Theme.bgOnAccent 
                                        : (saverMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }

                                MouseArea {
                                    id: saverMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.PowerProfile.toggleSaver()
                                        saverAnim.restart()
                                        saverPopAnim.restart()
                                    }
                                }
                            }

                            // 3. Dark Theme Toggle Tile (Active/Nyala when Dark Mode)
                            Rectangle {
                                id: themeTile
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                radius: Services.Theme.radiusLg
                                readonly property bool isDark: Services.Config ? (Services.Config.themeMode === "dark" || Services.Config.themeMode !== "light") : true
                                color: isDark 
                                    ? Services.Theme.accent 
                                    : (themeMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                                border.color: isDark ? Services.Theme.accent : (themeMouse.containsMouse ? Services.Theme.borderHighlight : "transparent")
                                border.width: 1
                                scale: themeMouse.pressed ? 0.93 : 1.0
                                clip: true

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                // Active Pulse Wave
                                Rectangle {
                                    id: themePulse
                                    anchors.centerIn: parent
                                    width: 44; height: 44; radius: 22
                                    color: Services.Theme.accent
                                    opacity: 0
                                    scale: 0.4
                                }

                                ParallelAnimation {
                                    id: themeAnim
                                    NumberAnimation { target: themePulse; property: "scale"; from: 0.4; to: 2.2; duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: themePulse; property: "opacity"; from: 0.5; to: 0.0; duration: 280 }
                                }

                                Text {
                                    id: themeIcon
                                    anchors.centerIn: parent
                                    text: Services.Icons.contrast
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 18
                                    scale: themeTile.isDark ? 1.15 : (themeMouse.containsMouse ? 1.08 : 1.0)
                                    rotation: themeTile.isDark ? 0 : 180
                                    color: themeTile.isDark 
                                        ? Services.Theme.bgOnAccent 
                                        : (themeMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    Behavior on rotation { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
                                }

                                MouseArea {
                                    id: themeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (Services.Config) {
                                            var nextMode = themeTile.isDark ? "light" : "dark"
                                            Services.Config.setThemeMode(nextMode)
                                            themeAnim.restart()
                                        }
                                    }
                                }
                            }

                            // 4. Audio Mute Tile
                            Rectangle {
                                id: muteTile
                                Layout.fillWidth: true
                                Layout.preferredHeight: 50
                                radius: Services.Theme.radiusLg
                                readonly property bool isActive: Services.Audio.muted
                                color: isActive 
                                    ? Services.Theme.accent 
                                    : (muteMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)
                                border.color: isActive ? Services.Theme.accent : (muteMouse.containsMouse ? Services.Theme.borderHighlight : "transparent")
                                border.width: 1
                                scale: muteMouse.pressed ? 0.93 : 1.0
                                clip: true

                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                // Active Pulse Wave
                                Rectangle {
                                    id: mutePulse
                                    anchors.centerIn: parent
                                    width: 44; height: 44; radius: 22
                                    color: Services.Theme.accent
                                    opacity: 0
                                    scale: 0.4
                                }

                                ParallelAnimation {
                                    id: muteAnim
                                    NumberAnimation { target: mutePulse; property: "scale"; from: 0.4; to: 2.2; duration: 280; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: mutePulse; property: "opacity"; from: 0.5; to: 0.0; duration: 280 }
                                }

                                SequentialAnimation {
                                    id: mutePopAnim
                                    NumberAnimation { target: muteIcon; property: "scale"; from: 1.0; to: 1.3; duration: 120; easing.type: Easing.OutBack }
                                    NumberAnimation { target: muteIcon; property: "scale"; from: 1.3; to: 1.15; duration: 140; easing.type: Easing.OutQuad }
                                }

                                Text {
                                    id: muteIcon
                                    anchors.centerIn: parent
                                    text: muteTile.isActive ? Services.Icons.volMute : Services.Icons.speaker
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 18
                                    scale: muteTile.isActive ? 1.15 : (muteMouse.containsMouse ? 1.08 : 1.0)
                                    color: muteTile.isActive 
                                        ? Services.Theme.bgOnAccent 
                                        : (muteMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }

                                MouseArea {
                                    id: muteMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Audio.toggleMute()
                                        if (Services.Audio.muted) {
                                            muteAnim.restart()
                                            mutePopAnim.restart()
                                        }
                                    }
                                }
                            }
                        }

                        // Media Player Card
                        Local.MediaTile {
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ── Bottom Fixed Controls Card & Footer (Hard-locked to panel.bottom) ──
            ColumnLayout {
                id: bottomCol
                anchors {
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                anchors.margins: 16
                spacing: 12
                opacity: fullPanelOverlay.isOpen ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.4
                }

                ControlCard {
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Controls"
                            font.pixelSize: 11
                            font.bold: true
                            color: Services.Theme.textSecondary
                        }

                        Item { Layout.fillWidth: true }

                        // Audio Output Device Selector Button (Opens sub-panel like WiFi/BT)
                        Rectangle {
                            height: 20; radius: 10
                            color: audioSinkMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                            implicitWidth: sinkRow.implicitWidth + 12
                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            RowLayout {
                                id: sinkRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: Services.Icons.headphone
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 9
                                    color: Services.Theme.textSecondary
                                }
                                Text {
                                    text: Services.Audio.sinkDescription
                                    font.pixelSize: 10
                                    color: Services.Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 120
                                }
                                Text {
                                    text: Services.Icons.chevDown
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 8
                                    color: Services.Theme.textDisabled
                                    rotation: Services.OverlayManager.audioPanelVisible ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                }
                            }

                            MouseArea {
                                id: audioSinkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.OverlayManager.audioPanelVisible = !Services.OverlayManager.audioPanelVisible
                                    if (Services.OverlayManager.audioPanelVisible) {
                                        Services.Audio.refreshSinks()
                                        Services.OverlayManager.wifiPanelVisible = false
                                        Services.OverlayManager.btPanelVisible = false
                                    }
                                }
                            }
                        }
                    }

                    ControlSlider {
                        icon: Services.Icons.brightnessIcon(Services.Brightness.percent)
                        value: Services.Brightness.percent
                        onMoved: (v) => Services.Brightness.setPercent(v)
                    }

                    ControlSlider {
                        icon: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
                        value: Services.Audio.volume
                        onMoved: (v) => Services.Audio.setVolume(v)
                    }
                }

                // System Status Bar Footer
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: Services.Theme.radiusMd
                    color: Services.Theme.surfaceVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        // CPU
                        RowLayout {
                            spacing: 4
                            Text { text: Services.Icons.cpu; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.accent }
                            Text { text: Math.round(Services.Sysmon.cpuUsage) + "%"; font.pixelSize: 10; font.bold: true; color: Services.Theme.textSecondary }
                        }

                        Item { Layout.fillWidth: true }

                        // RAM
                        RowLayout {
                            spacing: 4
                            Text { text: Services.Icons.ram; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.accent }
                            Text { text: Math.round(Services.Sysmon.ramUsage) + "%"; font.pixelSize: 10; font.bold: true; color: Services.Theme.textSecondary }
                        }

                        Item { Layout.fillWidth: true }

                        // Temp
                        RowLayout {
                            spacing: 4
                            visible: Services.Sysmon.cpuTemp > 0
                            Text { text: Services.Icons.temp; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.accent }
                            Text { text: Math.round(Services.Sysmon.cpuTemp) + "°C"; font.pixelSize: 10; font.bold: true; color: Services.Theme.textSecondary }
                        }

                        Item { Layout.fillWidth: true; visible: Services.Sysmon.cpuTemp > 0 }

                        // Disk
                        RowLayout {
                            spacing: 4
                            Text { text: Services.Icons.disk; font.family: Services.Theme.fontSymbols; font.pixelSize: 10; color: Services.Theme.accent }
                            Text { text: Math.round(Services.Sysmon.diskUsage) + "%"; font.pixelSize: 10; font.bold: true; color: Services.Theme.textSecondary }
                        }
                    }
                }
        }

            Rectangle {
                id: fullPanelOverlay
                z: 100
                anchors.fill: parent
                color: Services.Theme.surface
                radius: Services.Theme.radiusMd
                clip: true

                readonly property bool isOpen: Services.OverlayManager.audioPanelVisible || Services.OverlayManager.updatePanelVisible

                opacity: isOpen ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Back Button (<)
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: backBtnMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.chevLeft
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: Services.Theme.textPrimary
                            }

                            MouseArea {
                                id: backBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.OverlayManager.wifiPanelVisible = false
                                    Services.OverlayManager.btPanelVisible = false
                                    Services.OverlayManager.audioPanelVisible = false
                                    Services.OverlayManager.updatePanelVisible = false
                                }
                            }
                        }

                        // Header Title
                        Text {
                            text: Services.OverlayManager.wifiPanelVisible 
                                  ? "Wi-Fi Networks" 
                                  : (Services.OverlayManager.btPanelVisible 
                                     ? "Bluetooth Devices" 
                                     : (Services.OverlayManager.audioPanelVisible 
                                        ? "Audio Output Devices" 
                                        : "Shell Updates & Branches"))
                            color: Services.Theme.textPrimary
                            font.bold: true
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }

                        // Refresh Button (for WiFi, BT, Audio)
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            visible: !Services.OverlayManager.updatePanelVisible
                            color: refreshBtnMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.refreshOrSpinIcon((Services.OverlayManager.wifiPanelVisible && Services.Wifi.scanning) || (Services.OverlayManager.btPanelVisible && Services.Bluetooth.refreshing))
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: Services.Theme.textSecondary
                            }

                            MouseArea {
                                id: refreshBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Services.OverlayManager.wifiPanelVisible) Services.Wifi.scan()
                                    else if (Services.OverlayManager.btPanelVisible) Services.Bluetooth.listDevices()
                                    else if (Services.OverlayManager.audioPanelVisible) Services.Audio.refreshSinks()
                                }
                            }
                        }

                        Rectangle {
                            width: 38; height: 20; radius: 10
                            visible: Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible
                            color: (Services.OverlayManager.wifiPanelVisible ? Services.Wifi.enabled : Services.Bluetooth.enabled)
                                   ? Services.Theme.accent : Services.Theme.surfaceVariant
                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 16; height: 16; radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                x: (Services.OverlayManager.wifiPanelVisible ? Services.Wifi.enabled : Services.Bluetooth.enabled) ? parent.width - width - 2 : 2
                                color: (Services.OverlayManager.wifiPanelVisible ? Services.Wifi.enabled : Services.Bluetooth.enabled) ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Services.OverlayManager.wifiPanelVisible) Services.Wifi.toggle()
                                    else if (Services.OverlayManager.btPanelVisible) Services.Bluetooth.toggle()
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Services.Theme.border; opacity: 0.4 }

                    // Scrollable List Body Container
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: overlayContentCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: overlayContentCol
                            width: parent.width
                            spacing: 8

                            // ── Wi-Fi Section ──
                            ColumnLayout {
                                visible: Services.OverlayManager.wifiPanelVisible
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    visible: !Services.Wifi.enabled
                                    text: "Wi-Fi is turned off"
                                    font.pixelSize: 11
                                    color: Services.Theme.textDisabled
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    visible: Services.Wifi.enabled && Services.Wifi.networks.length === 0 && !Services.Wifi.scanning
                                    text: "No networks found"
                                    font.pixelSize: 11
                                    color: Services.Theme.textDisabled
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Repeater {
                                    model: Services.Wifi.enabled ? Services.Wifi.networks : []
                                    delegate: Rectangle {
                                        id: netRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: netCol.implicitHeight + 14
                                        radius: Services.Theme.radiusSm
                                        color: netArea.containsMouse ? Services.Theme.bgHover : (netRow.modelData.inUse ? Services.Theme.surfaceVariant : "transparent")
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        readonly property bool isSaved: Services.Wifi.isSaved(netRow.modelData.ssid)
                                        readonly property bool isPwOpen: root.wifiPasswordTarget === netRow.modelData.ssid

                                        ColumnLayout {
                                            id: netCol
                                            anchors { left: parent.left; right: parent.right; top: parent.top }
                                            anchors.margins: 8
                                            spacing: 6

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                MouseArea {
                                                    id: netArea
                                                    Layout.fillWidth: true
                                                    implicitHeight: 26
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (netRow.modelData.inUse) Services.Wifi.disconnectNetwork()
                                                        else if (netRow.isSaved || netRow.modelData.security.length === 0) Services.Wifi.connectNetwork(netRow.modelData.ssid, "")
                                                        else {
                                                            root.wifiPasswordTarget = netRow.isPwOpen ? "" : netRow.modelData.ssid
                                                            root.wifiPasswordInput = ""
                                                        }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 8

                                                        Text {
                                                            text: Services.Icons.wifiSecurityIcon(netRow.modelData.security.length > 0)
                                                            font.family: Services.Theme.fontSymbols
                                                            font.pixelSize: 11
                                                            color: netRow.modelData.inUse ? Services.Theme.accent : Services.Theme.textSecondary
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1

                                                            Text {
                                                                text: netRow.modelData.ssid
                                                                font.pixelSize: 11
                                                                font.bold: netRow.modelData.inUse
                                                                color: netRow.modelData.inUse ? Services.Theme.accent : Services.Theme.textPrimary
                                                                Layout.fillWidth: true
                                                                elide: Text.ElideRight
                                                            }
                                                            Text {
                                                                visible: netRow.modelData.inUse || netRow.isSaved
                                                                text: netRow.modelData.inUse ? "Connected" : "Saved"
                                                                font.pixelSize: 9
                                                                color: Services.Theme.textDisabled
                                                            }
                                                        }

                                                        SignalBars { signal: netRow.modelData.signal }
                                                    }
                                                }

                                                // Forget Button
                                                Item {
                                                    visible: netRow.isSaved
                                                    Layout.preferredWidth: 22; Layout.preferredHeight: 22

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 6
                                                        color: forgetHover.containsMouse ? Services.Theme.danger : "transparent"
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Services.Icons.trash
                                                        font.family: Services.Theme.fontSymbols
                                                        font.pixelSize: 10
                                                        color: forgetHover.containsMouse ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                                    }
                                                    MouseArea {
                                                        id: forgetHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: Services.Wifi.forgetNetwork(netRow.modelData.ssid)
                                                    }
                                                }
                                            }

                                            // Password Input Box
                                            ColumnLayout {
                                                visible: netRow.isPwOpen
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 32
                                                    radius: 6
                                                    color: Services.Theme.surfaceVariant
                                                    border.color: pwInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                                    border.width: 1

                                                    TextInput {
                                                        id: pwInput
                                                        anchors.fill: parent
                                                        anchors.margins: 6
                                                        text: root.wifiPasswordInput
                                                        echoMode: TextInput.Password
                                                        font.pixelSize: 11
                                                        color: Services.Theme.textPrimary
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        onTextChanged: root.wifiPasswordInput = text
                                                        Keys.onReturnPressed: {
                                                            Services.Wifi.connectNetwork(netRow.modelData.ssid, root.wifiPasswordInput)
                                                            root.wifiPasswordTarget = ""
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Bluetooth Section ──
                            ColumnLayout {
                                visible: Services.OverlayManager.btPanelVisible
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    visible: !Services.Bluetooth.enabled
                                    text: "Bluetooth is turned off"
                                    font.pixelSize: 11
                                    color: Services.Theme.textDisabled
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    visible: Services.Bluetooth.enabled && Services.Bluetooth.devices.length === 0
                                    text: "No paired devices found"
                                    font.pixelSize: 11
                                    color: Services.Theme.textDisabled
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Repeater {
                                    model: Services.Bluetooth.enabled ? Services.Bluetooth.devices : []
                                    delegate: Rectangle {
                                        id: btRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 44
                                        radius: Services.Theme.radiusMd
                                        color: btArea.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        MouseArea {
                                            id: btArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (btRow.modelData.connected) Services.Bluetooth.disconnectDevice(btRow.modelData.mac)
                                                else Services.Bluetooth.connectDevice(btRow.modelData.mac)
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 10

                                                Text {
                                                    text: Services.Icons.btIcon(btRow.modelData.connected)
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 14
                                                    color: btRow.modelData.connected ? Services.Theme.accent : Services.Theme.textSecondary
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        text: btRow.modelData.name
                                                        color: Services.Theme.textPrimary
                                                        font.bold: btRow.modelData.connected
                                                        font.pixelSize: 11
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: btRow.modelData.connected ? "Connected" : "Disconnected"
                                                        color: btRow.modelData.connected ? Services.Theme.accent : Services.Theme.textDisabled
                                                        font.pixelSize: 9
                                                    }
                                                }

                                                Rectangle {
                                                    implicitWidth: btBtnText.implicitWidth + 14
                                                    implicitHeight: 22
                                                    radius: 11
                                                    color: btRow.modelData.connected ? Services.Theme.surfaceVariant : Services.Theme.accent

                                                    Text {
                                                        id: btBtnText
                                                        anchors.centerIn: parent
                                                        text: btRow.modelData.connected ? "Disconnect" : "Connect"
                                                        font.pixelSize: 9
                                                        font.bold: true
                                                        color: btRow.modelData.connected ? Services.Theme.textPrimary : Services.Theme.bgDeep
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Audio Section ──
                            ColumnLayout {
                                visible: Services.OverlayManager.audioPanelVisible
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: Services.Audio.sinks
                                    delegate: Rectangle {
                                        id: sinkRow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 44
                                        radius: Services.Theme.radiusMd
                                        color: sinkRow.modelData.isCurrent ? Services.Theme.accent : (sinkRowArea.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant)

                                        MouseArea {
                                            id: sinkRowArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Audio.setSink(sinkRow.modelData.name)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.sinkIcon(sinkRow.modelData.description)
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: sinkRow.modelData.isCurrent ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                            }

                                            Text {
                                                text: sinkRow.modelData.description
                                                color: sinkRow.modelData.isCurrent ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                font.bold: sinkRow.modelData.isCurrent
                                                font.pixelSize: 11
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: sinkRow.modelData.isCurrent
                                                text: Services.Icons.check
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 11
                                                color: Services.Theme.bgDeep
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Shell Update Section ──
                            ColumnLayout {
                                visible: Services.OverlayManager.updatePanelVisible
                                Layout.fillWidth: true
                                spacing: 12

                                // Release Channel Selector
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "Release Channel"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Services.Theme.textDisabled
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Stable Pill (main)
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 32
                                            radius: Services.Theme.radiusSm
                                            color: Services.ShellUpdate.currentBranch === "main" 
                                                   ? Services.Theme.accent 
                                                   : (stableBtnMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover)
                                            border.color: Services.ShellUpdate.currentBranch === "main" ? Services.Theme.accent : Services.Theme.border
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: Services.Icons.check
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 10
                                                    color: Services.ShellUpdate.currentBranch === "main" ? Services.Theme.bgDeep : Services.Theme.accent
                                                    visible: Services.ShellUpdate.currentBranch === "main"
                                                }

                                                Text {
                                                    text: "Stable (main)"
                                                    font.bold: Services.ShellUpdate.currentBranch === "main"
                                                    font.pixelSize: 11
                                                    color: Services.ShellUpdate.currentBranch === "main" ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                }
                                            }

                                            MouseArea {
                                                id: stableBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.ShellUpdate.switchBranch("main")
                                            }
                                        }

                                        // Unstable Pill (master)
                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 32
                                            radius: Services.Theme.radiusSm
                                            color: Services.ShellUpdate.currentBranch === "master" 
                                                   ? Services.Theme.accent 
                                                   : (unstableBtnMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover)
                                            border.color: Services.ShellUpdate.currentBranch === "master" ? Services.Theme.accent : Services.Theme.border
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 6

                                                Text {
                                                    text: Services.Icons.check
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 10
                                                    color: Services.ShellUpdate.currentBranch === "master" ? Services.Theme.bgDeep : Services.Theme.accent
                                                    visible: Services.ShellUpdate.currentBranch === "master"
                                                }

                                                Text {
                                                    text: "Unstable (master)"
                                                    font.bold: Services.ShellUpdate.currentBranch === "master"
                                                    font.pixelSize: 11
                                                    color: Services.ShellUpdate.currentBranch === "master" ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                }
                                            }

                                            MouseArea {
                                                id: unstableBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.ShellUpdate.switchBranch("master")
                                            }
                                        }
                                    }
                                }

                                // Status Card Box
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: statusCol.implicitHeight + 20
                                    radius: Services.Theme.radiusSm
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1

                                    ColumnLayout {
                                        id: statusCol
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: 10
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: Services.Icons.refreshOrSpinIcon(Services.ShellUpdate.isChecking || Services.ShellUpdate.isPulling || Services.ShellUpdate.isSwitching)
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 12
                                                color: Services.Theme.accent
                                            }

                                            Text {
                                                text: Services.ShellUpdate.isSwitching 
                                                      ? "Switching release channel..." 
                                                      : (Services.ShellUpdate.isPulling 
                                                         ? "Downloading and applying updates..." 
                                                         : (Services.ShellUpdate.isChecking 
                                                            ? "Checking for updates..." 
                                                            : (Services.ShellUpdate.hasUpdate 
                                                               ? "Update available (" + Services.ShellUpdate.behindCount + " new commit" + (Services.ShellUpdate.behindCount > 1 ? "s" : "") + ")" 
                                                               : "Your Quickshell build is up to date.")))
                                                font.bold: true
                                                font.pixelSize: 11
                                                color: Services.Theme.textPrimary
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            text: "Current branch: " + Services.ShellUpdate.currentBranch + " (" + Services.ShellUpdate.channelName + " channel)"
                                                  + (Services.ShellUpdate.lastCheckTime ? " • Last checked " + Services.ShellUpdate.lastCheckTime : "")
                                            font.pixelSize: 10
                                            color: Services.Theme.textSecondary
                                        }

                                        // Commit log preview if updates available
                                        Rectangle {
                                            visible: Services.ShellUpdate.hasUpdate && Services.ShellUpdate.commitLogs !== ""
                                            Layout.fillWidth: true
                                            implicitHeight: commitLogText.implicitHeight + 12
                                            radius: 4
                                            color: Services.Theme.bgDeep
                                            border.color: Services.Theme.border
                                            border.width: 1

                                            Text {
                                                id: commitLogText
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.margins: 6
                                                text: Services.ShellUpdate.commitLogs
                                                font.family: "Monospace"
                                                font.pixelSize: 9
                                                color: Services.Theme.textSecondary
                                                wrapMode: Text.WrapAnywhere
                                            }
                                        }

                                        // Last error / pull message if present
                                        Text {
                                            visible: Services.ShellUpdate.lastError !== ""
                                            text: Services.ShellUpdate.lastError
                                            font.pixelSize: 10
                                            color: Services.Theme.danger
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            visible: Services.ShellUpdate.pullMessage !== "" && Services.ShellUpdate.lastError === ""
                                            text: Services.ShellUpdate.pullMessage
                                            font.pixelSize: 10
                                            color: Services.Theme.accent
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                // Action Buttons Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Check Updates Button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: Services.Theme.radiusSm
                                        color: checkBtnMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.bgHover
                                        border.color: Services.Theme.border
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.ShellUpdate.isChecking ? "Checking..." : "Check for Updates"
                                            font.bold: true
                                            font.pixelSize: 11
                                            color: Services.Theme.textPrimary
                                        }

                                        MouseArea {
                                            id: checkBtnMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.ShellUpdate.checkUpdates()
                                        }
                                    }

                                    // Update Now Button (visible if hasUpdate)
                                    Rectangle {
                                        visible: Services.ShellUpdate.hasUpdate
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: Services.Theme.radiusSm
                                        color: updateBtnClickMouse.containsMouse ? Services.Theme.accent : Services.Theme.bgHover
                                        border.color: Services.Theme.accent
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.ShellUpdate.isPulling ? "Updating..." : "Update Now"
                                            font.bold: true
                                            font.pixelSize: 11
                                            color: updateBtnClickMouse.containsMouse ? Services.Theme.bgDeep : Services.Theme.accent
                                        }

                                        MouseArea {
                                            id: updateBtnClickMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.ShellUpdate.applyUpdate()
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
