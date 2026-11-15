import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Item {
    id: root
    implicitWidth: 16
    implicitHeight: 16
    Layout.alignment: Qt.AlignVCenter

    // Interactive spring scale on press & hover
    scale: ccMouse.pressed ? 0.88 : (ccMouse.containsMouse ? 1.12 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    // Rotating morph container
    Item {
        id: rotateWrapper
        anchors.centerIn: parent
        width: 16
        height: 16
        rotation: Services.OverlayManager.controlCenterVisible ? 180 : 0
        Behavior on rotation {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.3
            }
        }

        // State A: Sliders Icon (Morphs out)
        Text {
            anchors.centerIn: parent
            text: Services.Icons.controlcenter
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            font.weight: Font.Bold
            color: (ccMouse.containsMouse || Services.OverlayManager.controlCenterVisible) ? Services.Theme.accent : Services.Theme.textPrimary
            opacity: Services.OverlayManager.controlCenterVisible ? 0.0 : 1.0
            scale: Services.OverlayManager.controlCenterVisible ? 0.4 : 1.0
            rotation: Services.OverlayManager.controlCenterVisible ? -90 : 0

            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        // State B: Close Icon (Morphs in)
        Text {
            anchors.centerIn: parent
            text: Services.Icons.close
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 10
            font.weight: Font.Bold
            color: (ccMouse.containsMouse || Services.OverlayManager.controlCenterVisible) ? Services.Theme.accent : Services.Theme.textPrimary
            opacity: Services.OverlayManager.controlCenterVisible ? 1.0 : 0.0
            scale: Services.OverlayManager.controlCenterVisible ? 1.0 : 0.4
            rotation: Services.OverlayManager.controlCenterVisible ? 0 : 90

            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        id: ccMouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.OverlayManager.controlCenterVisible
            if (newState) Services.OverlayManager.closeAllExcept("controlCenter")
            Services.OverlayManager.controlCenterVisible = newState
        }
    }
}
