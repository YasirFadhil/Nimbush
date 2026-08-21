pragma Singleton
import QtQuick
import "." as Services

QtObject {
    id: themeRoot

    // ─── Theme Mode & State ────────────────────────────────────────────────
    readonly property bool isDark: Services.Config ? (Services.Config.themeMode !== "light") : true
    readonly property string mode: Services.Config ? Services.Config.themeMode : "dark"

    // ─── Transition Durations ──────────────────────────────────────────────
    readonly property int themeAnimDuration: 150

    // ─── Accent Color ──────────────────────────────────────────────────────
    property color accent: {
        var raw = (Services.Config && Services.Config.accentColor) ? Services.Config.accentColor : ""
        if (raw && typeof raw === "string" && raw.startsWith("#")) {
            return raw
        }
        return isDark ? "#d4d4d4" : "#0071e3"
    }
    Behavior on accent { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

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
    Behavior on bgOnAccent { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Background & Layout ───────────────────────────────────────────────
    property color bg:          isDark ? "#cc111113" : "#ebf0f4f8"   // deepest background (~85-90% opaque)
    Behavior on bg { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color bgElevated:  isDark ? "#d918181c" : "#f8ffffff"   // panel, bar (~85-95% opaque)
    Behavior on bgElevated { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color bgHover:     isDark ? "#e026262c" : "#e2e6ed"   // hover state (~85-90% opaque)
    Behavior on bgHover { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color bgDeep:      isDark ? "#09090b"   : "#ffffff"   // container background
    Behavior on bgDeep { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color bgPure:      isDark ? "#0c0c0e"   : "#ffffff"   // DynamicIsland primary background
    Behavior on bgPure { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color overlayDim:  isDark ? "#aa000000" : "#45000000" // semi-transparent backdrop overlay
    Behavior on overlayDim { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Surface ───────────────────────────────────────────────────────────
    property color surface:        isDark ? "#cc16161a" : "#f0ffffff" // card background (~80-92% opaque)
    Behavior on surface { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color surfaceSolid:   isDark ? "#1c1c20"   : "#f4f5f8" // solid card background (non-transparent)
    Behavior on surfaceSolid { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color surfaced:       isDark ? "#202026"   : "#eaedf2"
    Behavior on surfaced { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color surfaceVariant: isDark ? "#cc24242c" : "#e8ecf2" // inner card / item container
    Behavior on surfaceVariant { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Text & Typography ─────────────────────────────────────────────────
    property color textPrimary:   isDark ? "#f4f4f6" : "#09090b"    // ultra crisp primary text
    Behavior on textPrimary { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color textSecondary: isDark ? "#a1a1aa" : "#475569"    // rich secondary text
    Behavior on textSecondary { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color textDisabled:  isDark ? "#52525b" : "#94a3b8"    // subtle disabled text
    Behavior on textDisabled { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    readonly property color white:         "#ffffff"                         // solid white

    property color textOnSafe:    isDark ? "#b0b0b8" : "#475569"    // gray text in non-danger state
    Behavior on textOnSafe { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Icon Colors ───────────────────────────────────────────────────────
    property color iconPrimary:   isDark ? "#f4f4f6" : "#09090b"
    Behavior on iconPrimary { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color iconSecondary: isDark ? "#a1a1aa" : "#475569"
    Behavior on iconSecondary { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color iconAccent:    accent
    Behavior on iconAccent { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color iconDisabled:  isDark ? "#52525b" : "#94a3b8"
    Behavior on iconDisabled { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Secondary Accents & Status ────────────────────────────────────────
    property color accentDim:  Qt.rgba(accent.r, accent.g, accent.b, isDark ? 0.55 : 0.65)
    Behavior on accentDim { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color accentBlue:  isDark ? "#cdd6f4" : "#0071e3"     // Catppuccin Lavender / macOS Blue
    Behavior on accentBlue { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color alertYellow: isDark ? "#ffcc00" : "#d97706"     // caps lock / warning yellow
    Behavior on alertYellow { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Border & Dividers ─────────────────────────────────────────────────
    property color border:          isDark ? "#2a2a34" : "#cbd5e1" // crisp high-contrast border
    Behavior on border { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color borderHighlight: isDark ? "#464658" : "#94a3b8"
    Behavior on borderHighlight { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color borderSubtle:    isDark ? "#1f1f26" : "#e2e8f0" // subtle border
    Behavior on borderSubtle { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Status Colors ─────────────────────────────────────────────────────
    property color danger:     isDark ? "#ef4444" : "#dc2626"
    Behavior on danger { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color dangerDeep: isDark ? "#7f1d1d" : "#991b1b"      // darker danger
    Behavior on dangerDeep { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color warning:    isDark ? "#f59e0b" : "#d97706"
    Behavior on warning { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    property color success:    isDark ? "#10b981" : "#16a34a"
    Behavior on success { ColorAnimation { duration: themeRoot.themeAnimDuration; easing.type: Easing.OutCubic } }

    // ─── Radius ────────────────────────────────────────────────────────────
    readonly property int baseRadius: Services.Config ? Services.Config.cornerRadius : 16
    readonly property int radiusSm:   Math.max(4, Math.round(baseRadius * 0.5))
    readonly property int radiusMd:   Math.max(6, Math.round(baseRadius * 0.75))
    readonly property int radiusLg:   baseRadius
    readonly property int radiusXl:   Math.round(baseRadius * 1.5)

    // ─── Font Families ─────────────────────────────────────────────────────
    readonly property string fontFamily: (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "Liga SFMono Nerd Font, monospace"
    readonly property string fontMono:    (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "Liga SFMono Nerd Font, monospace"              // bar & text UI
    readonly property string fontSymbols: "Symbols Nerd Font Mono, Liga SFMono Nerd Font, FontAwesome, monospace" // icons / glyphs
    readonly property string fontDisplay: (Services.Config && Services.Config.fontFamily) ? Services.Config.fontFamily : "SF Pro Display, Inter, Sans-Serif"  // headings / large display
    readonly property string fontPrimary: fontDisplay

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
