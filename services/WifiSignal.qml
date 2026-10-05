import QtQuick

Item {
    id: root

    property int signalStrength: 0
    property bool connected: false
    property bool wifiEnabled: true
    property bool showDisabledStatus: false
    property color activeColor: "#ffffff"
    property color inactiveColor: Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.22)

    implicitWidth: 22
    implicitHeight: 22

    Canvas {
        id: canvas
        anchors.fill: parent

        function level() {
            if (!root.wifiEnabled && root.showDisabledStatus) return 3
            if (!root.connected) return 0
            if (root.signalStrength >= 75) return 3
            if (root.signalStrength >= 40) return 2
            if (root.signalStrength > 0) return 1
            return 0
        }

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            var cx = w / 2
            var cy = h * 0.74
            var scale = Math.min(w, h)
            var currentLevel = level()

            ctx.clearRect(0, 0, w, h)
            ctx.lineCap = "round"
            ctx.lineWidth = Math.max(1.6, scale * 0.11)

            var radii = [scale * 0.19, scale * 0.34, scale * 0.49]
            for (var i = 0; i < radii.length; i++) {
                ctx.beginPath()
                ctx.strokeStyle = i < currentLevel ? root.activeColor : root.inactiveColor
                ctx.arc(cx, cy, radii[i], Math.PI * 1.25, Math.PI * 1.75, false)
                ctx.stroke()
            }

            ctx.beginPath()
            ctx.fillStyle = root.wifiEnabled && currentLevel > 0 ? root.activeColor : root.inactiveColor
            ctx.arc(cx, cy, Math.max(1.5, scale * 0.075), 0, Math.PI * 2, false)
            ctx.fill()

            if (!root.wifiEnabled && root.showDisabledStatus) {
                ctx.beginPath()
                ctx.strokeStyle = root.inactiveColor
                ctx.lineWidth = Math.max(1.8, scale * 0.13)
                ctx.moveTo(scale * 0.18, scale * 0.18)
                ctx.lineTo(scale * 0.82, scale * 0.82)
                ctx.stroke()
            }
        }
    }

    onSignalStrengthChanged: canvas.requestPaint()
    onConnectedChanged: canvas.requestPaint()
    onWifiEnabledChanged: canvas.requestPaint()
    onShowDisabledStatusChanged: canvas.requestPaint()
    onActiveColorChanged: canvas.requestPaint()
    onInactiveColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
