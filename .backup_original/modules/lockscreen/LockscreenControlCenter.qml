import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../services" as Services

Rectangle {
    id: root

    width: 340
    implicitHeight: mainCol.implicitHeight + 32
    radius: Services.Theme.radiusMd
    color: Services.Theme.surface
    border.color: Services.Theme.border
    border.width: 1
    clip: true

    property string wifiPasswordTarget: ""
    property string wifiPasswordInput: ""
    property bool pwrPanelVisible: false

    Process { id: suspendProc; command: ["systemctl", "suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["systemctl", "poweroff"] }

    function close() {
        Services.OverlayManager.controlCenterVisible = false
        Services.OverlayManager.wifiPanelVisible = false
        Services.OverlayManager.btPanelVisible = false
        root.pwrPanelVisible = false
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
        color: Services.Theme.surfaceVariant
        clip: true

        // Active track fill
        Rectangle {
            id: fillBar
            height: parent.height
            radius: parent.radius
            color: Services.Theme.accent
            width: Math.max(38, Math.min(parent.width, sliderRoot.value * parent.width))
            Behavior on width { NumberAnimation { duration: 80 } }
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
                color: (fillBar.width > (iconText.x + sliderContentRow.x + iconText.width / 2)) ? Services.Theme.bgDeep : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 80 } }
            }

            Item { Layout.fillWidth: true }

            Text {
                id: percentText
                text: Math.round(sliderRoot.value * 100) + "%"
                font.pixelSize: 11
                font.bold: true
                color: (fillBar.width > (percentText.x + sliderContentRow.x + percentText.width / 2)) ? Services.Theme.bgDeep : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 80 } }
            }
        }

        MouseArea {
            anchors.fill: parent
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

            // Battery Info Badge
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
                        font.family: Services.Theme.fontMono
                        font.pixelSize: 11
                        color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : (Services.PowerProfile.saverEnabled ? Services.Theme.alertYellow : Services.Theme.textPrimary)))
                        Behavior on color { ColorAnimation { duration: 250 } }

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
                        color: Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : (Services.PowerProfile.saverEnabled ? Services.Theme.alertYellow : Services.Theme.textSecondary))
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                }
            }

            // Power Morphing Panel Toggle Button
            Rectangle {
                width: 26; height: 26; radius: 13
                color: (root.pwrPanelVisible || pwrHover.containsMouse) ? Services.Theme.surfaceVariant : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: Services.Icons.power
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 12
                    color: (root.pwrPanelVisible || pwrHover.containsMouse) ? Services.Theme.danger : Services.Theme.textSecondary
                }

                MouseArea {
                    id: pwrHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.pwrPanelVisible = !root.pwrPanelVisible
                        if (root.pwrPanelVisible) {
                            Services.OverlayManager.wifiPanelVisible = false
                            Services.OverlayManager.btPanelVisible = false
                        }
                    }
                }
            }
        }

        // Dynamic Island Morphing Control Tiles Row (Wi-Fi, Bluetooth & Power Expander)
        RowLayout {
            id: morphingTilesRow
            Layout.fillWidth: true
            spacing: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible || root.pwrPanelVisible) ? 0 : 10
            Behavior on spacing { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

            // Wi-Fi Card with Full Interactive Expander
            Rectangle {
                id: wifiTile
                Layout.fillWidth: (!Services.OverlayManager.btPanelVisible && !root.pwrPanelVisible)
                Layout.preferredWidth: (Services.OverlayManager.btPanelVisible || root.pwrPanelVisible) ? 0 : (Services.OverlayManager.wifiPanelVisible ? 308 : 149)
                Layout.preferredHeight: Services.OverlayManager.wifiPanelVisible ? 248 : 72
                radius: Services.OverlayManager.wifiPanelVisible ? Services.Theme.radiusLg : Services.Theme.radiusLg
                color: Services.Wifi.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                clip: true

                visible: opacity > 0.01
                opacity: (Services.OverlayManager.btPanelVisible || root.pwrPanelVisible) ? 0 : 1

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Dynamic Island Header Bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 36; height: 36; radius: 18
                            color: wifiIconMouse.containsMouse 
                                   ? (Services.Wifi.enabled ? Services.Theme.bgHover : Services.Theme.bgHover) 
                                   : (Services.Wifi.enabled ? Services.Theme.surfaceVariant : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.wifi
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 18
                                color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                            }

                            MouseArea {
                                id: wifiIconMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Wifi.toggle()
                            }
                        }

                        MouseArea {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.OverlayManager.wifiPanelVisible = !Services.OverlayManager.wifiPanelVisible
                                if (Services.OverlayManager.wifiPanelVisible) {
                                    Services.Wifi.scan()
                                    root.pwrPanelVisible = false
                                }
                                Services.OverlayManager.btPanelVisible = false
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
                                        color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                    }
                                    Text {
                                        text: Services.OverlayManager.wifiPanelVisible
                                              ? (Services.Wifi.scanning ? "Scanning networks..." : (Services.Wifi.networks.length + " networks found"))
                                              : (Services.Wifi.enabled ? (Services.Wifi.connected ? "Connected" : "On") : "Off")
                                        font.pixelSize: 10
                                        color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                    }
                                }

                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    visible: Services.OverlayManager.wifiPanelVisible
                                    color: refreshWifiMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
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

                                Text {
                                    text: Services.Icons.chevDown
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                    rotation: Services.OverlayManager.wifiPanelVisible ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: Services.OverlayManager.wifiPanelVisible
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Wifi.enabled ? Services.Theme.borderSubtle : Services.Theme.border
                        opacity: 0.5
                    }

                    Flickable {
                        visible: Services.OverlayManager.wifiPanelVisible
                        opacity: Services.OverlayManager.wifiPanelVisible ? 1 : 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: wifiCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }

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
                                color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
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
                                           ? (netRowArea.containsMouse ? Services.Theme.bgHover : (netRow.modelData.inUse ? Services.Theme.surfaceVariant : "transparent"))
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
                                                            color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                                        }
                                                    }

                                                    SignalBars { signal: netRow.modelData.signal }
                                                }
                                            }

                                            Item {
                                                visible: netRow.isSaved
                                                Layout.preferredWidth: 22; Layout.preferredHeight: 22

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 6
                                                    color: forgetHover.containsMouse ? Services.Theme.dangerDeep : "transparent"
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

                                        ColumnLayout {
                                            visible: netRow.isPwOpen
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 30
                                                radius: 6
                                                color: Services.Wifi.enabled ? Services.Theme.surfaceVariant : Services.Theme.surfaceVariant

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

            // Bluetooth Card with Full Interactive Expander
            Rectangle {
                id: btTile
                Layout.fillWidth: (!Services.OverlayManager.wifiPanelVisible && !root.pwrPanelVisible)
                Layout.preferredWidth: (Services.OverlayManager.wifiPanelVisible || root.pwrPanelVisible) ? 0 : (Services.OverlayManager.btPanelVisible ? 308 : 149)
                Layout.preferredHeight: Services.OverlayManager.btPanelVisible ? 248 : 72
                radius: Services.OverlayManager.btPanelVisible ? Services.Theme.radiusLg : Services.Theme.radiusLg
                color: Services.Bluetooth.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                clip: true

                visible: opacity > 0.01
                opacity: (Services.OverlayManager.wifiPanelVisible || root.pwrPanelVisible) ? 0 : 1

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 36; height: 36; radius: 18
                            color: btIconMouse.containsMouse 
                                   ? (Services.Bluetooth.enabled ? Services.Theme.bgHover : Services.Theme.bgHover) 
                                   : (Services.Bluetooth.enabled ? Services.Theme.surfaceVariant : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.bluetooth
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 18
                                color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                            }

                            MouseArea {
                                id: btIconMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Bluetooth.toggle()
                            }
                        }

                        MouseArea {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.OverlayManager.btPanelVisible = !Services.OverlayManager.btPanelVisible
                                if (Services.OverlayManager.btPanelVisible) {
                                    Services.Bluetooth.listDevices()
                                    root.pwrPanelVisible = false
                                }
                                Services.OverlayManager.wifiPanelVisible = false
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
                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                    }
                                    Text {
                                        text: Services.OverlayManager.btPanelVisible
                                              ? (Services.Bluetooth.refreshing ? "Searching devices..." : (Services.Bluetooth.devices.length + " paired devices"))
                                              : (Services.Bluetooth.enabled ? (Services.Bluetooth.devices.some(d => d.connected) ? "Connected" : "On") : "Off")
                                        font.pixelSize: 10
                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                    }
                                }

                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    visible: Services.OverlayManager.btPanelVisible
                                    color: refreshBtMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
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

                                Text {
                                    text: Services.Icons.chevDown
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                    rotation: Services.OverlayManager.btPanelVisible ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: Services.OverlayManager.btPanelVisible
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Bluetooth.enabled ? Services.Theme.borderSubtle : Services.Theme.border
                        opacity: 0.5
                    }

                    Flickable {
                        visible: Services.OverlayManager.btPanelVisible
                        opacity: Services.OverlayManager.btPanelVisible ? 1 : 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: btCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }

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
                                color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Repeater {
                                model: Services.Bluetooth.enabled ? Services.Bluetooth.devices : []
                                delegate: Rectangle {
                                    id: btRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    radius: Services.Theme.radiusSm
                                    color: Services.Bluetooth.enabled
                                           ? (btRowArea.containsMouse ? Services.Theme.bgHover : (btRow.modelData.connected ? Services.Theme.surfaceVariant : "transparent"))
                                           : (btRowArea.containsMouse ? Services.Theme.bgHover : "transparent")

                                    MouseArea {
                                        id: btRowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (btRow.modelData.connected) Services.Bluetooth.disconnectDevice(btRow.modelData.mac)
                                            else Services.Bluetooth.connectDevice(btRow.modelData.mac)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 8

                                            Text {
                                                text: Services.Icons.bluetooth
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 13
                                                color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textSecondary
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                Text {
                                                    text: btRow.modelData.name
                                                    font.pixelSize: 11
                                                    font.bold: btRow.modelData.connected
                                                    color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: btRow.modelData.connected ? "Connected" : "Paired"
                                                    font.pixelSize: 9
                                                    color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
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

                                            // Unpair / Forget button
                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: unpairLsMouse.containsMouse ? Services.Theme.danger : Services.Theme.surfaceVariant

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰆴"
                                                    font.family: Services.Theme.fontSymbols
                                                    font.pixelSize: 9
                                                    color: unpairLsMouse.containsMouse ? "#ffffff" : Services.Theme.textSecondary
                                                }

                                                MouseArea {
                                                    id: unpairLsMouse
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

                            // Scan New Devices Button
                            Rectangle {
                                visible: Services.Bluetooth.enabled
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: Services.Theme.radiusSm
                                color: lsScanArea.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: Services.Icons.refreshOrSpinIcon(Services.Bluetooth.scanning)
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 11
                                        color: Services.Theme.accent
                                    }

                                    Text {
                                        text: Services.Bluetooth.scanning ? "Scanning..." : "Scan New Devices"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Services.Theme.textPrimary
                                    }
                                }

                                MouseArea {
                                    id: lsScanArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.Bluetooth.toggleScan()
                                }
                            }

                            // Available / Unpaired Devices
                            Repeater {
                                model: Services.Bluetooth.enabled ? Services.Bluetooth.unpairedDevices : []
                                delegate: Rectangle {
                                    id: lsUnpRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    radius: Services.Theme.radiusSm
                                    color: lsUnpArea.containsMouse ? Services.Theme.bgHover : "transparent"

                                    MouseArea {
                                        id: lsUnpArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Bluetooth.pairAndConnect(lsUnpRow.modelData.mac)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 8

                                            Text {
                                                text: "󰂲"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 13
                                                color: Services.Theme.accent
                                            }

                                            Text {
                                                text: lsUnpRow.modelData.name || lsUnpRow.modelData.mac
                                                font.pixelSize: 11
                                                color: Services.Theme.textPrimary
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                implicitWidth: lsUnpTxt.implicitWidth + 14
                                                implicitHeight: 22
                                                radius: 11
                                                color: Services.Theme.accent

                                                Text {
                                                    id: lsUnpTxt
                                                    anchors.centerIn: parent
                                                    text: Services.Bluetooth.pairingMac === lsUnpRow.modelData.mac ? "Pairing..." : "Pair"
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: Services.Theme.bgDeep
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

            // Power Card with Full Interactive Morphing Expander
            Rectangle {
                id: pwrTile
                Layout.fillWidth: (!Services.OverlayManager.wifiPanelVisible && !Services.OverlayManager.btPanelVisible)
                Layout.preferredWidth: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible) ? 0 : (root.pwrPanelVisible ? 308 : 0)
                Layout.preferredHeight: root.pwrPanelVisible ? 248 : 0
                radius: Services.Theme.radiusLg
                color: Services.Theme.surfaceVariant
                clip: true

                visible: opacity > 0.01
                opacity: (Services.OverlayManager.wifiPanelVisible || Services.OverlayManager.btPanelVisible) ? 0 : (root.pwrPanelVisible ? 1 : 0)

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Dynamic Island Header Bar
                    MouseArea {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pwrPanelVisible = false

                        RowLayout {
                            anchors.fill: parent
                            spacing: 8

                            Rectangle {
                                width: 36; height: 36; radius: 18
                                color: Services.Theme.bgHover

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.power
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 18
                                    color: Services.Theme.danger
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: "Power Options"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Services.Theme.textPrimary
                                }
                                Text {
                                    text: "Select a system action"
                                    font.pixelSize: 10
                                    color: Services.Theme.textDisabled
                                }
                            }

                            Text {
                                text: Services.Icons.chevDown
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 10
                                color: Services.Theme.textSecondary
                                rotation: root.pwrPanelVisible ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Theme.borderSubtle
                        opacity: 0.5
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        // Sleep / Suspend Option Row
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Services.Theme.radiusSm
                            color: sleepRowArea.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
                            border.color: sleepRowArea.containsMouse ? Services.Theme.accent : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: sleepRowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.pwrPanelVisible = false
                                    suspendProc.running = true
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Services.Icons.pmSleep
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 16
                                    color: sleepRowArea.containsMouse ? Services.Theme.accent : Services.Theme.accentDim
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Sleep"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: sleepRowArea.containsMouse ? Services.Theme.white : Services.Theme.textPrimary
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    Text {
                                        text: "Suspend system session"
                                        font.pixelSize: 9
                                        color: sleepRowArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }
                        }

                        // Reboot Option Row
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Services.Theme.radiusSm
                            color: rebootRowArea.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
                            border.color: rebootRowArea.containsMouse ? Services.Theme.warning : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: rebootRowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.pwrPanelVisible = false
                                    rebootProc.running = true
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Services.Icons.pmReboot
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 16
                                    color: rebootRowArea.containsMouse ? Services.Theme.warning : Services.Theme.warning
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Reboot"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: rebootRowArea.containsMouse ? Services.Theme.warning : Services.Theme.textPrimary
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    Text {
                                        text: "Restart system"
                                        font.pixelSize: 9
                                        color: rebootRowArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }
                        }

                        // Power Off / Shutdown Option Row
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Services.Theme.radiusSm
                            color: shutdownRowArea.containsMouse ? Services.Theme.dangerDeep : Services.Theme.surface
                            border.color: shutdownRowArea.containsMouse ? Services.Theme.danger : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: shutdownRowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.pwrPanelVisible = false
                                    shutdownProc.running = true
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Services.Icons.pmShutdown
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 16
                                    color: shutdownRowArea.containsMouse ? Services.Theme.white : Services.Theme.danger
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Power Off"
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: shutdownRowArea.containsMouse ? Services.Theme.white : Services.Theme.danger
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    Text {
                                        text: "Turn off system"
                                        font.pixelSize: 9
                                        color: shutdownRowArea.containsMouse ? Services.Theme.white : Services.Theme.textDisabled
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Dedicated Display & Sound Sliders Card
        ControlCard {
            ControlSlider {
                icon: Services.Icons.volumeIcon(Services.Audio.volume || 0, Services.Audio.muted)
                value: Services.Audio.muted ? 0 : (Services.Audio.volume || 0)
                onMoved: (val) => Services.Audio.setVolume(val)

                MouseArea {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 38
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.Audio.toggleMute()
                }
            }

            ControlSlider {
                icon: Services.Icons.brightnessIcon(Services.Brightness.value || 0)
                value: Services.Brightness.value || 0
                onMoved: (val) => Services.Brightness.setValue(val)
            }
        }
    }
}
