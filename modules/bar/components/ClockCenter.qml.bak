import QtQuick
import "../../../services" as Services

Rectangle {
    id: clockPill

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    // ── Tray layout contract ──────────────────────────────────────
    property bool trayCompact: false
    property bool trayYielded: false
    property int hPadOverride: -1

    readonly property int baseHPad: isMinimal ? 12 : 20
    readonly property int hPad: hPadOverride >= 0 ? hPadOverride : baseHPad

    TextMetrics {
        id: mClockFull
        font: clockText.font
        text: {
            const is24 = Services.Config ? Services.Config.clock24h : true
            const sec  = Services.Config ? Services.Config.clockShowSeconds : false
            const date = Services.Config ? Services.Config.clockShowDate : true
            const fmt  = Services.Config ? Services.Config.clockDateFormat : "short"
            let p = ""
            if (date) p = (fmt === "full" ? "Wednesday, 30 September  " : "Wed, 30 Sep  ")
            return p + (is24 ? (sec ? "00:00:00" : "00:00") : (sec ? "00:00:00 AM" : "00:00 AM"))
        }
    }
    TextMetrics {
        id: mClockCompact
        font: clockText.font
        text: (Services.Config && Services.Config.clock24h) ? "00:00" : "00:00 AM"
    }

    readonly property real trayWidthFull: Math.ceil(mClockFull.width) + baseHPad
    readonly property real trayWidthCompact: trayWidthFull

    implicitHeight: isMinimal ? 24 : 28
    implicitWidth: trayCompact ? trayWidthCompact : trayWidthFull
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

    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    onTrayCompactChanged: clockText.updateTime()

    Text {
        id: clockText
        anchors.centerIn: parent
        font.family: Services.Theme.fontFamily
        font.pixelSize: clockPill.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeLg
        font.weight: Font.DemiBold
        font.letterSpacing: 0.3
        color: Services.Theme.textPrimary

        function updateTime() {
            const is24 = Services.Config ? Services.Config.clock24h : true
            const showSec = Services.Config ? Services.Config.clockShowSeconds : false
            // compact memaksa: tanpa tanggal, tanpa detik
            const showDate = clockPill.trayCompact ? false : (Services.Config ? Services.Config.clockShowDate : true)
            const useSec   = clockPill.trayCompact ? false : showSec
            const dateFmt  = Services.Config ? Services.Config.clockDateFormat : "short"

            const timePattern = is24 
                ? (useSec ? "HH:mm:ss" : "HH:mm")
                : (useSec ? "hh:mm:ss A" : "hh:mm A")

            let datePrefix = ""
            if (showDate) {
                datePrefix = (dateFmt === "full" ? "dddd, d MMMM  " : "ddd, d MMM  ")
            }

            clockText.text = Qt.formatDateTime(new Date(), datePrefix + timePattern)
        }

        Timer {
            interval: (Services.Config && Services.Config.clockShowSeconds) ? 1000 : 5000
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
