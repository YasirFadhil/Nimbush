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
    radius: Services.Theme.radiusLg
    color: Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.95)
    border.color: Services.Theme.borderHighlight
    border.width: 1
    clip: true

    signal requestClose()

    property bool wifiExpanded: false
    property bool btExpanded: false
    property bool pwrExpanded: false
    property string wifiPasswordTarget: ""
    property string wifiPasswordInput: ""

    Process { id: ccSuspendProc; command: ["systemctl", "suspend"] }
    Process { id: ccRebootProc; command: ["systemctl", "reboot"] }
    Process { id: ccShutdownProc; command: ["systemctl", "poweroff"] }

    function close() {
        wifiExpanded = false
        btExpanded = false
        pwrExpanded = false
        wifiPasswordTarget = ""
        wifiPasswordInput = ""
        root.requestClose()
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
        border.color: sliderMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
        border.width: 1
        clip: true

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

        // Active track fill
        Rectangle {
            id: fillBar
            height: parent.height
            radius: parent.radius
            color: sliderMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.08) : Services.Theme.accent
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
                color: (fillBar.width > (iconText.x + sliderContentRow.x + iconText.width / 2)) ? Services.Theme.bgDeep : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }

            Item { Layout.fillWidth: true }

            Text {
                id: percentText
                text: Math.round(sliderRoot.value * 100) + "%"
                font.pixelSize: 11
                font.bold: true
                color: (fillBar.width > (percentText.x + sliderContentRow.x + percentText.width / 2)) ? Services.Theme.bgDeep : Services.Theme.textPrimary
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
        radius: Services.Theme.radiusMd
        color: Services.Theme.surfaceVariant
        border.color: Services.Theme.border
        border.width: 1
        implicitHeight: inner.implicitHeight + 20

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
        }
    }

    // Signal strength indicator
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
                color: (index < bars.tier) ? (root.wifiExpanded ? Services.Theme.accent : Services.Theme.bgDeep) : Services.Theme.border
                opacity: (index < bars.tier) ? 1 : 0.4
            }
        }
    }

    // Consume clicks on the control center card so it doesn't close on click
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    ColumnLayout {
        id: mainCol
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        anchors.margins: 14
        spacing: 12

        // ── Header Bar: Title, Battery Info & Close Button ──────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Control Center"
                color: Services.Theme.textPrimary
                font.bold: true
                font.pixelSize: 14
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
                        text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 11
                        color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.accent))
                    }
                    Text {
                        text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                        font.pixelSize: 10
                        font.bold: true
                        color: Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textSecondary)
                    }
                }
            }

            // Power Panel Toggle Button
            Rectangle {
                width: 24; height: 24; radius: 12
                color: (root.pwrExpanded || pwrMouse.containsMouse) ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) : "transparent"
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: Services.Icons.power
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 11
                    color: (root.pwrExpanded || pwrMouse.containsMouse) ? Services.Theme.danger : Services.Theme.textSecondary
                }

                MouseArea {
                    id: pwrMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.pwrExpanded = !root.pwrExpanded
                        if (root.pwrExpanded) {
                            root.wifiExpanded = false
                            root.btExpanded = false
                        }
                    }
                }
            }

            // Close Button (✕)
            Rectangle {
                width: 24; height: 24; radius: 12
                color: closeMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: Services.Icons.close
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 11
                    color: closeMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
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

        // ── Morphing Quick Tiles Row (Wi-Fi, Bluetooth & Power) ─────────────
        RowLayout {
            id: morphingTilesRow
            Layout.fillWidth: true
            spacing: (root.wifiExpanded || root.btExpanded || root.pwrExpanded) ? 0 : 8
            Behavior on spacing { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            // ── Wi-Fi Card with Full Interactive Expander ───────────────────
            Rectangle {
                id: wifiTile
                Layout.fillWidth: !root.btExpanded && !root.pwrExpanded
                Layout.preferredWidth: (root.btExpanded || root.pwrExpanded) ? 0 : (root.wifiExpanded ? 312 : 152)
                Layout.preferredHeight: root.wifiExpanded ? 240 : (root.pwrExpanded ? 0 : 70)
                radius: Services.Theme.radiusMd
                color: Services.Wifi.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                border.color: Services.Wifi.enabled ? Services.Theme.accent : Services.Theme.border
                border.width: 1
                clip: true

                visible: opacity > 0.01
                opacity: (root.btExpanded || root.pwrExpanded) ? 0 : 1

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Wi-Fi Circular Toggle Button
                        Rectangle {
                            width: 34; height: 34; radius: 17
                            color: wifiIconMouse.containsMouse 
                                   ? (Services.Wifi.enabled ? Qt.rgba(0,0,0,0.15) : Services.Theme.bgHover) 
                                   : (Services.Wifi.enabled ? Qt.rgba(0,0,0,0.1) : "transparent")
                            border.color: Services.Wifi.enabled ? "transparent" : Services.Theme.border
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.wifi
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 16
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

                        // Expander Click Area
                        MouseArea {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.wifiExpanded = !root.wifiExpanded
                                if (root.wifiExpanded) {
                                    Services.Wifi.scan()
                                    root.btExpanded = false
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: root.wifiExpanded 
                                              ? "Wi-Fi Networks" 
                                              : (Services.Wifi.enabled ? (Services.Wifi.connected ? Services.Wifi.ssid : "Wi-Fi") : "Wi-Fi")
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                    }
                                    Text {
                                        text: root.wifiExpanded
                                              ? (Services.Wifi.scanning ? "Scanning..." : (Services.Wifi.networks.length + " networks"))
                                              : (Services.Wifi.enabled ? (Services.Wifi.connected ? "Connected" : "On") : "Off")
                                        font.pixelSize: 9
                                        color: Services.Wifi.enabled ? Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75) : Services.Theme.textDisabled
                                    }
                                }

                                Text {
                                    text: Services.Icons.chevDown
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                    rotation: root.wifiExpanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.wifiExpanded
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Wifi.enabled ? Qt.rgba(0,0,0,0.12) : Services.Theme.border
                    }

                    // Expanded Wi-Fi Network List
                    Flickable {
                        visible: root.wifiExpanded
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: wifiCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: wifiCol
                            width: parent.width
                            spacing: 4

                            Text {
                                visible: !Services.Wifi.enabled
                                text: "Wi-Fi is turned off"
                                font.pixelSize: 11
                                color: Services.Theme.bgDeep
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Repeater {
                                model: Services.Wifi.enabled ? Services.Wifi.networks : []
                                delegate: Rectangle {
                                    id: netRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: netRowCol.implicitHeight + 8
                                    radius: Services.Theme.radiusSm
                                    color: netMouse.containsMouse ? Qt.rgba(0,0,0,0.1) : "transparent"

                                    property bool isPwOpen: root.wifiPasswordTarget !== "" && root.wifiPasswordTarget === (netRow.modelData ? netRow.modelData.ssid : "")

                                    ColumnLayout {
                                        id: netRowCol
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            SignalBars {
                                                signal: netRow.modelData.signal || 0
                                            }

                                            Text {
                                                text: netRow.modelData.ssid || "Hidden Network"
                                                font.pixelSize: 11
                                                font.bold: Boolean(netRow.modelData && netRow.modelData.connected)
                                                color: Services.Wifi.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: Boolean(netRow.modelData && netRow.modelData.security && netRow.modelData.security.length > 0 && netRow.modelData.security !== "--")
                                                text: "󰌾"
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 10
                                                color: Services.Theme.bgDeep
                                                opacity: 0.7
                                            }

                                            Rectangle {
                                                visible: Boolean(netRow.modelData && netRow.modelData.connected)
                                                height: 18
                                                implicitWidth: conTxt.implicitWidth + 10
                                                radius: 9
                                                color: Qt.rgba(0,0,0,0.18)
                                                Text {
                                                    id: conTxt
                                                    anchors.centerIn: parent
                                                    text: "Active"
                                                    font.pixelSize: 8
                                                    font.bold: true
                                                    color: Services.Theme.bgDeep
                                                }
                                            }
                                        }

                                        // Inline Password Input when network is clicked
                                        ColumnLayout {
                                            visible: netRow.isPwOpen && !netRow.modelData.connected
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 28
                                                radius: 6
                                                color: Qt.rgba(255,255,255,0.9)
                                                border.color: Services.Theme.border
                                                border.width: 1

                                                TextInput {
                                                    id: pwInputBox
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    text: root.wifiPasswordInput
                                                    echoMode: TextInput.Password
                                                    font.pixelSize: 11
                                                    color: "#111111"
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    onTextChanged: root.wifiPasswordInput = text
                                                    Keys.onReturnPressed: {
                                                        Services.Wifi.connectNetwork(netRow.modelData.ssid, root.wifiPasswordInput)
                                                        root.wifiPasswordTarget = ""
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 24
                                                    radius: 4
                                                    color: Qt.rgba(0,0,0,0.2)
                                                    Text { anchors.centerIn: parent; text: "Cancel"; font.pixelSize: 9; color: Services.Theme.bgDeep; font.bold: true }
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.wifiPasswordTarget = "" }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 24
                                                    radius: 4
                                                    color: Qt.rgba(0,0,0,0.4)
                                                    Text { anchors.centerIn: parent; text: "Connect"; font.pixelSize: 9; color: Services.Theme.white; font.bold: true }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            Services.Wifi.connectNetwork(netRow.modelData.ssid, root.wifiPasswordInput)
                                                            root.wifiPasswordTarget = ""
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: netMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        visible: !netRow.isPwOpen
                                        onClicked: {
                                            if (netRow.modelData.connected) return
                                            if (netRow.modelData.security && netRow.modelData.security.length > 0 && netRow.modelData.security !== "--") {
                                                root.wifiPasswordTarget = netRow.modelData.ssid
                                                root.wifiPasswordInput = ""
                                            } else {
                                                Services.Wifi.connectNetwork(netRow.modelData.ssid, "")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Bluetooth Card with Full Interactive Expander ───────────────
            Rectangle {
                id: btTile
                Layout.fillWidth: !root.wifiExpanded && !root.pwrExpanded
                Layout.preferredWidth: (root.wifiExpanded || root.pwrExpanded) ? 0 : (root.btExpanded ? 312 : 152)
                Layout.preferredHeight: root.btExpanded ? 240 : (root.pwrExpanded ? 0 : 70)
                radius: Services.Theme.radiusMd
                color: Services.Bluetooth.enabled ? Services.Theme.accent : Services.Theme.surfaceVariant
                border.color: Services.Bluetooth.enabled ? Services.Theme.accent : Services.Theme.border
                border.width: 1
                clip: true

                visible: opacity > 0.01
                opacity: (root.wifiExpanded || root.pwrExpanded) ? 0 : 1

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Bluetooth Circular Toggle Button
                        Rectangle {
                            width: 34; height: 34; radius: 17
                            color: btIconMouse.containsMouse 
                                   ? (Services.Bluetooth.enabled ? Qt.rgba(0,0,0,0.15) : Services.Theme.bgHover) 
                                   : (Services.Bluetooth.enabled ? Qt.rgba(0,0,0,0.1) : "transparent")
                            border.color: Services.Bluetooth.enabled ? "transparent" : Services.Theme.border
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.bluetooth
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 16
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

                        // Expander Click Area
                        MouseArea {
                            Layout.fillWidth: true
                            implicitHeight: 34
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.btExpanded = !root.btExpanded
                                if (root.btExpanded) {
                                    Services.Bluetooth.listDevices()
                                    root.wifiExpanded = false
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 4

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: root.btExpanded ? "Bluetooth Devices" : "Bluetooth"
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textPrimary
                                    }
                                    Text {
                                        text: root.btExpanded
                                              ? (Services.Bluetooth.refreshing ? "Searching..." : (Services.Bluetooth.devices.length + " paired"))
                                              : (Services.Bluetooth.enabled ? (Services.Bluetooth.devices.some(d => d.connected) ? "Connected" : "On") : "Off")
                                        font.pixelSize: 9
                                        color: Services.Bluetooth.enabled ? Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75) : Services.Theme.textDisabled
                                    }
                                }

                                Text {
                                    text: Services.Icons.chevDown
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Bluetooth.enabled ? Services.Theme.bgDeep : Services.Theme.textDisabled
                                    rotation: root.btExpanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.btExpanded
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Bluetooth.enabled ? Qt.rgba(0,0,0,0.12) : Services.Theme.border
                    }

                    // Expanded Bluetooth Device List
                    Flickable {
                        visible: root.btExpanded
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: btCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: btCol
                            width: parent.width
                            spacing: 4

                            Text {
                                visible: !Services.Bluetooth.enabled
                                text: "Bluetooth is turned off"
                                font.pixelSize: 11
                                color: Services.Theme.bgDeep
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                visible: Services.Bluetooth.enabled && Services.Bluetooth.devices.length === 0
                                text: "No paired devices"
                                font.pixelSize: 11
                                color: Services.Theme.bgDeep
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Repeater {
                                model: Services.Bluetooth.enabled ? Services.Bluetooth.devices : []
                                delegate: Rectangle {
                                    id: btRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: Services.Theme.radiusSm
                                    color: btRowMouse.containsMouse ? Qt.rgba(0,0,0,0.1) : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 8

                                        Text {
                                            text: btRow.modelData.connected ? "󰂱" : "󰂯"
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 13
                                            color: Services.Theme.bgDeep
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: btRow.modelData.name || btRow.modelData.mac
                                                font.pixelSize: 11
                                                font.bold: btRow.modelData.connected
                                                color: Services.Theme.bgDeep
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: btRow.modelData.connected ? "Connected" : "Paired"
                                                font.pixelSize: 8
                                                color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75)
                                            }
                                        }

                                        Rectangle {
                                            height: 20
                                            implicitWidth: btConBtnTxt.implicitWidth + 12
                                            radius: 10
                                            color: btRow.modelData.connected ? Qt.rgba(0,0,0,0.2) : Qt.rgba(0,0,0,0.3)

                                            Text {
                                                id: btConBtnTxt
                                                anchors.centerIn: parent
                                                text: btRow.modelData.connected ? "Disconnect" : "Connect"
                                                font.pixelSize: 8
                                                font.bold: true
                                                color: Services.Theme.white
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: btRowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (btRow.modelData.connected) {
                                                Services.Bluetooth.disconnectDevice(btRow.modelData.mac)
                                            } else {
                                                Services.Bluetooth.connectDevice(btRow.modelData.mac)
                                            }
                                        }
                                    }
                                }
                            }

                            // Scan Button
                            Rectangle {
                                visible: Services.Bluetooth.enabled
                                Layout.fillWidth: true
                                height: 26
                                radius: Services.Theme.radiusSm
                                color: Qt.rgba(0,0,0,0.12)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: Services.Icons.refreshOrSpinIcon(Services.Bluetooth.scanning)
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 10
                                        color: Services.Theme.bgDeep
                                    }
                                    Text {
                                        text: Services.Bluetooth.scanning ? "Scanning..." : "Scan New Devices"
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: Services.Theme.bgDeep
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.Bluetooth.toggleScan()
                                }
                            }
                        }
                    }
                }
            }

            // ── Power Card with Full Interactive Morphing Expander ──────────
            Rectangle {
                id: pwrTile
                Layout.fillWidth: !root.wifiExpanded && !root.btExpanded
                Layout.preferredWidth: (root.wifiExpanded || root.btExpanded) ? 0 : (root.pwrExpanded ? 312 : 0)
                Layout.preferredHeight: root.pwrExpanded ? 180 : 0
                radius: Services.Theme.radiusMd
                color: Services.Theme.surfaceVariant
                border.color: Services.Theme.borderHighlight
                border.width: 1
                clip: true

                visible: opacity > 0.01
                opacity: (root.wifiExpanded || root.btExpanded) ? 0 : (root.pwrExpanded ? 1 : 0)

                Behavior on Layout.preferredWidth { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Power Options"
                            font.pixelSize: 11
                            font.bold: true
                            color: Services.Theme.textPrimary
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: pwrTileCloseMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.close
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 9
                                color: Services.Theme.textSecondary
                            }
                            MouseArea {
                                id: pwrTileCloseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pwrExpanded = false
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Services.Theme.border
                    }

                    // Sleep
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Services.Theme.radiusSm
                        color: ccSleepMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8
                            Text { text: Services.Icons.pmSleep; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.accent }
                            Text { text: "Sleep System"; font.pixelSize: 10; font.bold: true; color: Services.Theme.textPrimary; Layout.fillWidth: true }
                        }
                        MouseArea {
                            id: ccSleepMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                ccSuspendProc.running = true
                            }
                        }
                    }

                    // Reboot
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Services.Theme.radiusSm
                        color: ccRebootMouse.containsMouse ? Qt.rgba(Services.Theme.warning.r, Services.Theme.warning.g, Services.Theme.warning.b, 0.15) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8
                            Text { text: Services.Icons.pmReboot; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.warning }
                            Text { text: "Reboot System"; font.pixelSize: 10; font.bold: true; color: Services.Theme.textPrimary; Layout.fillWidth: true }
                        }
                        MouseArea {
                            id: ccRebootMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                ccRebootProc.running = true
                            }
                        }
                    }

                    // Power Off
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Services.Theme.radiusSm
                        color: ccPowerMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8
                            Text { text: Services.Icons.pmShutdown; font.family: Services.Theme.fontSymbols; font.pixelSize: 13; color: Services.Theme.danger }
                            Text { text: "Power Off System"; font.pixelSize: 10; font.bold: true; color: Services.Theme.danger; Layout.fillWidth: true }
                        }
                        MouseArea {
                            id: ccPowerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                ccShutdownProc.running = true
                            }
                        }
                    }
                }
            }
        }

        // ── Sliders Card: Volume & Brightness ───────────────────────────────
        ControlCard {
            ControlSlider {
                icon: Services.Icons.volumeIcon(Services.Audio.volume || 0, Services.Audio.muted)
                value: Services.Audio.muted ? 0 : (Services.Audio.volume || 0)
                onMoved: (val) => Services.Audio.setVolume(val)
            }

            ControlSlider {
                icon: Services.Icons.brightnessIcon(Services.Brightness.value || 0)
                value: Services.Brightness.value || 0
                onMoved: (val) => Services.Brightness.setValue(val)
            }
        }
    }
}
