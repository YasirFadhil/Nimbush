pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

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
    property string hyprLayout: "dwindle"
    property bool hyprResizeOnBorder: false
    property string hyprBorderColorPreset: "cyan_emerald"

    // Input & Touchpad
    property bool hyprTouchpadNatural: true
    property bool hyprTouchpadTap: true
    property bool hyprTouchpadDwt: true
    property real hyprSensitivity: 0.0
    property int hyprFollowMouse: 1
    property bool hyprWorkspaceSwipe: true
    property bool hyprSwipeInvert: false

    // Performance, Gaming & Power
    property bool hyprDisableLogo: false
    property bool hyprVFR: true
    property bool hyprAllowTearing: false
    property bool hyprSmartGaps: false
    property string activePreset: "custom"

    // ── Keybindings from Compositor Config ────────────────────────────────────
    property var keybindsList: []
    property bool isLoadingBinds: false
    property string keybindStatus: ""
    property string keybindError: ""

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

    // ── Fast Direct Key Mapping for Hyprland (.conf fallback) ─────────────────
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
        "follow_mouse": "input:follow_mouse",
        "workspace_swipe": "gestures:workspace_swipe",
        "workspace_swipe_invert": "gestures:workspace_swipe_invert",
        "resize_border": "general:resize_on_border",
        "disable_hyprland_logo": "misc:disable_hyprland_logo",
        "vfr": "misc:vfr",
        "allow_tearing": "general:allow_tearing",
        "smart_gaps": "dwindle:no_gaps_when_only"
    })

    // ── Lua Config Builder for Hyprland 0.56+ (hl.config) ──────────────────────
    function buildLuaConfig(changes) {
        let decor = {}
        let general = {}
        let anim = {}
        let input = {}
        let misc = {}
        let gestures = {}

        for (let k in changes) {
            let v = changes[k]
            switch (k) {
                case "blur":
                    if (!decor.blur) decor.blur = {}
                    decor.blur.enabled = Boolean(v)
                    break
                case "blur_size":
                    if (!decor.blur) decor.blur = {}
                    decor.blur.size = Math.round(Number(v))
                    break
                case "blur_passes":
                    if (!decor.blur) decor.blur = {}
                    decor.blur.passes = Math.round(Number(v))
                    break
                case "shadow":
                    if (!decor.shadow) decor.shadow = {}
                    decor.shadow.enabled = Boolean(v)
                    break
                case "shadow_range":
                    if (!decor.shadow) decor.shadow = {}
                    decor.shadow.range = Math.round(Number(v))
                    break
                case "shadow_power":
                    if (!decor.shadow) decor.shadow = {}
                    decor.shadow.render_power = Math.round(Number(v))
                    break
                case "rounding":
                    decor.rounding = Math.round(Number(v))
                    break
                case "active_opacity":
                    decor.active_opacity = Number(Number(v).toFixed(2))
                    break
                case "inactive_opacity":
                    decor.inactive_opacity = Number(Number(v).toFixed(2))
                    break
                case "dim_inactive":
                    decor.dim_inactive = Boolean(v)
                    break
                case "dim_strength":
                    decor.dim_strength = Number(Number(v).toFixed(2))
                    break
                case "anim":
                    anim.enabled = Boolean(v)
                    break
                case "border_size":
                    general.border_size = Math.round(Number(v))
                    break
                case "gaps_in":
                    general.gaps_in = Math.round(Number(v))
                    break
                case "gaps_out":
                    general.gaps_out = Math.round(Number(v))
                    break
                case "layout":
                    general.layout = String(v)
                    break
                case "resize_border":
                    general.resize_on_border = Boolean(v)
                    break
                case "touchpad_natural":
                    if (!input.touchpad) input.touchpad = {}
                    input.touchpad.natural_scroll = Boolean(v)
                    break
                case "touchpad_tap":
                    if (!input.touchpad) input.touchpad = {}
                    input.touchpad.tap_to_click = Boolean(v)
                    break
                case "touchpad_dwt":
                    if (!input.touchpad) input.touchpad = {}
                    input.touchpad.disable_while_typing = Boolean(v)
                    break
                case "sensitivity":
                    input.sensitivity = Number(Number(v).toFixed(2))
                    break
                case "disable_hyprland_logo":
                    misc.disable_hyprland_logo = Boolean(v)
                    break
                case "vfr":
                    misc.vfr = Boolean(v)
                    break
                case "allow_tearing":
                    general.allow_tearing = Boolean(v)
                    break
                case "smart_gaps":
                    general.no_gaps_when_only = Boolean(v) ? 1 : 0
                    break
                case "follow_mouse":
                    input.follow_mouse = Math.round(Number(v))
                    break
                case "workspace_swipe":
                    gestures.workspace_swipe = Boolean(v)
                    break
                case "workspace_swipe_invert":
                    gestures.workspace_swipe_invert = Boolean(v)
                    break
                case "border_color_preset":
                    if (!general.col) general.col = {}
                    general.col.active_border = v
                    break
            }
        }

        function toLua(val) {
            if (typeof val === "boolean") return val ? "true" : "false"
            if (typeof val === "number") return String(val)
            if (typeof val === "string") return '"' + val.replace(/"/g, '\\"') + '"'
            if (typeof val === "object" && val !== null) {
                let parts = []
                for (let prop in val) {
                    parts.push(prop + " = " + toLua(val[prop]))
                }
                return "{ " + parts.join(", ") + " }"
            }
            return "nil"
        }

        let rootTable = {}
        if (Object.keys(decor).length > 0) rootTable.decoration = decor
        if (Object.keys(general).length > 0) rootTable.general = general
        if (Object.keys(anim).length > 0) rootTable.animations = anim
        if (Object.keys(input).length > 0) rootTable.input = input
        if (Object.keys(misc).length > 0) rootTable.misc = misc
        if (Object.keys(gestures).length > 0) rootTable.gestures = gestures

        if (Object.keys(rootTable).length === 0) return ""
        return "hl.config(" + toLua(rootTable) + ")"
    }

    // Coalesced pending changes for batch & zero-latency execution
    property var _pendingChanges: ({})
    property bool _isApplying: false

    Timer {
        id: batchTimer
        interval: 16 // 60fps coalescing timer
        repeat: false
        onTriggered: root._flushPendingChanges()
    }

    Component.onCompleted: {
        refreshState()
        loadKeybinds()
    }

    function refreshState() {
        if (queryProcess.running) return
        queryProcess.running = true
    }

    // ── Direct & Fast Option Application ──────────────────────────────────────
    function setOption(optName, optVal) {
        _pendingChanges[optName] = optVal
        if (!_isApplying) {
            if (!batchTimer.running) {
                batchTimer.restart()
            }
        }
    }

    function _flushPendingChanges() {
        if (_isApplying) return
        const keys = Object.keys(_pendingChanges)
        if (keys.length === 0) return

        const currentChanges = Object.assign({}, _pendingChanges)
        _pendingChanges = {}
        _isApplying = true

        if (activeCompositor === "hyprland") {
            // Save options to configuration file asynchronously
            saveOptionsProc.command = [helperScript, "options-apply", "--changes", JSON.stringify(currentChanges)]
            saveOptionsProc.running = true

            if (configType === "lua") {
                const luaCode = buildLuaConfig(currentChanges)
                if (luaCode.length > 0) {
                    fastHyprProc.command = ["hyprctl", "eval", luaCode]
                    fastHyprProc.running = true
                    return
                }
            } else {
                let cmdParts = []
                for (let i = 0; i < keys.length; i++) {
                    const k = keys[i]
                    const v = currentChanges[k]
                    const hyprKey = hyprKeyMap[k]
                    if (hyprKey) {
                        let formattedVal = String(v)
                        if (typeof v === "boolean") formattedVal = v ? "1" : "0"
                        cmdParts.push("keyword " + hyprKey + " " + formattedVal)
                    }
                }
                if (cmdParts.length > 0) {
                    fastHyprProc.command = ["hyprctl", "--batch", cmdParts.join(" ; ")]
                    fastHyprProc.running = true
                    return
                }
            }
            _isApplying = false
        } else {
            // Fallback to helper script for other compositors
            const firstKey = keys[0]
            const firstVal = currentChanges[firstKey]
            delete currentChanges[firstKey]
            _pendingChanges = Object.assign(currentChanges, _pendingChanges)

            applyProcess.command = [helperScript, "set", firstKey, String(firstVal)]
            applyProcess.running = true
        }
    }

    Process {
        id: saveOptionsProc
    }

    Process {
        id: fastHyprProc
        onExited: {
            root._isApplying = false
            if (Object.keys(root._pendingChanges).length > 0) {
                root._flushPendingChanges()
            }
        }
    }

    Process {
        id: applyProcess
        onExited: {
            root._isApplying = false
            if (Object.keys(root._pendingChanges).length > 0) {
                root._flushPendingChanges()
            }
        }
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
        hyprBlurSize = Math.round(Number(val))
        setOption("blur_size", hyprBlurSize)
    }

    function setHyprBlurPasses(val) {
        hyprBlurPasses = Math.round(Number(val))
        setOption("blur_passes", hyprBlurPasses)
    }

    function toggleHyprShadow() {
        hyprShadow = !hyprShadow
        setOption("shadow", hyprShadow)
    }

    function setHyprShadowRange(val) {
        hyprShadowRange = Math.round(Number(val))
        setOption("shadow_range", hyprShadowRange)
    }

    function setHyprShadowPower(val) {
        hyprShadowPower = Math.round(Number(val))
        setOption("shadow_power", hyprShadowPower)
    }

    function setHyprActiveOpacity(val) {
        hyprActiveOpacity = Number(Number(val).toFixed(2))
        setOption("active_opacity", hyprActiveOpacity)
    }

    function setHyprInactiveOpacity(val) {
        hyprInactiveOpacity = Number(Number(val).toFixed(2))
        setOption("inactive_opacity", hyprInactiveOpacity)
    }

    function toggleHyprDimInactive() {
        hyprDimInactive = !hyprDimInactive
        setOption("dim_inactive", hyprDimInactive)
    }

    function setHyprDimStrength(val) {
        hyprDimStrength = Number(Number(val).toFixed(2))
        setOption("dim_strength", hyprDimStrength)
    }

    function setHyprRounding(val) {
        hyprRounding = Math.round(Number(val))
        setOption("rounding", hyprRounding)
    }

    function setHyprBorderSize(val) {
        hyprBorderSize = Math.round(Number(val))
        setOption("border_size", hyprBorderSize)
    }

    function setHyprGapsIn(val) {
        hyprGapsIn = Math.round(Number(val))
        setOption("gaps_in", hyprGapsIn)
    }

    function setHyprGapsOut(val) {
        hyprGapsOut = Math.round(Number(val))
        setOption("gaps_out", hyprGapsOut)
    }

    function setHyprLayout(val) {
        hyprLayout = String(val)
        setOption("layout", hyprLayout)
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
        hyprSensitivity = Number(Number(val).toFixed(2))
        setOption("sensitivity", hyprSensitivity)
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

    function toggleHyprVFR() {
        hyprVFR = !hyprVFR
        setOption("vfr", hyprVFR)
    }

    function toggleHyprTearing() {
        hyprAllowTearing = !hyprAllowTearing
        setOption("allow_tearing", hyprAllowTearing)
    }

    function toggleHyprSmartGaps() {
        hyprSmartGaps = !hyprSmartGaps
        setOption("smart_gaps", hyprSmartGaps)
    }

    function setHyprFollowMouse(val) {
        hyprFollowMouse = Math.round(Number(val))
        setOption("follow_mouse", hyprFollowMouse)
    }

    function toggleHyprWorkspaceSwipe() {
        hyprWorkspaceSwipe = !hyprWorkspaceSwipe
        setOption("workspace_swipe", hyprWorkspaceSwipe)
    }

    function toggleHyprSwipeInvert() {
        hyprSwipeInvert = !hyprSwipeInvert
        setOption("workspace_swipe_invert", hyprSwipeInvert)
    }

    function setMonitorScale(monName, scaleVal, saveToConfig) {
        if (!monName) return
        const s = Number(Number(scaleVal).toFixed(2))
        if (configType === "lua") {
            fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", scale = ${s} })`]
        } else {
            fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},preferred,auto,${s}`]
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "scale", s)
            refreshTimer.restart()
        }
    }

    function setMonitorMode(monName, modeStr, saveToConfig) {
        if (!monName || !modeStr) return
        if (configType === "lua") {
            fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", mode = "${modeStr}" })`]
        } else {
            fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},${modeStr},auto,1`]
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "mode", modeStr)
            refreshTimer.restart()
        }
    }

    function setMonitorTransform(monName, transformVal, saveToConfig) {
        if (!monName) return
        const t = parseInt(transformVal) || 0
        if (configType === "lua") {
            fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", transform = ${t} })`]
        } else {
            fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},preferred,auto,1,transform,${t}`]
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "transform", t)
            refreshTimer.restart()
        }
    }

    function setMonitorPosition(monName, x, y, saveToConfig) {
        if (!monName) return
        const posX = parseInt(x) || 0
        const posY = parseInt(y) || 0
        if (configType === "lua") {
            fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", position = "${posX}x${posY}" })`]
        } else {
            fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},preferred,${posX}x${posY},1`]
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "x", posX)
            updateMonitorProperty(monName, "y", posY)
            refreshTimer.restart()
        }
    }

    function setMonitorVRR(monName, vrrBool, saveToConfig) {
        if (!monName) return
        const v = vrrBool ? 1 : 0
        if (configType === "lua") {
            fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", vrr = ${v} }) ; hl.config({ misc = { vrr = ${v} } })`]
        } else {
            fastHyprProc.command = ["hyprctl", "keyword", "misc:vrr", `${v}`]
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "vrr", Boolean(vrrBool))
            refreshTimer.restart()
        }
    }

    function setMonitorDisabled(monName, disabledBool, saveToConfig) {
        if (!monName) return
        if (configType === "lua") {
            if (disabledBool) {
                fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", mode = "disabled" })`]
            } else {
                fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", mode = "preferred" })`]
            }
        } else {
            if (disabledBool) {
                fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},disable`]
            } else {
                fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},preferred,auto,1`]
            }
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "disabled", Boolean(disabledBool))
            refreshTimer.restart()
        }
    }

    function setMonitorMirror(monName, mirrorTarget, saveToConfig) {
        if (!monName) return
        const mTarget = (mirrorTarget && mirrorTarget !== "none" && mirrorTarget !== monName) ? mirrorTarget : "none"
        if (configType === "lua") {
            if (mTarget !== "none") {
                fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", mirror = "${mTarget}" })`]
            } else {
                fastHyprProc.command = ["hyprctl", "eval", `hl.monitor({ output = "${monName}", mirror = "" })`]
            }
        } else {
            if (mTarget !== "none") {
                fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},preferred,auto,1,mirror,${mTarget}`]
            } else {
                fastHyprProc.command = ["hyprctl", "keyword", "monitor", `${monName},preferred,auto,1`]
            }
        }
        fastHyprProc.running = true
        if (saveToConfig) {
            updateMonitorProperty(monName, "mirrorOf", mTarget)
            refreshTimer.restart()
        }
    }

    function setPrimaryMonitor(monName) {
        if (!monName) return
        if (activeCompositor === "hyprland") {
            fastHyprProc.command = ["hyprctl", "dispatch", "focusmonitor", monName]
            fastHyprProc.running = true
        }
        refreshTimer.restart()
    }

    function updateMonitorProperty(monName, prop, val) {
        if (!monitorsList || monitorsList.length === 0) return
        var list = JSON.parse(JSON.stringify(monitorsList))
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === monName) {
                list[i][prop] = val
                break
            }
        }
        applyMonitorLayout(list, true)
    }

    function applyMonitorLayout(layoutArray, saveToConfig) {
        if (!Array.isArray(layoutArray) || layoutArray.length === 0) return
        
        if (configType === "lua") {
            var parts = []
            for (var i = 0; i < layoutArray.length; i++) {
                var m = layoutArray[i]
                if (!m.name) continue
                if (m.disabled) {
                    parts.push(`hl.monitor({ output = "${m.name}", mode = "disabled" })`)
                } else if (m.mirrorOf && m.mirrorOf !== "none" && m.mirrorOf !== m.name) {
                    var mPos = `${parseInt(m.x || 0)}x${parseInt(m.y || 0)}`
                    var mSc = parseFloat(m.scale || 1.0)
                    var mMd = (m.mode && m.mode !== "preferred") ? `mode = "${m.mode}", ` : ""
                    parts.push(`hl.monitor({ output = "${m.name}", ${mMd}position = "${mPos}", scale = ${mSc}, mirror = "${m.mirrorOf}" })`)
                } else {
                    var x = parseInt(m.x || 0)
                    var y = parseInt(m.y || 0)
                    var sc = parseFloat(m.scale || 1.0)
                    var tr = parseInt(m.transform || 0)
                    var vr = m.vrr ? 1 : 0
                    var md = (m.mode && m.mode !== "preferred") ? `mode = "${m.mode}", ` : ""
                    parts.push(`hl.monitor({ output = "${m.name}", ${md}position = "${x}x${y}", scale = ${sc}, transform = ${tr}, vrr = ${vr} })`)
                }
            }
            if (parts.length > 0) {
                fastHyprProc.command = ["hyprctl", "eval", parts.join(" ; ")]
                fastHyprProc.running = true
            }
        } else if (activeCompositor === "hyprland") {
            var kwParts = []
            for (var j = 0; j < layoutArray.length; j++) {
                var mj = layoutArray[j]
                if (!mj.name) continue
                if (mj.disabled) {
                    kwParts.push("keyword monitor " + mj.name + ",disable")
                } else if (mj.mirrorOf && mj.mirrorOf !== "none" && mj.mirrorOf !== mj.name) {
                    kwParts.push("keyword monitor " + mj.name + ",preferred,auto," + parseFloat(mj.scale || 1.0) + ",mirror," + mj.mirrorOf)
                } else {
                    var modeStr = mj.mode || "preferred"
                    var posStr = parseInt(mj.x || 0) + "x" + parseInt(mj.y || 0)
                    kwParts.push("keyword monitor " + mj.name + "," + modeStr + "," + posStr + "," + parseFloat(mj.scale || 1.0) + ",transform," + parseInt(mj.transform || 0))
                }
            }
            if (kwParts.length > 0) {
                fastHyprProc.command = ["hyprctl", "--batch", kwParts.join(" ; ")]
                fastHyprProc.running = true
            }
        }

        if (saveToConfig) {
            monitorsApplyProc.command = [root.helperScript, "monitors-apply", "--layout", JSON.stringify(layoutArray), "--save"]
            monitorsApplyProc.running = true
            refreshTimer.restart()
        }
    }

    function identifyMonitors() {
        if (Services.OverlayManager) {
            Services.OverlayManager.triggerIdentifyMonitors()
        }
    }

    Process {
        id: monitorsApplyProc
        property string qOutput: ""
        stdout: SplitParser {
            onRead: chunk => { monitorsApplyProc.qOutput += chunk }
        }
        onExited: {
            monitorsApplyProc.qOutput = ""
            root.refreshState()
        }
    }

    Timer {
        id: refreshTimer
        interval: 300
        repeat: false
        onTriggered: root.refreshState()
    }

    function applyPreset(presetId) {
        activePreset = presetId
        switch (presetId) {
            case "glass":
                hyprAnim = true; setOption("anim", true)
                hyprBlur = true; setOption("blur", true)
                hyprBlurSize = 6; setOption("blur_size", 6)
                hyprBlurPasses = 3; setOption("blur_passes", 3)
                hyprShadow = true; setOption("shadow", true)
                hyprShadowRange = 14; setOption("shadow_range", 14)
                hyprActiveOpacity = 0.88; setOption("active_opacity", 0.88)
                hyprInactiveOpacity = 0.92; setOption("inactive_opacity", 0.92)
                hyprRounding = 14; setOption("rounding", 14)
                hyprBorderSize = 1; setOption("border_size", 1)
                hyprGapsIn = 6; setOption("gaps_in", 6)
                hyprGapsOut = 12; setOption("gaps_out", 12)
                break
            case "gaming":
                hyprAnim = false; setOption("anim", false)
                hyprBlur = false; setOption("blur", false)
                hyprShadow = false; setOption("shadow", false)
                hyprAllowTearing = true; setOption("allow_tearing", true)
                hyprVFR = true; setOption("vfr", true)
                hyprActiveOpacity = 1.0; setOption("active_opacity", 1.0)
                hyprInactiveOpacity = 1.0; setOption("inactive_opacity", 1.0)
                hyprRounding = 4; setOption("rounding", 4)
                hyprBorderSize = 1; setOption("border_size", 1)
                hyprGapsIn = 0; setOption("gaps_in", 0)
                hyprGapsOut = 0; setOption("gaps_out", 0)
                break
            case "minimal":
                hyprAnim = true; setOption("anim", true)
                hyprBlur = false; setOption("blur", false)
                hyprShadow = false; setOption("shadow", false)
                hyprActiveOpacity = 1.0; setOption("active_opacity", 1.0)
                hyprInactiveOpacity = 1.0; setOption("inactive_opacity", 1.0)
                hyprRounding = 0; setOption("rounding", 0)
                hyprBorderSize = 0; setOption("border_size", 0)
                hyprGapsIn = 0; setOption("gaps_in", 0)
                hyprGapsOut = 0; setOption("gaps_out", 0)
                break
            case "material":
                hyprAnim = true; setOption("anim", true)
                hyprBlur = true; setOption("blur", true)
                hyprBlurSize = 4; setOption("blur_size", 4)
                hyprBlurPasses = 2; setOption("blur_passes", 2)
                hyprShadow = true; setOption("shadow", true)
                hyprActiveOpacity = 0.92; setOption("active_opacity", 0.92)
                hyprInactiveOpacity = 0.96; setOption("inactive_opacity", 0.96)
                hyprRounding = 12; setOption("rounding", 12)
                hyprBorderSize = 1; setOption("border_size", 1)
                hyprGapsIn = 5; setOption("gaps_in", 5)
                hyprGapsOut = 10; setOption("gaps_out", 10)
                break
        }
    }

    // ── Keybindings Management (Direct from Compositor Config) ───────────────
    function loadKeybinds() {
        isLoadingBinds = true
        bindsListProc.qOutput = ""
        bindsListProc.command = [root.helperScript, "binds-list"]
        bindsListProc.running = true
    }

    function addKeybind(keys, action, desc, file) {
        if (!keys || !action) return
        keybindStatus = "Adding keybind..."
        bindsAddProc.qOutput = ""
        var cmd = [root.helperScript, "binds-add", "--keys", keys, "--action", action, "--desc", desc || ""]
        if (file) { cmd.push("--file", file) }
        bindsAddProc.command = cmd
        bindsAddProc.running = true
    }

    function updateKeybind(lineNum, keys, action, desc, file) {
        if (!lineNum || !keys || !action) return
        keybindStatus = "Updating keybind..."
        bindsUpdateProc.qOutput = ""
        var cmd = [root.helperScript, "binds-update", "--line", String(lineNum), "--keys", keys, "--action", action, "--desc", desc || ""]
        if (file) { cmd.push("--file", file) }
        bindsUpdateProc.command = cmd
        bindsUpdateProc.running = true
    }

    function deleteKeybind(lineNum, file) {
        if (!lineNum) return
        keybindStatus = "Deleting keybind..."
        bindsDeleteProc.qOutput = ""
        var cmd = [root.helperScript, "binds-delete", "--line", String(lineNum)]
        if (file) { cmd.push("--file", file) }
        bindsDeleteProc.command = cmd
        bindsDeleteProc.running = true
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
                    if (data.follow_mouse !== undefined) root.hyprFollowMouse = data.follow_mouse
                    if (data.workspace_swipe !== undefined) root.hyprWorkspaceSwipe = data.workspace_swipe
                    if (data.workspace_swipe_invert !== undefined) root.hyprSwipeInvert = data.workspace_swipe_invert
                    if (data.vfr !== undefined) root.hyprVFR = data.vfr
                    if (data.allow_tearing !== undefined) root.hyprAllowTearing = data.allow_tearing
                    if (data.smart_gaps !== undefined) root.hyprSmartGaps = data.smart_gaps
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

    Process {
        id: bindsListProc
        property string qOutput: ""
        command: [root.helperScript, "binds-list"]
        stdout: SplitParser {
            onRead: chunk => {
                bindsListProc.qOutput += chunk
            }
        }
        onExited: {
            root.isLoadingBinds = false
            try {
                const data = JSON.parse(bindsListProc.qOutput.trim())
                if (data && data.ok && Array.isArray(data.binds)) {
                    root.keybindsList = data.binds
                }
            } catch (e) {}
            bindsListProc.qOutput = ""
        }
    }

    Process {
        id: bindsAddProc
        property string qOutput: ""
        stdout: SplitParser {
            onRead: chunk => {
                bindsAddProc.qOutput += chunk
            }
        }
        onExited: (exitCode) => {
            try {
                const res = JSON.parse(bindsAddProc.qOutput.trim())
                if (res && res.ok) {
                    root.keybindStatus = "Keybind added successfully"
                    root.loadKeybinds()
                } else {
                    root.keybindError = res.error || "Failed to add keybind"
                }
            } catch (e) {
                root.loadKeybinds()
            }
            bindsAddProc.qOutput = ""
        }
    }

    Process {
        id: bindsUpdateProc
        property string qOutput: ""
        stdout: SplitParser {
            onRead: chunk => {
                bindsUpdateProc.qOutput += chunk
            }
        }
        onExited: (exitCode) => {
            try {
                const res = JSON.parse(bindsUpdateProc.qOutput.trim())
                if (res && res.ok) {
                    root.keybindStatus = "Keybind updated successfully"
                    root.loadKeybinds()
                } else {
                    root.keybindError = res.error || "Failed to update keybind"
                }
            } catch (e) {
                root.loadKeybinds()
            }
            bindsUpdateProc.qOutput = ""
        }
    }

    Process {
        id: bindsDeleteProc
        property string qOutput: ""
        stdout: SplitParser {
            onRead: chunk => {
                bindsDeleteProc.qOutput += chunk
            }
        }
        onExited: (exitCode) => {
            try {
                const res = JSON.parse(bindsDeleteProc.qOutput.trim())
                if (res && res.ok) {
                    root.keybindStatus = "Keybind deleted successfully"
                    root.loadKeybinds()
                } else {
                    root.keybindError = res.error || "Failed to delete keybind"
                }
            } catch (e) {
                root.loadKeybinds()
            }
            bindsDeleteProc.qOutput = ""
        }
    }
}