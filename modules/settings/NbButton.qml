import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Rectangle {
    id: btn

QtObject {
    id: ui
    readonly property bool dark: Services.Theme.isDark
    readonly property color fg: Services.Theme.textPrimary
    readonly property color accent: Services.Theme.accent
    readonly property color onAccent: Services.Theme.bgOnAccent || "#ffffff"
    readonly property color canvas: Services.Theme.bg
    function tone(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
    function wash(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
    function layer(a) { return Qt.tint(canvas, Qt.rgba(fg.r, fg.g, fg.b, a)) }
    readonly property color tile: layer(dark ? 0.065 : 0.045)
    readonly property color tileHover: layer(dark ? 0.105 : 0.08)
    readonly property int rOuter: 20
    readonly property int rInner: 6
}


    property string text: ""
    property string icon: ""
    property string kind: "tonal"
    property bool active: false
    property bool enabledState: true
    signal clicked()

    readonly property bool _filled: kind === "filled" || active
    readonly property color _tint: kind === "danger" ? Services.Theme.danger : ui.accent

    implicitHeight: 34
    implicitWidth: btnRow.implicitWidth + 28
    radius: 10
    opacity: enabledState ? 1.0 : 0.45
    color: _filled
        ? (btnMouse.containsMouse ? Qt.lighter(_tint, 1.08) : _tint)
        : (kind === "outline"
            ? (btnMouse.containsMouse ? ui.tone(0.07) : "transparent")
            : (btnMouse.containsMouse
                ? Qt.rgba(_tint.r, _tint.g, _tint.b, 0.24)
                : (kind === "danger" ? Qt.rgba(_tint.r, _tint.g, _tint.b, 0.14) : ui.tone(0.09))))
    border.width: kind === "outline" ? 1.5 : 0
    border.color: ui.tone(0.25)
    scale: btnMouse.pressed ? 0.97 : 1.0
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    RowLayout {
        id: btnRow
        anchors.centerIn: parent
        spacing: 7

        Text {
            visible: btn.icon.length > 0
            text: btn.icon
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 13
            color: btn._filled ? ui.onAccent : btn._tint
        }
        Text {
            visible: btn.text.length > 0
            text: btn.text
            font.pixelSize: 12
            font.weight: Font.Medium
            color: btn._filled ? ui.onAccent : (btn.kind === "danger" ? btn._tint : Services.Theme.textPrimary)
        }
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabledState
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
