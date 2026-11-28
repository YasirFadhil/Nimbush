import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "calendar"

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isCenteredBar: barStyle !== "islands"
    readonly property int barTotalHeight: Services.Config ? (barStyle === "minimal" ? 30 : (barStyle === "unified" ? 38 : (barStyle === "floating" ? 46 : 36))) : 36

    readonly property bool isOpen: Services.OverlayManager.calendarVisible
    readonly property color tileBg: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color tileBgHover: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color tileBorder: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)

    property date viewDate: new Date()
    property date today: new Date()
    readonly property bool isCurrentMonth: viewDate.getMonth() === today.getMonth() && viewDate.getFullYear() === today.getFullYear()

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: isOpen || (panel && panel.opacity > 0.01)
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:calendar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    onIsOpenChanged: {
        if (isOpen) {
            const now = new Date()
            root.today = now
            root.viewDate = now
        }
    }

    Item {
        id: escFocus
        focus: root.isOpen
        Keys.onEscapePressed: root.close()
    }

    function close() {
        Services.OverlayManager.calendarVisible = false
    }
    function hide() { close() }

    Component.onCompleted: Services.OverlayManager.register(root)

    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function firstWeekday(y, m) { return new Date(y, m, 1).getDay() }

    function shiftMonth(delta) {
        viewDate = new Date(viewDate.getFullYear(), viewDate.getMonth() + delta, 1)
    }

    function buildGrid() {
        const y = viewDate.getFullYear()
        const m = viewDate.getMonth()
        const total = daysInMonth(y, m)
        const startOffset = firstWeekday(y, m)
        const prevTotal = daysInMonth(y, m - 1)
        const cells = []

        for (let i = startOffset - 1; i >= 0; i--) {
            cells.push({ day: prevTotal - i, offset: -1 })
        }
        for (let d = 1; d <= total; d++) {
            cells.push({ day: d, offset: 0 })
        }
        const rem = (7 - (cells.length % 7)) % 7
        for (let d = 1; d <= rem; d++) {
            cells.push({ day: d, offset: 1 })
        }
        return cells
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isOpen
        onClicked: root.close()

        Rectangle {
            id: panel
            width: 304
            implicitHeight: col.implicitHeight + 32
            x: root.isCenteredBar ? Math.round((parent.width - width) / 2) : (parent.width - width - 12)
            y: root.isBottom ? (parent.height - height - 12) : 12
            radius: 20
            color: Services.Theme.isDark ? Qt.rgba(0.14, 0.14, 0.15, 0.62) : Qt.rgba(1, 1, 1, 0.66)
            border.color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
            border.width: 1
            clip: true

            opacity: root.isOpen ? 1.0 : 0.0
            scale: root.isOpen ? 1.0 : 0.96
            transform: Translate {
                y: root.isOpen ? 0 : (root.isBottom ? 20 : -20)
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── 1. Header ───────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.viewDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                            font.family: Services.Theme.fontPrimary
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeXl
                            color: Services.Theme.textPrimary
                        }

                        Text {
                            text: root.today.toLocaleDateString(Qt.locale(), "dddd, MMM d")
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textTertiary
                        }
                    }

                    // "Today" quick jump pill (when viewing another month)
                    Rectangle {
                        visible: !root.isCurrentMonth
                        implicitWidth: todayLabel.implicitWidth + 14
                        height: 22
                        radius: 11
                        color: todayMouse.containsMouse
                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22)
                            : root.tileBg
                        border.color: todayMouse.containsMouse ? Services.Theme.accent : root.tileBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: todayLabel
                            anchors.centerIn: parent
                            text: "Today"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: todayMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }

                        MouseArea {
                            id: todayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewDate = new Date()
                        }
                    }

                    // Prev / Next Month Buttons
                    Repeater {
                        model: [
                            { delta: -1, icon: Services.Icons.chevLeft },
                            { delta:  1, icon: Services.Icons.chevRight }
                        ]
                        delegate: Rectangle {
                            width: 24; height: 24; radius: 12
                            color: navMouse.containsMouse ? root.tileBgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 11
                                color: navMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.shiftMonth(modelData.delta)
                            }
                        }
                    }
                }

                // ── 2. Calendar Grid ────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: gridCol.implicitHeight + 16
                    radius: Services.Theme.radiusMd
                    color: root.tileBg
                    border.color: root.tileBorder
                    border.width: 1

                    ColumnLayout {
                        id: gridCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        // Weekday Headers
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            columnSpacing: 2

                            Repeater {
                                model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: (index === 0 || index === 6) ? Services.Theme.textDisabled : Services.Theme.textTertiary
                                }
                            }
                        }

                        // Days Grid
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            columnSpacing: 2
                            rowSpacing: 2

                            Repeater {
                                model: root.buildGrid()

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index

                                    readonly property bool inMonth: modelData.offset === 0
                                    readonly property bool isToday: inMonth
                                        && modelData.day === root.today.getDate()
                                        && root.isCurrentMonth
                                    readonly property bool isWeekend: (index % 7 === 0) || (index % 7 === 6)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: 8
                                    color: isToday
                                        ? Services.Theme.accent
                                        : (dayMouse.containsMouse ? root.tileBgHover : "transparent")
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        font.weight: isToday ? Font.Bold : (inMonth ? Font.Medium : Font.Normal)
                                        color: isToday
                                            ? Services.Theme.bgOnAccent
                                            : (!inMonth
                                                ? Services.Theme.textDisabled
                                                : (dayMouse.containsMouse
                                                    ? Services.Theme.accent
                                                    : (isWeekend ? Services.Theme.textSecondary : Services.Theme.textPrimary)))
                                        opacity: inMonth ? 1.0 : 0.45
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                    }

                                    MouseArea {
                                        id: dayMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: !inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (!inMonth) root.shiftMonth(modelData.offset)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
