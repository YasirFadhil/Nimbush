import QtQuick
import "../../../services" as Services

Rectangle {
    id: clockPill

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"
    readonly property bool isMacMenuBar: isIslands

    // ── Tray layout contract ──────────────────────────────────────
    property bool trayCompact: false
    property bool trayYielded: false
    property int hPadOverride: -1

    readonly property int baseHPad: isMinimal ? 10 : (isMacMenuBar ? 14 : 18)
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
            if (date) {
                p = isMacMenuBar
                    ? "Wed 30 Sep  "
                    : (fmt === "full" ? "Wednesday, 30 September  " : "Wed, 30 Sep  ")
            }
            const timeSample = isMacMenuBar
                ? (is24 ? (sec ? "23:59:59" : "23:59") : (sec ? "9:59:59 PM" : "9:59 PM"))
                : (is24 ? (sec ? "00:00:00" : "00:00") : (sec ? "00:00:00 AM" : "00:00 AM"))
            return p + timeSample
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
    radius: isMinimal ? 6 : (isMacMenuBar ? 14 : 10)

    readonly property bool glassDark: Services.Theme.isDark
    // Dock glass material
    color: isMacMenuBar
         ? (clockArea.containsMouse ? Qt.rgba(1, 1, 1, glassDark ? 0.14 : 0.22) : "transparent")
         : (isMinimal ? (clockArea.containsMouse ? Services.Theme.bgHover : "transparent")
         : (clockArea.containsMouse ? (glassDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.65))
                                    : (glassDark ? Qt.rgba(0.11, 0.11, 0.12, 0.55) : Qt.rgba(1, 1, 1, 0.48))))

    border.color: isMacMenuBar ? "transparent"
         : (isMinimal ? (clockArea.containsMouse ? Services.Theme.borderHighlight : "transparent")
         : (clockArea.containsMouse ? (glassDark ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(1, 1, 1, 0.85))
                                    : (glassDark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.65))))
    border.width: (isMinimal || isMacMenuBar) ? 0 : 1

    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    onTrayCompactChanged: clockText.updateTime()

    Text {
        id: clockText
        anchors.centerIn: parent
        font.family: Services.Theme.fontFamily
        font.pixelSize: clockPill.isMinimal || clockPill.isMacMenuBar ? Services.Theme.fontSizeMd : Services.Theme.fontSizeLg
        font.weight: clockPill.isMacMenuBar ? Font.Medium : Font.DemiBold
        font.letterSpacing: 0.3
        color: clockPill.isMacMenuBar ? "#f6f6f9" : Services.Theme.textPrimary

        function updateTime() {
            const is24 = Services.Config ? Services.Config.clock24h : true
            const showSec = Services.Config ? Services.Config.clockShowSeconds : false
            // compact memaksa: tanpa tanggal, tanpa detik
            const showDate = clockPill.trayCompact ? false : (Services.Config ? Services.Config.clockShowDate : true)
            const useSec   = clockPill.trayCompact ? false : showSec
            const dateFmt  = Services.Config ? Services.Config.clockDateFormat : "short"

            const timePattern = is24
                ? (useSec ? (clockPill.isMacMenuBar ? "H:mm:ss" : "HH:mm:ss") : (clockPill.isMacMenuBar ? "H:mm" : "HH:mm"))
                : (useSec ? (clockPill.isMacMenuBar ? "h:mm:ss A" : "hh:mm:ss A") : (clockPill.isMacMenuBar ? "h:mm A" : "hh:mm A"))

            let datePrefix = ""
            if (showDate) {
                datePrefix = clockPill.isMacMenuBar
                    ? "ddd d MMM  "
                    : (dateFmt === "full" ? "dddd, d MMMM  " : "ddd, d MMM  ")
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
