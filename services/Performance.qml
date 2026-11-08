pragma Singleton
import QtQuick
import Quickshell
import "." as Services

Singleton {
    id: root

    // ── Public API & State ───────────────────────────────────────────────────
    // Current active profile: "normal" | "balanced" | "critical"
    property string profile: "normal"

    // User preference: "auto" | "normal" | "balanced" | "critical"
    readonly property string userMode: Services.Config ? (Services.Config.performanceMode || "auto") : "auto"
    readonly property bool isAutomatic: userMode === "auto"

    // Compatibility and feature quality flags
    readonly property bool highLoad: profile !== "normal"
    readonly property bool decorativeMotion: profile === "normal"
    readonly property bool blurEnabled: profile === "normal"
    readonly property bool reflectionEnabled: profile === "normal"
    readonly property bool waveformEnabled: profile !== "critical"
    readonly property bool marqueeEnabled: profile !== "critical"
    readonly property int positionUpdateInterval: profile === "normal" ? 250 : 500
    readonly property real transitionScale: profile === "normal" ? 1.0 : (profile === "balanced" ? 0.8 : 0.5)

    // Internal state tracking for automatic mode
    property int consecutivePressureSamples: 0
    property int consecutiveCalmSamples: 0
    property double lastProfileChangeTime: 0

    // Thresholds & Hysteresis Constants
    readonly property int minDwellTimeMs: 8000          // 8s minimum dwell time to prevent flapping
    readonly property int pressureSamplesThreshold: 3  // 3 samples (~7.5s) of sustained pressure to escalate
    readonly property int calmSamplesThreshold: 5      // 5 samples (~12.5s) of sustained calm to step down

    // ── Public Control Methods ───────────────────────────────────────────────
    function setUserMode(mode) {
        if (mode !== "auto" && mode !== "normal" && mode !== "balanced" && mode !== "critical") return
        if (Services.Config) {
            Services.Config.setPerformanceMode(mode)
        }
        applyMode()
    }

    function resetToAuto() {
        setUserMode("auto")
    }

    function applyMode() {
        const mode = root.userMode
        if (mode === "normal" || mode === "balanced" || mode === "critical") {
            setProfile(mode, "Manual user mode selection")
        } else {
            // In auto mode, immediately evaluate metrics or default to normal
            if (root.profile !== "normal" && root.profile !== "balanced" && root.profile !== "critical") {
                root.profile = "normal"
            }
            evaluateMetrics()
        }
    }

    onUserModeChanged: applyMode()

    function setProfile(newProfile, reason) {
        if (newProfile !== "normal" && newProfile !== "balanced" && newProfile !== "critical") return
        if (root.profile !== newProfile) {
            console.log("[Performance] Profile changed:", root.profile, "->", newProfile, "| Reason:", reason)
            root.profile = newProfile
            root.lastProfileChangeTime = Date.now()
            root.consecutivePressureSamples = 0
            root.consecutiveCalmSamples = 0
        }
    }

    // ── Metrics Evaluation (Runs on each Sysmon snapshot) ─────────────────────
    Connections {
        target: Services.Sysmon
        function onMetricsUpdated() {
            if (!root.isAutomatic) return
            root.evaluateMetrics()
        }
    }

    function evaluateMetrics() {
        const cpu = Services.Sysmon ? Services.Sysmon.cpuUsage : 0
        const memAvail = Services.Sysmon ? Services.Sysmon.memAvailablePct : 100
        const cpuPsi = Services.Sysmon ? Services.Sysmon.cpuPsi : 0
        const memPsi = Services.Sysmon ? Services.Sysmon.memPsi : 0

        // Classify immediate sample
        let sampleDemand = "normal"
        let reason = ""

        // Critical criteria:
        // CPU >= 90% OR MemAvailable <= 8% OR CPU PSI >= 50.0 OR Mem PSI >= 25.0
        if (cpu >= 90 || memAvail <= 8 || cpuPsi >= 50.0 || memPsi >= 25.0) {
            sampleDemand = "critical"
            reason = "High pressure: CPU=" + cpu + "%, MemAvail=" + memAvail + "%, cpuPsi=" + cpuPsi + ", memPsi=" + memPsi
        }
        // Balanced criteria:
        // CPU >= 75% OR MemAvailable <= 15% OR CPU PSI >= 25.0 OR Mem PSI >= 10.0
        else if (cpu >= 75 || memAvail <= 15 || cpuPsi >= 25.0 || memPsi >= 10.0) {
            sampleDemand = "balanced"
            reason = "Elevated pressure: CPU=" + cpu + "%, MemAvail=" + memAvail + "%, cpuPsi=" + cpuPsi + ", memPsi=" + memPsi
        }

        const now = Date.now()
        const dwellElapsed = (now - root.lastProfileChangeTime) >= root.minDwellTimeMs

        // Escalation logic:
        if (sampleDemand === "critical") {
            if (root.profile !== "critical") {
                root.consecutiveCalmSamples = 0
                root.consecutivePressureSamples++
                if (root.consecutivePressureSamples >= root.pressureSamplesThreshold) {
                    setProfile("critical", reason)
                }
            } else {
                root.consecutivePressureSamples = 0
                root.consecutiveCalmSamples = 0
            }
            return
        }

        if (sampleDemand === "balanced") {
            root.consecutiveCalmSamples = 0
            if (root.profile === "normal") {
                root.consecutivePressureSamples++
                if (root.consecutivePressureSamples >= root.pressureSamplesThreshold) {
                    setProfile("balanced", reason)
                }
            } else if (root.profile === "critical" && dwellElapsed) {
                // If in critical and demand is balanced, consider stepping down after calm samples
                root.consecutivePressureSamples = 0
                root.consecutiveCalmSamples++
                if (root.consecutiveCalmSamples >= root.calmSamplesThreshold) {
                    setProfile("balanced", "Stepping down from critical to balanced")
                }
            }
            return
        }

        // Sample demand is "normal" (calm)
        root.consecutivePressureSamples = 0
        if (root.profile !== "normal" && dwellElapsed) {
            // Calm verification: CPU < 60% and MemAvail > 20%
            const isTrulyCalm = (cpu < 60) && (memAvail > 20) && (cpuPsi < 15.0) && (memPsi < 5.0)
            if (isTrulyCalm) {
                root.consecutiveCalmSamples++
                if (root.consecutiveCalmSamples >= root.calmSamplesThreshold) {
                    if (root.profile === "critical") {
                        setProfile("balanced", "Gradual recovery: critical -> balanced")
                    } else if (root.profile === "balanced") {
                        setProfile("normal", "System recovered to normal")
                    }
                }
            } else {
                root.consecutiveCalmSamples = 0
            }
        }
    }

    Component.onCompleted: {
        applyMode()
    }
}
