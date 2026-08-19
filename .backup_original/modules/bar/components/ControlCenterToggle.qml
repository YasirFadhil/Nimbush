import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Item {
    Layout.preferredWidth: ccIcon.implicitWidth
    Layout.preferredHeight: ccIcon.implicitHeight

    Text {
        id: ccIcon
        anchors.fill: parent
        text: Services.Icons.controlcenter
        font.family: Services.Theme.fontMono
        font.pixelSize: Services.Theme.fontSize4xl
        font.weight: Font.Bold
        color: Services.OverlayManager.controlCenterVisible ? Services.Theme.accent : Services.Theme.textPrimary
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.OverlayManager.controlCenterVisible
            if (newState) Services.OverlayManager.closeAllExcept("controlCenter")
            Services.OverlayManager.controlCenterVisible = newState
        }
    }
}
