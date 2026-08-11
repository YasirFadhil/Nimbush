import QtQuick
import "../../../services" as Services

Rectangle {
    id: clockPill
    implicitHeight: 28
    implicitWidth: clockText.implicitWidth + 20
    radius: 14
    color: clockArea.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
    border.color: Services.Theme.border
    border.width: 1

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
        id: clockText
        anchors.centerIn: parent
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 12
        font.weight: Font.Bold
        color: Services.Theme.textPrimary

        function updateTime() {
            clockText.text = Qt.formatDateTime(new Date(), "ddd, d MMM hh:mm A")
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clockText.updateTime()
        }

        Component.onCompleted: updateTime()
    }

    MouseArea {
        id: clockArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.OverlayManager.calendarVisible
            if (newState) Services.OverlayManager.closeAllExcept("calendar")
            Services.OverlayManager.calendarVisible = newState
        }
    }
}
