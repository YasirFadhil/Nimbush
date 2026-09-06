import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:/services" as Services

PanelWindow {
    id: powerOsd
    anchors { bottom: true }
    margins {
        bottom: (Services.Config && Services.Config.barPosition === "bottom") ? 96 : 60
    }
    implicitWidth: 150
    implicitHeight: 120
    color: "transparent"
    exclusiveZone: 0
    visible: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:hud"

    property bool charging: false
    property real percentage: 0
    property string icon: ""
    property bool active: false

    readonly property string statusText: charging ? "Charging" : "On battery"

    Timer {
        id: hideTimer
        interval: 2200
        repeat: false
        onTriggered: powerOsd.active = false
    }

    Timer {
        id: unmapTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!powerOsd.active) {
                powerOsd.visible = false
            }
        }
    }

    onActiveChanged: {
        if (active) {
            unmapTimer.stop()
            powerOsd.visible = true
        } else {
            unmapTimer.restart()
        }
    }

    function show(isCharging, pct) {
        charging = isCharging
        percentage = pct
        icon = Services.Icons.powerIconSimple(isCharging, pct)
        active = true
        hideTimer.restart()
    }

    Connections {
        target: Services.Power
        function onChargingStateChanged(charging, percentage) {
            powerOsd.show(charging, percentage)
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Math.min(22, Services.Theme.baseRadius + 4)
        color: Services.Theme.bgElevated
        border.color: Services.Theme.border
        border.width: 1

        opacity: powerOsd.active ? 1.0 : 0.0
        scale: powerOsd.active ? 1.0 : 0.93
        transform: Translate {
            y: powerOsd.active ? 0 : 20
            Behavior on y {
                NumberAnimation {
                    duration: powerOsd.active ? 250 : 200
                    easing.type: powerOsd.active ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 0.5
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: powerOsd.active ? 200 : 190
                easing.type: powerOsd.active ? Easing.OutCubic : Easing.InCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: powerOsd.active ? 250 : 200
                easing.type: powerOsd.active ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 0.5
            }
        }

        // Inner specular highlight border
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, Services.Theme.isDark ? 0.08 : 0.22)
            border.width: 1
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
                width: 44
                height: 44
                radius: 14
                color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, Services.Theme.isDark ? 0.16 : 0.12)
                border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, Services.Theme.isDark ? 0.32 : 0.24)
                border.width: 1
                Layout.alignment: Qt.AlignHCenter

                Text {
                    anchors.centerIn: parent
                    text: powerOsd.icon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 22
                    color: powerOsd.charging ? Services.Theme.success : Services.Theme.accent
                }
            }

            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignHCenter

                Text {
                    text: powerOsd.statusText
                    font.family: Services.Theme.fontDisplay
                    font.pixelSize: 12
                    font.weight: Font.SemiBold
                    color: Services.Theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: Math.round(powerOsd.percentage * 100) + "%"
                    font.family: Services.Theme.fontMono
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: powerOsd.charging ? Services.Theme.success : Services.Theme.accent
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
