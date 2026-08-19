import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "calendar"

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.calendarVisible
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:calendar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Item {
        id: escFocus
        focus: Services.OverlayManager.calendarVisible
        Keys.onEscapePressed: root.close()
    }

    property date viewDate: new Date()
    readonly property date today: new Date()
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false

    function close() {
        Services.OverlayManager.calendarVisible = false
    }
    function hide() { close() }

    Component.onCompleted: Services.OverlayManager.register(root)

    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function firstWeekday(y, m) { return new Date(y, m, 1).getDay() }

    function buildGrid() {
        const y = viewDate.getFullYear()
        const m = viewDate.getMonth()
        const total = daysInMonth(y, m)
        const startOffset = firstWeekday(y, m)
        const cells = []
        for (let i = 0; i < startOffset; i++) cells.push(0)
        for (let d = 1; d <= total; d++) cells.push(d)
        return cells
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: panel
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: root.isBottom ? (parent.height - height - 12) : 12
            width: 300
            height: col.implicitHeight + 32
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.calendarVisible ? 1 : 0
            transform: Translate {
                y: Services.OverlayManager.calendarVisible ? 0 : (root.isBottom ? 32 : -32)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            }
            scale: Services.OverlayManager.calendarVisible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: root.viewDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                        color: Services.Theme.textPrimary
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 6
                        color: prevMonthMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.chevLeft
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: prevMonthMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: prevMonthMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() - 1, 1)
                        }
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 6
                        color: nextMonthMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.chevRight
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: nextMonthMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: nextMonthMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewDate = new Date(root.viewDate.getFullYear(), root.viewDate.getMonth() + 1, 1)
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 4

                    Repeater {
                        model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                        Text {
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            font.pixelSize: 10
                            color: Services.Theme.textDisabled
                        }
                    }

                    Repeater {
                        model: root.buildGrid()

                        Rectangle {
                            required property int modelData
                            required property int index

                            readonly property bool isToday: modelData > 0
                                && modelData === root.today.getDate()
                                && root.viewDate.getMonth() === root.today.getMonth()
                                && root.viewDate.getFullYear() === root.today.getFullYear()

                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 30
                            radius: 8
                            color: isToday ? Services.Theme.accent : (modelData > 0 && dayMouse.containsMouse ? Services.Theme.bgHover : "transparent")
                            border.color: (!isToday && modelData > 0 && dayMouse.containsMouse) ? Services.Theme.border : "transparent"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData > 0 ? modelData : ""
                                font.pixelSize: 11
                                font.bold: isToday
                                color: isToday ? Services.Theme.bgOnAccent : (dayMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: dayMouse
                                anchors.fill: parent
                                enabled: modelData > 0
                                hoverEnabled: true
                                cursorShape: modelData > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                        }
                    }
                }
            }
        }
    }
}
