import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services
import "." as Local

PanelWindow {
    id: root
    property string overlayId: "controlCenter"

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.controlCenterVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property string wifiPasswordTarget: ""
    property string wifiPasswordInput: ""

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        Services.OverlayManager.controlCenterVisible = true
    }
    function close() {
        Services.OverlayManager.controlCenterVisible = false
        Services.OverlayManager.wifiPanelVisible = false
        Services.OverlayManager.btPanelVisible = false
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

    component ControlSlider: ColumnLayout {
        id: sliderRoot
        property string icon: ""
        property real value: 0
        signal moved(real newValue)

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: sliderRoot.icon
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 14
                color: Services.Theme.textPrimary
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Services.Theme.surfaceVariant

                    Rectangle {
                        height: parent.height
                        radius: 3
                        color: Services.Theme.accent
                        width: Math.max(6, sliderRoot.value * parent.width)
                        Behavior on width { NumberAnimation { duration: 80 } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (mouse) => sliderRoot.moved(Math.max(0, Math.min(1, mouse.x / width)))
                    onPositionChanged: (mouse) => {
                        if (pressed) sliderRoot.moved(Math.max(0, Math.min(1, mouse.x / width)))
                    }
                }
            }

            Text {
                text: Math.round(sliderRoot.value * 100) + "%"
                font.pixelSize: 11
                color: Services.Theme.textSecondary
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignRight
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

    // Signal strength ala macOS — 4 bar naik tinggi, keisi sesuai persentase
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
            anchors { top: parent.top; right: parent.right }
            anchors.rightMargin: 12
            anchors.topMargin: 12
            width: 340
            height: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible)
                ? 480
                : Math.max(220, Math.min(mainCol.implicitHeight + 32, 640))
            radius: Services.Theme.radiusMd
            // Background selalu Theme.surface agar Hyprland blur pada layer rule tetap aktif
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                opacity: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible) ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Text {
                    text: "Control Center"
                    color: Services.Theme.textPrimary
                    font.bold: true
                    font.pixelSize: 15
                }

                // ── WiFi + Media (baris atas, TETAP kayak sebelumnya) ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        id: wifiTile
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 88
                        radius: Services.Theme.radiusLg
                        color: Services.Wifi.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                text: "\uf1eb"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 16
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.Wifi.enabled ? "#0a0a0a" : Services.Theme.textPrimary
                            }
                            Text {
                                text: Services.Wifi.enabled ? (Services.Wifi.connected ? Services.Wifi.ssid : "On") : "Off"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.preferredWidth: 84
                                horizontalAlignment: Text.AlignHCenter
                                color: Services.Wifi.enabled ? "#0a0a0a" : Services.Theme.textSecondary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Wifi.toggle()
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 5
                            anchors { top: parent.top; right: parent.right; margins: 4 }
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Services.OverlayManager.wifiPanelVisible ? "\uf077" : "\uf078"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 9
                                color: Services.Wifi.enabled ? "#0a0a0a" : Services.Theme.textDisabled
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.OverlayManager.wifiPanelVisible = !Services.OverlayManager.wifiPanelVisible
                                    if (Services.OverlayManager.wifiPanelVisible) Services.Wifi.scan()
                                    Services.OverlayManager.btPanelVisible = false
                                }
                            }
                        }
                    }

                    Local.MediaTile {
                        Layout.fillWidth: true
                    }
                }

                // ── Bluetooth + Focus + Battery Saver (baris bawah) ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        id: btTile
                        Layout.preferredWidth: 92
                        Layout.preferredHeight: 56
                        radius: Services.Theme.radiusLg
                        color: Services.Bluetooth.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                text: "\uf294"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.Bluetooth.enabled ? "#0a0a0a" : Services.Theme.textPrimary
                            }
                            Text {
                                text: Services.Bluetooth.enabled ? "On" : "Off"
                                font.pixelSize: 9
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.Bluetooth.enabled ? "#0a0a0a" : Services.Theme.textSecondary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Bluetooth.toggle()
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 5
                            anchors { top: parent.top; right: parent.right; margins: 4 }
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: Services.OverlayManager.btPanelVisible ? "\uf077" : "\uf078"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 8
                                color: Services.Bluetooth.enabled ? "#0a0a0a" : Services.Theme.textDisabled
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.OverlayManager.btPanelVisible = !Services.OverlayManager.btPanelVisible
                                    if (Services.OverlayManager.btPanelVisible) Services.Bluetooth.listDevices()
                                    Services.OverlayManager.wifiPanelVisible = false
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 92
                        Layout.preferredHeight: 56
                        radius: Services.Theme.radiusLg
                        color: Services.Notifications.doNotDisturb ? Services.Theme.accent : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                text: "\uf186"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.Notifications.doNotDisturb ? "#0a0a0a" : Services.Theme.textPrimary
                            }
                            Text {
                                text: "Focus"
                                font.pixelSize: 9
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.Notifications.doNotDisturb ? "#0a0a0a" : Services.Theme.textSecondary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Notifications.doNotDisturb = !Services.Notifications.doNotDisturb
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 92
                        Layout.preferredHeight: 56
                        radius: Services.Theme.radiusLg
                        color: Services.PowerProfile.saverEnabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                        Behavior on color { ColorAnimation { duration: 120 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                text: "\uf06c"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.PowerProfile.saverEnabled ? "#0a0a0a" : Services.Theme.textPrimary
                            }
                            Text {
                                text: "Saver"
                                font.pixelSize: 9
                                Layout.alignment: Qt.AlignHCenter
                                color: Services.PowerProfile.saverEnabled ? "#0a0a0a" : Services.Theme.textSecondary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.PowerProfile.toggleSaver()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.4
                }

                ControlCard {
                    Text {
                        text: "Display"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Theme.textSecondary
                    }
                    ControlSlider {
                        Layout.fillWidth: true
                        icon: Services.Icons.brightnessIcon(Services.Brightness.percent)
                        value: Services.Brightness.percent
                        onMoved: (v) => Services.Brightness.setPercent(v)
                    }
                }

                ControlCard {
                    Text {
                        text: "Sound"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Theme.textSecondary
                    }
                    ControlSlider {
                        Layout.fillWidth: true
                        icon: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted)
                        value: Services.Audio.volume
                        onMoved: (v) => Services.Audio.setVolume(v)
                    }
                }
            }

            // ── WiFi overlay: ngambang di atas, nutupin konten bawahnya ──
            Rectangle {
                id: wifiOverlay
                z: 100
                x: 0
                y: 0
                width: panel.width
                height: Services.OverlayManager.wifiPanelVisible ? panel.height : 0
                color: "transparent"
                clip: true

                opacity: Services.OverlayManager.wifiPanelVisible ? 1 : 0
                visible: opacity > 0.01
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 160 } }

                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Back Button
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: backWifiMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\uf053"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 12
                                color: Services.Theme.textPrimary
                            }
                            MouseArea {
                                id: backWifiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.OverlayManager.wifiPanelVisible = false
                            }
                        }

                        Text {
                            text: "Wi-Fi Networks"
                            color: Services.Theme.textPrimary
                            font.bold: true
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }

                        // Refresh Button
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: refreshWifiMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Wifi.scanning ? "\uf110" : "\uf021"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 12
                                color: Services.Wifi.scanning ? Services.Theme.accent : Services.Theme.textSecondary
                            }
                            MouseArea {
                                id: refreshWifiMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Services.Wifi.enabled) Services.Wifi.scan()
                                }
                            }
                        }

                        // Master Toggle Switch
                        Rectangle {
                            width: 42; height: 22; radius: 11
                            color: Services.Wifi.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                width: 18; height: 18; radius: 9
                                x: Services.Wifi.enabled ? parent.width - width - 2 : 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: Services.Wifi.enabled ? "#0a0a0a" : Services.Theme.textSecondary
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Wifi.toggle()
                            }
                        }
                    }

                    Flickable {
                        id: wifiFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: wifiOverlayCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: wifiOverlayCol
                            width: wifiFlickable.width
                            spacing: 8

                            // Wi-Fi Disabled State Card
                            Rectangle {
                                visible: !Services.Wifi.enabled
                                Layout.fillWidth: true
                                implicitHeight: 130
                                radius: Services.Theme.radiusLg
                                color: Services.Theme.surfaceVariant

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Text {
                                        text: "\uf1eb"
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 24
                                        color: Services.Theme.textDisabled
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Wi-Fi is turned off"
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: 12
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: 90; Layout.preferredHeight: 28; radius: 14
                                        color: Services.Theme.accent
                                        Layout.alignment: Qt.AlignHCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Turn On"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: "#0a0a0a"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Wifi.toggle()
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: Services.Wifi.enabled && Services.Wifi.lastError.length > 0
                                text: Services.Wifi.lastError
                                color: Services.Theme.danger
                                font.pixelSize: 10
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: Services.Wifi.enabled && Services.Wifi.networks.length === 0 && !Services.Wifi.scanning
                                text: "No networks found"
                                color: Services.Theme.textDisabled
                                font.pixelSize: 11
                            }

                            Repeater {
                                model: Services.Wifi.enabled ? Services.Wifi.networks : []
                                delegate: Rectangle {
                                    id: netRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: netCol.implicitHeight + 16
                                    radius: Services.Theme.radiusMd
                                    color: netArea.containsMouse ? Services.Theme.bgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    readonly property bool isSaved: Services.Wifi.isSaved(netRow.modelData.ssid)
                                    readonly property bool isPwOpen: root.wifiPasswordTarget === netRow.modelData.ssid
                                    property bool showPassword: false

                                    function doJoin() {
                                        Services.Wifi.connectNetwork(netRow.modelData.ssid, root.wifiPasswordInput)
                                        root.wifiPasswordTarget = ""
                                    }

                                    ColumnLayout {
                                        id: netCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top }
                                        anchors.margins: 8
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Item {
                                                Layout.fillWidth: true
                                                implicitHeight: rowContent.implicitHeight

                                                RowLayout {
                                                    id: rowContent
                                                    anchors.fill: parent
                                                    spacing: 10

                                                    Text {
                                                        text: netRow.modelData.security.length > 0 ? "\uf023" : "\uf09c"
                                                        font.family: "Symbols Nerd Font Mono"
                                                        font.pixelSize: 12
                                                        color: netRow.modelData.inUse ? Services.Theme.accent : Services.Theme.textSecondary
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1
                                                        Text {
                                                            text: netRow.modelData.ssid
                                                            color: netRow.modelData.inUse ? Services.Theme.accent : Services.Theme.textPrimary
                                                            font.bold: netRow.modelData.inUse
                                                            font.pixelSize: 12
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            visible: netRow.modelData.inUse || netRow.isSaved
                                                            text: netRow.modelData.inUse ? "Connected" : "Saved · auto-connect"
                                                            color: Services.Theme.textDisabled
                                                            font.pixelSize: 9
                                                        }
                                                    }

                                                    SignalBars { signal: netRow.modelData.signal }
                                                }

                                                MouseArea {
                                                    id: netArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (netRow.modelData.inUse) {
                                                            Services.Wifi.disconnectNetwork()
                                                        } else if (netRow.isSaved || netRow.modelData.security.length === 0) {
                                                            Services.Wifi.connectNetwork(netRow.modelData.ssid, "")
                                                        } else {
                                                            root.wifiPasswordTarget = netRow.isPwOpen ? "" : netRow.modelData.ssid
                                                            root.wifiPasswordInput = ""
                                                        }
                                                    }
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
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "\uf1f8"
                                                    font.family: "Symbols Nerd Font Mono"
                                                    font.pixelSize: 10
                                                    color: forgetHover.containsMouse ? "#0a0a0a" : Services.Theme.textDisabled
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

                                        // Dark-themed Password Input Box
                                        ColumnLayout {
                                            visible: netRow.isPwOpen
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 34
                                                radius: Services.Theme.radiusSm
                                                color: Services.Theme.surfaceVariant
                                                border.color: pwInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                                border.width: 1

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 6

                                                    TextInput {
                                                        id: pwInput
                                                        Layout.fillWidth: true
                                                        text: root.wifiPasswordInput
                                                        echoMode: netRow.showPassword ? TextInput.Normal : TextInput.Password
                                                        font.pixelSize: 12
                                                        color: Services.Theme.textPrimary
                                                        verticalAlignment: TextInput.AlignVCenter
                                                        clip: true

                                                        Text {
                                                            visible: pwInput.text.length === 0
                                                            text: "Enter password"
                                                            color: Services.Theme.textDisabled
                                                            font.pixelSize: 12
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        onTextChanged: root.wifiPasswordInput = text
                                                        Keys.onReturnPressed: netRow.doJoin()
                                                    }

                                                    Text {
                                                        text: netRow.showPassword ? "\uf06e" : "\uf070"
                                                        font.family: "Symbols Nerd Font Mono"
                                                        font.pixelSize: 12
                                                        color: eyeMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                                        MouseArea {
                                                            id: eyeMouse
                                                            anchors.fill: parent
                                                            anchors.margins: -4
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: netRow.showPassword = !netRow.showPassword
                                                        }
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignRight
                                                spacing: 8

                                                Rectangle {
                                                    width: 60; height: 26; radius: 13
                                                    color: cancelMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                                    Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 11; color: Services.Theme.textSecondary }
                                                    MouseArea {
                                                        id: cancelMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.wifiPasswordTarget = ""
                                                    }
                                                }

                                                Rectangle {
                                                    width: 60; height: 26; radius: 13
                                                    color: Services.Theme.accent
                                                    Text { anchors.centerIn: parent; text: "Join"; font.pixelSize: 11; font.bold: true; color: "#0a0a0a" }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: netRow.doJoin()
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

            // ── Bluetooth overlay ──
            Rectangle {
                id: btOverlay
                z: 100
                x: 0
                y: 0
                width: panel.width
                height: Services.OverlayManager.btPanelVisible ? panel.height : 0
                color: "transparent"
                clip: true

                opacity: Services.OverlayManager.btPanelVisible ? 1 : 0
                visible: opacity > 0.01
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 160 } }

                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Back Button
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: backBtMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: "\uf053"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 12
                                color: Services.Theme.textPrimary
                            }
                            MouseArea {
                                id: backBtMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.OverlayManager.btPanelVisible = false
                            }
                        }

                        Text {
                            text: "Bluetooth Devices"
                            color: Services.Theme.textPrimary
                            font.bold: true
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }

                        // Refresh Button
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: refreshBtMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Bluetooth.refreshing ? "\uf110" : "\uf021"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 12
                                color: Services.Bluetooth.refreshing ? Services.Theme.accent : Services.Theme.textSecondary
                            }
                            MouseArea {
                                id: refreshBtMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Services.Bluetooth.enabled) Services.Bluetooth.listDevices()
                                }
                            }
                        }

                        // Master Toggle Switch
                        Rectangle {
                            width: 42; height: 22; radius: 11
                            color: Services.Bluetooth.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                width: 18; height: 18; radius: 9
                                x: Services.Bluetooth.enabled ? parent.width - width - 2 : 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: Services.Bluetooth.enabled ? "#0a0a0a" : Services.Theme.textSecondary
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Bluetooth.toggle()
                            }
                        }
                    }

                    Flickable {
                        id: btFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: btOverlayCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: btOverlayCol
                            width: btFlickable.width
                            spacing: 8

                            // Bluetooth Disabled State Card
                            Rectangle {
                                visible: !Services.Bluetooth.enabled
                                Layout.fillWidth: true
                                implicitHeight: 130
                                radius: Services.Theme.radiusLg
                                color: Services.Theme.surfaceVariant

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Text {
                                        text: "\uf294"
                                        font.family: "Symbols Nerd Font Mono"
                                        font.pixelSize: 24
                                        color: Services.Theme.textDisabled
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: "Bluetooth is turned off"
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: 12
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: 90; Layout.preferredHeight: 28; radius: 14
                                        color: Services.Theme.accent
                                        Layout.alignment: Qt.AlignHCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Turn On"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: "#0a0a0a"
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Bluetooth.toggle()
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: Services.Bluetooth.enabled && Services.Bluetooth.devices.length === 0 && !Services.Bluetooth.refreshing
                                text: "No paired devices found"
                                color: Services.Theme.textDisabled
                                font.pixelSize: 11
                            }

                            Repeater {
                                model: Services.Bluetooth.enabled ? Services.Bluetooth.devices : []
                                delegate: Rectangle {
                                    id: btRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: btRowLayout.implicitHeight + 16
                                    radius: Services.Theme.radiusMd
                                    color: btArea.containsMouse ? Services.Theme.bgHover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    MouseArea {
                                        id: btArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    RowLayout {
                                        id: btRowLayout
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                        anchors.margins: 8
                                        spacing: 10

                                        Text {
                                            text: btRow.modelData.connected ? "\uf294" : "\uf293"
                                            font.family: "Symbols Nerd Font Mono"
                                            font.pixelSize: 14
                                            color: btRow.modelData.connected ? Services.Theme.accent : Services.Theme.textSecondary
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                text: btRow.modelData.name
                                                color: Services.Theme.textPrimary
                                                font.pixelSize: 12
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: btRow.modelData.connected ? "Connected" : "Paired"
                                                color: Services.Theme.textDisabled
                                                font.pixelSize: 9
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 80; Layout.preferredHeight: 26; radius: 13
                                            color: btRow.modelData.connected ? Services.Theme.surfaceVariant : Services.Theme.accent
                                            Text {
                                                anchors.centerIn: parent
                                                text: btRow.modelData.connected ? "Disconnect" : "Connect"
                                                font.pixelSize: 9
                                                color: btRow.modelData.connected ? Services.Theme.textSecondary : "#0a0a0a"
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (btRow.modelData.connected) Services.Bluetooth.disconnectDevice(btRow.modelData.mac)
                                                    else Services.Bluetooth.connectDevice(btRow.modelData.mac)
                                                }
                                            }
                                        }

                                        Item {
                                            Layout.preferredWidth: 22; Layout.preferredHeight: 22

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 6
                                                color: forgetBtHover.containsMouse ? Services.Theme.danger : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "\uf1f8"
                                                font.family: "Symbols Nerd Font Mono"
                                                font.pixelSize: 10
                                                color: forgetBtHover.containsMouse ? "#0a0a0a" : Services.Theme.textDisabled
                                            }
                                            MouseArea {
                                                id: forgetBtHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Services.Bluetooth.removeDevice(btRow.modelData.mac)
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

