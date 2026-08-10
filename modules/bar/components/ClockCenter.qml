import QtQuick
import "../../../services" as Services

Item {
    implicitWidth: clock.implicitWidth
    implicitHeight: clock.implicitHeight

    Text {
        id: clock
        anchors.fill: parent
        font.family: "Liga SFMono Nerd Font"
        font.pixelSize: 13
        font.weight: Font.Bold
        color: Services.Theme.textPrimary

        function updateTime() {
            clock.text = Qt.formatDateTime(new Date(), "ddd, d MMM hh:mm A")
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.updateTime()
        }

        Component.onCompleted: updateTime()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const newState = !Services.OverlayManager.calendarVisible
            if (newState) Services.OverlayManager.closeAllExcept("calendar")
            Services.OverlayManager.calendarVisible = newState
        }
    }
}
