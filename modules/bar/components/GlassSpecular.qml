import QtQuick
import "../../../services" as Services

// One faint specular hairline along the top edge: the only highlight the Dock has,
// reused on every pill / popup so the bar shares the Dock's glass material.
// Drop it inside any Rectangle:  GlassSpecular {}
Rectangle {
    readonly property bool dark: Services.Theme.isDark
    anchors.top: parent.top
    anchors.topMargin: 1
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.max(0, parent.width - (parent.radius || 0) * 1.4)
    height: 1
    z: 0
    visible: parent.border.color.a > 0.01
    color: dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.65)
}
