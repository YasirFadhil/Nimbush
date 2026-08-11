import QtQuick
import QtQuick.Layouts
import "../../../services" as Services
import "." as Components

RowLayout {
    spacing: 8

    // System Tray App Icons
    Components.SystemTrayIcons {
        trayMenuPopup: trayMenuPopup
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
        implicitHeight: 28
        implicitWidth: batLayout.implicitWidth + 20
        radius: 14
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        RowLayout {
            id: batLayout
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 13
                color: Services.Theme.textPrimary
            }
            Text {
                text: Math.round(Services.Power.percentage * 100) + "%"
                font.family: "Liga SFMono Nerd Font"
                font.pixelSize: 11
                color: Services.Theme.textSecondary
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
