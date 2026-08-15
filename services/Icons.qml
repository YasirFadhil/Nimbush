pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // ── Volume / Speaker ────────────────────────────────────────────────────────
    readonly property string volOff:  "\u{f0e08}"
    readonly property string volLow:  "\u{f057f}"
    readonly property string volMed:  "\u{f0580}"
    // readonly property string volMed:  "\uefcf"
    readonly property string volHigh: "\u{f057e}"

    // Headphone/jack icons (Material Design via Nerd Fonts)
    readonly property string hpOff:  "\udb81\udfce"  // nf-md-headphones_off (muted)
    readonly property string hpOn:   "\uf025"  // nf-md-headphones

    // TWS / earbuds icons
    readonly property string twsOn:  "\u{f0970}"     // earbuds
    readonly property string twsOff: "\u{f0e08}"     // muted (reuse volOff)

    // ── Brightness ──────────────────────────────────────────────────────────────
    readonly property string brigLow:   "\udb80\udcde"
    readonly property string brigMed:   "\udb80\udcdf"
    readonly property string brigMedUp: "\udb80\udcdd"
    readonly property string brigFull:  "\udb80\udce0"
    readonly property string sun:       "\udb80\udce0"

    // ── System / Dashboard ──────────────────────────────────────────────────────
    readonly property string cpu:    "\uf2db"         // nf-fa-microchip
    readonly property string ram:    "\udb81\ude1a"   // nf-md-memory
    readonly property string disk:   "\uf0a0"
    readonly property string temp:   "\uf2c9"
    readonly property string kernel: "\uf17c"
    readonly property string uptime: "\uf017"
    readonly property string shell:  "\uf120"
    readonly property string lock:   "\uf023"
    readonly property string power:  "\uf011"
    readonly property string close:  "\uf00d"
    readonly property string dash:   "\uf0e4"
    readonly property string image:  "\uf03e"
    readonly property string upload: "\uf093"
    readonly property string folder: "\uf07c"
    readonly property string plus:   "\uf067"


    // ── Wifi ────────────────────────────────────────────────────────────────────
    readonly property string wifi:     "\uf1eb"   // nf-fa-wifi
    readonly property string wifiLock: "\uf023"   // secured network (reuse lock)
    readonly property string wifiOpen: "\uf09c"   // open/unlocked network

    // ── Bluetooth ───────────────────────────────────────────────────────────────
    readonly property string bluetooth:    "\uf294"  // nf-fa-bluetooth
    readonly property string bluetoothOff: "\uf293"  // nf-fa-bluetooth_b (inactive)

    // ── Navigation / UI ─────────────────────────────────────────────────────────
    readonly property string chevDown:  "\uf078"  // nf-fa-chevron_down
    readonly property string chevLeft:  "\uf053"  // nf-fa-chevron_left
    readonly property string chevRight: "\uf054"  // nf-fa-chevron_right
    readonly property string arrowRight:"\uf061"  // nf-fa-arrow_right (submit)
    readonly property string check:     "\uf00c"  // nf-fa-check
    readonly property string trash:     "\uf1f8"  // nf-fa-trash
    readonly property string refresh:   "\uf021"  // nf-fa-refresh
    readonly property string spinner:   "\uf110"  // nf-fa-spinner
    readonly property string download:  "\uf063"  // nf-fa-arrow_down

    // ── Quick Actions ───────────────────────────────────────────────────────────
    readonly property string moon:     "\uf186"   // nf-fa-moon_o (DND/focus)
    readonly property string tree:     "\uf06c"   // nf-fa-tree (power saver)
    readonly property string camera:   "\uf030"   // nf-fa-camera (screenshot)
    readonly property string volMute:  "\uf466"   // nf-fa-volume_off (mute tile)
    readonly property string speaker:  "\uf028"   // nf-fa-volume_up
    readonly property string headphone:"\uf025"   // nf-fa-headphones
    readonly property string sliders:  "\uf1de"   // nf-fa-sliders (CC toggle on lockscreen)

    // ── Media Controls ──────────────────────────────────────────────────────────
    readonly property string music:      "\uf001"  // nf-fa-music
    readonly property string musicNote:  "\u266a"  // ♪ (Unicode music note)
    readonly property string mediaPrev:  "\uf04a"  // nf-fa-step_backward
    readonly property string mediaPlay:  "\uf04b"  // nf-fa-play
    readonly property string mediaPause: "\uf04c"  // nf-fa-pause
    readonly property string mediaNext:  "\uf04e"  // nf-fa-step_forward
    readonly property string mediaShuffle:  "\uf074"  // nf-fa-random
    readonly property string mediaLoopAll:  "\uf364"  // nf-fa-repeat
    readonly property string mediaLoopOne:  "\uf365"  // nf-fa-repeat (one)

    // ── User / Lockscreen ───────────────────────────────────────────────────────
    readonly property string user:      "\uf007"  // nf-fa-user
    readonly property string eyeOpen:   "\uf06e"  // nf-fa-eye
    readonly property string eyeClosed: "\uf070"  // nf-fa-eye_slash
    readonly property string bell:      "\uf0a2"  // nf-fa-bell_o

    // ── Power Menu ──────────────────────────────────────────────────────────────
    readonly property string reboot: "\u{f05ad}"  // nf-md-restart

    // Power Menu Action Icons
    readonly property string pmLock:     "\u{f033e}"  // nf-md-lock
    readonly property string pmLogout:   "\u{f0343}"  // nf-md-logout
    readonly property string pmSleep:    "\u{f04b2}"  // nf-md-sleep
    readonly property string pmReboot:   "\u{f0709}"  // nf-md-restart_alert
    readonly property string pmShutdown: "\u{f0425}"  // nf-md-power

    // ── Launcher / Search ────────────────────────────────────────────────────────
    readonly property string search: "\uf002"  // nf-fa-search

    // ── Clipboard ───────────────────────────────────────────────────────────────
    readonly property string clipboard: "\uf0ea"  // nf-fa-clipboard
    readonly property string pin:       "\uf08d"  // nf-fa-thumb_tack
    readonly property string file:      "\uf0f6"  // nf-fa-file_text

    // ── Bar ─────────────────────────────────────────────────────────────────────
    readonly property string controlcenter: "\u{eb52}"  // nf-cod-layout_panel_center

    // ── Helper Functions ─────────────────────────────────────────────────────────

    // volumeIcon(volume, muted, isHeadphone, isTws)
    // isTws   → Bluetooth earbuds icon (f0970)
    // isHeadphone → wired headphone icon
    // else    → speaker icon
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
      if (brightness < 0.25) return brigLow
      if (brightness < 0.50) return brigMed
      if (brightness < 0.75) return brigMedUp
      return brigFull
    }

    // Used by PowerOsd.qml — simple 2-state icon helper
    function powerIconSimple(charging, percentage) {
        if (charging) return "\uf0e7"
        return "\uf240"
    }

    // Used by StatusTray.qml in bar — tiered battery icons from FontAwesome family
    // matching icon style across the project
    function powerIcon(charging, percentage) {
        if (charging) return "\uf0e7"
        var p = (percentage > 0 && percentage <= 1) ? percentage * 100 : percentage
        if (p >= 75) return "\uf240"
        if (p >= 50) return "\uf241"
        if (p >= 25) return "\uf242"
        if (p >= 10) return "\uf243"
        return "\uf244"
    }

    // mediaPlayPause(isPlaying) → play or pause icon
    function mediaPlayPause(isPlaying) {
        return isPlaying ? mediaPause : mediaPlay
    }

    // btIcon(connected) → bluetooth connected or inactive icon
    function btIcon(connected) {
        return connected ? bluetooth : bluetoothOff
    }

    // wifiSecurityIcon(hasPassword) → lock or open icon
    function wifiSecurityIcon(hasPassword) {
        return hasPassword ? wifiLock : wifiOpen
    }

    // sinkIcon(description) → headphone or speaker icon based on device name
    function sinkIcon(description) {
        return description.toLowerCase().includes("headphone") ? headphone : speaker
    }

    // updateIcon(isPulling, isChecking) → spinner, refresh, or download
    function updateIcon(isPulling, isChecking) {
        if (isPulling)   return spinner
        if (isChecking)  return refresh
        return download
    }

    // refreshOrSpinIcon(isLoading) → spinner when loading, refresh otherwise
    function refreshOrSpinIcon(isLoading) {
        return isLoading ? spinner : refresh
    }
}
