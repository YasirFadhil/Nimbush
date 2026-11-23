import QtQuick
import QtQuick.Layouts
import "../../services" as Services

// macOS-style menu row: accent fill + on-accent text on hover.
// Shared between DockMenu and AppMenu.
Rectangle {
    id: row

    property string label: ""
    property string glyph: ""
    property string shortcut: ""
    property bool hasSubmenu: false
    property bool enabled: true
    property real labelSize: Services.Theme.fontSizeSm
    property bool emphasized: false          // accent-coloured label while idle (e.g. active window)
    readonly property bool hovered: rowMouse.containsMouse
    signal triggered()

    readonly property bool dark: Services.Theme.isDark
    readonly property color idleText: dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.85)
    readonly property color idleGlyph: dark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color fg: !enabled ? Services.Theme.textDisabled : (hovered ? Services.Theme.bgOnAccent : (emphasized ? Services.Theme.accent : idleText))

    Layout.fillWidth: true
    Layout.preferredHeight: 28
    implicitHeight: 28
    radius: 5
    color: (!enabled || !hovered) ? "transparent" : Services.Theme.accent

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Text {
            visible: row.glyph !== ""
            text: row.glyph
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 12
            color: (!row.enabled) ? Services.Theme.textDisabled : (row.hovered ? Services.Theme.bgOnAccent : row.idleGlyph)
        }
        Text {
            text: row.label
            font.pixelSize: row.labelSize
            color: row.fg
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Text {
            visible: row.shortcut !== ""
            text: row.shortcut
            font.pixelSize: row.labelSize - 1
            font.family: Services.Theme.fontMono
            color: (!row.enabled) ? Services.Theme.textDisabled : (row.hovered ? Services.Theme.bgOnAccent : Services.Theme.textDisabled)
        }
        Text {
            visible: row.hasSubmenu
            text: "\uf054" // chevron right
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 10
            color: (!row.enabled) ? Services.Theme.textDisabled : (row.hovered ? Services.Theme.bgOnAccent : Services.Theme.textDisabled)
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: row.enabled
        cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (row.enabled) row.triggered()
        }
    }
}
