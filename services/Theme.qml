pragma Singleton
import QtQuick

QtObject {
    // Base — dark tapi bukan pure black, ada breathing room
    readonly property color bg:          "#cc111111"   // background paling dalam (~80% opaque)
    readonly property color bgElevated:  "#cc181818"   // panel, bar (~80% opaque)
    readonly property color bgHover:     "#d91e1e1e"   // hover state (~85% opaque)

    // Surface
    readonly property color surface:        "#b31e1e1e"   // card background (~70% opaque)
    readonly property color surfaced:       "#1e1e1e"
    readonly property color surfaceVariant: "#b3272727"   // inner card / item hover (~70% opaque)
    readonly property color seurfa:         '#1b272727'

    // Text
    readonly property color textPrimary:   "#e8e8e8"
    readonly property color textSecondary: "#8a8a8a"
    readonly property color textDisabled:  "#4a4a4a"

    // Accent — silver/white, satu-satunya highlight warna
    readonly property color accent:    "#d4d4d4"
    readonly property color accentDim: "#6a6a6a"

    // Border
    readonly property color border:          "#2e2e2e"
    readonly property color borderHighlight: "#4a4a4a"

    // Status (desaturated)
    readonly property color danger:  "#8a5252"
    readonly property color warning: "#8a7a52"
    readonly property color success: "#5c8a5c"

    // Radius tokens
    readonly property int radiusSm: 8
    readonly property int radiusMd: 12
    readonly property int radiusLg: 16
}
