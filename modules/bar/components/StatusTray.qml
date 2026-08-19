import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../../../services" as Services
import "." as Components

RowLayout {
    id: root
    spacing: 8

    property bool collapseNear: false
    property bool collapseMore: false

    readonly property real fullUncollapsedWidth: {
        const trayCount = (typeof SystemTray !== "undefined" && SystemTray.items && SystemTray.items.values) ? SystemTray.items.values.length : 0
        const maxVis = sysTrayIcons ? sysTrayIcons.maxVisibleCount : 2
        const visibleCount = Math.min(maxVis, trayCount)
        const hasOverflow = trayCount > maxVis
        const trayW = trayCount > 0 ? (visibleCount * 24 + (hasOverflow ? 20 : 0) + 16) : 0
        return trayW + 370
    }

    // System Tray App Icons (Hides on Lock, collapseNear, or collapseMore)
    Components.SystemTrayIcons {
        id: sysTrayIcons
        trayMenuPopup: trayMenuPopup
        trayOverflowPopup: trayOverflowPopup

        opacity: (Services.OverlayManager.isLocked || root.collapseNear || root.collapseMore) ? 0 : 1
        visible: (Services.Config ? Services.Config.showSysTray : true) && opacity > 0

        transform: Translate {
            x: Services.OverlayManager.isLocked ? 35 : ((root.collapseNear || root.collapseMore) ? 32 : 0)
            Behavior on x { NumberAnimation { duration: 350; easing.type: (Services.OverlayManager.isLocked || root.collapseNear || root.collapseMore) ? Easing.OutCubic : Easing.InCubic } }
        }

        Behavior on opacity { NumberAnimation { duration: 350; easing.type: (Services.OverlayManager.isLocked || root.collapseNear || root.collapseMore) ? Easing.OutCubic : Easing.InCubic } }
    }

    Components.TrayMenuPopup {
        id: trayMenuPopup
    }

    Components.TrayOverflowPopup {
        id: trayOverflowPopup
        trayMenuPopup: trayMenuPopup
        maxVisibleCount: sysTrayIcons.maxVisibleCount
    }

    // CPU Usage (Hides on Lock or collapseMore)
    Components.SysmonIndicator {
        opacity: (Services.OverlayManager.isLocked || root.collapseMore) ? 0.0 : 1.0
        visible: (Services.Config ? Services.Config.showSysmonTray : true) && opacity > 0
        transform: Translate {
            x: Services.OverlayManager.isLocked ? 35 : (root.collapseMore ? 32 : 0)
            Behavior on x { NumberAnimation { duration: 350; easing.type: (Services.OverlayManager.isLocked || root.collapseMore) ? Easing.OutCubic : Easing.InCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: (Services.OverlayManager.isLocked || root.collapseMore) ? Easing.OutCubic : Easing.InCubic } }
    }

    // Volume Pill (Hides on Lock)
    Rectangle {
        id: volPill
        implicitHeight: 28
        implicitWidth: volLayout.implicitWidth + 20
        radius: 14
        color: volMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
        border.color: volMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
        border.width: 1
        opacity: Services.OverlayManager.isLocked ? 0.0 : 1.0
        visible: (Services.Config ? Services.Config.showVolumeTray : true) && opacity > 0

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        transform: Translate {
            x: Services.OverlayManager.isLocked ? 35 : 0
            Behavior on x { NumberAnimation { duration: 350; easing.type: Services.OverlayManager.isLocked ? Easing.OutCubic : Easing.InCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Services.OverlayManager.isLocked ? Easing.OutCubic : Easing.InCubic } }

        RowLayout {
            id: volLayout
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted, Services.Audio.isHeadphone, Services.Audio.isTws)
                font.family: Services.Theme.fontMono
                font.pixelSize: Services.Theme.fontSizeXl
                color: volMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                text: Math.round(Services.Audio.volume * 100) + "%"
                font.family: Services.Theme.fontMono
                font.pixelSize: Services.Theme.fontSizeMd
                color: Services.Theme.textSecondary
            }
        }

        MouseArea {
            id: volMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const newState = !Services.OverlayManager.controlCenterVisible
                if (newState) Services.OverlayManager.closeAllExcept("controlCenter")
                Services.OverlayManager.controlCenterVisible = newState
            }
        }
    }

    // Battery Pill (Stays Visible & Morphs Seamlessly into Lockscreen)
    Rectangle {
        id: batPill
        implicitHeight: 28
        implicitWidth: batLayout.implicitWidth + 20
        radius: 14
        color: batMouse.containsMouse ? Services.Theme.surfaceVariant : Services.Theme.surface
        border.color: batMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border
        border.width: 1
        visible: Services.Config ? Services.Config.showBatteryTray : true

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        RowLayout {
            id: batLayout
            anchors.centerIn: parent
            spacing: 6

            Text {
                id: batIconText
                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                font.family: Services.Theme.fontMono
                font.pixelSize: Services.Theme.fontSizeXl
                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : (batMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary)))
                Behavior on color { ColorAnimation { duration: 250 } }

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
                font.pixelSize: Services.Theme.fontSizeMd
                color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : Services.Theme.textSecondary))
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }

        MouseArea {
            id: batMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const newState = !Services.OverlayManager.controlCenterVisible
                if (newState) Services.OverlayManager.closeAllExcept("controlCenter")
                Services.OverlayManager.controlCenterVisible = newState
            }
        }
    }

    // Notification Bell & Control Center Pill (Stays Visible & Morphs Seamlessly into Lockscreen)
    Rectangle {
        id: ctrlPill
        implicitHeight: 28
        implicitWidth: ctrlLayout.implicitWidth + 20
        radius: 14
        color: (ctrlPillArea.containsMouse || Services.OverlayManager.controlCenterVisible || Services.Notifications.centerVisible) ? Services.Theme.surfaceVariant : Services.Theme.surface
        border.color: (ctrlPillArea.containsMouse || Services.OverlayManager.controlCenterVisible || Services.Notifications.centerVisible) ? Services.Theme.borderHighlight : Services.Theme.border
        border.width: 1
        visible: Services.Config ? Services.Config.showControlCenterTray : true

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        MouseArea {
            id: ctrlPillArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        RowLayout {
            id: ctrlLayout
            anchors.centerIn: parent
            spacing: 10

            Components.NotificationIndicator {}

            Rectangle {
                width: 1
                height: 12
                color: Services.Theme.border
                opacity: 0.8
            }

            Components.ControlCenterToggle {}
        }
    }

    // Clock & Date Pill (Hides on Lock as Lockscreen Has Large Clock)
    Components.ClockCenter {
        opacity: Services.OverlayManager.isLocked ? 0.0 : 1.0
        visible: (Services.Config ? Services.Config.showClockTray : true) && opacity > 0
        transform: Translate {
            x: Services.OverlayManager.isLocked ? 35 : 0
            Behavior on x { NumberAnimation { duration: 350; easing.type: Services.OverlayManager.isLocked ? Easing.OutCubic : Easing.InCubic } }
        }
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Services.OverlayManager.isLocked ? Easing.OutCubic : Easing.InCubic } }
    }
}
