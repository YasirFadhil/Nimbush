import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
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
    WlrLayershell.namespace: "quickshell:hud"

    property real value: 0
    property string icon: ""
    // Guard: suppress signals that fire during quickshell init/reload
    property bool osdReady: false
    Timer {
        id: osdInitTimer
        interval: 400
        running: true
        repeat: false
        onTriggered: osd.osdReady = true
    }

    Timer { id: hideTimer; interval: 1500; onTriggered: osd.visible = false }

    function show(v, ic) {
        if (!osd.osdReady) return
        value = v; icon = ic; visible = true; hideTimer.restart()
    }

    Connections {
      target: Services.Audio
      function onVolumeChanged() {
        if (!osd.osdReady) return
        osd.show(Services.Audio.volume, Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws))
        Services.SoundFeedback.playVolumeChange()
      }
      function onMutedChanged() {
        if (!osd.osdReady) return
        osd.show(Services.Audio.volume, Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws))
        Services.SoundFeedback.playVolumeChange()
      }
    }
    
    Connections {
      target: Services.Brightness
      function onPercentChanged() {
        osd.show(Services.Brightness.percent, Services.Icons.brightnessIcon(Services.Brightness.percent))
        // No sound feedback for brightness — only volume, notifications, USB, and charge/discharge
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
            Item {
                id: osdIconBox
                property string icon: osd.icon
                property string oldIcon: ""
                implicitWidth: mainOsdText.implicitWidth
                implicitHeight: mainOsdText.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                onIconChanged: {
                    if (icon !== mainOsdText.text) {
                        oldIcon = mainOsdText.text
                        oldOsdText.opacity = 1.0
                        mainOsdText.text = icon
                        mainOsdText.opacity = 0.0
                        osdCrossFade.restart()
                    }
                }

                Component.onCompleted: mainOsdText.text = icon

                Text {
                    id: oldOsdText
                    anchors.centerIn: parent
                    text: osdIconBox.oldIcon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize7xl
                    color: Services.Theme.textPrimary
                    opacity: 0.0
                    visible: opacity > 0
                }

                Text {
                    id: mainOsdText
                    anchors.centerIn: parent
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSize7xl
                    color: Services.Theme.textPrimary
                    opacity: 1.0
                }

                ParallelAnimation {
                    id: osdCrossFade
                    NumberAnimation { target: oldOsdText; property: "opacity"; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: mainOsdText; property: "opacity"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                }
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
