import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../services" as Services

PanelWindow {
    id: root
    property string overlayId: "sysmonPanel"

    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property string barStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property int barTotalHeight: Services.Config ? (barStyle === "minimal" ? 30 : (barStyle === "unified" ? 38 : (barStyle === "floating" ? 46 : 36))) : 36

    readonly property bool isOpen: Services.OverlayManager.sysmonPanelVisible
    readonly property color tileBg: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    readonly property color tileBgHover: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color tileBorder: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    visible: isOpen || (panel && panel.opacity > 0.01)
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
        focus: root.isOpen
        Keys.onEscapePressed: root.close()
    }

    // Task Model for In-Place Updates (Preserves Scroll Position and Prevents Jump-to-Top)
    ListModel {
        id: taskModel
    }

    function makeTaskEntry(p) {
        return {
            "pid": p.pid,
            "name": String(p.name || "Unknown"),
            "cpu": Number(p.cpu) || 0,
            "mem": Number(p.mem) || 0,
            "rss_str": String(p.rss_str || ""),
            "category": String(p.category || "process")
        }
    }

    function updateTaskModel() {
        const procs = Services.Sysmon.processes
        if (!procs || !Array.isArray(procs) || procs.length === 0) {
            taskModel.clear()
            return
        }

        if (taskListView.moving || taskListView.dragging || taskListView.flicking) {
            return
        }

        if (taskModel.count === 0) {
            for (let i = 0; i < procs.length; i++) {
                taskModel.append(makeTaskEntry(procs[i]))
            }
            return
        }

        // 1. Remove tasks no longer present
        const pidSet = {}
        for (let i = 0; i < procs.length; i++) pidSet[procs[i].pid] = true
        for (let i = taskModel.count - 1; i >= 0; i--) {
            if (!pidSet[taskModel.get(i).pid]) {
                taskModel.remove(i, 1)
            }
        }

        // 2. Move/insert/update in-place without clearing (no blink)
        for (let i = 0; i < procs.length; i++) {
            const p = procs[i]
            let foundIdx = -1
            for (let j = i; j < taskModel.count; j++) {
                if (taskModel.get(j).pid === p.pid) {
                    foundIdx = j
                    break
                }
            }

            if (foundIdx === -1) {
                taskModel.insert(i, makeTaskEntry(p))
            } else {
                if (foundIdx !== i) {
                    taskModel.move(foundIdx, i, 1)
                }
                const m = taskModel.get(i)
                const cpuVal = Number(p.cpu) || 0
                const memVal = Number(p.mem) || 0
                const rssVal = String(p.rss_str || "")
                const nameVal = String(p.name || "Unknown")
                const catVal = String(p.category || "process")

                if (m.cpu !== cpuVal) taskModel.setProperty(i, "cpu", cpuVal)
                if (m.mem !== memVal) taskModel.setProperty(i, "mem", memVal)
                if (m.rss_str !== rssVal) taskModel.setProperty(i, "rss_str", rssVal)
                if (m.name !== nameVal) taskModel.setProperty(i, "name", nameVal)
                if (m.category !== catVal) taskModel.setProperty(i, "category", catVal)
            }
        }

        if (taskModel.count > procs.length) {
            taskModel.remove(procs.length, taskModel.count - procs.length)
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
        enabled: root.isOpen
        onClicked: root.close()

        Rectangle {
            id: panel
            width: 356
            implicitHeight: mainCol.implicitHeight + 32
            readonly property real targetX: Services.OverlayManager.sysmonTargetX > 0
                ? Services.OverlayManager.sysmonTargetX
                : (parent.width - 240)
            x: Math.max(12, Math.min(parent.width - width - 12, targetX - (width / 2)))
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
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ── 1. Clean Header ─────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "System Resources"
                            font.family: Services.Theme.fontPrimary
                            font.bold: true
                            font.pixelSize: Services.Theme.fontSizeXl
                            color: Services.Theme.textPrimary
                        }

                        Text {
                            text: (Services.Sysmon.uptimeStr ? ("up " + Services.Sysmon.uptimeStr + " • ") : "")
                                + (Services.Sysmon.cpuTemp > 0 ? (Math.round(Services.Sysmon.cpuTemp) + "°C") : (Services.Sysmon.cpuCores + " Cores"))
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Sysmon.cpuTemp > 75 ? Services.Theme.warning : Services.Theme.textTertiary
                        }
                    }

                    // Refresh Button
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: refreshBtnArea.containsMouse ? root.tileBgHover : "transparent"

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
                        color: htopBtnArea.containsMouse ? root.tileBgHover : "transparent"

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
                        color: closeBtnArea.containsMouse ? root.tileBgHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: Services.Icons.close
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: closeBtnArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textTertiary
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

                // ── 2. 3-Column Resource Overview ───────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { key: "cpu",  icon: Services.Icons.cpu,     label: "CPU",  warnAt: 50, critAt: 80 },
                            { key: "ram",  icon: Services.Icons.sliders, label: "RAM",  warnAt: 70, critAt: 85 },
                            { key: "disk", icon: Services.Icons.disk,    label: "DISK", warnAt: 80, critAt: 90 }
                        ]
                        delegate: Rectangle {
                            readonly property real val: {
                                const raw = modelData.key === "cpu" ? Services.Sysmon.cpuUsage
                                    : (modelData.key === "ram" ? Services.Sysmon.ramUsage : Services.Sysmon.diskUsage)
                                return Math.max(0, Math.min(100, Number(raw) || 0))
                            }
                            readonly property string detailText: modelData.key === "cpu"
                                ? (Services.Sysmon.cpuCores ? (Services.Sysmon.cpuCores + "c") : "")
                                : (modelData.key === "ram" ? (Services.Sysmon.ramUsedStr || "") : (Services.Sysmon.diskUsedStr || ""))
                            property real animatedVal: val
                            property color ringColor: val > modelData.critAt
                                ? Services.Theme.danger
                                : (val > modelData.warnAt ? Services.Theme.warning : Services.Theme.accent)

                            Behavior on animatedVal { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                            Behavior on ringColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            onAnimatedValChanged: gaugeCanvas.requestPaint()
                            onRingColorChanged: gaugeCanvas.requestPaint()

                            Layout.fillWidth: true
                            implicitHeight: 102
                            radius: Services.Theme.radiusMd
                            color: root.tileBg
                            border.color: root.tileBorder
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: modelData.icon
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 10
                                        color: ringColor
                                    }
                                    Text {
                                        text: modelData.label
                                        font.pixelSize: Services.Theme.fontSizeXs
                                        font.bold: true
                                        color: Services.Theme.textSecondary
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: detailText
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: 9
                                        color: Services.Theme.textTertiary
                                    }
                                }

                                // Circular Donut Gauge
                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 56
                                    height: 56

                                    Canvas {
                                        id: gaugeCanvas
                                        anchors.fill: parent
                                        Component.onCompleted: requestPaint()
                                        onPaint: {
                                            const ctx = getContext("2d")
                                            const w = width
                                            const h = height
                                            ctx.clearRect(0, 0, w, h)

                                            const cx = w / 2
                                            const cy = h / 2
                                            const r = Math.min(cx, cy) - 4
                                            const start = -Math.PI / 2
                                            const pct = Math.max(0, Math.min(100, animatedVal)) / 100.0

                                            // Track ring
                                            ctx.beginPath()
                                            ctx.arc(cx, cy, r, 0, Math.PI * 2, false)
                                            ctx.lineWidth = 4.5
                                            ctx.strokeStyle = Services.Theme.isDark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.08)"
                                            ctx.stroke()

                                            // Active arc
                                            if (pct > 0.005) {
                                                ctx.beginPath()
                                                ctx.arc(cx, cy, r, start, start + (Math.PI * 2 * pct), false)
                                                ctx.lineWidth = 4.5
                                                ctx.lineCap = "round"
                                                ctx.strokeStyle = ringColor.toString()
                                                ctx.stroke()
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Math.round(animatedVal) + "%"
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        font.bold: true
                                        color: val > modelData.critAt ? Services.Theme.danger : Services.Theme.textPrimary
                                        Behavior on color { ColorAnimation { duration: 250 } }
                                    }
                                }
                            }
                        }
                    }
                }

                // Processor Model Caption
                Text {
                    visible: Services.Sysmon.cpuModel && Services.Sysmon.cpuModel.length > 0
                    Layout.fillWidth: true
                    text: Services.Sysmon.cpuModel || ""
                    font.pixelSize: 10
                    color: Services.Theme.textTertiary
                    elide: Text.ElideRight
                }

                // ── 3. Running Tasks Header & Sort ──────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Tasks"
                        font.bold: true
                        font.pixelSize: Services.Theme.fontSizeMd
                        color: Services.Theme.textPrimary
                    }

                    Text {
                        text: "(" + taskModel.count + ")"
                        font.family: Services.Theme.fontMono
                        font.pixelSize: Services.Theme.fontSizeXs
                        color: Services.Theme.textTertiary
                    }

                    Item { Layout.fillWidth: true }

                    // Segmented Sort Pill
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: 78
                        radius: 11
                        color: root.tileBg
                        border.color: root.tileBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 2

                            Repeater {
                                model: [
                                    { key: "cpu", label: "CPU" },
                                    { key: "mem", label: "RAM" }
                                ]
                                delegate: Rectangle {
                                    readonly property bool active: Services.Sysmon.sortBy === modelData.key
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 9
                                    color: active ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.20) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.bold: active
                                        font.pixelSize: 9
                                        color: active ? Services.Theme.accent : Services.Theme.textSecondary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            taskListView.contentY = 0
                                            Services.Sysmon.setSort(modelData.key)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Filter Input
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Services.Theme.radiusSm
                    color: root.tileBg
                    border.color: taskSearchInput.activeFocus ? Services.Theme.accent : root.tileBorder
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

                // ── 4. Tasks ListView ───────────────────────────────────────
                ListView {
                    id: taskListView
                    Layout.fillWidth: true
                    implicitHeight: Math.min(246, Math.max(76, (taskModel.count > 0 ? taskModel.count * 41 : 76)))
                    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: taskModel

                    move: Transition {
                        NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
                    }

                    onMovementEnded: root.updateTaskModel()

                    ScrollBar.vertical: ScrollBar {
                        id: taskScrollBar
                        policy: taskListView.contentHeight > taskListView.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: taskScrollBar.active ? Services.Theme.accent : root.tileBgHover
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    delegate: Item {
                        width: taskListView.width - (taskListView.contentHeight > taskListView.height ? 8 : 0)
                        height: 38

                        readonly property bool isMemSort: Services.Sysmon.sortBy === "mem"
                        readonly property real metricVal: isMemSort ? (Number(model.mem) || 0) : (Number(model.cpu) || 0)
                        readonly property color metricColor: isMemSort
                            ? (metricVal > 20 ? Services.Theme.danger : (metricVal > 10 ? Services.Theme.warning : Services.Theme.accent))
                            : (metricVal > 15 ? Services.Theme.danger : (metricVal > 5 ? Services.Theme.warning : Services.Theme.accent))

                        Rectangle {
                            anchors.fill: parent
                            radius: Services.Theme.radiusSm
                            color: (rowHover.hovered || killMouse.containsMouse) ? root.tileBgHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            HoverHandler {
                                id: rowHover
                                cursorShape: Qt.ArrowCursor
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 8
                                spacing: 8

                                // Rank Number
                                Text {
                                    Layout.preferredWidth: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (index + 1)
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 10
                                    font.weight: index < 3 ? Font.Bold : Font.Normal
                                    color: index < 3 ? Services.Theme.accent : Services.Theme.textDisabled
                                }

                                // Category Icon
                                Text {
                                    text: {
                                        const cat = model.category || "process"
                                        if (cat === "browser") return Services.Icons.wifi
                                        if (cat === "editor") return Services.Icons.file
                                        if (cat === "terminal") return Services.Icons.terminal
                                        if (cat === "media") return Services.Icons.music
                                        return Services.Icons.cpu
                                    }
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 12
                                    color: (rowHover.hovered || killMouse.containsMouse) ? Services.Theme.accent : Services.Theme.textTertiary
                                }

                                // Name + PID / Secondary Metric
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: model.name || "Unknown"
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: isMemSort
                                            ? ("PID " + model.pid + " • " + Math.round(model.cpu || 0) + "% CPU")
                                            : ("PID " + model.pid + (model.rss_str ? (" • " + model.rss_str) : ""))
                                        font.pixelSize: 9
                                        color: Services.Theme.textTertiary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Primary Ranked Metric + Mini Bar
                                ColumnLayout {
                                    Layout.preferredWidth: 52
                                    spacing: 3

                                    Text {
                                        Layout.alignment: Qt.AlignRight
                                        text: (isMemSort && model.rss_str)
                                            ? model.rss_str
                                            : (Math.round(model.cpu || 0) + "%")
                                        font.family: Services.Theme.fontMono
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        color: metricVal > (isMemSort ? 20 : 15)
                                            ? Services.Theme.danger
                                            : (metricVal > (isMemSort ? 10 : 5) ? Services.Theme.warning : Services.Theme.textPrimary)
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 2.5
                                        radius: 1.25
                                        color: Services.Theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)

                                        Rectangle {
                                            height: parent.height
                                            radius: parent.radius
                                            width: Math.max(2, Math.min(parent.width, (Math.min(100, metricVal) / 100.0) * parent.width))
                                            color: metricColor
                                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }
                                }

                                // Smooth Hover Kill Button
                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    opacity: (rowHover.hovered || killMouse.containsMouse) ? 1 : 0
                                    color: killMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.22) : root.tileBg
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

                // Empty / Loading State
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: taskModel.count === 0
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

                // Action Feedback Strip
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 22
                    radius: Services.Theme.radiusSm
                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.14)
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
