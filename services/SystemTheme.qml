pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    readonly property string helperScript: {
        var u = Qt.resolvedUrl("../scripts/system-theme-helper.py").toString()
        var p = u.startsWith("file://") ? u.substring(7) : u
        return p.length > 0 ? p : (Quickshell.env("HOME") + "/.config/quickshell/scripts/system-theme-helper.py")
    }

    // ── Discovered System Models ─────────────────────────────────────────────
    property var gtkThemes: []
    property var iconThemes: []
    property var cursorThemes: []
    property var cursorSizes: [
        { id: 16, label: "16 px" },
        { id: 24, label: "24 px (Default)" },
        { id: 32, label: "32 px" },
        { id: 36, label: "36 px" },
        { id: 48, label: "48 px" },
        { id: 64, label: "64 px" }
    ]
    property var systemFonts: []
    property var monospaceFonts: []

    // ── Current System State ─────────────────────────────────────────────────
    property string currentGtkTheme: "Tahoe-Dark-Amber"
    property string currentIconTheme: "MacTahoe"
    property string currentCursorTheme: "MacTahoe-dark"
    property int currentCursorSize: 24
    property string currentFontFamily: "Liga SFMonoNerdFont"
    property int currentFontSize: 11
    property string currentDocFontFamily: "Adwaita Sans"
    property int currentDocFontSize: 12
    property string currentMonoFontFamily: "Adwaita Mono"
    property int currentMonoFontSize: 11
    property string currentFontHinting: "slight"
    property string currentFontAntialiasing: "grayscale"
    property real currentTextScaling: 1.0
    property string currentColorScheme: "default"

    property bool isLoaded: false
    property bool isBusy: false

    Component.onCompleted: {
        refresh()
        loadCacheProc.running = true
    }

    function refresh() {
        if (queryProc.running) return
        queryProc.rawOutput = ""
        queryProc.running = true
    }

    // ── Setter Actions with Optimistic UI & Subprocess Execution ─────────────
    function setGtkTheme(name) {
        if (!name) return
        currentGtkTheme = name
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_gtk_theme", name]
        execProc.running = true
    }

    function setIconTheme(name) {
        if (!name) return
        currentIconTheme = name
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_icon_theme", name]
        execProc.running = true
    }

    function setCursorTheme(name, size) {
        if (!name) return
        currentCursorTheme = name
        var sz = size !== undefined ? size : currentCursorSize
        currentCursorSize = sz
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_cursor", name, String(sz)]
        execProc.running = true
    }

    function setCursorSize(size) {
        if (!size) return
        currentCursorSize = size
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_cursor", currentCursorTheme, String(size)]
        execProc.running = true
    }

    function setFont(kind, family, size) {
        if (!family) return
        var sz = size || 11
        var fontSpec = family + " " + sz
        if (kind === "interface") {
            currentFontFamily = family
            currentFontSize = sz
        } else if (kind === "document") {
            currentDocFontFamily = family
            currentDocFontSize = sz
        } else if (kind === "monospace") {
            currentMonoFontFamily = family
            currentMonoFontSize = sz
        }
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_font", kind, fontSpec]
        execProc.running = true
    }

    function setFontHinting(hinting) {
        if (!hinting) return
        currentFontHinting = hinting
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_font_rendering", hinting, currentFontAntialiasing, String(currentTextScaling)]
        execProc.running = true
    }

    function setFontAntialiasing(aa) {
        if (!aa) return
        currentFontAntialiasing = aa
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_font_rendering", currentFontHinting, aa, String(currentTextScaling)]
        execProc.running = true
    }

    function setTextScaling(scaling) {
        if (scaling === undefined) return
        currentTextScaling = scaling
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_font_rendering", currentFontHinting, currentFontAntialiasing, String(scaling)]
        execProc.running = true
    }

    function setColorScheme(scheme) {
        var val = "prefer-dark"
        if (typeof scheme === "boolean") {
            val = scheme ? "prefer-dark" : "prefer-light"
        } else if (typeof scheme === "string") {
            val = (scheme === "prefer-light" || scheme === "light") ? "prefer-light" : "prefer-dark"
        }
        currentColorScheme = val
        execProc.running = false
        execProc.command = ["python3", helperScript, "set_color_scheme", val]
        execProc.running = true
    }

    // ── Icon Cache & Reactive Resolution ─────────────────────────────────────
    property var iconCacheMap: ({})
    property int iconThemeRev: 0

    FileView {
        id: iconCacheFileView
        path: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.cache/quickshell/icon_theme_cache.json"
        blockLoading: false
        printErrors: false
        onLoaded: {
            try {
                var raw = iconCacheFileView.text()
                if (raw && raw.trim().startsWith("{")) {
                    root.iconCacheMap = JSON.parse(raw.trim())
                    root.iconThemeRev++
                }
            } catch (e) {}
        }
    }

    function getIcon(iconName) {
        if (!iconName || typeof iconName !== "string") return ""
        if (iconName.startsWith("file://")) return iconName
        if (iconName.startsWith("/")) return "file://" + iconName
        
        var clean = iconName.toLowerCase().trim()
        if (clean.endsWith(".svg") || clean.endsWith(".png") || clean.endsWith(".xpm")) {
            clean = clean.substring(0, clean.lastIndexOf("."))
        }
        
        if (iconCacheMap && iconCacheMap[clean]) {
            return "file://" + iconCacheMap[clean]
        }
        
        // Try fallback with dot suffix or app name (e.g. org.gnome.Nautilus -> nautilus)
        if (clean.indexOf(".") !== -1) {
            var parts = clean.split(".")
            var lastPart = parts[parts.length - 1]
            if (iconCacheMap && iconCacheMap[lastPart]) {
                return "file://" + iconCacheMap[lastPart]
            }
            var dashed = clean.replace(/\./g, "-")
            if (iconCacheMap && iconCacheMap[dashed]) {
                return "file://" + iconCacheMap[dashed]
            }
        }
        
        var qp = Quickshell.iconPath(iconName, true)
        if (qp && qp.length > 0) {
            return qp.startsWith("file://") ? qp : (qp.startsWith("/") ? ("file://" + qp) : qp)
        }
        return ""
    }

    // ── Processes ────────────────────────────────────────────────────────────
    Process {
        id: loadCacheProc
        command: ["cat", (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.cache/quickshell/icon_theme_cache.json"]
        property string rawOutput: ""

        stdout: SplitParser {
            onRead: chunk => {
                loadCacheProc.rawOutput += chunk
            }
        }

        onExited: (exitCode, exitStatus) => {
            var trimmed = loadCacheProc.rawOutput.trim()
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    root.iconCacheMap = JSON.parse(trimmed)
                    root.iconThemeRev++
                } catch (e) {}
            }
        }
    }

    Process {
        id: queryProc
        command: ["python3", root.helperScript, "query"]
        property string rawOutput: ""

        stdout: SplitParser {
            onRead: chunk => {
                queryProc.rawOutput += chunk
            }
        }

        onExited: (exitCode, exitStatus) => {
            var trimmed = queryProc.rawOutput.trim()
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    var data = JSON.parse(trimmed)
                    if (data) {
                        if (data.gtk_themes) root.gtkThemes = data.gtk_themes
                        if (data.icon_themes) root.iconThemes = data.icon_themes
                        if (data.cursor_themes) root.cursorThemes = data.cursor_themes
                        if (data.system_fonts) root.systemFonts = data.system_fonts
                        if (data.monospace_fonts) root.monospaceFonts = data.monospace_fonts
                        
                        if (data.current) {
                            var cur = data.current
                            if (cur.gtk_theme) root.currentGtkTheme = cur.gtk_theme
                            if (cur.icon_theme) root.currentIconTheme = cur.icon_theme
                            if (cur.cursor_theme) root.currentCursorTheme = cur.cursor_theme
                            if (cur.cursor_size) root.currentCursorSize = cur.cursor_size
                            if (cur.font_family) root.currentFontFamily = cur.font_family
                            if (cur.font_size) root.currentFontSize = cur.font_size
                            if (cur.doc_font_family) root.currentDocFontFamily = cur.doc_font_family
                            if (cur.doc_font_size) root.currentDocFontSize = cur.doc_font_size
                            if (cur.mono_font_family) root.currentMonoFontFamily = cur.mono_font_family
                            if (cur.mono_font_size) root.currentMonoFontSize = cur.mono_font_size
                            if (cur.font_hinting) root.currentFontHinting = cur.font_hinting
                            if (cur.font_antialiasing) root.currentFontAntialiasing = cur.font_antialiasing
                            if (cur.text_scaling_factor !== undefined) root.currentTextScaling = cur.text_scaling_factor
                            if (cur.color_scheme) root.currentColorScheme = cur.color_scheme
                        }
                        root.isLoaded = true
                        loadCacheProc.rawOutput = ""
                        loadCacheProc.running = true
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: execProc
        onExited: (exitCode, exitStatus) => {
            if (execProc.command && execProc.command.indexOf("set_icon_theme") !== -1) {
                loadCacheProc.rawOutput = ""
                loadCacheProc.running = true
                iconCacheFileView.reload()
            }
        }
    }
}
