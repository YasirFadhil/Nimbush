import QtQuick

// Soft text-edge fade as an alpha MASK (not a coloured gradient). A coloured gradient only
// works on an opaque island; on glass it would paint a darker smudge over the blur.
// Use as maskSource of a MultiEffect on the text container.
Item {
    id: efm
    property real leftAmt: 0.0     // 0..1 how much the left edge is faded out
    property real rightAmt: 0.0    // 0..1 how much the right edge is faded out
    property real edge: 22
    visible: false
    layer.enabled: true
    layer.smooth: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 1.0 - efm.leftAmt) }
            GradientStop { position: Math.min(0.49, efm.edge / Math.max(1, efm.width)); color: "#000000" }
            GradientStop { position: Math.max(0.51, 1.0 - efm.edge / Math.max(1, efm.width)); color: "#000000" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 1.0 - efm.rightAmt) }
        }
    }
}
