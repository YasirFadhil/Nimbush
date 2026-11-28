import QtQuick
import QtQuick.Layouts
import "../../services" as Services

// Vertical pill slider: fill rises from the bottom, icon sits inside.
Rectangle {
    id: vs
    property string icon: ""
    property real value: 0
    property bool isMuted: false
    signal moved(real newValue)
    signal iconClicked()

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: Services.Theme.radiusMd
    color: Qt.alpha(Services.Theme.textPrimary, (vsMouse.containsMouse || iconArea.containsMouse) ? 0.12 : 0.08)
    clip: true
    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.max(0, Math.min(1, vs.value)) * parent.height
        radius: vs.radius
        color: vs.isMuted
            ? Services.Theme.textDisabled
            : (vsMouse.pressed ? Services.Theme.accent : (vsMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.06) : Services.Theme.accent))
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 80 } }
    }

    Text {
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: vs.isMuted ? "Mute" : (Math.round(vs.value * 100) + "%")
        font.pixelSize: 10
        font.bold: true
        color: vs.value > 0.86 && !vs.isMuted ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
    }

    Item {
        id: iconContainer
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: 34
        z: 2

        Text {
            anchors.centerIn: parent
            text: vs.icon
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 15
            color: (vs.value > 0.12 && !vs.isMuted) ? Services.Theme.bgOnAccent : Services.Theme.textPrimary
        }

        MouseArea {
            id: iconArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: vs.iconClicked()
        }
    }

    MouseArea {
        id: vsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                vs.iconClicked()
            } else {
                vs.moved(Math.max(0, Math.min(1, 1 - mouse.y / height)))
            }
        }
        onPositionChanged: (mouse) => {
            if (pressed && (mouse.buttons & Qt.LeftButton)) {
                vs.moved(Math.max(0, Math.min(1, 1 - mouse.y / height)))
            }
        }
        onWheel: (wheel) => {
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
            vs.moved(Math.max(0, Math.min(1, vs.value + step)))
        }
    }
}
