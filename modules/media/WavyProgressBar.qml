import QtQuick
import "../../services" as Services

Item {
    id: root

    property real position: 0.0 // in seconds
    property real duration: 0.0 // in seconds
    property real livePosition: position
    property real value: duration > 0 ? Math.max(0, Math.min(1, livePosition / duration)) : 0.0
    property bool isPlaying: false

    property color waveColor: Services.Theme ? Services.Theme.accent : "#4f46e5"
    property color trackColor: Services.Theme ? Services.Theme.surfaceVariant : Qt.rgba(1, 1, 1, 0.2)
    property real lineWidth: 3.0
    property real maxAmplitude: 2.8
    property real waveFrequency: 0.16 // Wave frequency / density

    signal seekRequested(real ratio)

    implicitHeight: 18
    implicitWidth: 200

    onPositionChanged: {
        livePosition = position
        canvas.requestPaint()
    }

    Timer {
        id: liveProgressTimer
        interval: 200
        running: root.isPlaying && root.duration > 0 && root.visible
        repeat: true
        onTriggered: {
            if (root.duration > 0 && root.livePosition < root.duration) {
                root.livePosition = Math.min(root.duration, root.livePosition + 0.2)
                canvas.requestPaint()
            }
        }
    }

    property real currentAmplitude: isPlaying ? maxAmplitude : 0.0
    Behavior on currentAmplitude {
        NumberAnimation { duration: 350; easing.type: Easing.InOutQuad }
    }

    property real phase: 0.0
    NumberAnimation on phase {
        running: root.isPlaying && root.visible
        loops: Animation.Infinite
        from: 0.0
        to: Math.PI * 2
        duration: 1200
    }

    onValueChanged: canvas.requestPaint()
    onPhaseChanged: canvas.requestPaint()
    onCurrentAmplitudeChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onWaveColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const cy = height / 2
            const progress = Math.max(0, Math.min(1, root.value))
            const progressX = progress * width
            const amp = root.currentAmplitude

            // 1. Draw Unplayed Track (Straight Line)
            if (progressX < width) {
                ctx.beginPath()
                ctx.strokeStyle = root.trackColor
                ctx.lineWidth = root.lineWidth
                ctx.lineCap = "round"
                ctx.moveTo(Math.max(progressX, root.lineWidth / 2), cy)
                ctx.lineTo(width - (root.lineWidth / 2), cy)
                ctx.stroke()
            }

            // 2. Draw Played Track (Wavy Sine Wave Line)
            if (progressX > 0) {
                ctx.beginPath()
                ctx.strokeStyle = root.waveColor
                ctx.lineWidth = root.lineWidth
                ctx.lineCap = "round"

                const step = 2 // Smooth pixel resolution
                const startX = root.lineWidth / 2
                ctx.moveTo(startX, cy)

                for (let x = startX; x <= progressX; x += step) {
                    // Smooth envelope so the wave gently rises from 0 and gently returns to center at the thumb
                    const distFromEnd = Math.min(x - startX, progressX - x)
                    const envelope = Math.min(1.0, Math.max(0.0, distFromEnd / 10.0))
                    
                    const y = cy + Math.sin(x * root.waveFrequency - root.phase) * amp * envelope
                    ctx.lineTo(x, y)
                }

                ctx.lineTo(progressX, cy)
                ctx.stroke()

                // 3. Thumb / Scrubber Head
                ctx.beginPath()
                ctx.fillStyle = root.waveColor
                const isHovered = seekMouse.containsMouse || seekMouse.pressed
                const thumbRadius = isHovered ? 5.5 : 4.0
                ctx.arc(progressX, cy, thumbRadius, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    MouseArea {
        id: seekMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            const ratio = Math.max(0, Math.min(1, mouse.x / width))
            if (root.duration > 0) root.livePosition = ratio * root.duration
            root.seekRequested(ratio)
            canvas.requestPaint()
        }
        onPositionChanged: mouse => {
            if (pressed) {
                const ratio = Math.max(0, Math.min(1, mouse.x / width))
                if (root.duration > 0) root.livePosition = ratio * root.duration
                root.seekRequested(ratio)
                canvas.requestPaint()
            }
        }
    }
}
