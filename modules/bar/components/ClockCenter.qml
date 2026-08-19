import QtQuick
import "../../../services" as Services

Rectangle {
    id: clockPill
    implicitHeight: 28
    implicitWidth: clockText.implicitWidth + 20
    radius: 14
    color: clockArea.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
    border.color: clockArea.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    Text {
        id: clockText
        anchors.centerIn: parent
        font.family: Services.Theme.fontMono
        font.pixelSize: Services.Theme.fontSizeLg
        font.weight: Font.Bold
        color: Services.Theme.textPrimary

        function updateTime() {
            const is24 = Services.Config ? Services.Config.clock24h : true
            const showSec = Services.Config ? Services.Config.clockShowSeconds : false
            const showDate = Services.Config ? Services.Config.clockShowDate : true
            const dateFmt = Services.Config ? Services.Config.clockDateFormat : "short"

            const timePattern = is24 
                ? (showSec ? "HH:mm:ss" : "HH:mm")
                : (showSec ? "hh:mm:ss A" : "hh:mm A")

            let datePrefix = ""
            if (showDate) {
                datePrefix = (dateFmt === "full" ? "dddd, d MMMM " : "ddd, d MMM ")
            }

            clockText.text = Qt.formatDateTime(new Date(), datePrefix + timePattern)
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clockText.updateTime()
        }

        Component.onCompleted: updateTime()
    }

    Connections {
        target: Services.Config
        function onConfigChanged() {
            clockText.updateTime()
        }
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
