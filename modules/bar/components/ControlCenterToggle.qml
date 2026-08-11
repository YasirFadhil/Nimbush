import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Item {
    Layout.preferredWidth: ccIcon.implicitWidth
    Layout.preferredHeight: ccIcon.implicitHeight

    Text {
        id: ccIcon
        anchors.fill: parent
        text: "\u{eb52}"
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 16
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
