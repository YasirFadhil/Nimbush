import QtQuick
import QtQuick.Layouts
import "../../../services" as Services
import "." as Components

RowLayout {
    id: root
    spacing: 8

    property bool collapseNear: false

    // System Tray App Icons
    Components.SystemTrayIcons {
        trayMenuPopup: trayMenuPopup

        opacity: root.collapseNear ? 0 : 1

        transform: Translate {
            x: root.collapseNear ? 32 : 0
            Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutExpo } }
        }

        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutQuad } }
    }

    Components.TrayMenuPopup {
        id: trayMenuPopup
    }

    // CPU Usage
    Components.SysmonIndicator {}

    // Volume Pill
    Rectangle {
        implicitHeight: 28
        implicitWidth: volLayout.implicitWidth + 20
        radius: 14
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        RowLayout {
            id: volLayout
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted)
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 13
                color: Services.Theme.textPrimary
            }
            Text {
                text: Math.round(Services.Audio.volume * 100) + "%"
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 11
                color: Services.Theme.textSecondary
            }
        }
    }

    // Battery Pill
    Rectangle {
        id: batPill
        implicitHeight: 28
        implicitWidth: batLayout.implicitWidth + 20
        radius: 14
        color: Services.Power.isLow ? "#2d1616" : Services.Theme.surface
        border.color: Services.Power.isLow ? "#ff4444" : Services.Theme.border
        border.width: 1

        Behavior on color { ColorAnimation { duration: 250 } }
        Behavior on border.color { ColorAnimation { duration: 250 } }

        SequentialAnimation {
            id: blinkAnim
            running: Services.Power.isLow
            loops: Animation.Infinite
            NumberAnimation { target: batPill; property: "opacity"; to: 0.25; duration: 500; easing.type: Easing.InOutQuad }
            NumberAnimation { target: batPill; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
        }

        Connections {
            target: Services.Power
            function onIsLowChanged() {
                if (!Services.Power.isLow) {
                    batPill.opacity = 1.0
                }
            }
        }

        RowLayout {
            id: batLayout
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 13
                color: Services.Power.isLow ? "#ff4444" : (Services.PowerProfile.saverEnabled ? "#ff9800" : Services.Theme.textPrimary)
                Behavior on color { ColorAnimation { duration: 250 } }
            }
            Text {
                text: Math.round(Services.Power.percentage * 100) + "%"
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 11
                color: Services.Power.isLow ? "#ff4444" : (Services.PowerProfile.saverEnabled ? "#ff9800" : Services.Theme.textSecondary)
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }
    }

    // Notification Bell & Control Center Pill
    Rectangle {
        implicitHeight: 28
        implicitWidth: ctrlLayout.implicitWidth + 20
        radius: 14
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

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

    // Clock & Date Pill
    Components.ClockCenter {}
}
