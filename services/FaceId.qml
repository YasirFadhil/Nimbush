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
    property bool hasFaceModule: false
    property bool hasFaceDetector: false
    property string status: "idle" // "idle" | "starting" | "scanning" | "detected" | "success" | "unrecognized" | "timeout" | "camera_unavailable" | "not_enrolled"
    property string statusMessage: ""
    property real confidence: 0.0
    property real enrollProgress: 0.0
    property string enrollStepName: ""
    property int enrollStepNumber: 1
    property var availableDevices: ["/dev/video0"]

    readonly property string pythonExec: Quickshell.env("FACEID_PYTHON") || "python3"

    readonly property string helperScript: {
        var home = Quickshell.env("HOME") || ("/home/" + (Quickshell.env("USER") || "user"))
        return home + "/.config/quickshell/scripts/faceid-helper.py"
    }

    readonly property string cameraDevice: (Services.Config && Services.Config.faceIdCameraDevice && Services.Config.faceIdCameraDevice.length > 0)
        ? Services.Config.faceIdCameraDevice
        : "/dev/video0"

    readonly property real maxDistance: (Services.Config && Services.Config.faceIdConfidence > 0)
        ? Services.Config.faceIdConfidence
        : 98.0

    readonly property bool autoUnlock: Services.Config ? Services.Config.faceIdAutoUnlock : true
    readonly property bool canEnroll: isEnabled && hasFaceModule && hasFaceDetector

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

    property bool intentionalStop: false

    function startScan() {
        intentionalStop = false
        if (!isEnabled) {
            status = "idle"
            return
        }
        if (isScanning || verifyProc.running) return
        if (isEnrolling || enrollProc.running) return
        const blocker = root.enrollBlockReason()
        if (blocker.length > 0) {
            root.status = "error"
            root.statusMessage = blocker
            root.scanFailed(blocker)
            return
        }

        status = "starting"
        statusMessage = "Starting Face ID..."
        isScanning = true

        verifyProc.command = [
            root.pythonExec,
            root.helperScript,
            "verify",
            "--camera", root.effectiveCameraDevice(),
            "--timeout", "10.0",
            "--confidence", String(root.maxDistance)
        ]
        verifyProc.running = true
    }

    function resetStatus() {
        intentionalStop = true
        if (verifyProc.running) {
            verifyProc.running = false
        }
        isScanning = false
        status = "idle"
        statusMessage = ""
    }

    function stopScan() {
        intentionalStop = true
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
        const blocker = root.enrollBlockReason()
        if (blocker.length > 0) {
            root.status = "error"
            root.statusMessage = blocker
            root.enrollError(blocker)
            return
        }

        isEnrolling = true
        enrollProgress = 0.0
        enrollStepName = "Frontal"
        enrollStepNumber = 1
        statusMessage = "Preparing camera for enrollment..."

        enrollProc.command = [
            root.pythonExec,
            root.helperScript,
            "enroll",
            "--camera", root.effectiveCameraDevice(),
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
        clearProc.command = [root.pythonExec, root.helperScript, "clear"]
        clearProc.running = true
    }

    function enrollBlockReason() {
        if (!isEnabled) return "Face ID is disabled."
        if (!hasFaceModule) return "OpenCV contrib / cv2.face is missing on this system."
        if (!hasFaceDetector) return "Face detector cascade is not available."
        return ""
    }

    function effectiveCameraDevice() {
        var preferred = root.cameraDevice
        if (preferred && root.availableDevices && root.availableDevices.indexOf(preferred) !== -1) {
            return preferred
        }
        if (preferred && preferred.indexOf("/dev/video") === 0) {
            var preferredSuffix = preferred.replace("/dev/video", "")
            if (preferredSuffix.length > 0 && !isNaN(parseInt(preferredSuffix))) {
                var mapped = "/dev/video" + parseInt(preferredSuffix)
                if (root.availableDevices && root.availableDevices.indexOf(mapped) !== -1) {
                    return mapped
                }
            }
        }
        if (root.availableDevices && root.availableDevices.length > 0) {
            return root.availableDevices[0]
        }
        return preferred || "/dev/video0"
    }

    // ── Status Inspection Process ──────────────────────────────────────────
    Process {
        id: statusProc
        command: [root.pythonExec, root.helperScript, "status"]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length === 0 || !line.startsWith("{")) return
                try {
                    const parsed = JSON.parse(line)
                    root.isEnrolled = Boolean(parsed.enrolled)
                    if (parsed.face_module_available !== undefined) {
                        root.hasFaceModule = Boolean(parsed.face_module_available)
                    }
                    if (parsed.detector_available !== undefined) {
                        root.hasFaceDetector = Boolean(parsed.detector_available)
                    }
                    if (parsed.devices && Array.isArray(parsed.devices)) {
                        root.availableDevices = parsed.devices
                    }
                } catch (e) {
                    console.warn("[FaceId] Failed to parse status JSON:", e)
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length > 0) {
                    console.warn("[FaceId] status stderr:", line)
                }
            }
        }
    }

    // ── Verification Process ───────────────────────────────────────────────
    Process {
        id: verifyProc
        command: [root.pythonExec, root.helperScript, "verify"]

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
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length > 0) {
                    console.warn("[FaceId] verify stderr:", line)
                }
            }
        }

        onExited: (code, status) => {
            root.isScanning = false
            if (root.intentionalStop) {
                root.intentionalStop = false
                root.status = "idle"
                return
            }
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
        command: [root.pythonExec, root.helperScript, "enroll"]

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
        stderr: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.length > 0) {
                    console.warn("[FaceId] enroll stderr:", line)
                    if (root.isEnrolling) {
                        root.status = "error"
                        root.statusMessage = line
                    }
                }
            }
        }

        onExited: (code, status) => {
            root.isEnrolling = false
            if (code !== 0 && !root.isEnrolled) {
                root.status = "error"
                if (!root.statusMessage || root.statusMessage.length === 0) {
                    root.statusMessage = "Enrollment failed with code " + code
                }
                root.enrollError(root.statusMessage)
            }
        }
    }

    // ── Clear Model Process ────────────────────────────────────────────────
    Process {
        id: clearProc
        command: [root.pythonExec, root.helperScript, "clear"]
        onExited: {
            root.isEnrolled = false
            root.status = "idle"
            root.checkStatus()
        }
    }
}
