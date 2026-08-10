import QtQuick
import QtQuick.Layouts
import Quickshell
import "root:/services" as Services

PanelWindow {
    id: osd
    anchors { bottom: true }
    margins { bottom: 80 }
    implicitWidth: 280
    implicitHeight: 64
    color: "transparent"
    exclusiveZone: 0
    visible: false

    property real value: 0
    property string icon: ""

    Timer { id: hideTimer; interval: 1500; onTriggered: osd.visible = false }

    function show(v, ic) { value = v; icon = ic; visible = true; hideTimer.restart() }

    Connections {
      target: Services.Audio
      function onVolumeChanged() {
        osd.show(Services.Audio.volume, Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted))
      }
      function onMutedChanged() {
        osd.show(Services.Audio.volume, Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted))
      }
    }
    
    Connections {
      target: Services.Brightness
      function onPercentChanged() {
        osd.show(Services.Brightness.percent, Services.Icons.brightnessIcon(Services.Brightness.percent))
      }
    }

    Rectangle {
        anchors.fill: parent
        radius: Services.Theme.radiusLg
        color: Services.Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Text {
              text: osd.icon
              font.family: "Symbols Nerd Font Mono"   // ganti sesuai output fc-list tadi
              font.pixelSize: 22
              color: Services.Theme.textPrimary
            }
            Rectangle {
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: Services.Theme.surfaceVariant
                Rectangle { width: parent.width * osd.value; height: parent.height; radius: 4; color: Services.Theme.accent }
            }
        }
    }
}
