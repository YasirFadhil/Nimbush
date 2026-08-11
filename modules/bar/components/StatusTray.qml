import QtQuick
import QtQuick.Layouts
import "../../../services" as Services
import "." as Components

RowLayout {
    spacing: 14

    Components.NotificationIndicator {}
    // Components.MediaIndicator {}
    Components.SysmonIndicator {}

    Components.Separator {}

    // Volume
    RowLayout {
        spacing: 6
        Text {
            text: Services.Icons.volumeIcon(Services.Audio.volume, Services.Audio.muted)
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 14
            color: Services.Theme.textPrimary
        }
        Text {
            text: Math.round(Services.Audio.volume * 100) + "%"
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 12
            color: Services.Theme.textSecondary
        }
    }

    // Brightness
    // RowLayout {
    //     spacing: 6
    //     Text {
    //         text: Services.Icons.brightnessIcon(Services.brightness.percent)
    //         font.family: "Liga SFMono Nerd Font"
    //         font.pixelSize: 14
    //         color: Services.Theme.textPrimary
    //     }
    //     Text {
    //         text: Math.round(Services.Brightness.percent * 100) + "%"
    //         font.family: "Liga SFMono Nerd Font"
    //         font.pixelSize: 12
    //         color: Services.Theme.textSecondary
    //     }
    // }

    Components.Separator {}

    // Battery
    RowLayout {
        spacing: 6
        Text {
            text: Services.Icons.powerIcon(Services.Power.charging, Services.Power.percentage * 100)
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 14
            color: Services.Theme.textPrimary
        }
        Text {
            text: Math.round(Services.Power.percentage * 100) + "%"
            font.family: "Liga SFMono Nerd Font"
            font.pixelSize: 12
            color: Services.Theme.textSecondary
        }
    }

    Components.Separator {}

    Components.ControlCenterToggle {}
    
    Components.Separator {}

    Components.ClockCenter {}
}
