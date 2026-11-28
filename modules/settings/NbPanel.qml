import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Rectangle {
    id: panelRoot

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


    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    default property alias content: panelBody.data

    property bool isTile: true
    property bool isFirst: false
    property bool isLast: false

    Layout.fillWidth: true
    color: ui.tile
    topLeftRadius: isFirst ? ui.rOuter : ui.rInner
    topRightRadius: isFirst ? ui.rOuter : ui.rInner
    bottomLeftRadius: isLast ? ui.rOuter : ui.rInner
    bottomRightRadius: isLast ? ui.rOuter : ui.rInner
    Behavior on topLeftRadius { NumberAnimation { duration: 120 } }
    Behavior on topRightRadius { NumberAnimation { duration: 120 } }
    Behavior on bottomLeftRadius { NumberAnimation { duration: 120 } }
    Behavior on bottomRightRadius { NumberAnimation { duration: 120 } }

    onVisibleChanged: if (parent && parent.relayout) parent.relayout()
    Component.onCompleted: if (parent && parent.relayout) parent.relayout()

    implicitHeight: panelCol.implicitHeight + 30

    ColumnLayout {
        id: panelCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 15
        spacing: 14

        RowLayout {
            visible: panelRoot.title.length > 0 || panelRoot.trailing.length > 0
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: panelRoot.title
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: Services.Theme.textPrimary
                    elide: Text.ElideRight
                }
                Text {
                    visible: panelRoot.subtitle.length > 0
                    Layout.fillWidth: true
                    text: panelRoot.subtitle
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Services.Theme.textSecondary
                }
            }
            Rectangle {
                visible: panelRoot.trailing.length > 0
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 26
                implicitWidth: trailText.implicitWidth + 20
                radius: 9
                color: ui.wash(0.16)
                Text {
                    id: trailText
                    anchors.centerIn: parent
                    text: panelRoot.trailing
                    font.pixelSize: 12
                    font.weight: Font.SemiBold
                    color: ui.accent
                }
            }
        }

        ColumnLayout {
            id: panelBody
            Layout.fillWidth: true
            spacing: 10
        }
    }
}
