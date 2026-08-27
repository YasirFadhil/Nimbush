import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Item {
    implicitWidth: ccIcon.implicitWidth
    implicitHeight: ccIcon.implicitHeight

    Text {
        id: ccIcon
        anchors.fill: parent
        text: Services.Icons.controlcenter
        font.family: Services.Theme.fontSymbols
        font.pixelSize: Services.Theme.fontSize4xl
        font.weight: Font.Bold
        color: (ccMouse.containsMouse || Services.OverlayManager.controlCenterVisible) ? Services.Theme.accent : Services.Theme.textPrimary
        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: ccMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.OverlayManager.controlCenterVisible
            if (newState) Services.OverlayManager.closeAllExcept("controlCenter")
            Services.OverlayManager.controlCenterVisible = newState
        }
    }
}
