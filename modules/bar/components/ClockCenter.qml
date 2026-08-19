import QtQuick
import "../../../services" as Services

Rectangle {
    id: clockPill

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    implicitHeight: isMinimal ? 24 : 28
    implicitWidth: clockText.implicitWidth + (isMinimal ? 12 : 20)
    radius: isMinimal ? 6 : (isIslands ? 14 : 10)

    color: clockArea.containsMouse ? Services.Theme.bgHover 
         : (isIslands ? Services.Theme.surface 
         : (isFloating ? Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.45) 
         : (isUnified ? Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.4) : "transparent")))

    border.color: clockArea.containsMouse ? Services.Theme.borderHighlight 
         : (isIslands ? Services.Theme.border 
         : (isFloating ? Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.4) 
         : (isUnified ? Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.3) : "transparent")))
    border.width: isMinimal ? 0 : 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    Text {
        id: clockText
        anchors.centerIn: parent
        font.family: Services.Theme.fontMono
        font.pixelSize: clockPill.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeLg
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
