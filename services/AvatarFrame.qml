import QtQuick
import QtQuick.Effects

// AvatarFrame – Reusable smooth avatar component.
// Uses Canvas for the BORDER (perfectly smooth anti-aliased ring)
// and Rectangle mask for the IMAGE (sharp, no blur).
//
// Usage:
//   AvatarFrame {
//       width: 64; height: 64
//       source: "file:///path/to/photo.jpg"
//       shapeRadius: 32
//       borderColor: Theme.accent
//       borderWidth: 2
//   }

Item {
    id: root

    property string source: ""
    property real shapeRadius: width / 2
    property color borderColor: "transparent"
    property real borderWidth: 0
    property color backgroundColor: "transparent"

    property string fallbackText: ""
    property color fallbackColor: "white"
    property real fallbackFontSize: 14
    property string fallbackFontFamily: ""
    property bool fallbackBold: true

    readonly property int imageStatus: _img.status
    readonly property real _innerRadius: Math.max(0, shapeRadius - borderWidth)

    // ── Background fill (visible when image not loaded) ──
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.borderWidth
        radius: root._innerRadius
        color: root.backgroundColor
        antialiasing: true
        visible: _img.status !== Image.Ready
    }

    // ── Hidden image source ──
    Image {
        id: _img
        anchors.fill: parent
        anchors.margins: root.borderWidth
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: false
    }

    // ── Mask shape (Rectangle — keeps image sharp, no layer resampling) ──
    Item {
        id: _maskItem
        anchors.fill: _img
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: root._innerRadius
            color: "black"
            antialiasing: true
        }
    }

    // ── Masked image output ──
    MultiEffect {
        anchors.fill: _img
        source: _img
        maskEnabled: true
        maskSource: _maskItem
        visible: _img.status === Image.Ready
    }

    // ── Border ring (Canvas-drawn for perfectly smooth edges) ──
    Canvas {
        id: _borderCanvas
        anchors.fill: parent
        visible: root.borderWidth > 0

        property real r: root.shapeRadius
        property real bw: root.borderWidth
        property color bc: root.borderColor
        onRChanged: requestPaint()
        onBwChanged: requestPaint()
        onBcChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0 || bw <= 0) return
            ctx.strokeStyle = bc
            ctx.lineWidth = bw
            var half = bw / 2
            root._roundedPath(ctx, half, half, width - bw, height - bw, Math.max(0, r - half))
            ctx.stroke()
        }
    }

    // ── Fallback monogram ──
    Text {
        anchors.centerIn: parent
        visible: _img.status !== Image.Ready && root.fallbackText.length > 0
        text: root.fallbackText
        font.family: root.fallbackFontFamily
        font.pixelSize: root.fallbackFontSize
        font.bold: root.fallbackBold
        color: root.fallbackColor
        z: 1
    }

    // ── Helper: draw a rounded rectangle path ──
    function _roundedPath(ctx, x, y, w, h, r) {
        r = Math.max(0, Math.min(r, w / 2, h / 2))
        if (r <= 0) {
            ctx.beginPath()
            ctx.rect(x, y, w, h)
            return
        }
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.arcTo(x + w, y, x + w, y + r, r)
        ctx.lineTo(x + w, y + h - r)
        ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
        ctx.lineTo(x + r, y + h)
        ctx.arcTo(x, y + h, x, y + h - r, r)
        ctx.lineTo(x, y + r)
        ctx.arcTo(x, y, x + r, y, r)
        ctx.closePath()
    }
}
