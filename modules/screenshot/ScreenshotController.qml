import QtQuick
import Quickshell
import Quickshell.Io
import "../../services" as Services

Scope {
    id: controller

    // State machine: "idle" | "capturing" | "selecting" | "processing" | "completed" | "error" | "cancelled"
    property string state: "idle"
    property bool overlayVisible: false
    readonly property bool busy: state === "capturing" || state === "selecting" || state === "processing"

    // Session & captured outputs
    property string sessionDir: ""
    // Map of screenName -> { name, path, width, height }
    property var outputsMap: ({})
    property string activeScreenName: ""
    property real activeScreenWidth: 0
    property real activeScreenHeight: 0

    // Selection coordinates (logical screen coordinates on activeScreenName)
    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0
    property bool isDragging: false
    property bool hasSelection: false

    // Normalized selection rectangle
    readonly property real selX: Math.min(startX, endX)
    readonly property real selY: Math.min(startY, endY)
    readonly property real selW: Math.abs(endX - startX)
    readonly property real selH: Math.abs(endY - startY)
    readonly property bool isValidSelection: hasSelection && selW >= 2 && selH >= 2

    // Pointer state (default ON, matching Niri's frozen-cursor screenshot behavior)
    property bool includePointer: true
    property real pointerX: -1
    property real pointerY: -1
    property bool hasPointerPos: false

    // Internal buffers for Process output
    property string _captureStdout: ""
    property string _captureStderr: ""
    property string _processStdout: ""
    property string _processStderr: ""

    readonly property string backendScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/screenshot-process.py"

    function resetSelection() {
        startX = 0
        startY = 0
        endX = 0
        endY = 0
        isDragging = false
        hasSelection = false
    }

    function beginDrag(screenName, screenW, screenH, x, y) {
        if (state !== "selecting") return
        activeScreenName = screenName
        activeScreenWidth = screenW
        activeScreenHeight = screenH
        startX = Math.max(0, Math.min(x, screenW))
        startY = Math.max(0, Math.min(y, screenH))
        endX = startX
        endY = startY
        isDragging = true
        hasSelection = true
    }

    function updateDrag(x, y) {
        if (!isDragging || state !== "selecting") return
        endX = Math.max(0, Math.min(x, activeScreenWidth))
        endY = Math.max(0, Math.min(y, activeScreenHeight))
    }

    function endDrag(x, y) {
        if (!isDragging || state !== "selecting") return
        endX = Math.max(0, Math.min(x, activeScreenWidth))
        endY = Math.max(0, Math.min(y, activeScreenHeight))
        isDragging = false
        if (selW < 2 || selH < 2) {
            hasSelection = false
        }
    }

    function updatePointer(screenName, x, y) {
        if (state !== "selecting") return
        if (activeScreenName === "" || activeScreenName === screenName || !hasSelection) {
            if (!hasSelection) {
                activeScreenName = screenName
            }
        }
        if (screenName === activeScreenName || !hasSelection) {
            pointerX = x
            pointerY = y
            hasPointerPos = true
        }
    }

    function toggleIncludePointer() {
        if (state !== "selecting") return
        includePointer = !includePointer
    }

    function startSession() {
        if (state !== "idle") return
        if (Services.OverlayManager && (Services.OverlayManager.isLocked || Services.OverlayManager.isWizardActive)) {
            return
        }

        if (Services.OverlayManager) {
            Services.OverlayManager.closeAllExcept("screenshot")
        }

        resetSelection()
        includePointer = true
        hasPointerPos = false
        pointerX = -1
        pointerY = -1
        activeScreenName = ""
        activeScreenWidth = 0
        activeScreenHeight = 0
        sessionDir = ""
        outputsMap = ({})
        _captureStdout = ""
        _captureStderr = ""

        state = "capturing"
        captureProc.running = true
    }

    function cancel() {
        if (state === "idle" || state === "processing") return
        const dirToClean = sessionDir
        state = "cancelled"
        overlayVisible = false
        resetSelection()

        if (dirToClean !== "") {
            cleanupProc.command = ["python3", backendScript, "cleanup", "--session-dir", dirToClean]
            cleanupProc.running = true
        }
        sessionDir = ""
        outputsMap = ({})
        state = "idle"
    }

    function confirm(action) {
        if (state !== "selecting" || !isValidSelection) return

        let outInfo = outputsMap[activeScreenName]
        if (!outInfo) {
            const keys = Object.keys(outputsMap)
            if (keys.length > 0) outInfo = outputsMap[keys[0]]
        }
        if (!outInfo) {
            cancel()
            return
        }

        const logicalW = activeScreenWidth > 0 ? activeScreenWidth : outInfo.width
        const logicalH = activeScreenHeight > 0 ? activeScreenHeight : outInfo.height
        const scaleX = outInfo.width / logicalW
        const scaleY = outInfo.height / logicalH

        const cropX = Math.max(0, Math.min(Math.round(selX * scaleX), outInfo.width - 1))
        const cropY = Math.max(0, Math.min(Math.round(selY * scaleY), outInfo.height - 1))
        const cropW = Math.max(1, Math.min(Math.round(selW * scaleX), outInfo.width - cropX))
        const cropH = Math.max(1, Math.min(Math.round(selH * scaleY), outInfo.height - cropY))

        const srcPath = (includePointer && outInfo.cursorPath) ? outInfo.cursorPath : outInfo.path
        const cmd = [
            "python3", backendScript, "process",
            "--source", srcPath,
            "--session-dir", sessionDir,
            "--x", String(cropX),
            "--y", String(cropY),
            "--w", String(cropW),
            "--h", String(cropH),
            "--action", action || "copy"
        ]

        state = "processing"
        overlayVisible = false
        _processStdout = ""
        _processStderr = ""
        processProc.command = cmd
        processProc.running = true
    }

    function imageForScreen(screenName) {
        const entry = outputsMap[screenName] || outputsMap["full"]
        if (!entry) return ""
        return (includePointer && entry.cursorPath) ? entry.cursorPath : (entry.path || "")
    }

    Process {
        id: captureProc
        command: ["python3", controller.backendScript, "capture"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { controller._captureStdout += data }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => { controller._captureStderr += data }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("[Screenshot] Capture failed:", controller._captureStderr)
                controller.state = "error"
                controller.overlayVisible = false
                controller.state = "idle"
                return
            }
            try {
                const payload = JSON.parse(controller._captureStdout.trim())
                if (payload.error || !payload.outputs || payload.outputs.length === 0) {
                    console.warn("[Screenshot] Capture payload error:", payload.error)
                    controller.state = "idle"
                    return
                }
                const map = {}
                for (let i = 0; i < payload.outputs.length; i++) {
                    const o = payload.outputs[i]
                    map[o.name] = o
                }
                controller.sessionDir = payload.sessionDir || ""
                controller.outputsMap = map
                controller.state = "selecting"
                controller.overlayVisible = true
            } catch (e) {
                console.warn("[Screenshot] Failed to parse capture JSON:", e)
                controller.state = "idle"
            }
        }
    }

    Process {
        id: processProc
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { controller._processStdout += data }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: data => { controller._processStderr += data }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("[Screenshot] Process failed:", controller._processStderr)
                controller.state = "error"
            } else {
                controller.state = "completed"
            }
            controller.sessionDir = ""
            controller.outputsMap = ({})
            controller.resetSelection()
            controller.state = "idle"
        }
    }

    Process {
        id: cleanupProc
    }
}
