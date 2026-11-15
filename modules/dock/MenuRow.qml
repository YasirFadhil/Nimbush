import QtQuick
import QtQuick.Layouts
import "../../services" as Services

// macOS-style menu row: accent fill + on-accent text on hover.
// Used by DockMenu.qml. If modules/dock has a qmldir, add:  MenuRow MenuRow.qml
Rectangle {
    id: row

    property string label: ""
    property string glyph: ""
    property real labelSize: Services.Theme.fontSizeSm
    property bool emphasized: false          // accent-coloured label while idle (e.g. active window)
    readonly property bool hovered: rowMouse.containsMouse
    signal triggered()

    readonly property bool dark: Services.Theme.isDark
    readonly property color idleText: dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0, 0, 0, 0.85)
    readonly property color idleGlyph: dark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color fg: hovered ? Services.Theme.bgOnAccent : (emphasized ? Services.Theme.accent : idleText)

    Layout.fillWidth: true
    Layout.preferredHeight: 28
    implicitHeight: 28
    radius: 5
    color: hovered ? Services.Theme.accent : "transparent"

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
            color: row.hovered ? Services.Theme.bgOnAccent : row.idleGlyph
        }
        Text {
            text: row.label
            font.pixelSize: row.labelSize
            color: row.fg
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.triggered()
    }
}
