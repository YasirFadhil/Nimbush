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
        var p = (percentage > 0 && percentage <= 1) ? percentage * 100 : percentage
        if (p >= 75) return "\uf240"
        if (p >= 50) return "\uf241"
        if (p >= 25) return "\uf242"
        if (p >= 10) return "\uf243"
        return "\uf244"
    }

    // Dashboard & System icons
    readonly property string cpu:    "\u{f0140}"
    readonly property string ram:    "\u{f061a}"
    readonly property string disk:   "\uf0a0"
    readonly property string temp:   "\uf2c9"
    readonly property string kernel: "\uf17c"
    readonly property string uptime: "\uf017"
    readonly property string shell:  "\uf120"
    readonly property string lock:   "\uf023"
    readonly property string power:  "\uf011"
    readonly property string close:  "\uf00d"
    readonly property string dash:   "\uf0e4"
}
