import QtQuick
import QtQuick.Layouts
import "../../../services" as Services

Rectangle {
    id: sysmonPill

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    readonly property bool isActive: Services.OverlayManager ? Services.OverlayManager.sysmonPanelVisible : false

    // ── Tray layout contract ──────────────────────────────────────
    property bool trayCompact: false
    property bool trayYielded: false
    property int hPadOverride: -1

    readonly property int baseHPad: isMinimal ? 12 : 20
    readonly property int hPad: hPadOverride >= 0 ? hPadOverride : baseHPad
    readonly property int innerSpacing: isMinimal ? 4 : 6

    TextMetrics {
        id: mIcon
        font.family: Services.Theme.fontSymbols
        font.pixelSize: sysmonPill.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
        text: Services.Icons.cpu
    }
    TextMetrics {
        id: mPct
        font.family: Services.Theme.fontMono
        font.pixelSize: sysmonPill.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
        // Pakai lebar tetap 3 digit ("100%"), bukan nilai live, agar tidak recompute tiap detik
        text: "100%"
    }

    readonly property real trayWidthCompact: Math.ceil(mIcon.width) + baseHPad
    readonly property real trayWidthFull: trayWidthCompact + innerSpacing + Math.ceil(mPct.width)

    implicitHeight: isMinimal ? 24 : 28
    implicitWidth: trayCompact ? trayWidthCompact : trayWidthFull
    radius: isMinimal ? 6 : (isIslands ? 14 : 10)

    color: (sysmonMouse.containsMouse || isActive) ? Services.Theme.bgHover 
         : (isIslands ? Services.Theme.surface 
         : (isFloating ? Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.45) 
         : (isUnified ? Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.4) : "transparent")))

    border.color: (sysmonMouse.containsMouse || isActive) ? Services.Theme.borderHighlight 
         : (isIslands ? Services.Theme.border 
         : (isFloating ? Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.4) 
         : (isUnified ? Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.3) : "transparent")))
    border.width: isMinimal ? 0 : 1

    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

    Item {
        id: sysmonIconBox
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: sysmonPill.isMinimal ? 6 : 10
        width: sysmonIconText.implicitWidth
        height: sysmonIconText.implicitHeight

        Text {
            id: sysmonIconText
            anchors.centerIn: parent
            text: Services.Icons.cpu
            font.family: Services.Theme.fontSymbols
            font.pixelSize: sysmonPill.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
            color: (sysmonMouse.containsMouse || sysmonPill.isActive) ? Services.Theme.accent : Services.Theme.textPrimary
            Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }
    }

    Text {
        id: sysmonPctText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: sysmonIconBox.right
        anchors.leftMargin: sysmonPill.innerSpacing
        text: Math.round(Services.Sysmon.cpuUsage) + "%"
        font.family: Services.Theme.fontMono
        font.pixelSize: sysmonPill.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
        color: (sysmonMouse.containsMouse || sysmonPill.isActive) ? Services.Theme.accent : Services.Theme.textSecondary
        visible: opacity > 0.01
        opacity: sysmonPill.trayCompact ? 0.0 : 1.0
        clip: true
        Behavior on opacity { NumberAnimation { duration: sysmonPill.trayCompact ? 160 : 260; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: sysmonMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const centerX = sysmonPill.mapToItem(null, sysmonPill.width / 2, 0).x
            Services.OverlayManager.sysmonTargetX = centerX
            const newState = !Services.OverlayManager.sysmonPanelVisible
            if (newState) Services.OverlayManager.closeAllExcept("sysmonPanel")
            Services.OverlayManager.sysmonPanelVisible = newState
        }
    }
}
