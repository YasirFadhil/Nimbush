pragma Singleton
import QtQuick
import "." as Services

QtObject {
    id: themeRoot

    // ─── Theme Mode & State ────────────────────────────────────────────────
    readonly property bool isDark: Services.Config ? (Services.Config.themeMode !== "light") : true
    readonly property string mode: Services.Config ? Services.Config.themeMode : "dark"

    // ─── Accent Color ──────────────────────────────────────────────────────
    readonly property color accent: {
        var raw = (Services.Config && Services.Config.accentColor) ? Services.Config.accentColor : ""
        if (raw && typeof raw === "string" && raw.startsWith("#")) {
            return raw
        }
        return isDark ? "#d4d4d4" : "#0071e3"
    }

    function getLuminance(col) {
        try {
            var c = Qt.color(col)
            return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114)
        } catch (e) {
            return 0.5
        }
    }

    // Dynamic contrast for text and icons placed on top of accent color
    readonly property color bgOnAccent: getLuminance(accent) > 0.58 ? "#111114" : "#ffffff"

    // ─── Background & Layout ───────────────────────────────────────────────
    readonly property color bg:          isDark ? "#cc111113" : "#ebf0f4f8"   // deepest background (~85-90% opaque)
    readonly property color bgElevated:  isDark ? "#d918181c" : "#f8ffffff"   // panel, bar (~85-95% opaque)
    readonly property color bgHover:     isDark ? "#e026262c" : "#e2e6ed"   // hover state (~85-90% opaque)
    readonly property color bgDeep:      isDark ? "#09090b"   : "#ffffff"   // container background
    readonly property color bgPure:      isDark ? "#0c0c0e"   : "#ffffff"   // DynamicIsland primary background
    readonly property color overlayDim:  isDark ? "#aa000000" : "#45000000" // semi-transparent backdrop overlay

    // ─── Surface ───────────────────────────────────────────────────────────
    readonly property color surface:        isDark ? "#cc16161a" : "#f0ffffff" // card background (~80-92% opaque)
    readonly property color surfaceSolid:   isDark ? "#1c1c20"   : "#f4f5f8" // solid card background (non-transparent)
    readonly property color surfaced:       isDark ? "#202026"   : "#eaedf2"
    readonly property color surfaceVariant: isDark ? "#cc24242c" : "#e8ecf2" // inner card / item container

    // ─── Text & Typography ─────────────────────────────────────────────────
    readonly property color textPrimary:   isDark ? "#f4f4f6" : "#09090b"    // ultra crisp primary text
    readonly property color textSecondary: isDark ? "#a1a1aa" : "#475569"    // rich secondary text
    readonly property color textDisabled:  isDark ? "#52525b" : "#94a3b8"    // subtle disabled text
    readonly property color white:         "#ffffff"                         // solid white
    readonly property color textOnSafe:    isDark ? "#b0b0b8" : "#475569"    // gray text in non-danger state

    // ─── Icon Colors ───────────────────────────────────────────────────────
    readonly property color iconPrimary:   isDark ? "#f4f4f6" : "#09090b"
    readonly property color iconSecondary: isDark ? "#a1a1aa" : "#475569"
    readonly property color iconAccent:    accent
    readonly property color iconDisabled:  isDark ? "#52525b" : "#94a3b8"

    // ─── Secondary Accents & Status ────────────────────────────────────────
    readonly property color accentDim:  Qt.rgba(accent.r, accent.g, accent.b, isDark ? 0.55 : 0.65)
    readonly property color accentBlue:  isDark ? "#cdd6f4" : "#0071e3"     // Catppuccin Lavender / macOS Blue
    readonly property color alertYellow: isDark ? "#ffcc00" : "#d97706"     // caps lock / warning yellow

    // ─── Border & Dividers ─────────────────────────────────────────────────
    readonly property color border:          isDark ? "#2a2a34" : "#cbd5e1" // crisp high-contrast border
    readonly property color borderHighlight: isDark ? "#464658" : "#94a3b8"
    readonly property color borderSubtle:    isDark ? "#1f1f26" : "#e2e8f0" // subtle border

    // ─── Status Colors ─────────────────────────────────────────────────────
    readonly property color danger:     isDark ? "#ef4444" : "#dc2626"
    readonly property color dangerDeep: isDark ? "#7f1d1d" : "#991b1b"      // darker danger
    readonly property color warning:    isDark ? "#f59e0b" : "#d97706"
    readonly property color success:    isDark ? "#10b981" : "#16a34a"

    // ─── Radius ────────────────────────────────────────────────────────────
    readonly property int baseRadius: Services.Config ? Services.Config.cornerRadius : 16
    readonly property int radiusSm:   Math.max(4, Math.round(baseRadius * 0.5))
    readonly property int radiusMd:   Math.max(6, Math.round(baseRadius * 0.75))
    readonly property int radiusLg:   baseRadius

    // ─── Font Families ─────────────────────────────────────────────────────
    readonly property string fontMono:    (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "Liga SFMono Nerd Font, monospace"              // bar & text UI
    readonly property string fontSymbols: "Symbols Nerd Font Mono, Liga SFMono Nerd Font, FontAwesome, monospace" // icons / glyphs
    readonly property string fontDisplay: (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "SF Pro Display, Inter, Sans-Serif"  // headings / large display

    // ─── Font Scale ─────────────────────────────────────────────────────────
    readonly property real scale: Services.Config ? Services.Config.uiScale : 1.0

    // ─── Font Sizes (pixelSize) ─────────────────────────────────────────────
    readonly property int fontSizeXs:   Math.round(9  * scale) // small caption, tiny badge
    readonly property int fontSizeSm:   Math.round(10 * scale) // small label, badge
    readonly property int fontSizeMd:   Math.round(11 * scale) // normal / default text
    readonly property int fontSizeLg:   Math.round(12 * scale) // slightly larger text
    readonly property int fontSizeXl:   Math.round(13 * scale) // subtitle
    readonly property int fontSize2xl:  Math.round(14 * scale) // small heading
    readonly property int fontSize3xl:  Math.round(15 * scale) // heading
    readonly property int fontSize4xl:  Math.round(16 * scale) // header
    readonly property int fontSize5xl:  Math.round(18 * scale) // section title / icon
    readonly property int fontSize6xl:  Math.round(20 * scale) // large icon
    readonly property int fontSize7xl:  Math.round(22 * scale) // OSD icon
    readonly property int fontSize8xl:  Math.round(24 * scale) // large launcher icon
    readonly property int fontSize9xl:  Math.round(26 * scale) // large notification icon
    readonly property int fontSizeXxl:  Math.round(36 * scale) // power OSD icon
    readonly property int fontSizeHero: Math.round(96 * scale) // lockscreen clock
}
