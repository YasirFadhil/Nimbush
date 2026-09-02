import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../../../services" as Services
import "." as Components

RowLayout {
    id: root
    spacing: 0

    property real barWidth: 1920
    property real islandRightEdge: 0
    property real islandCollapsedRightEdge: 0
    property bool isIslandExpanded: false

    readonly property int itemSpacing: isMinimal ? 4 : 8

    // Push delta = how many px the island right edge grew from collapsed baseline.
    readonly property real islandPushDelta: {
        if (!isIslandExpanded || islandRightEdge <= 0 || islandCollapsedRightEdge <= 0) return 0
        return Math.max(0, islandRightEdge - islandCollapsedRightEdge)
    }

    // Available space from island right edge to screen edge
    readonly property real availableRightSpace: (barWidth > 0 && islandRightEdge > 0) ? (barWidth - islandRightEdge) : 9999

    // Adaptively collapse items in cascade as Island expands:
    // 1. Volume yields on standard expansions (HUD, Notif, Media) -> CPU & SysTray slide right smoothly
    readonly property bool hideVolume: isIslandExpanded && ((availableRightSpace < 560 && islandPushDelta >= 35) || islandPushDelta >= 160)
    // 2. Sysmon (CPU) only yields on large expansions (e.g. Wallpaper Studio 480px) -> SysTray slides next to Battery
    readonly property bool hideSysmon: isIslandExpanded && ((availableRightSpace < 460 && islandPushDelta >= 140) || islandPushDelta >= 160)
    // 3. SysTray only yields on extreme small-screen space constraints
    readonly property bool hideTrayIcons: isIslandExpanded && (availableRightSpace < 380 && islandPushDelta >= 160)

    // Right anchor items only hide on extreme screen constraints
    readonly property bool hideBattery: isIslandExpanded && (availableRightSpace < 160)
    readonly property bool hideControl: isIslandExpanded && (availableRightSpace < 110)
    readonly property bool hideClock: isIslandExpanded && (availableRightSpace < 60)

    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isIslands: barStyle === "islands"
    readonly property bool isMinimal: barStyle === "minimal"
    readonly property bool isFloating: barStyle === "floating"
    readonly property bool isUnified: barStyle === "unified"

    readonly property int pillHeight: isMinimal ? 24 : 28
    readonly property int pillRadius: isMinimal ? 6 : (isIslands ? 14 : 10)

    function getPillBg(hovered) {
        if (hovered) return Services.Theme.bgHover
        if (isIslands) return Services.Theme.surface
        if (isFloating) return Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.45)
        if (isUnified) return Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.4)
        return "transparent"
    }

    function getPillBorder(hovered) {
        if (hovered) return Services.Theme.borderHighlight
        if (isIslands) return Services.Theme.border
        if (isFloating) return Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.4)
        if (isUnified) return Qt.rgba(Services.Theme.border.r, Services.Theme.border.g, Services.Theme.border.b, 0.3)
        return "transparent"
    }

    readonly property real fullUncollapsedWidth: {
        const trayCount = (typeof SystemTray !== "undefined" && SystemTray.items && SystemTray.items.values) ? SystemTray.items.values.length : 0
        const maxVis = sysTrayIcons ? sysTrayIcons.maxVisibleCount : 2
        const visibleCount = Math.min(maxVis, trayCount)
        const hasOverflow = trayCount > maxVis
        const trayW = trayCount > 0 ? (visibleCount * 24 + (hasOverflow ? 20 : 0) + 16) : 0
        return trayW + 370
    }

    // ── 1. System Tray App Icons ───────────────────────────────────────────
    Components.SystemTrayIcons {
        id: sysTrayIcons
        trayMenuPopup: trayMenuPopup
        trayOverflowPopup: trayOverflowPopup

        readonly property bool shouldHide: Services.OverlayManager.isLocked || root.hideTrayIcons

        Layout.preferredWidth: shouldHide ? 0 : implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: shouldHide ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        opacity: shouldHide ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showSysTray : true
        enabled: opacity > 0.5

        Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    Components.TrayMenuPopup {
        id: trayMenuPopup
    }

    Components.TrayOverflowPopup {
        id: trayOverflowPopup
        trayMenuPopup: trayMenuPopup
        maxVisibleCount: sysTrayIcons.maxVisibleCount
    }

    // ── 2. CPU / Sysmon Indicator ─────────────────────────────────────────
    Components.SysmonIndicator {
        id: sysmonInd
        readonly property bool shouldHide: Services.OverlayManager.isLocked || root.hideSysmon

        Layout.preferredWidth: shouldHide ? 0 : implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: shouldHide ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        opacity: shouldHide ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showSysmonTray : true
        enabled: opacity > 0.5

        Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }

    // ── 3. Volume Pill ────────────────────────────────────────────────────
    Rectangle {
        id: volPill
        readonly property bool shouldHide: Services.OverlayManager.isLocked || root.hideVolume

        implicitHeight: root.pillHeight
        implicitWidth: volLayout.implicitWidth + (root.isMinimal ? 12 : 20)
        Layout.preferredWidth: shouldHide ? 0 : implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: shouldHide ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        radius: root.pillRadius
        color: root.getPillBg(volMouse.containsMouse || Services.OverlayManager.volumePanelVisible)
        border.color: root.getPillBorder(volMouse.containsMouse || Services.OverlayManager.volumePanelVisible)
        border.width: root.isMinimal ? 0 : 1
        
        opacity: shouldHide ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showVolumeTray : true
        enabled: opacity > 0.5

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        RowLayout {
            id: volLayout
            anchors.right: parent.right
            anchors.rightMargin: root.isMinimal ? 6 : 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.isMinimal ? 4 : 6

            Item {
                id: volIconBox
                property string icon: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
                property string oldIcon: ""
                property color iconColor: (volMouse.containsMouse || Services.OverlayManager.volumePanelVisible) ? Services.Theme.accent : Services.Theme.textPrimary
                Behavior on iconColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                implicitWidth: mainVolText.implicitWidth
                implicitHeight: mainVolText.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                onIconChanged: {
                    if (icon !== mainVolText.text) {
                        oldIcon = mainVolText.text
                        oldVolText.opacity = 1.0
                        mainVolText.text = icon
                        mainVolText.opacity = 0.0
                        volCrossFade.restart()
                    }
                }

                Component.onCompleted: mainVolText.text = icon

                Text {
                    id: oldVolText
                    anchors.centerIn: parent
                    text: volIconBox.oldIcon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
                    color: volIconBox.iconColor
                    opacity: 0.0
                    visible: opacity > 0
                }

                Text {
                    id: mainVolText
                    anchors.centerIn: parent
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
                    color: volIconBox.iconColor
                    opacity: 1.0
                }

                ParallelAnimation {
                    id: volCrossFade
                    NumberAnimation { target: oldVolText; property: "opacity"; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: mainVolText; property: "opacity"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                }
            }
            Text {
                text: Math.round(Services.Audio.volume * 100) + "%"
                font.family: Services.Theme.fontMono
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
                color: (volMouse.containsMouse || Services.OverlayManager.volumePanelVisible) ? Services.Theme.accent : Services.Theme.textSecondary
            }
        }

        MouseArea {
            id: volMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const centerX = volPill.mapToItem(null, volPill.width / 2, 0).x
                Services.OverlayManager.volumeTargetX = centerX
                const newState = !Services.OverlayManager.volumePanelVisible
                if (newState) Services.OverlayManager.closeAllExcept("volumePanel")
                Services.OverlayManager.volumePanelVisible = newState
            }
        }
    }

    // ── 4. Battery Pill (Anchor) ──────────────────────────────────────────
    Rectangle {
        id: batPill
        readonly property bool shouldHide: Services.OverlayManager.isLocked || root.hideBattery

        implicitHeight: root.pillHeight
        implicitWidth: batLayout.implicitWidth + (root.isMinimal ? 12 : 20)
        Layout.preferredWidth: shouldHide ? 0 : implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: shouldHide ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        radius: root.pillRadius
        color: root.getPillBg(batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible)
        border.color: root.getPillBorder(batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible)
        border.width: root.isMinimal ? 0 : 1

        opacity: shouldHide ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showBatteryTray : true
        enabled: opacity > 0.5

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        RowLayout {
            id: batLayout
            anchors.centerIn: parent
            spacing: root.isMinimal ? 4 : 6

            Text {
                id: batIconText
                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                font.family: Services.Theme.fontSymbols
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : ((batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible) ? Services.Theme.accent : Services.Theme.textPrimary)))
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                SequentialAnimation {
                    id: blinkAnim
                    running: Services.Power.isLow
                    loops: Animation.Infinite
                    NumberAnimation { target: batIconText; property: "opacity"; to: 0.2; duration: 500; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: batIconText; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                }

                Connections {
                    target: Services.Power
                    function onIsLowChanged() {
                        if (!Services.Power.isLow) {
                            batIconText.opacity = 1.0
                        }
                    }
                }
            }
            Text {
                text: Math.round(Services.Power.percentage * 100) + "%"
                font.family: Services.Theme.fontMono
                font.pixelSize: root.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : ((batMouse.containsMouse || Services.OverlayManager.batteryPanelVisible) ? Services.Theme.accent : Services.Theme.textSecondary)))
                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }

        MouseArea {
            id: batMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const centerX = batPill.mapToItem(null, batPill.width / 2, 0).x
                Services.OverlayManager.batteryTargetX = centerX
                const newState = !Services.OverlayManager.batteryPanelVisible
                if (newState) Services.OverlayManager.closeAllExcept("batteryPanel")
                Services.OverlayManager.batteryPanelVisible = newState
            }
        }
    }

    // ── 5. Notification Bell & Control Center Pill ────────────────────────
    Rectangle {
        id: ctrlPill
        readonly property bool shouldHide: Services.OverlayManager.isLocked || root.hideControl

        implicitHeight: root.pillHeight
        implicitWidth: ctrlLayout.implicitWidth + (root.isMinimal ? 12 : 20)
        Layout.preferredWidth: shouldHide ? 0 : implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: shouldHide ? 0 : root.itemSpacing
        Layout.alignment: Qt.AlignVCenter
        clip: true
        radius: root.pillRadius
        color: root.getPillBg(Services.OverlayManager.controlCenterVisible || Services.Notifications.centerVisible)
        border.color: root.getPillBorder(Services.OverlayManager.controlCenterVisible || Services.Notifications.centerVisible)
        border.width: root.isMinimal ? 0 : 1

        opacity: shouldHide ? 0.0 : 1.0
        visible: Services.Config ? Services.Config.showControlCenterTray : true
        enabled: opacity > 0.5

        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on Layout.rightMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        RowLayout {
            id: ctrlLayout
            anchors.centerIn: parent
            spacing: root.isMinimal ? 6 : 10

            Components.NotificationIndicator {}

            Rectangle {
                width: 1
                height: root.isMinimal ? 10 : 12
                color: Services.Theme.border
                opacity: 0.8
            }

            Components.ControlCenterToggle {}
        }
    }

    // ── 6. Clock & Date Pill ──────────────────────────────────────────────
    Components.ClockCenter {
        id: clockCenterPill
        readonly property bool shouldHide: Services.OverlayManager.isLocked || root.hideClock

        Layout.preferredWidth: shouldHide ? 0 : implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.rightMargin: 0
        Layout.alignment: Qt.AlignVCenter
        clip: true
        opacity: shouldHide ? 0.0 : 1.0
        visible: root.isIslands && (Services.Config ? Services.Config.showClockTray : true)
        enabled: opacity > 0.5

        Behavior on Layout.preferredWidth { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    }
}
