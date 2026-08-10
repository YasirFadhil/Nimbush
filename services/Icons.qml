pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string volOff:  "\u{f0581}"
    readonly property string volLow:  "\u{f057f}"
    readonly property string volMed:  "\u{f0580}"
    readonly property string volHigh: "\u{f057e}"

    readonly property string brigLow: "\udb80\udcde"
    readonly property string brigMed: "\udb80\udcdf"
    readonly property string brigMedUp: "\udb80\udcdd"
    readonly property string brigFull: "\udb80\udce0"

    function volumeIcon(volume, muted) {
        if (muted || volume <= 0) return volOff
        if (volume < 0.33) return volLow
        if (volume < 0.66) return volMed
        return volHigh
    }

    function brightnessIcon(brightness) {
      if (brightness < 0.25) return brigLow
      if (brightness < 0.50) return brigMed
      if (brightness < 0.75) return brigMedUp
      return brigFull
    }

    // Dipake PowerOsd.qml — sengaja simpel, 2 state doang
    function powerIconSimple(charging, percentage) {
        if (charging) return "\uf0e7"
        return "\uf240"
    }

    // Dipake StatusTray.qml di bar — tiered, pakai FA battery family (3-hex,
    // sama gaya sama icon lain yang udah kebukti render bener di project ini)
    function powerIcon(charging, percentage) {
        if (charging) return "\uf0e7"
        if (percentage >= 80) return "\uf240"
        if (percentage >= 55) return "\uf241"
        if (percentage >= 30) return "\uf242"
        if (percentage >= 10) return "\uf243"
        return "\uf244"
    }
}
