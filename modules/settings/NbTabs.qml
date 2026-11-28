import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Item {
    id: tabsRoot

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


    property var model: []          // [{ id, label, icon }]
    property var currentValue: 0
    signal selected(var val)

    Layout.fillWidth: true
    implicitHeight: 48

    readonly property int curIdx: {
        for (let i = 0; i < model.length; i++) if (model[i].id === currentValue) return i
        return -1
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: ui.tone(0.10)
    }

    RowLayout {
        id: tabsRow
        anchors.fill: parent
        anchors.bottomMargin: 1
        spacing: 2

        Repeater {
            id: tabsRep
            model: tabsRoot.model
            delegate: Item {
                id: tabItem
                required property var modelData
                required property int index
                readonly property bool isCur: index === tabsRoot.curIdx
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    radius: 12
                    color: ui.tone(0.06)
                    opacity: (!tabItem.isCur && tabMouse.containsMouse) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }

                RowLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 8, implicitWidth)
                    spacing: 7

                    Text {
                        visible: !!tabItem.modelData.icon
                        text: tabItem.modelData.icon || ""
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 14
                        color: tabItem.isCur ? ui.accent : Services.Theme.textSecondary
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: tabItem.modelData.label
                        font.pixelSize: 13
                        font.weight: tabItem.isCur ? Font.SemiBold : Font.Medium
                        color: tabItem.isCur ? Services.Theme.textPrimary : Services.Theme.textSecondary
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tabsRoot.selected(tabItem.modelData.id)
                }
            }
        }
    }

    Rectangle {
        id: tabsInk
        visible: tabsRoot.curIdx >= 0
        anchors.bottom: parent.bottom
        height: 3
        radius: 2
        color: ui.accent
        x: {
            var c = tabsRep.count
            var it = tabsRep.itemAt(tabsRoot.curIdx)
            return it ? it.x + 14 : 0
        }
        width: {
            var c = tabsRep.count
            var it = tabsRep.itemAt(tabsRoot.curIdx)
            return it ? Math.max(0, it.width - 28) : 0
        }
        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    }
}
