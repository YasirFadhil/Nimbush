import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "sysmonPanel"

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool isFloating: barStyle === "floating"
    readonly property int barTotalHeight: Services.Config ? (Services.Config.barStyle === "minimal" ? 30 : (Services.Config.barStyle === "unified" ? 38 : (Services.Config.barStyle === "floating" ? 46 : 36))) : 36

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: Services.OverlayManager.sysmonPanelVisible
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:sysmon"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: 0
            y: root.isBottom ? 0 : root.barTotalHeight
            width: root.width
            height: root.height - root.barTotalHeight
        }
    }

    function open() {
        Services.OverlayManager.closeAllExcept(root)
        Services.OverlayManager.sysmonPanelVisible = true
        if (taskSearchInput) taskSearchInput.text = ""
        Services.Sysmon.setSearch("")
        Services.Sysmon.refreshTasks()
    }

    function close() {
        Services.OverlayManager.sysmonPanelVisible = false
    }

    function hide() { close() }
    function show() { open() }
    function toggle() {
        if (Services.OverlayManager.sysmonPanelVisible) close()
        else open()
    }

    onVisibleChanged: {
        if (visible) {
            if (taskSearchInput) taskSearchInput.text = ""
            Services.Sysmon.setSearch("")
            Services.Sysmon.refreshTasks()
        }
    }

    Component.onCompleted: Services.OverlayManager.register(root)

    Item {
        id: escFocus
        focus: Services.OverlayManager.sysmonPanelVisible
        Keys.onEscapePressed: root.close()
    }

    // Task Model for In-Place Updates (Preserves Scroll Position and Prevents Jump-to-Top)
    ListModel {
        id: taskModel
    }

    function updateTaskModel() {
        const procs = Services.Sysmon.processes
        if (!procs || !Array.isArray(procs) || procs.length === 0) {
            taskModel.clear()
            return
        }

        // If user is actively dragging or scrolling the list, defer update
        if (taskListView.moving || taskListView.dragging || taskListView.flicking) {
            return
        }

        const currentScrollY = taskListView.contentY

        // 1. Initial population if empty
        if (taskModel.count === 0) {
            for (let i = 0; i < procs.length; i++) {
                const p = procs[i]
                taskModel.append({
                    "pid": p.pid,
                    "name": String(p.name || "Unknown"),
                    "cpu": Number(p.cpu) || 0,
                    "mem": Number(p.mem) || 0,
                    "rss_str": String(p.rss_str || ""),
                    "category": String(p.category || "process")
                })
            }
            return
        }

        // 2. Check if item count and PID order match exactly
        let sameOrder = (taskModel.count === procs.length)
        if (sameOrder) {
            for (let i = 0; i < procs.length; i++) {
                if (taskModel.get(i).pid !== procs[i].pid) {
                    sameOrder = false
                    break
                }
            }
        }

        if (sameOrder) {
            // FAST PATH: In-place property updates (zero scroll jumping, zero delegate destruction)
            for (let i = 0; i < procs.length; i++) {
                const m = taskModel.get(i)
                const p = procs[i]
                if (m.cpu !== p.cpu) taskModel.setProperty(i, "cpu", Number(p.cpu) || 0)
                if (m.mem !== p.mem) taskModel.setProperty(i, "mem", Number(p.mem) || 0)
                if (m.rss_str !== p.rss_str) taskModel.setProperty(i, "rss_str", String(p.rss_str || ""))
                if (m.name !== p.name) taskModel.setProperty(i, "name", String(p.name || "Unknown"))
                if (m.category !== p.category) taskModel.setProperty(i, "category", String(p.category || "process"))
            }
            return
        }

        // 3. Fallback: Rebuild and restore exact scroll position
        taskModel.clear()
        for (let i = 0; i < procs.length; i++) {
            const p = procs[i]
            taskModel.append({
                "pid": p.pid,
                "name": String(p.name || "Unknown"),
                "cpu": Number(p.cpu) || 0,
                "mem": Number(p.mem) || 0,
                "rss_str": String(p.rss_str || ""),
                "category": String(p.category || "process")
            })
        }

        if (currentScrollY > 0) {
            Qt.callLater(() => {
                const maxY = Math.max(0, taskListView.contentHeight - taskListView.height)
                taskListView.contentY = Math.min(currentScrollY, maxY)
            })
        }
    }

    Connections {
        target: Services.Sysmon
        function onProcessesChanged() {
            root.updateTaskModel()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()

        Rectangle {
            id: panel
            width: 365
            implicitHeight: mainCol.implicitHeight + 28
            readonly property real targetX: Services.OverlayManager.sysmonTargetX > 0 
                ? Services.OverlayManager.sysmonTargetX 
                : (parent.width - 240)
            x: Math.max(12, Math.min(parent.width - width - 12, targetX - (width / 2)))
            y: root.isBottom ? (parent.height - height - 12) : 12
            radius: Services.Theme.radiusLg
            color: Services.Theme.surface
            border.color: Services.Theme.border
            border.width: 1
            clip: true

            opacity: Services.OverlayManager.sysmonPanelVisible ? 1 : 0
            transform: Translate {
                y: Services.OverlayManager.sysmonPanelVisible ? 0 : (root.isBottom ? 24 : -24)
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            scale: Services.OverlayManager.sysmonPanelVisible ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent; onClicked: {} }

            ColumnLayout {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // ── 1. Modern Minimal Header ────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Activity Icon Pill
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.14)

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.cpu
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 13
                            color: Services.Sysmon.cpuUsage > 80 ? Services.Theme.danger : Services.Theme.accent
                        }
                    }

                    Text {
                        text: "System Resources"
                        font.family: Services.Theme.fontPrimary
                        font.bold: true
                        font.pixelSize: Services.Theme.fontSizeXl
                        color: Services.Theme.textPrimary
                        Layout.fillWidth: true
                    }

                    // Status Badge (Uptime & Temp)
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: statusBadgeText.implicitWidth + 12
                        radius: 11
                        color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.7)
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        Text {
                            id: statusBadgeText
                            anchors.centerIn: parent
                            text: (Services.Sysmon.uptimeStr ? (Services.Sysmon.uptimeStr + " • ") : "") + (Services.Sysmon.cpuTemp > 0 ? (Math.round(Services.Sysmon.cpuTemp) + "°C") : (Services.Sysmon.cpuCores + " Cores"))
                            font.pixelSize: Services.Theme.fontSizeXs
                            font.bold: true
                            color: Services.Sysmon.cpuTemp > 75 ? Services.Theme.warning : Services.Theme.accent
                        }
                    }

                    // Refresh Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: refreshBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: refreshIconText
                            anchors.centerIn: parent
                            text: Services.Icons.refresh
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: refreshBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary

                            RotationAnimation {
                                target: refreshIconText
                                property: "rotation"
                                from: 0; to: 360; duration: 750
                                loops: Animation.Infinite
                                running: Services.Sysmon.isLoadingTasks
                            }
                        }
                        MouseArea {
                            id: refreshBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Sysmon.refreshTasks()
                        }
                    }

                    // Launch Full Task Manager Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: htopBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.terminal
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: htopBtnArea.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: htopBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Sysmon.launchTaskManager()
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: closeBtnArea.containsMouse ? Services.Theme.bgHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: closeBtnArea.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                        }
                        MouseArea {
                            id: closeBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }

                // ── 2. Balanced 3-Column Resource Overview ───────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // CPU Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 80
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: Services.Icons.cpu
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Sysmon.cpuUsage > 80 ? Services.Theme.danger : Services.Theme.accent
                                }
                                Text {
                                    text: "CPU"
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.bold: true
                                    color: Services.Theme.textSecondary
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: (Services.Sysmon.cpuCores ? (Services.Sysmon.cpuCores + "c") : "")
                                    font.pixelSize: 9
                                    color: Services.Theme.textDisabled
                                }
                            }

                            Text {
                                text: Math.round(Services.Sysmon.cpuUsage) + "%"
                                font.family: Services.Theme.fontMono
                                font.pixelSize: Services.Theme.fontSize2xl
                                font.bold: true
                                color: Services.Sysmon.cpuUsage > 80 ? Services.Theme.danger : (Services.Sysmon.cpuUsage > 50 ? Services.Theme.warning : Services.Theme.textPrimary)
                            }

                            // Slim Progress Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 3
                                radius: 1.5
                                color: Services.Theme.bgDeep

                                Rectangle {
                                    height: parent.height
                                    radius: parent.radius
                                    width: Math.max(3, Math.min(parent.width, (Services.Sysmon.cpuUsage / 100.0) * parent.width))
                                    color: Services.Sysmon.cpuUsage > 80 ? Services.Theme.danger : (Services.Sysmon.cpuUsage > 50 ? Services.Theme.warning : Services.Theme.accent)
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                        }
                    }

                    // RAM Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 80
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: Services.Icons.sliders
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Sysmon.ramUsage > 85 ? Services.Theme.danger : Services.Theme.accent
                                }
                                Text {
                                    text: "RAM"
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.bold: true
                                    color: Services.Theme.textSecondary
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: Services.Sysmon.ramUsedStr || ""
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 9
                                    color: Services.Theme.textDisabled
                                }
                            }

                            Text {
                                text: Math.round(Services.Sysmon.ramUsage) + "%"
                                font.family: Services.Theme.fontMono
                                font.pixelSize: Services.Theme.fontSize2xl
                                font.bold: true
                                color: Services.Sysmon.ramUsage > 85 ? Services.Theme.danger : (Services.Sysmon.ramUsage > 70 ? Services.Theme.warning : Services.Theme.textPrimary)
                            }

                            // Slim Progress Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 3
                                radius: 1.5
                                color: Services.Theme.bgDeep

                                Rectangle {
                                    height: parent.height
                                    radius: parent.radius
                                    width: Math.max(3, Math.min(parent.width, (Services.Sysmon.ramUsage / 100.0) * parent.width))
                                    color: Services.Sysmon.ramUsage > 85 ? Services.Theme.danger : (Services.Sysmon.ramUsage > 70 ? Services.Theme.warning : Services.Theme.accent)
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                        }
                    }

                    // Disk Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 80
                        radius: Services.Theme.radiusMd
                        color: Services.Theme.surfaceVariant
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: Services.Icons.disk
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: "DISK"
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.bold: true
                                    color: Services.Theme.textSecondary
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: Services.Sysmon.diskUsedStr || ""
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 9
                                    color: Services.Theme.textDisabled
                                }
                            }

                            Text {
                                text: Math.round(Services.Sysmon.diskUsage) + "%"
                                font.family: Services.Theme.fontMono
                                font.pixelSize: Services.Theme.fontSize2xl
                                font.bold: true
                                color: Services.Sysmon.diskUsage > 90 ? Services.Theme.danger : Services.Theme.textPrimary
                            }

                            // Slim Progress Bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 3
                                radius: 1.5
                                color: Services.Theme.bgDeep

                                Rectangle {
                                    height: parent.height
                                    radius: parent.radius
                                    width: Math.max(3, Math.min(parent.width, (Services.Sysmon.diskUsage / 100.0) * parent.width))
                                    color: Services.Sysmon.diskUsage > 90 ? Services.Theme.danger : Services.Theme.accent
                                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }
                            }
                        }
                    }
                }

                // Subtle Processor Model Strip
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 22
                    radius: Services.Theme.radiusSm
                    color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.45)
                    visible: Services.Sysmon.cpuModel && Services.Sysmon.cpuModel.length > 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: Services.Icons.info
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: Services.Theme.textDisabled
                        }

                        Text {
                            text: Services.Sysmon.cpuModel || "Processor"
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                // ── 3. Running Tasks Header & Controls ──────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Running Tasks"
                        font.bold: true
                        font.pixelSize: Services.Theme.fontSizeMd
                        color: Services.Theme.textPrimary
                    }

                    // Count Badge
                    Rectangle {
                        implicitHeight: 18
                        implicitWidth: taskCountText.implicitWidth + 10
                        radius: 9
                        color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.7)
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        Text {
                            id: taskCountText
                            anchors.centerIn: parent
                            text: taskModel.count
                            font.pixelSize: 9
                            font.bold: true
                            color: Services.Theme.textSecondary
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Seamless Segmented Sort Pill
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: 80
                        radius: 11
                        color: Services.Theme.bgDeep
                        border.color: Services.Theme.borderSubtle
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0
                            anchors.margins: 2

                            // CPU Sort Segment
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 9
                                readonly property bool active: Services.Sysmon.sortBy === "cpu"
                                color: active ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22) : "transparent"
                                border.color: active ? Services.Theme.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "CPU"
                                    font.bold: parent.active
                                    font.pixelSize: 9
                                    color: parent.active ? Services.Theme.accent : Services.Theme.textSecondary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        taskListView.contentY = 0
                                        Services.Sysmon.setSort("cpu")
                                    }
                                }
                            }

                            // RAM Sort Segment
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 9
                                readonly property bool active: Services.Sysmon.sortBy === "mem"
                                color: active ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.22) : "transparent"
                                border.color: active ? Services.Theme.accent : "transparent"
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "RAM"
                                    font.bold: parent.active
                                    font.pixelSize: 9
                                    color: parent.active ? Services.Theme.accent : Services.Theme.textSecondary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        taskListView.contentY = 0
                                        Services.Sysmon.setSort("mem")
                                    }
                                }
                            }
                        }
                    }
                }

                // Mini Search Input Bar
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: Services.Theme.radiusSm
                    color: Services.Theme.bgDeep
                    border.color: taskSearchInput.activeFocus ? Services.Theme.accent : Services.Theme.borderSubtle
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Text {
                            text: Services.Icons.search
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 10
                            color: taskSearchInput.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                        }

                        TextInput {
                            id: taskSearchInput
                            Layout.fillWidth: true
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textPrimary
                            selectionColor: Services.Theme.accent
                            selectedTextColor: Services.Theme.bgOnAccent
                            clip: true
                            onTextChanged: {
                                taskListView.contentY = 0
                                Services.Sysmon.setSearch(text)
                            }

                            Text {
                                text: "Filter processes..."
                                font.pixelSize: Services.Theme.fontSizeXs
                                color: Services.Theme.textDisabled
                                visible: !taskSearchInput.text && !taskSearchInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 9
                            color: clearSearchMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                            visible: taskSearchInput.text.length > 0

                            MouseArea {
                                id: clearSearchMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    taskSearchInput.text = ""
                                    taskListView.contentY = 0
                                    Services.Sysmon.setSearch("")
                                }
                            }
                        }
                    }
                }

                // ── 4. Scrollable Modern Tasks ListView with In-Place Stability ──
                ListView {
                    id: taskListView
                    Layout.fillWidth: true
                    implicitHeight: Math.min(250, Math.max(76, (taskModel.count > 0 ? taskModel.count * 38 : 76)))
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: taskModel

                    onMovementEnded: {
                        root.updateTaskModel()
                    }

                    ScrollBar.vertical: ScrollBar {
                        id: taskScrollBar
                        policy: taskListView.contentHeight > taskListView.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: taskScrollBar.active ? Services.Theme.accent : Qt.rgba(Services.Theme.borderHighlight.r, Services.Theme.borderHighlight.g, Services.Theme.borderHighlight.b, 0.6)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    delegate: Item {
                        id: delegateRoot
                        width: taskListView.width - (taskListView.contentHeight > taskListView.height ? 8 : 0)
                        height: 36

                        Rectangle {
                            id: taskRow
                            anchors.fill: parent
                            radius: Services.Theme.radiusSm
                            color: (rowHover.hovered || killMouse.containsMouse) ? Services.Theme.bgHover : "transparent"
                            border.color: (rowHover.hovered || killMouse.containsMouse) ? Services.Theme.borderSubtle : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            // Native HoverHandler: Completely eliminates flickering
                            HoverHandler {
                                id: rowHover
                                cursorShape: Qt.ArrowCursor
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Category Icon Avatar
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 11
                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, (rowHover.hovered || killMouse.containsMouse) ? 0.22 : 0.12)
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            const cat = model.category || "process"
                                            if (cat === "browser") return Services.Icons.wifi
                                            if (cat === "editor") return Services.Icons.file
                                            if (cat === "terminal") return Services.Icons.terminal
                                            if (cat === "media") return Services.Icons.music
                                            return Services.Icons.cpu
                                        }
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 10
                                        color: Services.Theme.accent
                                    }
                                }

                                // Process Name & PID/Memory Info
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        text: model.name || "Unknown"
                                        font.bold: true
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: "PID " + model.pid + (model.rss_str ? (" • " + model.rss_str) : "")
                                        font.pixelSize: 9
                                        color: Services.Theme.textSecondary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Usage Metric Text (CPU % or RAM)
                                Text {
                                    text: {
                                        if (Services.Sysmon.sortBy === "mem" && model.rss_str) {
                                            return model.rss_str
                                        }
                                        return Math.round(model.cpu || 0) + "%"
                                    }
                                    font.family: Services.Theme.fontMono
                                    font.bold: true
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    color: (model.cpu || 0) > 15 ? Services.Theme.danger : ((model.cpu || 0) > 5 ? Services.Theme.warning : Services.Theme.textPrimary)
                                }

                                // Smooth Hover Kill Button
                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 10
                                    opacity: (rowHover.hovered || killMouse.containsMouse) ? 1 : 0
                                    color: killMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.25) : Services.Theme.bgDeep
                                    border.color: killMouse.containsMouse ? Services.Theme.danger : Services.Theme.borderSubtle
                                    border.width: 1
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.close
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 8
                                        color: killMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                                    }

                                    MouseArea {
                                        id: killMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Sysmon.killTask(model.pid, false)
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty / Loading State fallback
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 50
                    color: "transparent"
                    visible: taskModel.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: Services.Sysmon.isLoadingTasks ? Services.Icons.spinner : Services.Icons.checkCircle
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 14
                            color: Services.Theme.textDisabled
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: Services.Sysmon.isLoadingTasks ? "Loading processes..." : "No matching tasks found"
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textDisabled
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                // Action Feedback Strip (if killed recently)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 20
                    radius: Services.Theme.radiusSm
                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12)
                    visible: Services.Sysmon.lastActionMessage && Services.Sysmon.lastActionMessage.length > 0

                    Text {
                        anchors.centerIn: parent
                        text: Services.Sysmon.lastActionMessage
                        font.pixelSize: Services.Theme.fontSizeXs
                        color: Services.Theme.accent
                    }
                }
            }
        }
    }
}
