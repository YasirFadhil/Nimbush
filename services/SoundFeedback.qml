pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Sound feedback service using Freedesktop XDG sound theme.
// Sound files live at /run/current-system/sw/share/sounds/freedesktop/stereo/
// Playback is handled via `paplay` (PipeWire/PulseAudio).
Singleton {
    id: root

    // Path to freedesktop stereo sound directory
    readonly property string soundDir: "/run/current-system/sw/share/sounds/freedesktop/stereo/"

    // ── Freedesktop sound event names ────────────────────────────────────────
    readonly property string sndVolumeChange:    "audio-volume-change"
    readonly property string sndNotification:    "message-new-instant"
    readonly property string sndError:           "dialog-error"
    readonly property string sndWarning:         "dialog-warning"
    readonly property string sndInfo:            "dialog-information"
    readonly property string sndDeviceAdded:     "device-added"
    readonly property string sndDeviceRemoved:   "device-removed"
    readonly property string sndComplete:        "complete"
    readonly property string sndTrash:           "trash-empty"
    readonly property string sndLogin:           "service-login"
    readonly property string sndLogout:          "service-logout"
    readonly property string sndBell:            "bell"
    readonly property string sndAlarm:           "alarm-clock-elapsed"
    readonly property string sndPowerPlug:       "power-plug"
    readonly property string sndPowerUnplug:     "power-unplug"
    readonly property string sndNetConnected:    "network-connectivity-established"
    readonly property string sndNetLost:         "network-connectivity-lost"
    readonly property string sndWindowAttention: "window-attention"

    // ── Global enable/disable switch ─────────────────────────────────────────
    property bool enabled: true

    // ── Internal player process ──────────────────────────────────────────────
    Process {
        id: playerProc
        property string pendingSound: ""

        // paplay with event role so it respects the sound theme volume in PW
        command: ["paplay",
                  "--property=media.role=event",
                  soundDir + pendingSound + ".oga"]
        running: false
    }

    // ── Public API ───────────────────────────────────────────────────────────

    // play(eventName) — e.g. SoundFeedback.play(SoundFeedback.sndNotification)
    function play(eventName) {
        if (!root.enabled) return
        playerProc.pendingSound = eventName
        playerProc.running = false   // reset to allow re-trigger
        playerProc.running = true
    }

    // Convenience wrappers
    function playNotification() { play(sndNotification) }
    function playError()        { play(sndError) }
    function playWarning()      { play(sndWarning) }
    function playInfo()         { play(sndInfo) }
    function playComplete()     { play(sndComplete) }
    function playVolumeChange() { play(sndVolumeChange) }
    function playDeviceAdded()  { play(sndDeviceAdded) }
    function playDeviceRemoved(){ play(sndDeviceRemoved) }
    function playTrash()        { play(sndTrash) }
    function playLogin()        { play(sndLogin) }
    function playLogout()       { play(sndLogout) }
    function playBell()         { play(sndBell) }
    function playAlarm()        { play(sndAlarm) }
    function playPowerPlug()    { play(sndPowerPlug) }
    function playPowerUnplug()  { play(sndPowerUnplug) }
    function playNetConnected() { play(sndNetConnected) }
    function playNetLost()      { play(sndNetLost) }
}
