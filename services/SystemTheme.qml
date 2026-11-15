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
    property string currentGtkTheme: "MacTahoe-Dark"
    property string currentIconTheme: "MacTahoe"
    property string currentCursorTheme: "MacTahoe"
    property int currentCursorSize: 24
    property string currentFontFamily: "SFProDisplay Nerd Font Propo"
    property int currentFontSize: 12
    property string currentDocFontFamily: "SFProDisplay Nerd Font Propo"
    property int currentDocFontSize: 11
    property string currentMonoFontFamily: "Liga SFMono Nerd Font"
    property int currentMonoFontSize: 11
    property string currentFontHinting: "slight"
    property string currentFontAntialiasing: "grayscale"
    property real currentTextScaling: 1.0
    property string currentColorScheme: "prefer-dark"
    property var pixmapsMap: ({})

    property bool isLoaded: false
    property bool isBusy: false

    Component.onCompleted: {
        refresh()
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
        if (!name || name === currentIconTheme) return
        currentIconTheme = name
        _iconCache = {}
        iconThemeRev++
        execProc.lastAction = "set_icon_theme"
        execProc.pendingThemeName = name
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

    // ── Native Icon Resolution ───────────────────────────────────────────────
    property int iconThemeRev: 0
    property var _iconCache: ({})

    function getIcon(iconName) {
        if (!iconName) return ""
        var s = typeof iconName === "string" ? iconName.trim() : (iconName.name || iconName.toString() || "").trim()
        if (!s) return ""

        if (_iconCache[s] !== undefined) {
            return _iconCache[s]
        }

        var result = ""

        // If it's already an absolute file path or network URI
        if (s.startsWith("file://") || s.startsWith("http://") || s.startsWith("https://") || s.startsWith("qrc:/")) {
            result = s
        } else if (s.startsWith("/")) {
            result = "file://" + s
        } else {
            // Strip image://icon/ if passed
            var clean = s
            if (clean.startsWith("image://icon/")) clean = clean.substring(13).trim()
            if (clean.startsWith("image://")) {
                result = clean
            } else if (clean.length > 0) {
                // Check direct pixmaps cache (e.g. yazi, gvim)
                if (pixmapsMap[clean]) {
                    result = "file://" + pixmapsMap[clean]
                } else if (clean.indexOf(".") !== -1 && pixmapsMap[clean.replace(/\.[^/.]+$/, "")]) {
                    result = "file://" + pixmapsMap[clean.replace(/\.[^/.]+$/, "")]
                }

                if (!result) {
                    var baseName = clean.indexOf(".") !== -1 ? clean.replace(/\.[^/.]+$/, "") : clean

                    // 1. Quickshell theme resolution (baseName without extension)
                    var qp = Quickshell.iconPath(baseName, true)
                    if (qp && qp.length > 0) {
                        result = qp.startsWith("/") ? ("file://" + qp) : qp
                    }

                    // 2. Try lowercased baseName
                    if (!result && baseName.toLowerCase() !== baseName) {
                        var qpLower = Quickshell.iconPath(baseName.toLowerCase(), true)
                        if (qpLower && qpLower.length > 0) {
                            result = qpLower.startsWith("/") ? ("file://" + qpLower) : qpLower
                        }
                    }

                    // 3. Try reverse DNS suffix (e.g. com.mitchellh.ghostty -> ghostty)
                    if (!result && baseName.indexOf(".") !== -1) {
                        var parts = baseName.split(".")
                        var suffix = parts[parts.length - 1]
                        if (suffix && suffix.length > 0) {
                            var qpSuffix = Quickshell.iconPath(suffix, true) || Quickshell.iconPath(suffix.toLowerCase(), true)
                            if (qpSuffix && qpSuffix.length > 0) {
                                result = qpSuffix.startsWith("/") ? ("file://" + qpSuffix) : qpSuffix
                            }
                        }
                    }

                    // 4. Try common aliases
                    if (!result) {
                        var aliasMap = {
                            "multimedia-volume-control": ["pavucontrol", "org.pulseaudio.pavucontrol", "audio-volume-high"],
                            "preferences-system": ["org.quickshell", "preferences-desktop", "system-settings"],
                            "preferences-desktop-theme": ["gnome-theme-switcher", "preferences-desktop-appearance", "preferences-desktop"],
                            "web-browser": ["browser", "google-chrome", "chromium", "firefox", "helium"],
                            "gvim": ["vim", "nvim", "accessories-text-editor"],
                            "nvim": ["nvim", "io.neovim.nvim", "gvim", "vim"],
                            "utilities-terminal": ["com.mitchellh.ghostty", "ghostty", "kitty", "terminal"]
                        }
                        var aliases = aliasMap[baseName] || aliasMap[clean]
                        if (aliases && Array.isArray(aliases)) {
                            for (var ai = 0; ai < aliases.length; ai++) {
                                var qpAlias = Quickshell.iconPath(aliases[ai], true)
                                if (qpAlias && qpAlias.length > 0) {
                                    result = qpAlias.startsWith("/") ? ("file://" + qpAlias) : qpAlias
                                    break
                                }
                            }
                        }
                    }

                    // 5. Fallback for raw clean name if it had an extension
                    if (!result && clean !== baseName) {
                        var qpRaw = Quickshell.iconPath(clean, true)
                        if (qpRaw && qpRaw.length > 0) {
                            result = qpRaw.startsWith("/") ? ("file://" + qpRaw) : qpRaw
                        }
                    }
                }
            }
        }

        _iconCache[s] = result
        return result
    }

    // ── Processes ────────────────────────────────────────────────────────────
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
                        if (data.pixmaps) root.pixmapsMap = data.pixmaps
                        
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
                        root._iconCache = {}
                        root.iconThemeRev++
                        root.isLoaded = true
                        if (Services.Applications && typeof Services.Applications._rebuildIndex === "function") {
                            Services.Applications._rebuildIndex()
                        }
                    }
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: execProc
        property string lastAction: ""
        property string pendingThemeName: ""

        onExited: (exitCode, exitStatus) => {
            if (lastAction === "set_icon_theme" && exitCode === 0) {
                var themeName = pendingThemeName || root.currentIconTheme
                lastAction = ""
                pendingThemeName = ""

                notifyProc.command = [
                    "sh", "-c",
                    "if command -v notify-send >/dev/null 2>&1; then notify-send -a Nimbush -i preferences-desktop-theme 'Icon Theme Updated' 'Restarting Nimbush to apply '\"$1\"'...'; fi",
                    "sh", themeName
                ]
                notifyProc.running = true

                restartProc.running = true
            }
        }
    }

    Process {
        id: notifyProc
    }

    Process {
        id: restartProc
        command: ["python3", root.helperScript, "restart_quickshell"]
    }
}
