pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    // Configuration flags
    readonly property bool isEnabled: Services.Config ? Services.Config.faceIdEnabled : true
    property bool isEnrolled: false
    property bool isScanning: false
    property bool isEnrolling: false
    property string status: "idle" // "idle" | "starting" | "scanning" | "detected" | "success" | "unrecognized" | "timeout" | "camera_unavailable" | "not_enrolled"
    property string statusMessage: ""
    property real confidence: 0.0
    property real enrollProgress: 0.0
    property string enrollStepName: ""
    property int enrollStepNumber: 1
    property var availableDevices: ["/dev/video0"]

    readonly property string pythonBin: {
        var home = Quickshell.env("HOME") || "/home/yasirfadhil"
        return home + "/.config/quickshell/scripts/.faceid-env/bin/python3"
    }

    readonly property string helperScript: {
        var home = Quickshell.env("HOME") || "/home/yasirfadhil"
        return home + "/.config/quickshell/scripts/faceid-helper.py"
    }

    readonly property string cameraDevice: (Services.Config && Services.Config.faceIdCameraDevice && Services.Config.faceIdCameraDevice.length > 0)
        ? Services.Config.faceIdCameraDevice
        : "/dev/video0"

    readonly property real maxDistance: (Services.Config && Services.Config.faceIdConfidence > 0)
        ? Services.Config.faceIdConfidence
        : 98.0

    readonly property bool autoUnlock: Services.Config ? Services.Config.faceIdAutoUnlock : true

    // Signals
    signal authenticated(string user, real confidence)
    signal scanFailed(string reason)
    signal enrollStep(real progress, int count, int total)
    signal enrollSuccess(string message)
    signal enrollError(string error)

    Component.onCompleted: {
        checkStatus()
    }

    function checkStatus() {
        if (!statusProc.running) {
            statusProc.running = true
        }
    }

    function startScan() {
        if (!isEnabled) {
            status = "idle"
            return
        }
        if (isScanning || verifyProc.running) return
        if (isEnrolling || enrollProc.running) return

        status = "starting"
        statusMessage = "Starting Face ID..."
        isScanning = true

        verifyProc.command = [
            root.pythonBin,
            root.helperScript,
            "verify",
            "--camera", root.cameraDevice,
            "--timeout", "10.0",
            "--confidence", String(root.maxDistance)
        ]
        verifyProc.running = true
    }

    function resetStatus() {
        if (verifyProc.running) {
            verifyProc.running = false
        }
        isScanning = false
        status = "idle"
        statusMessage = ""
    }

    function stopScan() {
        if (verifyProc.running) {
            verifyProc.running = false
        }
        isScanning = false
        status = "idle"
        statusMessage = ""
    }

    function startEnroll() {
        if (verifyProc.running) stopScan()
        if (enrollProc.running) return

        isEnrolling = true
        enrollProgress = 0.0
        enrollStepName = "Frontal"
        enrollStepNumber = 1
        statusMessage = "Preparing camera for enrollment..."

        enrollProc.command = [
            root.pythonBin,
            root.helperScript,
            "enroll",
            "--camera", root.cameraDevice,
            "--samples", "24"
        ]
        enrollProc.running = true
    }

    function cancelEnroll() {
        if (enrollProc.running) {
            enrollProc.running = false
        }
        isEnrolling = false
        enrollProgress = 0.0
        enrollStepName = ""
        enrollStepNumber = 1
        statusMessage = ""
    }

    function clearData() {
        clearProc.command = [root.pythonBin, root.helperScript, "clear"]
        clearProc.running = true
    }

    // ── Status Inspection Process ──────────────────────────────────────────
    Process {
        id: statusProc
        command: [root.pythonBin, root.helperScript, "status"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0 || !line.startsWith("{")) return
                try {
                    const parsed = JSON.parse(line)
                    root.isEnrolled = Boolean(parsed.enrolled)
                    if (parsed.devices && Array.isArray(parsed.devices)) {
                        root.availableDevices = parsed.devices
                    }
                } catch (e) {
                    console.warn("[FaceId] Failed to parse status JSON:", e)
                }
            }
        }
    }

    // ── Verification Process ───────────────────────────────────────────────
    Process {
        id: verifyProc
        command: [root.helperScript, "verify"]

        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim()
                    if (line.length === 0 || !line.startsWith("{")) continue
                    try {
                        const evt = JSON.parse(line)
                        if (evt.status) {
                            root.status = evt.status
                            if (evt.message) root.statusMessage = evt.message
                            if (evt.confidence !== undefined) root.confidence = evt.confidence

                            if (evt.status === "success") {
                                root.isScanning = false
                                root.authenticated(evt.user || "user", evt.confidence || 0.0)
                            } else if (evt.status === "timeout" || evt.status === "camera_unavailable" || evt.status === "not_enrolled") {
                                root.isScanning = false
                                root.scanFailed(evt.message || evt.status)
                            }
                        }
                    } catch (e) {
                        console.warn("[FaceId] Parse error in verify stdout:", e)
                    }
                }
            }
        }

        onExited: (code, status) => {
            root.isScanning = false
            if (code !== 0 && root.status !== "success") {
                if (root.status !== "timeout" && root.status !== "camera_unavailable" && root.status !== "not_enrolled") {
                    root.status = "failed"
                    root.scanFailed("Scan failed with code " + code)
                }
            }
        }
    }

    // ── Enrollment Process ─────────────────────────────────────────────────
    Process {
        id: enrollProc
        command: [root.pythonBin, root.helperScript, "enroll"]

        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim()
                    if (line.length === 0 || !line.startsWith("{")) continue
                    try {
                        const evt = JSON.parse(line)
                        if (evt.status === "capturing") {
                            root.enrollProgress = evt.progress || 0.0
                            if (evt.step) root.enrollStepNumber = evt.step
                            if (evt.step_name) root.enrollStepName = evt.step_name
                            root.statusMessage = evt.message || ("Capturing " + (evt.step_name || "face") + " (" + evt.count + "/" + evt.total + ")...")
                            root.enrollStep(evt.progress, evt.count, evt.total)
                        } else if (evt.status === "review") {
                            root.enrollProgress = 1.0
                            root.enrollStepName = "Confirmation"
                            root.statusMessage = evt.message || "Reviewing biometric angles..."
                        } else if (evt.status === "cancelled") {
                            root.isEnrolling = false
                            root.enrollStepName = ""
                            root.statusMessage = "Enrollment cancelled"
                            root.enrollError("Enrollment cancelled by user")
                        } else if (evt.status === "training") {
                            root.statusMessage = evt.message || "Training face model..."
                        } else if (evt.status === "complete") {
                            root.isEnrolling = false
                            root.isEnrolled = true
                            root.enrollStepName = ""
                            root.statusMessage = evt.message || "Enrollment complete!"
                            root.enrollSuccess(evt.message)
                            root.checkStatus()
                        } else if (evt.status === "error" || evt.status === "camera_unavailable") {
                            root.isEnrolling = false
                            root.enrollStepName = ""
                            root.statusMessage = evt.message || "Enrollment failed"
                            root.enrollError(evt.message || evt.status)
                        }
                    } catch (e) {
                        console.warn("[FaceId] Parse error in enroll stdout:", e)
                    }
                }
            }
        }

        onExited: (code, status) => {
            root.isEnrolling = false
            if (code !== 0 && !root.isEnrolled) {
                root.enrollError("Enrollment process exited with code " + code)
            }
        }
    }

    // ── Clear Model Process ────────────────────────────────────────────────
    Process {
        id: clearProc
        command: [root.pythonBin, root.helperScript, "clear"]
        onExited: {
            root.isEnrolled = false
            root.status = "idle"
            root.checkStatus()
        }
    }
}
