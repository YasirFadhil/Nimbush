import QtQuick
import QtQuick.Layouts
import "../../services" as Services

// Vertical pill slider: fill rises from the bottom, icon sits inside.
Rectangle {
    id: vs
    property string icon: ""
    property real value: 0
    signal moved(real newValue)

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: Services.Theme.radiusMd
    color: Qt.alpha(Services.Theme.textPrimary, vsMouse.containsMouse ? 0.12 : 0.08)
    clip: true
    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.max(0, Math.min(1, vs.value)) * parent.height
        radius: vs.radius
        color: vsMouse.pressed ? Services.Theme.accent : (vsMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.06) : Services.Theme.accent)
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 80 } }
    }

    Text {
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: Math.round(vs.value * 100) + "%"
        font.pixelSize: 10
        font.bold: true
        color: vs.value > 0.86 ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        text: vs.icon
        font.family: Services.Theme.fontSymbols
        font.pixelSize: 15
        color: vs.value > 0.12 ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
    }

    MouseArea {
        id: vsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => vs.moved(Math.max(0, Math.min(1, 1 - mouse.y / height)))
        onPositionChanged: (mouse) => {
            if (pressed) vs.moved(Math.max(0, Math.min(1, 1 - mouse.y / height)))
        }
    }
    
}
