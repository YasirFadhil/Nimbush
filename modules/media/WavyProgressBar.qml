import QtQuick
import "../../services" as Services

// Capsule seek bar: chunky gradient pill, hover-preview ghost fill, slim handle on interaction.
// (Filename kept as WavyProgressBar so existing imports/ids keep working.)
Item {
    id: root

    property real position: 0.0 // in seconds
    property real duration: 0.0 // in seconds
    property real livePosition: position
    property real value: duration > 0 ? Math.max(0, Math.min(1, livePosition / duration)) : 0.0
    property bool isPlaying: false

    property color waveColor: Services.Theme ? Services.Theme.accent : "#4f46e5"
    property color trackColor: Services.Theme ? Services.Theme.surfaceVariant : Qt.rgba(1, 1, 1, 0.2)
    property real lineWidth: 3.0 // kept for compatibility with existing callers (unused)

    property real barHeight: 8 // thickness at rest

    signal seekRequested(real ratio)

    // 0..1 animated: drives thickness, ghost preview and handle
    property real hoverAmt: (seekMouse.containsMouse || seekMouse.pressed) ? 1.0 : 0.0
    Behavior on hoverAmt {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    readonly property real thickness: barHeight + hoverAmt * 4 // 8 → 12
    property real hoverX: 0

    implicitHeight: 22
    implicitWidth: 200

    onPositionChanged: {
        if (!seekMouse.pressed)
            livePosition = position
    }

    Timer {
        id: liveProgressTimer
        interval: 100
        running: root.isPlaying && root.duration > 0 && root.visible
        repeat: true
        onTriggered: {
            if (!seekMouse.pressed && root.duration > 0 && root.livePosition < root.duration)
                root.livePosition = Math.min(root.duration, root.livePosition + 0.1)
        }
    }

    // ── Track ──
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.thickness
        radius: height / 2
        color: root.trackColor
    }

    // ── Hover preview (ghost fill up to the cursor) ──
    Rectangle {
        id: ghost
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(root.width, root.hoverX))
        height: root.thickness
        radius: height / 2
        color: root.waveColor
        opacity: root.hoverAmt * 0.28
        visible: opacity > 0.01 && root.duration > 0
    }

    // ── Played fill (gradient capsule) ──
    Rectangle {
        id: fill
        anchors.verticalCenter: parent.verticalCenter
        visible: root.value > 0
        width: Math.max(root.thickness, root.value * root.width)
        height: root.thickness
        radius: height / 2

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.darker(root.waveColor, 1.55) }
            GradientStop { position: 1.0; color: root.waveColor }
        }

        // Matches the 100ms timer tick so progress glides; disabled while dragging so it follows the pointer 1:1
        Behavior on width {
            enabled: !seekMouse.pressed
            NumberAnimation { duration: 100; easing.type: Easing.Linear }
        }
    }

    // ── Slim vertical handle (appears on hover/drag) ──
    Rectangle {
        id: handle
        visible: root.duration > 0 && opacity > 0.01
        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: root.thickness + 4
        radius: 2
        color: "#ffffff"
        opacity: root.hoverAmt
        scale: seekMouse.pressed ? 1.15 : 1.0
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

        x: Math.max(0, Math.min(root.width - width, fill.width - width / 2))
    }

    MouseArea {
        id: seekMouse
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function seekTo(mx) {
            const ratio = Math.max(0, Math.min(1, mx / width))
            if (root.duration > 0) root.livePosition = ratio * root.duration
            root.seekRequested(ratio)
        }

        onClicked: mouse => seekTo(mouse.x)
        onPositionChanged: mouse => {
            root.hoverX = mouse.x
            if (pressed) seekTo(mouse.x)
        }
    }
}
