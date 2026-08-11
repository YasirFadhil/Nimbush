import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:/services" as Services

PanelWindow {
    id: powerOsd
    anchors { bottom: true }
    margins { bottom: 80 }
    implicitWidth: 120
    implicitHeight: 120
    color: "transparent"
    exclusiveZone: 0
    visible: false
    WlrLayershell.namespace: "quickshell:hud"

    property bool charging: false
    property real percentage: 0
    property string icon: ""

    readonly property string statusText: charging ? "Charging" : "On battery"

    Timer { id: hideTimer; interval: 2500; onTriggered: powerOsd.visible = false }

    function show(isCharging, pct) {
        charging = isCharging
        percentage = pct
        icon = Services.Icons.powerIconSimple(isCharging, pct)
        visible = true
        hideTimer.restart()
    }

    Connections {
        target: Services.Power
        function onChargingStateChanged(charging, percentage) {
            powerOsd.show(charging, percentage)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "#1e1e1e"

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10

            Text {
                text: powerOsd.icon
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 36
                color: "#cdd6f4"
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: powerOsd.statusText
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 13
                font.bold: true
                color: "#cdd6f4"
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}

