pragma Singleton
import QtQuick

QtObject {
    // ─── Background ────────────────────────────────────────────────────────
    readonly property color bg:          "#cc111111"   // deepest background (~80% opaque)
    readonly property color bgElevated:  "#cc181818"   // panel, bar (~80% opaque)
    readonly property color bgHover:     "#d91e1e1e"   // hover state (~85% opaque)
    readonly property color bgDeep:      "#0a0a0a"     // icon on filled/accent background
    readonly property color bgPure:      "#0c0c0c"     // DynamicIsland primary background
    readonly property color bgOnAccent:  "#111111"     // dark text on accent/white background
    readonly property color overlayDim:  "#99000000"   // semi-transparent dark overlay

    // ─── Surface ───────────────────────────────────────────────────────────
    readonly property color surface:        "#b31e1e1e"   // card background (~70% opaque)
    readonly property color surfaceSolid:   "#1b272727"   // solid card background (non-transparent)
    readonly property color surfaced:       "#1e1e1e"
    readonly property color surfaceVariant: "#b3272727"   // inner card / item hover (~70% opaque)

    // ─── Text ──────────────────────────────────────────────────────────────
    readonly property color textPrimary:   "#e8e8e8"
    readonly property color textSecondary: "#8a8a8a"
    readonly property color textDisabled:  "#4a4a4a"
    readonly property color white:         "#ffffff"    // solid white text
    readonly property color textOnSafe:    "#b0b0b0"   // gray text in non-danger state

    // ─── Accent ────────────────────────────────────────────────────────────
    readonly property color accent:      "#d4d4d4"
    readonly property color accentDim:   "#6a6a6a"
    readonly property color accentBlue:  "#cdd6f4"     // Catppuccin Lavender (power OSD)
    readonly property color alertYellow: "#ffcc00"     // caps lock / warning yellow

    // ─── Border ────────────────────────────────────────────────────────────
    readonly property color border:          "#2e2e2e"
    readonly property color borderHighlight: "#4a4a4a"
    readonly property color borderSubtle:    "#222222"  // subtle border

    // ─── Status ────────────────────────────────────────────────────────────
    readonly property color danger:     "#8a5252"
    readonly property color dangerDeep: "#5e2424"   // darker danger (powermenu confirmation)
    readonly property color warning:    "#8a7a52"
    readonly property color success:    "#5c8a5c"

    // ─── Radius ────────────────────────────────────────────────────────────
    readonly property int radiusSm: 8
    readonly property int radiusMd: 12
    readonly property int radiusLg: 16

    // ─── Font Families ─────────────────────────────────────────────────────
    readonly property string fontMono:    "Liga SFMono Nerd Font"              // bar & text UI
    readonly property string fontSymbols: "Symbols Nerd Font Mono"             // icons / glyphs
    readonly property string fontDisplay: "SF Pro Display, Inter, Sans-Serif"  // headings / large display

    // ─── Font Sizes (pixelSize) ─────────────────────────────────────────────
    readonly property int fontSizeXs:   9    // small caption, tiny badge
    readonly property int fontSizeSm:   10   // small label, badge
    readonly property int fontSizeMd:   11   // normal / default text
    readonly property int fontSizeLg:   12   // slightly larger text
    readonly property int fontSizeXl:   13   // subtitle
    readonly property int fontSize2xl:  14   // small heading
    readonly property int fontSize3xl:  15   // heading
    readonly property int fontSize4xl:  16   // header
    readonly property int fontSize5xl:  18   // section title / icon
    readonly property int fontSize6xl:  20   // large icon
    readonly property int fontSize7xl:  22   // OSD icon
    readonly property int fontSize8xl:  24   // large launcher icon
    readonly property int fontSize9xl:  26   // large notification icon
    readonly property int fontSizeXxl:  36   // power OSD icon
    readonly property int fontSizeHero: 96   // lockscreen clock
}

