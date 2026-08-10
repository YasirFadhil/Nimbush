import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: panel
            anchors { top: parent.top; right: parent.right }
            anchors.rightMargin: 12
            anchors.topMargin: 12
            width: 340
            height: Math.max(220, Math.min(mainCol.implicitHeight + 32, 640))
            radius: Services.Theme.radiusMd
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.controlCenterVisible ? 1 : 0
            scale: 1
            y: Services.OverlayManager.controlCenterVisible ? 0 : -24
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "Control Center"
                    color: Services.Theme.textPrimary
                    font.bold: true
                    font.pixelSize: 15
                }

                // ── WiFi + Media (baris atas) ───────────────────────
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

                // ── Bluetooth + Focus + Battery Saver ───────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        id: btTile
                        Layout.preferredWidth: 100
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
                        Layout.preferredWidth: 100
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
                        Layout.preferredWidth: 100
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
        }
    }
}
