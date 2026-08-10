import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.btPanelVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        id: escFocus
        focus: Services.OverlayManager.btPanelVisible
        Keys.onEscapePressed: root.close()
    }

    function close() {
        Services.OverlayManager.btPanelVisible = false
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: panel
            anchors { top: parent.top; right: parent.right }
            anchors.topMargin: 12
            anchors.rightMargin: 364
            width: 300
            height: Math.max(140, Math.min(col.implicitHeight + 32, 400))
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.btPanelVisible ? 1 : 0
            scale: Services.OverlayManager.btPanelVisible ? 1 : 0.96
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Paired Devices"; color: Services.Theme.textPrimary; font.bold: true; font.pixelSize: 13; Layout.fillWidth: true }
                    Text {
                        text: Services.Bluetooth.refreshing ? "Refreshing…" : "\uf021"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 12
                        color: Services.Theme.textDisabled
                        MouseArea { anchors.fill: parent; onClicked: Services.Bluetooth.listDevices() }
                    }
                }

                Text {
                    visible: Services.Bluetooth.devices.length === 0 && !Services.Bluetooth.refreshing
                    text: "No paired devices"
                    color: Services.Theme.textDisabled
                    font.pixelSize: 11
                }

                Repeater {
                    model: Services.Bluetooth.devices
                    delegate: RowLayout {
                        id: btRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: btRow.modelData.connected ? "\uf294" : "\uf293"
                            font.family: "Symbols Nerd Font Mono"
                            font.pixelSize: 12
                            color: btRow.modelData.connected ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        Text {
                            text: btRow.modelData.name
                            color: Services.Theme.textPrimary
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            width: 76; height: 24; radius: 7
                            color: btRow.modelData.connected ? Services.Theme.surfaceVariant : Services.Theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: btRow.modelData.connected ? "Disconnect" : "Connect"
                                font.pixelSize: 9
                                color: btRow.modelData.connected ? Services.Theme.textSecondary : "#0a0a0a"
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (btRow.modelData.connected) Services.Bluetooth.disconnectDevice(btRow.modelData.mac)
                                    else Services.Bluetooth.connectDevice(btRow.modelData.mac)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
