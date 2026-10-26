pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Item {
    id: root

    // ── State & Properties ──
    property var kdeDevices: []
    readonly property var defaultDevice: kdeDevices.length > 0 ? kdeDevices[0] : null
    readonly property bool hasKdeDevice: kdeDevices.length > 0
    // Availability is unknown until checkLocalSendProc finishes.
    property bool hasLocalSend: false
    property string localSendExecutable: ""

    // Live Transfer Feedback State
    // "idle" | "preparing" | "handoff" | "sending" | "success" | "error"
    property string transferState: "idle"
    // "" | "kdeconnect" | "localsend"
    property string transferBackend: ""
    property string transferTargetName: ""
    property int transferFileCount: 0
    property string transferPreviewUrl: ""
    property string transferMessage: ""

    readonly property string kdeHelperPath: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/scripts/kdeconnect-helper.py"

    // ── Timer for device polling ──
    Timer {
        id: pollTimer
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refreshKdeDevices()
    }

    // Timer to reset transfer state back to idle
    Timer {
        id: resetStateTimer
        interval: 2600
        repeat: false
        onTriggered: {
            root.transferState = "idle"
            root.transferBackend = ""
            root.transferTargetName = ""
            root.transferFileCount = 0
            root.transferPreviewUrl = ""
            root.transferMessage = ""
        }
    }

    // ── Process to list KDE Connect devices ──
    Process {
        id: listDevicesProc
        command: ["python3", root.kdeHelperPath, "devices"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (Array.isArray(parsed)) {
                        root.kdeDevices = parsed
                    }
                } catch (e) {
                    console.warn("DeviceShare: failed to parse devices JSON:", e)
                }
            }
        }
    }

    // ── Process to check LocalSend binary availability ──
    Process {
        id: checkLocalSendProc
        // `which A B` can fail if either name is missing. Check candidates
        // independently and return the first executable that actually exists.
        command: ["sh", "-c", "command -v localsend_app || command -v localsend || exit 1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const executable = data.trim()
                if (executable.length > 0) {
                    root.localSendExecutable = executable
                    root.hasLocalSend = true
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.localSendExecutable.length === 0) {
                root.hasLocalSend = false
            }
        }
    }

    // ── Process to share files via KDE Connect ──
    Process {
        id: shareKdeProc
        stdout: SplitParser {
            onRead: data => {
                try {
                    const res = JSON.parse(data.trim())
                    if (res.status === "ok") {
                        root.transferState = "success"
                        root.transferMessage = "Sent to " + root.transferTargetName
                        if (Services.SoundFeedback && Services.SoundFeedback.playDeviceAdded) {
                            Services.SoundFeedback.playDeviceAdded()
                        }
                    } else {
                        root.transferState = "error"
                        root.transferMessage = res.message || "Failed to send"
                    }
                } catch (e) {
                    root.transferState = "success"
                    root.transferMessage = "Dispatched"
                }
                resetStateTimer.restart()
            }
        }
    }

    // ── Process to launch LocalSend with files ──
    Process {
        id: shareLocalSendProc
        onExited: (code, status) => {
            // This process is a short-lived shell wrapper that launches
            // LocalSend in the background. Its exit status only confirms the
            // handoff was launched, not that a file transfer completed.
            if (code === 0) {
                root.transferState = "handoff"
                root.transferMessage = "Continue in LocalSend"
                if (Services.SoundFeedback && Services.SoundFeedback.playDeviceAdded) {
                    Services.SoundFeedback.playDeviceAdded()
                }
                resetStateTimer.interval = 4500
            } else {
                root.transferState = "error"
                root.transferMessage = "Could not open LocalSend"
                resetStateTimer.interval = 3500
            }
            resetStateTimer.restart()
        }
    }

    // ── Public API Methods ──

    function refreshKdeDevices() {
        if (!listDevicesProc.running) {
            listDevicesProc.running = true
        }
    }

    function cleanPaths(urls) {
        if (!urls) return []
        const res = []
        for (let i = 0; i < urls.length; i++) {
            let u = urls[i].toString()
            if (u.startsWith("file://")) {
                u = u.substring(7)
            }
            try {
                u = decodeURIComponent(u)
            } catch (e) {}
            if (u.length > 0) {
                res.push(u)
            }
        }
        return res
    }

    function extractPreview(urls) {
        if (!urls || urls.length === 0) return ""
        let first = urls[0].toString().trim()
        if (first.startsWith("file://")) first = first.substring(7)
        try { first = decodeURIComponent(first) } catch (e) {}
        const lower = first.toLowerCase()
        if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".webp") || lower.endsWith(".gif") || lower.endsWith(".svg") ||
            lower.endsWith(".ico") || lower.endsWith(".bmp")) {
            return "file://" + first
        }
        return ""
    }

    function sendKdeConnect(deviceId, urls) {
        const paths = cleanPaths(urls)
        if (paths.length === 0) return false

        const targetDev = kdeDevices.find(d => d.id === deviceId) || defaultDevice
        const devId = targetDev ? targetDev.id : (deviceId || "")
        const devName = targetDev ? targetDev.name : "Device"

        resetStateTimer.interval = 2600
        root.transferState = "sending"
        root.transferBackend = "kdeconnect"
        root.transferTargetName = devName
        root.transferFileCount = paths.length
        root.transferPreviewUrl = extractPreview(urls)
        root.transferMessage = "Sending to " + devName + "..."

        shareKdeProc.command = ["python3", root.kdeHelperPath, "share", "--device", devId, "--files"].concat(paths)
        shareKdeProc.running = true
        return true
    }

    function sendLocalSend(urls) {
        const paths = cleanPaths(urls)
        if (paths.length === 0) return false

        if (!root.hasLocalSend || root.localSendExecutable.length === 0) {
            root.transferState = "error"
            root.transferBackend = "localsend"
            root.transferTargetName = "LocalSend"
            root.transferFileCount = paths.length
            root.transferPreviewUrl = extractPreview(urls)
            root.transferMessage = "LocalSend is not available"
            resetStateTimer.interval = 3500
            resetStateTimer.restart()
            return false
        }

        resetStateTimer.stop()
        // Stage 1: preparing — show a truthful handoff state, never fake transfer progress.
        root.transferState = "preparing"
        root.transferBackend = "localsend"
        root.transferTargetName = "LocalSend"
        root.transferFileCount = paths.length
        root.transferPreviewUrl = extractPreview(urls)
        root.transferMessage = "Preparing LocalSend…"

        // Use the detected executable (localsend_app or localsend). A short-lived
        // shell launches it detached so its UI process lifetime does not hold the
        // Dynamic Island in the preparing state until the app is closed.
        shareLocalSendProc.command = [
            "sh", "-c",
            'app="$1"; shift; "$app" "$@" </dev/null >/dev/null 2>&1 &',
            "sh", root.localSendExecutable
        ].concat(paths)
        shareLocalSendProc.running = true
        return true
    }

    function sendAuto(urls) {
        // As requested by user: prompt/choice by default or send to connected phone if available
        if (root.hasKdeDevice) {
            return sendKdeConnect(root.defaultDevice.id, urls)
        } else {
            return sendLocalSend(urls)
        }
    }
}
