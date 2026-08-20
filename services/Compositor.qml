pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── Active Compositor Info ────────────────────────────────────────────────
    property string activeCompositor: {
        const niriSock = Quickshell.env("NIRI_SOCKET") || ""
        const hyprSig = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
        const swaySock = Quickshell.env("SWAYSOCK") || ""
        const desktop = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
        const session = (Quickshell.env("DESKTOP_SESSION") || "").toLowerCase()

        if (hyprSig !== "" || desktop.includes("hyprland") || session.includes("hyprland")) return "hyprland"
        if (niriSock !== "" || desktop.includes("niri") || session.includes("niri")) return "niri"
        if (swaySock !== "" || desktop.includes("sway") || session.includes("sway")) return "sway"
        if (desktop.includes("river") || session.includes("river")) return "river"
        if (desktop.includes("wayfire") || session.includes("wayfire")) return "wayfire"
        return "hyprland" // Default fallback
    }

    readonly property string activeDisplayName: {
        switch (activeCompositor) {
            case "hyprland": return "Hyprland"
            case "niri": return "Niri"
            case "sway": return "Sway"
            case "river": return "River"
            case "wayfire": return "Wayfire"
            default: return "Wayland Compositor"
        }
    }

    property string configType: "lua" // "lua", "conf", "kdl"
    property string activeVersion: "Detecting..."
    property int monitorsCount: 1
    property int workspacesCount: 1
    property int windowsCount: 0
    property var monitorsList: []

    // ── Live Options for Hyprland ─────────────────────────────────────────────
    // Visual & Effects
    property bool hyprAnim: true
    property bool hyprBlur: true
    property int hyprBlurSize: 4
    property int hyprBlurPasses: 2
    property bool hyprShadow: true
    property int hyprShadowRange: 4
    property int hyprShadowPower: 3
    property real hyprActiveOpacity: 0.90
    property real hyprInactiveOpacity: 0.95
    property bool hyprDimInactive: false
    property real hyprDimStrength: 0.50

    // Geometry & Layout
    property int hyprRounding: 10
    property int hyprBorderSize: 0
    property int hyprGapsIn: 5
    property int hyprGapsOut: 10
    property string hyprLayout: "scrolling"
    property bool hyprResizeOnBorder: false
    property string hyprBorderColorPreset: "cyan_emerald"

    // Input & Touchpad
    property bool hyprTouchpadNatural: true
    property bool hyprTouchpadTap: true
    property bool hyprTouchpadDwt: true
    property real hyprSensitivity: 0.0

    // Performance & Misc
    property bool hyprDisableLogo: false

    // ── Discovered Compositors & Configs ──────────────────────────────────────
    property var installedCompositors: []
    property var discoveredConfigFiles: []
    property string selectedConfigFile: ""
    property string currentContent: ""
    property string originalContent: ""
    property bool isModified: (currentContent !== originalContent && currentContent.length > 0)
    property bool isLoading: false
    property bool isSaving: false
    property string saveStatus: "idle" // "idle", "saving", "saved", "error"
    property string statusMessage: ""

    readonly property string helperScript: {
        var u = Qt.resolvedUrl("../scripts/compositor-helper.py").toString()
        var p = u.startsWith("file://") ? u.substring(7) : u
        return p.length > 0 ? p : (Quickshell.env("HOME") + "/.config/quickshell/scripts/compositor-helper.py")
    }

    // ── Fast Direct Key Mapping for Hyprland (0ms Latency) ────────────────────
    readonly property var hyprKeyMap: ({
        "blur": "decoration:blur:enabled",
        "blur_size": "decoration:blur:size",
        "blur_passes": "decoration:blur:passes",
        "anim": "animations:enabled",
        "shadow": "decoration:shadow:enabled",
        "shadow_range": "decoration:shadow:range",
        "shadow_power": "decoration:shadow:render_power",
        "rounding": "decoration:rounding",
        "border_size": "general:border_size",
        "gaps_in": "general:gaps_in",
        "gaps_out": "general:gaps_out",
        "active_opacity": "decoration:active_opacity",
        "inactive_opacity": "decoration:inactive_opacity",
        "dim_inactive": "decoration:dim_inactive",
        "dim_strength": "decoration:dim_strength",
        "layout": "general:layout",
        "touchpad_natural": "input:touchpad:natural_scroll",
        "touchpad_tap": "input:touchpad:tap-to-click",
        "touchpad_dwt": "input:touchpad:disable_while_typing",
        "sensitivity": "input:sensitivity",
        "resize_border": "general:resize_on_border",
        "disable_hyprland_logo": "misc:disable_hyprland_logo"
    })

    // Coalesced pending changes for batch & zero-latency execution
    property var _pendingChanges: ({})

    Timer {
        id: batchTimer
        interval: 16 // 60fps coalescing timer
        repeat: false
        onTriggered: root._flushPendingChanges()
    }

    Component.onCompleted: {
        refreshState()
    }

    function refreshState() {
        if (queryProcess.running) return
        queryProcess.running = true
    }

    // ── Direct & Fast Option Application ──────────────────────────────────────
    function setOption(optName, optVal) {
        _pendingChanges[optName] = optVal
        if (!batchTimer.running) {
            batchTimer.restart()
        }
    }

    function _flushPendingChanges() {
        const keys = Object.keys(_pendingChanges)
        if (keys.length === 0) return

        if (activeCompositor === "hyprland") {
            // Build batch of hyprctl keyword calls into a single fast shell command
            let cmdParts = []
            for (let i = 0; i < keys.length; i++) {
                const k = keys[i]
                const v = _pendingChanges[k]
                const hyprKey = hyprKeyMap[k]
                if (hyprKey) {
                    let formattedVal = String(v)
                    if (typeof v === "boolean") formattedVal = v ? "1" : "0"
                    cmdParts.push("hyprctl keyword " + hyprKey + " " + formattedVal)
                }
            }
            _pendingChanges = {}

            if (cmdParts.length > 0) {
                fastHyprProc.command = ["sh", "-c", cmdParts.join(" && ")]
                fastHyprProc.running = true
            }
        } else {
            // Fallback to helper script for other compositors
            for (let i = 0; i < keys.length; i++) {
                const k = keys[i]
                const v = _pendingChanges[k]
                applyProcess.command = [helperScript, "set", k, String(v)]
                applyProcess.running = true
            }
            _pendingChanges = {}
        }
    }

    Process {
        id: fastHyprProc
    }

    Process {
        id: applyProcess
    }

    // ── Live Setting Updates & Helpers ────────────────────────────────────────
    function setHyprOption(optKey, optVal) {
        setOption(optKey, optVal)
    }

    function toggleHyprAnim() {
        hyprAnim = !hyprAnim
        setOption("anim", hyprAnim)
    }

    function toggleHyprBlur() {
        hyprBlur = !hyprBlur
        setOption("blur", hyprBlur)
    }

    function setHyprBlurSize(val) {
        hyprBlurSize = val
        setOption("blur_size", val)
    }

    function setHyprBlurPasses(val) {
        hyprBlurPasses = val
        setOption("blur_passes", val)
    }

    function toggleHyprShadow() {
        hyprShadow = !hyprShadow
        setOption("shadow", hyprShadow)
    }

    function setHyprShadowRange(val) {
        hyprShadowRange = val
        setOption("shadow_range", val)
    }

    function setHyprShadowPower(val) {
        hyprShadowPower = val
        setOption("shadow_power", val)
    }

    function setHyprActiveOpacity(val) {
        hyprActiveOpacity = val
        setOption("active_opacity", val)
    }

    function setHyprInactiveOpacity(val) {
        hyprInactiveOpacity = val
        setOption("inactive_opacity", val)
    }

    function toggleHyprDimInactive() {
        hyprDimInactive = !hyprDimInactive
        setOption("dim_inactive", hyprDimInactive)
    }

    function setHyprDimStrength(val) {
        hyprDimStrength = val
        setOption("dim_strength", val)
    }

    function setHyprRounding(val) {
        hyprRounding = val
        setOption("rounding", val)
    }

    function setHyprBorderSize(val) {
        hyprBorderSize = val
        setOption("border_size", val)
    }

    function setHyprGapsIn(val) {
        hyprGapsIn = val
        setOption("gaps_in", val)
    }

    function setHyprGapsOut(val) {
        hyprGapsOut = val
        setOption("gaps_out", val)
    }

    function setHyprLayout(val) {
        hyprLayout = val
        setOption("layout", val)
    }

    function toggleHyprTouchpadNatural() {
        hyprTouchpadNatural = !hyprTouchpadNatural
        setOption("touchpad_natural", hyprTouchpadNatural)
    }

    function toggleHyprTouchpadTap() {
        hyprTouchpadTap = !hyprTouchpadTap
        setOption("touchpad_tap", hyprTouchpadTap)
    }

    function toggleHyprTouchpadDwt() {
        hyprTouchpadDwt = !hyprTouchpadDwt
        setOption("touchpad_dwt", hyprTouchpadDwt)
    }

    function setHyprSensitivity(val) {
        hyprSensitivity = val
        setOption("sensitivity", val)
    }

    function toggleHyprResizeBorder() {
        hyprResizeOnBorder = !hyprResizeOnBorder
        setOption("resize_border", hyprResizeOnBorder)
    }

    function toggleHyprDisableLogo() {
        hyprDisableLogo = !hyprDisableLogo
        setOption("disable_hyprland_logo", hyprDisableLogo)
    }

    function setBorderColorPreset(presetId, gradientStr) {
        hyprBorderColorPreset = presetId
        if (configType === "lua") {
            setOption("border_color_preset", gradientStr)
        }
    }

    // ── Config File Management ────────────────────────────────────────────────
    function loadFile(filePath) {
        if (!filePath) return
        selectedConfigFile = filePath
        isLoading = true
        saveStatus = "idle"
        statusMessage = "Loading " + filePath + "..."
        loadFileProc.targetPath = filePath
        loadFileProc.accumulated = ""
        loadFileProc.command = ["cat", filePath]
        loadFileProc.running = true
    }

    function saveCurrentFile(content) {
        if (!selectedConfigFile) return
        isSaving = true
        saveStatus = "saving"
        statusMessage = "Checking syntax & saving config..."
        currentContent = content

        try {
            const b64 = Qt.btoa(unescape(encodeURIComponent(content)))
            saveFileProc.targetPath = selectedConfigFile
            saveFileProc.outText = ""
            saveFileProc.command = [helperScript, "save-b64", selectedConfigFile, b64]
            saveFileProc.running = true
        } catch (e) {
            saveFileProc.targetPath = selectedConfigFile
            saveFileProc.outText = ""
            saveFileProc.command = [helperScript, "save", selectedConfigFile]
            saveFileProc.running = true
        }
    }

    function openExternalEditor(filePath) {
        const target = filePath || selectedConfigFile
        if (!target) return
        openEditorProc.command = [
            "sh", "-c",
            "if command -v kitty >/dev/null 2>&1 && command -v nvim >/dev/null 2>&1; then " +
            "kitty -e nvim \"" + target + "\" & " +
            "elif command -v kate >/dev/null 2>&1; then kate \"" + target + "\" & " +
            "elif command -v gedit >/dev/null 2>&1; then gedit \"" + target + "\" & " +
            "elif command -v code >/dev/null 2>&1; then code \"" + target + "\" & " +
            "else xdg-open \"" + target + "\" & fi"
        ]
        openEditorProc.running = true
    }

    function reloadCompositor() {
        saveStatus = "saving"
        statusMessage = "Reloading " + activeDisplayName + "..."
        reloadProc.command = [helperScript, "reload"]
        reloadProc.running = true
    }

    // ── Sub-processes ─────────────────────────────────────────────────────────

    Process {
        id: openEditorProc
    }

    Process {
        id: reloadProc
        property string outData: ""
        stdout: SplitParser {
            onRead: chunk => reloadProc.outData += chunk
        }
        onExited: (exitCode) => {
            try {
                const res = JSON.parse(reloadProc.outData.trim())
                if (res && res.ok) {
                    root.saveStatus = "saved"
                    root.statusMessage = root.activeDisplayName + " reloaded successfully!"
                    root.refreshState()
                } else {
                    root.saveStatus = "error"
                    root.statusMessage = res && res.error ? res.error : "Failed to reload compositor"
                }
            } catch (e) {
                if (exitCode === 0) {
                    root.saveStatus = "saved"
                    root.statusMessage = root.activeDisplayName + " reloaded successfully!"
                } else {
                    root.saveStatus = "error"
                    root.statusMessage = "Failed to reload " + root.activeDisplayName
                }
            }
            reloadProc.outData = ""
        }
    }

    Process {
        id: loadFileProc
        property string targetPath: ""
        property string accumulated: ""
        stdout: SplitParser {
            onRead: chunk => {
                loadFileProc.accumulated += chunk
            }
        }
        onExited: {
            root.isLoading = false
            root.currentContent = loadFileProc.accumulated
            root.originalContent = loadFileProc.accumulated
            root.saveStatus = "idle"
            root.statusMessage = "Loaded " + loadFileProc.targetPath
        }
    }

    Process {
        id: saveFileProc
        property string targetPath: ""
        property string outText: ""

        stdout: SplitParser {
            onRead: chunk => {
                saveFileProc.outText += chunk
            }
        }
        onExited: (exitCode) => {
            root.isSaving = false
            try {
                const res = JSON.parse(saveFileProc.outText.trim())
                if (res && res.ok) {
                    root.originalContent = root.currentContent
                    root.saveStatus = "saved"
                    root.statusMessage = "Saved successfully! Backup created: " + (res.backup ? res.backup.split("/").pop() : "")
                    root.reloadCompositor()
                } else if (res && res.syntax_error) {
                    root.saveStatus = "error"
                    root.statusMessage = res.error
                } else {
                    root.saveStatus = "error"
                    root.statusMessage = "Error: " + (res && res.error ? res.error : saveFileProc.outText.trim())
                }
            } catch (e) {
                if (exitCode === 0 && saveFileProc.outText.indexOf("ok") !== -1) {
                    root.originalContent = root.currentContent
                    root.saveStatus = "saved"
                    root.statusMessage = "Saved successfully!"
                    root.reloadCompositor()
                } else {
                    root.saveStatus = "error"
                    root.statusMessage = "Error saving file: " + saveFileProc.outText.trim()
                }
            }
            saveFileProc.outText = ""
        }
    }

    Process {
        id: queryProcess
        property string qOutput: ""
        command: [root.helperScript, "query"]
        stdout: SplitParser {
            onRead: chunk => {
                queryProcess.qOutput += chunk
            }
        }
        onExited: {
            try {
                const data = JSON.parse(queryProcess.qOutput.trim())
                if (data) {
                    if (data.version) root.activeVersion = data.version
                    if (data.configType) root.configType = data.configType
                    if (data.blur !== undefined) root.hyprBlur = data.blur
                    if (data.blur_size !== undefined) root.hyprBlurSize = data.blur_size
                    if (data.blur_passes !== undefined) root.hyprBlurPasses = data.blur_passes
                    if (data.anim !== undefined) root.hyprAnim = data.anim
                    if (data.shadow !== undefined) root.hyprShadow = data.shadow
                    if (data.shadow_range !== undefined) root.hyprShadowRange = data.shadow_range
                    if (data.shadow_power !== undefined) root.hyprShadowPower = data.shadow_power
                    if (data.rounding !== undefined) root.hyprRounding = data.rounding
                    if (data.border_size !== undefined) root.hyprBorderSize = data.border_size
                    if (data.gaps_in !== undefined) root.hyprGapsIn = data.gaps_in
                    if (data.gaps_out !== undefined) root.hyprGapsOut = data.gaps_out
                    if (data.active_opacity !== undefined) root.hyprActiveOpacity = data.active_opacity
                    if (data.inactive_opacity !== undefined) root.hyprInactiveOpacity = data.inactive_opacity
                    if (data.dim_inactive !== undefined) root.hyprDimInactive = data.dim_inactive
                    if (data.dim_strength !== undefined) root.hyprDimStrength = data.dim_strength
                    if (data.layout !== undefined) root.hyprLayout = data.layout
                    if (data.touchpad_natural !== undefined) root.hyprTouchpadNatural = data.touchpad_natural
                    if (data.touchpad_tap !== undefined) root.hyprTouchpadTap = data.touchpad_tap
                    if (data.touchpad_dwt !== undefined) root.hyprTouchpadDwt = data.touchpad_dwt
                    if (data.sensitivity !== undefined) root.hyprSensitivity = data.sensitivity
                    if (data.resize_border !== undefined) root.hyprResizeOnBorder = data.resize_border
                    if (data.disable_hyprland_logo !== undefined) root.hyprDisableLogo = data.disable_hyprland_logo
                    if (data.monitorsCount !== undefined) root.monitorsCount = data.monitorsCount
                    if (data.monitors !== undefined) root.monitorsList = data.monitors
                    if (data.workspacesCount !== undefined) root.workspacesCount = data.workspacesCount
                    if (data.windowsCount !== undefined) root.windowsCount = data.windowsCount
                    if (data.installedCompositors) root.installedCompositors = data.installedCompositors
                    if (data.discoveredConfigFiles) {
                        root.discoveredConfigFiles = data.discoveredConfigFiles
                        if (!root.selectedConfigFile && data.discoveredConfigFiles.length > 0) {
                            root.loadFile(data.discoveredConfigFiles[0].path)
                        }
                    }
                }
            } catch (e) {}
            queryProcess.qOutput = ""
        }
    }
}