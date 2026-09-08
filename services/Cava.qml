pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "." as Services

Singleton {
    id: root

    // ── Universal State & Properties ───────────────────────────────────────────
    property bool isAvailable: false
    property string cavaExecutable: "cava"
    property var values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    readonly property int barCount: 12
    property bool hasAudio: false
    property real peakEnergy: 0.0

    property int activeConsumers: 0

    // Lifecycle: active when media is playing, CAVA enabled, screen is unlocked, player is LOCAL (laptop), and capsule visualizer is active
    readonly property bool isMediaPlaying: Services.Mpris ? ((Services.Mpris.activePlayer !== null) && (Services.Mpris.activePlayer.isPlaying ?? false)) : false
    readonly property bool isLocalPlayer: Services.Mpris ? (Services.Mpris.isLocal ?? true) : true
    readonly property bool isLocked: Services.OverlayManager ? Services.OverlayManager.isLocked : false
    readonly property bool isConfigEnabled: Services.Config ? Services.Config.islandCavaWave : true
    readonly property bool shouldRun: isAvailable && isConfigEnabled && isMediaPlaying && isLocalPlayer && !isLocked && (activeConsumers > 0)

    readonly property string configPath: Quickshell.env("HOME") + "/.config/quickshell/assets/cava.conf"

    // ── Audio Detection Debounce ───────────────────────────────────────────────
    Timer {
        id: silenceDebounceTimer
        interval: 650
        repeat: false
        onTriggered: {
            root.hasAudio = false
            root.peakEnergy = 0.0
        }
    }

    // ── Universal Binary Check (Detects cava on any Linux distro / PATH) ───────
    Process {
        id: checkProc
        command: ["sh", "-c", "command -v cava || which cava 2>/dev/null"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const path = data.trim()
                if (path.length > 0 && !path.includes("not found")) {
                    root.cavaExecutable = path
                    root.isAvailable = true
                }
            }
        }
    }

    // ── CAVA Execution Process ────────────────────────────────────────────────
    Process {
        id: cavaProc
        command: [root.cavaExecutable, "-p", root.configPath]
        running: root.shouldRun

        stdout: SplitParser {
            onRead: data => {
                root.parseCavaOutput(data)
            }
        }
    }

    function parseCavaOutput(line) {
        if (!line || line.length === 0) return
        const parts = line.trim().split(";")
        if (parts.length < root.barCount) return

        let newVals = new Array(root.barCount)
        let activeEnergy = 0.0
        let foundSound = false

        for (let i = 0; i < root.barCount; i++) {
            const raw = parseInt(parts[i], 10)
            const v = (isNaN(raw) || raw < 0) ? 0.0 : Math.min(1.0, raw / 100.0)
            newVals[i] = v
            activeEnergy += v
            if (v > 0.03) {
                foundSound = true
            }
        }

        root.values = newVals
        root.peakEnergy = activeEnergy / root.barCount

        if (foundSound) {
            root.hasAudio = true
            silenceDebounceTimer.stop()
        } else if (root.hasAudio) {
            if (!silenceDebounceTimer.running) {
                silenceDebounceTimer.restart()
            }
        }
    }

    // ── Helper: Sample N bars with musical frequency compensation ─────────────
    function sample(index, totalRequested) {
        if (!values || values.length === 0) return 0.0
        if (totalRequested <= 1) return values[0] ?? 0.0

        const v = root.values
        if (totalRequested === 4) {
            // 4-bar equalizer: balanced cross-frequency mixing & compensation
            if (index === 0) {
                // Bar 0: Sub-bass & Bass kick
                const raw = (v[0] * 0.4 + v[1] * 0.6)
                return Math.min(1.0, raw * 1.05)
            } else if (index === 1) {
                // Bar 1: Low-mids & Rhythm body (tallest lead bar)
                const raw = (v[2] * 0.45 + v[3] * 0.55)
                return Math.min(1.0, raw * 1.25)
            } else if (index === 2) {
                // Bar 2: Midrange & Vocals
                const raw = (v[4] * 0.35 + v[5] * 0.45 + v[6] * 0.2)
                return Math.min(1.0, raw * 1.45)
            } else if (index === 3) {
                // Bar 3: Treble & Cymbals / Air
                const raw = (v[7] * 0.3 + v[8] * 0.4 + v[9] * 0.3)
                return Math.min(1.0, raw * 1.7)
            }
        }

        if (totalRequested === 3) {
            if (index === 0) return Math.min(1.0, (v[0] * 0.4 + v[1] * 0.6) * 1.05)
            if (index === 1) return Math.min(1.0, (v[3] * 0.5 + v[4] * 0.5) * 1.3)
            if (index === 2) return Math.min(1.0, (v[7] * 0.4 + v[8] * 0.6) * 1.6)
        }

        const step = (root.barCount - 1) / Math.max(1, totalRequested - 1)
        const sampleIdx = Math.min(root.barCount - 1, Math.max(0, Math.round(index * step)))
        return v[sampleIdx] ?? 0.0
    }

    // ── Restart CAVA on audio sink / output change ────────────────────────────
    Connections {
        target: Services.Audio
        function onSinkChanged() {
            if (cavaProc.running) {
                cavaProc.running = false
                restartTimer.restart()
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (root.shouldRun) {
                cavaProc.running = true
            }
        }
    }
}
