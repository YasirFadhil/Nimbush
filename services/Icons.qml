pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // ── Volume / Speaker ────────────────────────────────────────────────────────
    readonly property string volOff:  "\uf026"   // nf-fa-volume_off
    readonly property string volLow:  "\uf027"   // nf-fa-volume_down
    readonly property string volMed:  "\uf028"   // nf-fa-volume_up
    readonly property string volHigh: "\uf028"   // nf-fa-volume_up

    // Headphone/jack icons
    readonly property string hpOff:  "\uf025"   // nf-fa-headphones
    readonly property string hpOn:   "\uf025"   // nf-fa-headphones

    // TWS / earbuds icons
    readonly property string twsOn:  "\uf025"   // earbuds / headphones
    readonly property string twsOff: "\uf026"   // muted

    // ── Brightness / Sun ────────────────────────────────────────────────────────
    readonly property string brigLow:   "\uf185"   // nf-fa-sun_o
    readonly property string brigMed:   "\uf185"
    readonly property string brigMedUp: "\uf185"
    readonly property string brigFull:  "\uf185"
    readonly property string sun:       "\uf185"   // nf-fa-sun_o (100% universal)

    // ── System / Dashboard ──────────────────────────────────────────────────────
    readonly property string cpu:    "\uf2db"   // nf-fa-microchip
    readonly property string ram:    "\uf2db"   // nf-fa-microchip / memory
    readonly property string disk:   "\uf0a0"   // nf-fa-hdd_o
    readonly property string temp:   "\uf2c9"   // nf-fa-thermometer_quarter
    readonly property string kernel: "\uf17c"   // nf-fa-linux
    readonly property string uptime:    "\uf017"   // nf-fa-clock_o
    readonly property string clock:     "\uf017"   // nf-fa-clock_o
    readonly property string shell:     "\uf120"   // nf-fa-terminal
    readonly property string lock:      "\uf023"   // nf-fa-lock
    readonly property string power:     "\uf011"   // nf-fa-power_off
    readonly property string battery:   "\uf240"   // nf-fa-battery_full
    readonly property string close:     "\uf00d"   // nf-fa-times
    readonly property string dash:      "\uf0e4"   // nf-fa-tachometer
    readonly property string dashboard: "\uf0e4"   // nf-fa-tachometer
    readonly property string image:     "\uf03e"   // nf-fa-picture_o
    readonly property string upload: "\uf093"   // nf-fa-upload
    readonly property string folder: "\uf07c"   // nf-fa-folder_open
    readonly property string plus:   "\uf067"   // nf-fa-plus

    // ── Wifi ────────────────────────────────────────────────────────────────────
    readonly property string wifi:     "\uf1eb"   // nf-fa-wifi
    readonly property string wifiLock: "\uf023"   // secured network (lock)
    readonly property string wifiOpen: "\uf09c"   // open/unlocked network

    // ── Bluetooth ───────────────────────────────────────────────────────────────
    readonly property string bluetooth:    "\uf294"  // nf-fa-bluetooth
    readonly property string bluetoothOff: "\uf293"  // nf-fa-bluetooth_b

    // ── Navigation / UI ─────────────────────────────────────────────────────────
    readonly property string chevDown:   "\uf078"  // nf-fa-chevron_down
    readonly property string chevLeft:   "\uf053"  // nf-fa-chevron_left
    readonly property string chevRight:  "\uf054"  // nf-fa-chevron_right
    readonly property string arrowRight: "\uf061"  // nf-fa-arrow_right
    readonly property string check:      "\uf00c"  // nf-fa-check
    readonly property string trash:      "\uf1f8"  // nf-fa-trash
    readonly property string refresh:    "\uf021"  // nf-fa-refresh
    readonly property string spinner:    "\uf110"  // nf-fa-spinner
    readonly property string download:   "\uf063"  // nf-fa-arrow_down

    // ── Quick Actions ───────────────────────────────────────────────────────────
    readonly property string moon:     "\uf186"   // nf-fa-moon_o
    readonly property string tree:     "\uf06c"   // nf-fa-leaf / tree
    readonly property string camera:   "\uf030"   // nf-fa-camera
    readonly property string volMute:  "\uf026"   // nf-fa-volume_off
    readonly property string speaker:  "\uf028"   // nf-fa-volume_up
    readonly property string headphone:"\uf025"   // nf-fa-headphones
    readonly property string sliders:  "\uf1de"   // nf-fa-sliders

    // ── Media Controls ──────────────────────────────────────────────────────────
    readonly property string music:        "\uf001"  // nf-fa-music
    readonly property string musicNote:    "\u266a"  // ♪
    readonly property string mediaPrev:    "\uf04a"  // nf-fa-step_backward
    readonly property string mediaPlay:    "\uf04b"  // nf-fa-play
    readonly property string mediaPause:   "\uf04c"  // nf-fa-pause
    readonly property string mediaNext:    "\uf04e"  // nf-fa-step_forward
    readonly property string mediaShuffle: "\uf074"  // nf-fa-random
    readonly property string mediaLoopAll: "\uf01e"  // nf-fa-repeat
    readonly property string mediaLoopOne: "\uf021"  // nf-fa-refresh

    // ── User / Lockscreen ───────────────────────────────────────────────────────
    readonly property string user:      "\uf007"  // nf-fa-user
    readonly property string eyeOpen:   "\uf06e"  // nf-fa-eye
    readonly property string eyeClosed: "\uf070"  // nf-fa-eye_slash
    readonly property string bell:      "\uf0a2"  // nf-fa-bell_o

    // ── Power Menu ──────────────────────────────────────────────────────────────
    readonly property string reboot:     "\uf021"  // nf-fa-refresh / restart
    readonly property string pmLock:     "\uf023"  // nf-fa-lock
    readonly property string pmLogout:   "\uf08b"  // nf-fa-sign_out
    readonly property string pmSleep:    "\uf186"  // nf-fa-moon_o
    readonly property string pmReboot:   "\uf021"  // nf-fa-refresh
    readonly property string pmShutdown: "\uf011"  // nf-fa-power_off

    // ── Launcher / Search ────────────────────────────────────────────────────────
    readonly property string search: "\uf002"  // nf-fa-search

    // ── Clipboard ───────────────────────────────────────────────────────────────
    readonly property string clipboard: "\uf0ea"  // nf-fa-clipboard
    readonly property string pin:       "\uf08d"  // nf-fa-thumb_tack
    readonly property string file:      "\uf0f6"  // nf-fa-file_text

    // ── Bar / Navigation / Preferences ──────────────────────────────────────────
    readonly property string controlcenter: "\uf1de"   // nf-fa-sliders
    readonly property string settings:      "\uf013"   // nf-fa-cog / gear
    readonly property string palette:       "\uf1fc"   // nf-fa-paint_brush (100% universal)
    readonly property string brush:         "\uf1fc"   // nf-fa-paint_brush
    readonly property string wand:          "\uf0d0"   // nf-fa-magic / wizard
    readonly property string undo:          "\uf0e2"   // nf-fa-undo
    readonly property string display:       "\uf108"   // nf-fa-desktop
    readonly property string font:          "\uf031"   // nf-fa-font
    readonly property string keyboard:      "\uf11c"   // nf-fa-keyboard_o
    readonly property string sparkles:      "\uf0d0"   // nf-fa-magic / sparkle
    readonly property string terminal:      "\uf120"   // nf-fa-terminal
    readonly property string info:          "\uf129"   // nf-fa-info
    readonly property string tray:          "\uf0c9"   // nf-fa-bars / tray
    readonly property string checkCircle:   "\uf058"   // nf-fa-check_circle
    readonly property string dotCircle:     "\uf192"   // nf-fa-dot_circle_o
    readonly property string slidersH:      "\uf1de"   // nf-fa-sliders

    // ── Helper Functions ─────────────────────────────────────────────────────────

    function volumeIcon(volume, muted, isHeadphone, isTws) {
        if (isTws) {
            return (muted || volume <= 0) ? twsOff : twsOn
        }
        if (isHeadphone) {
            return (muted || volume <= 0) ? hpOff : hpOn
        }
        if (muted || volume <= 0) return volOff
        if (volume < 0.33) return volLow
        if (volume < 0.66) return volMed
        return volHigh
    }

    function brightnessIcon(brightness) {
        return sun
    }

    function powerIconSimple(charging, percentage) {
        if (charging) return "\uf0e7"
        return "\uf240"
    }

    function powerIcon(charging, percentage) {
        if (charging) return "\uf0e7"
        var p = (percentage > 0 && percentage <= 1) ? percentage * 100 : percentage
        if (p >= 75) return "\uf241"
        if (p >= 50) return "\uf242"
        if (p >= 25) return "\uf243"
        if (p >= 10) return "\uf243"
        return "\uf244"
    }

    function mediaPlayPause(isPlaying) {
        return isPlaying ? mediaPause : mediaPlay
    }

    function btIcon(connected) {
        return connected ? bluetooth : bluetoothOff
    }

    function wifiSecurityIcon(hasPassword) {
        return hasPassword ? wifiLock : wifiOpen
    }

    function sinkIcon(description) {
        return description.toLowerCase().includes("headphone") ? headphone : speaker
    }

    function updateIcon(isPulling, isChecking) {
        if (isPulling)   return spinner
        if (isChecking)  return refresh
        return download
    }

    function refreshOrSpinIcon(isLoading) {
        return isLoading ? spinner : refresh
    }
}
