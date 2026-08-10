pragma Singleton
import QtQuick

QtObject {
    // Base — dark tapi bukan pure black, ada breathing room
    readonly property color bg:          '#111111'   // background paling dalam
    readonly property color bgElevated:  "#181818"   // panel, bar
    readonly property color bgHover:     "#1e1e1e"   // hover state

    // Surface
    readonly property color surface:        "#1e1e1e"   // card background
    readonly property color surfaceVariant: "#272727"   // inner card / item hover

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