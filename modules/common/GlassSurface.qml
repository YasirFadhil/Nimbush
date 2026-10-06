import QtQuick
import "../../services" as Services

// Primitive tunggal untuk semua permukaan kaca.
// Taruh di folder yang sama dengan Dock.qml (sementara), pindahkan nanti
// ke folder common dan sesuaikan path import.
Item {
    id: root

    property int level: 1          // 0 / 1 / 2, lihat Glass.qml
    property real radius: Services.Glass.radiusMd
    property bool hovered: false   // mempertegas border

    // Fill + border
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Services.Glass.fill(root.level)
        border.width: Services.Glass.borderWidth
        border.color: Services.Glass.border(root.level, root.hovered)
        Behavior on border.color { ColorAnimation { duration: Services.Glass.durNormal } }
    }

    // Rim dalam (tepi kaca)
    Rectangle {
        visible: root.level > 0
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Services.Glass.rim(root.level)
    }

    // Kilau spekular di tepi atas, memudar ke kedua sisi
    Rectangle {
        visible: root.level > 0
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.radius * 0.7
        anchors.rightMargin: root.radius * 0.7
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Services.Glass.specularEdge }
            GradientStop { position: 0.5; color: Services.Glass.specular }
            GradientStop { position: 1.0; color: Services.Glass.specularEdge }
        }
    }
}
