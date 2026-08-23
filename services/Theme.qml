pragma Singleton
import QtQuick
import Quickshell
import "." as Services

Singleton {
    id: themeRoot

    // ─── Theme Mode & State ────────────────────────────────────────────────
    readonly property bool isDark: Services.Config ? (Services.Config.themeMode !== "light") : true
    readonly property string mode: Services.Config ? Services.Config.themeMode : "dark"

    // ─── Transition Durations ──────────────────────────────────────────────
    // Theme colors change INSTANTLY here. Animation is handled by each component's
    // own Behavior so all components animate from the same start→end simultaneously.
    readonly property int themeAnimDuration: 250

    // ─── Accent Color ──────────────────────────────────────────────────────
    property color accent: {
        var raw = (Services.Config && Services.Config.accentColor) ? Services.Config.accentColor : ""
        if (raw && typeof raw === "string" && raw.startsWith("#")) {
            return raw
        }
        return isDark ? "#d4d4d4" : "#0071e3"
    }
    // NO Behavior here — instant change, components animate it themselves

    function getLuminance(col) {
        try {
            var c = Qt.color(col)
            return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114)
        } catch (e) {
            return 0.5
        }
    }

    // Dynamic contrast for text and icons placed on top of accent color
    property color bgOnAccent: getLuminance(accent) > 0.58 ? "#111114" : "#ffffff"

    // ─── Background & Layout ───────────────────────────────────────────────
    property color bg:          isDark ? "#cc111113" : "#ebf0f4f8"
    property color bgElevated:  isDark ? "#d918181c" : "#f8ffffff"
    property color bgHover:     isDark ? "#e026262c" : "#e2e6ed"
    property color bgDeep:      isDark ? "#09090b"   : "#ffffff"
    property color bgPure:      isDark ? "#0c0c0e"   : "#ffffff"
    property color overlayDim:  isDark ? "#aa000000" : "#45000000"

    // ─── Surface ───────────────────────────────────────────────────────────
    property color surface:        isDark ? "#cc16161a" : "#f0ffffff"
    property color surfaceSolid:   isDark ? "#1c1c20"   : "#f4f5f8"
    property color surfaced:       isDark ? "#202026"   : "#eaedf2"
    property color surfaceVariant: isDark ? "#cc24242c" : "#e8ecf2"

    // ─── Text & Typography ─────────────────────────────────────────────────
    property color textPrimary:   isDark ? "#f4f4f6" : "#09090b"
    property color textSecondary: isDark ? "#a1a1aa" : "#475569"
    property color textDisabled:  isDark ? "#52525b" : "#94a3b8"
    readonly property color white: "#ffffff"
    property color textOnSafe:    isDark ? "#b0b0b8" : "#475569"

    // ─── Icon Colors ───────────────────────────────────────────────────────
    property color iconPrimary:   isDark ? "#f4f4f6" : "#09090b"
    property color iconSecondary: isDark ? "#a1a1aa" : "#475569"
    property color iconAccent:    accent
    property color iconDisabled:  isDark ? "#52525b" : "#94a3b8"

    // ─── Secondary Accents & Status ────────────────────────────────────────
    property color accentDim:  Qt.rgba(accent.r, accent.g, accent.b, isDark ? 0.55 : 0.65)
    property color accentBlue:  isDark ? "#cdd6f4" : "#0071e3"
    property color alertYellow: isDark ? "#ffcc00" : "#d97706"

    // ─── Border & Dividers ─────────────────────────────────────────────────
    property color border:          isDark ? "#2a2a34" : "#cbd5e1"
    property color borderHighlight: isDark ? "#464658" : "#94a3b8"
    property color borderSubtle:    isDark ? "#1f1f26" : "#e2e8f0"

    // ─── Status Colors ─────────────────────────────────────────────────────
    property color danger:     isDark ? "#ef4444" : "#dc2626"
    property color dangerDeep: isDark ? "#7f1d1d" : "#991b1b"
    property color warning:    isDark ? "#f59e0b" : "#d97706"
    property color success:    isDark ? "#10b981" : "#16a34a"

    // ─── Radius ────────────────────────────────────────────────────────────
    readonly property int baseRadius: Services.Config ? Services.Config.cornerRadius : 16
    readonly property int radiusSm:   Math.max(4, Math.round(baseRadius * 0.5))
    readonly property int radiusMd:   Math.max(6, Math.round(baseRadius * 0.75))
    readonly property int radiusLg:   baseRadius
    readonly property int radiusXl:   Math.round(baseRadius * 1.5)

    // ─── Font Families ─────────────────────────────────────────────────────
    readonly property string fontFamily: (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "Liga SFMono Nerd Font, monospace"
    readonly property string fontMono:    (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "Liga SFMono Nerd Font, monospace"
    readonly property string fontSymbols: "Symbols Nerd Font Mono, Liga SFMono Nerd Font, FontAwesome, monospace"
    readonly property string fontDisplay: (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "SF Pro Display, Inter, Sans-Serif"
    readonly property string fontPrimary: fontDisplay

    // ─── Font Scale ─────────────────────────────────────────────────────────
    readonly property real scale: Services.Config ? Services.Config.uiScale : 1.0

    // ─── Font Sizes (pixelSize) ─────────────────────────────────────────────
    readonly property int fontSizeXs:   Math.round(9  * scale)
    readonly property int fontSizeSm:   Math.round(10 * scale)
    readonly property int fontSizeMd:   Math.round(11 * scale)
    readonly property int fontSizeLg:   Math.round(12 * scale)
    readonly property int fontSizeXl:   Math.round(13 * scale)
    readonly property int fontSize2xl:  Math.round(14 * scale)
    readonly property int fontSize3xl:  Math.round(15 * scale)
    readonly property int fontSize4xl:  Math.round(16 * scale)
    readonly property int fontSize5xl:  Math.round(18 * scale)
    readonly property int fontSize6xl:  Math.round(20 * scale)
    readonly property int fontSize7xl:  Math.round(22 * scale)
    readonly property int fontSize8xl:  Math.round(24 * scale)
    readonly property int fontSize9xl:  Math.round(26 * scale)
    readonly property int fontSizeXxl:  Math.round(36 * scale)
    readonly property int fontSizeHero: Math.round(96 * scale)
}
