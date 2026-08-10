import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.wifiPanelVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        id: escFocus
        focus: Services.OverlayManager.wifiPanelVisible
        Keys.onEscapePressed: root.close()
    }

    property string passwordTarget: ""
    property string passwordInput: ""

    function close() {
        Services.OverlayManager.wifiPanelVisible = false
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
            height: Math.max(160, Math.min(col.implicitHeight + 32, 420))
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.wifiPanelVisible ? 1 : 0
            scale: Services.OverlayManager.wifiPanelVisible ? 1 : 0.96
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
                    Text { text: "Networks"; color: Services.Theme.textPrimary; font.bold: true; font.pixelSize: 13; Layout.fillWidth: true }
                    Text {
                        text: Services.Wifi.scanning ? "Scanning…" : "\uf021"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 12
                        color: Services.Theme.textDisabled
                        MouseArea { anchors.fill: parent; onClicked: Services.Wifi.scan() }
                    }
                }

                Text {
                    visible: Services.Wifi.lastError.length > 0
                    text: Services.Wifi.lastError
                    color: Services.Theme.danger
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Text {
                    visible: Services.Wifi.networks.length === 0 && !Services.Wifi.scanning
                    text: "No networks found"
                    color: Services.Theme.textDisabled
                    font.pixelSize: 11
                }

                Repeater {
                    model: Services.Wifi.networks
                    delegate: ColumnLayout {
                        id: netRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        function doJoin() {
                            Services.Wifi.connectNetwork(netRow.modelData.ssid, root.passwordInput)
                            root.passwordTarget = ""
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: netRow.modelData.security.length > 0 ? "\uf023" : "\uf09c"
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 11
                                color: Services.Theme.textSecondary
                            }
                            Text {
                                text: netRow.modelData.ssid
                                color: netRow.modelData.inUse ? Services.Theme.accent : Services.Theme.textPrimary
                                font.bold: netRow.modelData.inUse
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: netRow.modelData.signal + "%"
                                font.pixelSize: 10
                                color: Services.Theme.textDisabled
                            }
                        }

                        MouseArea {
                            Layout.fillWidth: true
                            height: 20
                            onClicked: {
                                if (netRow.modelData.inUse) {
                                    Services.Wifi.disconnectNetwork()
                                } else if (netRow.modelData.security.length === 0) {
                                    Services.Wifi.connectNetwork(netRow.modelData.ssid, "")
                                } else {
                                    root.passwordTarget = (root.passwordTarget === netRow.modelData.ssid) ? "" : netRow.modelData.ssid
                                    root.passwordInput = ""
                                }
                            }
                        }

                        RowLayout {
                            visible: root.passwordTarget === netRow.modelData.ssid
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                Layout.fillWidth: true
                                placeholderText: "Password"
                                echoMode: TextInput.Password
                                onTextChanged: root.passwordInput = text
                                Keys.onReturnPressed: netRow.doJoin()
                            }
                            Rectangle {
                                width: 56; height: 28; radius: 8
                                color: Services.Theme.accent
                                Text { anchors.centerIn: parent; text: "Join"; font.pixelSize: 11; color: "#0a0a0a" }
                                MouseArea { anchors.fill: parent; onClicked: netRow.doJoin() }
                            }
                        }
                    }
                }
            }
        }
    }
}
