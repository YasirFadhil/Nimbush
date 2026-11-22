// LiquidSplitBridge.qml
// Organic fluid meniscus / liquid neck connecting Dynamic Island and satellite droplets
import QtQuick
import "../../../services" as Services

Item {
    id: bridgeRoot

    property real gap: 0.0          // Distance between parent capsule edge and child circle apex (0 to ~8)
    property bool isRight: true     // true = bridge to the right of island, false = bridge to the left
    property bool snapped: true     // true = bridge broken/inactive, false = bridge actively rendering
    property real maxGap: 8.0

    implicitHeight: 32
    visible: !snapped && gap >= -8.0 && gap <= maxGap && width > 0

    onGapChanged: bridgeCanvas.requestPaint()
    onSnappedChanged: bridgeCanvas.requestPaint()
    onWidthChanged: bridgeCanvas.requestPaint()

    Canvas {
        id: bridgeCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            if (bridgeRoot.snapped || bridgeRoot.gap > bridgeRoot.maxGap || width <= 0) return

            const w = width
            const h = height
            const cy = h / 2

            // Normal gap progress: 0.0 at gap=0, 1.0 at gap=maxGap
            const clampedGap = Math.max(0.0, Math.min(bridgeRoot.maxGap, bridgeRoot.gap))
            const t = clampedGap / bridgeRoot.maxGap // 0.0 -> 1.0

            // Base attachment heights at the two ends (capsule and satellite circle)
            const edgeHalfH = Math.max(8.0, 15.0 - (t * 2.5)) // 15px down to 12.5px

            // Waist thickness in the middle: pinches from ~13.5px down to ~1.5px
            const waistHalfH = Math.max(1.0, (13.5 * Math.pow(1.0 - t, 1.35)))

            const midX = w / 2

            // Fill fluid body with solid background (merges capsule and droplet into one fluid body)
            ctx.fillStyle = Services.Theme.bgPure
            ctx.beginPath()
            // Top concave arc
            ctx.moveTo(0, cy - edgeHalfH)
            ctx.quadraticCurveTo(midX, cy - waistHalfH, w, cy - edgeHalfH)
            // End edge
            ctx.lineTo(w, cy + edgeHalfH)
            // Bottom concave arc
            ctx.quadraticCurveTo(midX, cy + waistHalfH, 0, cy + edgeHalfH)
            ctx.closePath()
            ctx.fill()

            // Subtle meniscus stroke on top and bottom edges
            ctx.strokeStyle = Services.Theme.borderSubtle
            ctx.lineWidth = 1.0
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            ctx.beginPath()
            ctx.moveTo(0, cy - edgeHalfH)
            ctx.quadraticCurveTo(midX, cy - waistHalfH, w, cy - edgeHalfH)
            ctx.stroke()

            ctx.beginPath()
            ctx.moveTo(w, cy + edgeHalfH)
            ctx.quadraticCurveTo(midX, cy + waistHalfH, 0, cy + edgeHalfH)
            ctx.stroke()
        }
    }
}
