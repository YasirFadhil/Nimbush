import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:/services" as Services

PanelWindow {
    id: osd
    anchors { bottom: true }
    margins {
        bottom: (Services.Config && Services.Config.barPosition === "bottom") ? 84 : 56
    }
    implicitWidth: 280
    implicitHeight: 44
    color: "transparent"
    exclusiveZone: 0
    visible: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:hud"

    property real value: 0
    property string icon: ""
    property string osdType: "volume" // "volume" | "brightness"
    property bool active: false

    // Guard: suppress signals that fire during quickshell init/reload
    property bool osdReady: false
    Timer {
        id: osdInitTimer
        interval: 400
        running: true
        repeat: false
        onTriggered: osd.osdReady = true
    }

    Timer {
        id: hideTimer
        interval: 1500
        repeat: false
        onTriggered: osd.active = false
    }

    Timer {
        id: unmapTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (!osd.active) {
                osd.visible = false
            }
        }
    }

    onActiveChanged: {
        if (active) {
            unmapTimer.stop()
            osd.visible = true
        } else {
            unmapTimer.restart()
        }
    }

    function show(v, ic, type) {
        if (!osd.osdReady) return
        value = v
        icon = ic
        if (type) osdType = type
        active = true
        hideTimer.restart()
    }

    readonly property bool isVolume: osdType === "volume"
    readonly property bool isMuted: isVolume && Services.Audio.muted
    readonly property bool isOverAmp: isVolume && value > 1.0
    readonly property real clampedValue: isMuted ? 0 : Math.max(0, Math.min(1.0, value))

    Connections {
        target: Services.Audio
        function onVolumeChanged() {
            if (!osd.osdReady) return
            osd.show(
                Services.Audio.volume,
                Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws),
                "volume"
            )
            Services.SoundFeedback.playVolumeChange()
        }
        function onMutedChanged() {
            if (!osd.osdReady) return
            osd.show(
                Services.Audio.volume,
                Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws),
                "volume"
            )
            Services.SoundFeedback.playVolumeChange()
        }
    }

    Connections {
        target: Services.Brightness
        function onPercentChanged() {
            if (!osd.osdReady) return
            osd.show(
                Services.Brightness.percent,
                Services.Icons.brightnessIcon(Services.Brightness.percent),
                "brightness"
            )
        }
    }

    // ── Floating Island Capsule (Harmonized with Quickshell Islands Theme) ──
    Rectangle {
        id: card
        anchors.fill: parent
        radius: height / 2
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: osd.active ? 1.0 : 0.0
        scale: osd.active ? 1.0 : 0.94
        transform: Translate {
            y: osd.active ? 0 : 10
            Behavior on y {
                NumberAnimation {
                    duration: osd.active ? 300 : 180
                    easing.type: osd.active ? Easing.OutExpo : Easing.InCubic
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: osd.active ? 200 : 160
                easing.type: osd.active ? Easing.OutCubic : Easing.InCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: osd.active ? 300 : 180
                easing.type: osd.active ? Easing.OutExpo : Easing.InCubic
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

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            // ── Left: Crossfading Icon ──
            Item {
                id: osdIconBox
                property string icon: osd.icon
                property string oldIcon: ""
                implicitWidth: 22
                implicitHeight: 22
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
                    font.pixelSize: 19
                    color: osd.isMuted ? Services.Theme.danger : (osd.isOverAmp ? Services.Theme.warning : Services.Theme.textPrimary)
                    opacity: 0.0
                    visible: opacity > 0
                }

                Text {
                    id: mainOsdText
                    anchors.centerIn: parent
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 19
                    color: osd.isMuted ? Services.Theme.danger : (osd.isOverAmp ? Services.Theme.warning : Services.Theme.textPrimary)
                    opacity: 1.0
                }

                ParallelAnimation {
                    id: osdCrossFade
                    NumberAnimation { target: oldOsdText; property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.OutCubic }
                    NumberAnimation { target: mainOsdText; property: "opacity"; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                }
            }

            // ── Center: Smooth Slider Track ──
            Rectangle {
                id: track
                Layout.fillWidth: true
                height: 7
                radius: 3.5
                color: Services.Theme.surfaceVariant
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: fillBar
                    width: Math.max(0, Math.min(track.width, track.width * osd.clampedValue))
                    height: parent.height
                    radius: 3.5
                    color: osd.isMuted ? Services.Theme.textDisabled : (osd.isOverAmp ? Services.Theme.warning : Services.Theme.accent)

                    Behavior on width {
                        NumberAnimation {
                            duration: 110
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            // ── Right: Clean Monospace Percentage ──
            Text {
                text: osd.isMuted ? "MUTED" : (Math.round(osd.value * 100) + "%")
                font.family: Services.Theme.fontMono
                font.pixelSize: osd.isMuted ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
                font.weight: Font.SemiBold
                color: osd.isMuted ? Services.Theme.danger : (osd.isOverAmp ? Services.Theme.warning : Services.Theme.textSecondary)
                horizontalAlignment: Text.AlignRight
                Layout.minimumWidth: 40
                Layout.alignment: Qt.AlignVCenter

                Behavior on color {
                    ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
