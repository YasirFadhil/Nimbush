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

    implicitHeight: 22
    implicitWidth: 200

    onPositionChanged: {
        if (!seekMouse.pressed) {
            livePosition = position
            canvas.requestPaint()
        }
    }

    Timer {
        id: liveProgressTimer
        interval: 100
        running: root.isPlaying && root.duration > 0 && root.visible
        repeat: true
        onTriggered: {
            if (!seekMouse.pressed && root.duration > 0 && root.livePosition < root.duration) {
                root.livePosition = Math.min(root.duration, root.livePosition + 0.1)
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
            }
        }
    }

    // ── Liquid Glass Scrubber Knob (True Settings Liquid Glass Architecture) ──
    Rectangle {
        id: knob
        visible: root.duration > 0
        anchors.verticalCenter: parent.verticalCenter

        property real expansion: (seekMouse.containsMouse || seekMouse.pressed) ? 1.0 : 0.0
        Behavior on expansion {
            NumberAnimation {
                duration: 170
                easing.type: Easing.OutBack
                easing.overshoot: 1.25
            }
        }

        // Horizontal pill at rest (matching Settings screenshot), blooms naturally on interaction
        width: 18 + expansion * 12
        height: 12 + expansion * 4
        radius: height / 2

        x: Math.max(0, Math.min(parent.width - width, (root.value * parent.width) - (width / 2)))

        // Viscous Elastic Squish
        property real targetSquashX: seekMouse.pressed ? 1.12 : 1.0
        property real targetSquashY: seekMouse.pressed ? 0.90 : 1.0
        property real squashX: targetSquashX
        property real squashY: targetSquashY

        Behavior on squashX {
            enabled: !releaseJiggleAnim.running
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }
        Behavior on squashY {
            enabled: !releaseJiggleAnim.running
            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
        }

        SequentialAnimation {
            id: releaseJiggleAnim
            ParallelAnimation {
                NumberAnimation { target: knob; property: "squashX"; to: 0.92; duration: 75; easing.type: Easing.OutQuad }
                NumberAnimation { target: knob; property: "squashY"; to: 1.08; duration: 75; easing.type: Easing.OutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: knob; property: "squashX"; to: 1.02; duration: 65; easing.type: Easing.InOutQuad }
                NumberAnimation { target: knob; property: "squashY"; to: 0.98; duration: 65; easing.type: Easing.InOutQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: knob; property: "squashX"; to: 1.0; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: knob; property: "squashY"; to: 1.0; duration: 110; easing.type: Easing.OutQuad }
            }
        }

        transform: Scale {
            origin.x: knob.width / 2
            origin.y: knob.height / 2
            xScale: knob.squashX
            yScale: knob.squashY
        }

        // Fluid Cross-Fade from Solid Porcelain (#ffffff) to Translucent Frosted Glass
        color: (Services.Theme && Services.Theme.isDark)
            ? Qt.rgba(1.0, 1.0, 1.0, 1.0 - expansion * 0.72)
            : Qt.rgba(1.0, 1.0, 1.0, 1.0 - expansion * 0.35)
        border.color: expansion > 0.01
            ? ((Services.Theme && Services.Theme.isDark) ? Qt.rgba(1.0, 1.0, 1.0, 0.55) : Qt.rgba(1.0, 1.0, 1.0, 0.85))
            : Qt.rgba(0, 0, 0, 0.08)
        border.width: expansion > 0.01 ? 1.2 : 1.0

        // ── Optical Refraction Chamber (Pembiasan & Pembengkokan Pensil Dalam Air) ──
        Item {
            anchors.fill: parent
            anchors.margins: 1.5
            clip: true
            opacity: knob.expansion

            // Refracted Track Core (Bent upwards with convex lens curvature & optical shift, exactly like SettingsSlider)
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2.0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: -1
                height: parent.height * 0.75
                radius: height / 2
                color: root.waveColor
                opacity: 0.85
            }
        }

        // Soft Inner Glass Refraction Bevel
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.color: (Services.Theme && Services.Theme.isDark) ? Qt.rgba(1.0, 1.0, 1.0, 0.22) : Qt.rgba(1.0, 1.0, 1.0, 0.45)
            border.width: 1
            opacity: knob.expansion
        }

        // Top Specular Glass Crescent Flare
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1.5
            height: Math.max(2, parent.height * 0.45)
            radius: height / 2
            opacity: knob.expansion
            gradient: Gradient {
                GradientStop { 
                    position: 0.0
                    color: (Services.Theme && Services.Theme.isDark) ? Qt.rgba(1.0, 1.0, 1.0, 0.55) : Qt.rgba(1.0, 1.0, 1.0, 0.80)
                }
                GradientStop { 
                    position: 1.0
                    color: "transparent"
                }
            }
        }

        // Bottom Internal Caustic Flare (Subtle Meniscus Light Catch)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 1.5
            height: Math.max(2, parent.height * 0.30)
            radius: height / 2
            opacity: knob.expansion * 0.60
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(1.0, 1.0, 1.0, 0.25) }
            }
        }

        // ── Background Optical Refraction Distortion Halo (Distorsi Latar Belakang) ──
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 4
            radius: height / 2
            color: root.waveColor
            opacity: knob.expansion * 0.40
            z: -1
        }

        // Natural Soft Drop Shadow
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1.5
            width: parent.width
            height: parent.height
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.20)
            opacity: 1.0 - knob.expansion * 0.45
            z: -2
        }
    }

    MouseArea {
        id: seekMouse
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
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
        onReleased: {
            releaseJiggleAnim.restart()
        }
    }
}
