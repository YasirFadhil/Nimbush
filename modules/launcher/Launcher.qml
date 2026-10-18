import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../services" as Services

PanelWindow {
    id: launcherWindow
    visible: false

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell:launcher"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Component.onCompleted: {
        Services.OverlayManager.register(launcherWindow)
        browserLookupProcess.running = true
    }

    property bool isOpen: false
    readonly property bool hasQuery: searchField.text.trim().length > 0
    readonly property bool isExpanded: hasQuery
    readonly property string searchQuery: searchField.text.trim()

    property var contextMenuApp: null
    property real contextMenuX: 0
    property real contextMenuY: 0
    readonly property bool isContextMenuOpen: contextMenuApp !== null

    // One searchable list: applications, a web-search action, and matching files.
    property var unifiedResults: []
    property string fileSearchQuery: ""
    property string defaultBrowserDesktopId: ""
    // The provider and the browser handler are independent settings.
    // Change this prefix to change the search engine without hardcoding a browser.
    readonly property string webSearchUrlPrefix: "https://duckduckgo.com/?q="

    function resolveDefaultBrowserEntry(rawId) {
        const id = (rawId || "").trim()
        if (!id) return null

        // Desktop IDs can differ in how a desktop environment exposes them.
        // Try exact IDs first, then common normalized variants.
        const leafId = id.split(/[\\/]/).pop()
        const plainId = leafId.replace(/\.desktop$/i, "")
        const candidates = [id, leafId, plainId]
        for (let i = 0; i < candidates.length; i++) {
            if (!candidates[i]) continue
            const entry = DesktopEntries.byId(candidates[i])
            if (entry) return entry
        }

        // Some desktop entry indexes need the application-name heuristic.
        // Prefer variants derived from the system-selected desktop ID.
        for (let j = 0; j < candidates.length; j++) {
            if (!candidates[j]) continue
            const entry = DesktopEntries.heuristicLookup(candidates[j])
            if (entry) return entry
        }
        return null
    }

    function browserNameFromId(rawId) {
        const id = (rawId || "").trim()
        if (!id) return "Default browser"
        const name = id.split(/[\\/]/).pop().replace(/\.desktop$/i, "")
            .replace(/([a-z])([A-Z])/g, "$1 $2")
            .replace(/[._-]+/g, " ")
        return name || "Default browser"
    }

    function iconSourceForDesktopIcon(rawIcon, fallback) {
        const icon = String(rawIcon || fallback || "")
        if (!icon) return ""

        // Desktop files are allowed to specify either an icon-theme name or a path.
        // Keep absolute paths intact; only send theme names through SystemTheme.
        if (icon.startsWith("/") || icon.startsWith("file://") || icon.startsWith("qrc:/")) {
            return icon
        }
        return Services.SystemTheme ? Services.SystemTheme.getIcon(icon) : ""
    }

    readonly property var defaultBrowserEntry: resolveDefaultBrowserEntry(defaultBrowserDesktopId)
    readonly property string defaultBrowserName: defaultBrowserEntry && defaultBrowserEntry.name
        ? defaultBrowserEntry.name : browserNameFromId(defaultBrowserDesktopId)
    readonly property string defaultBrowserIcon: defaultBrowserEntry && defaultBrowserEntry.icon
        ? defaultBrowserEntry.icon : "web-browser"

    ListModel { id: fileResults }

    Process {
        id: browserLookupProcess
        command: ["xdg-mime", "query", "default", "x-scheme-handler/https"]
        stdout: StdioCollector {
            id: browserLookupOutput
            onStreamFinished: {
                const httpsId = browserLookupOutput.text.trim()
                if (httpsId.length > 0) {
                    launcherWindow.defaultBrowserDesktopId = httpsId
                    launcherWindow.refreshUnifiedResults()
                } else {
                    browserLookupHttpProcess.running = true
                }
            }
        }
    }

    // A few desktop setups define an HTTP handler but not an HTTPS handler.
    Process {
        id: browserLookupHttpProcess
        command: ["xdg-mime", "query", "default", "x-scheme-handler/http"]
        stdout: StdioCollector {
            onStreamFinished: {
                const httpId = text.trim()
                if (httpId.length > 0) {
                    launcherWindow.defaultBrowserDesktopId = httpId
                    launcherWindow.refreshUnifiedResults()
                } else {
                    browserLookupSettingsProcess.running = true
                }
            }
        }
    }

    // Last fallback for desktop environments that expose the default browser via xdg-settings.
    Process {
        id: browserLookupSettingsProcess
        command: ["xdg-settings", "get", "default-web-browser"]
        stdout: StdioCollector {
            onStreamFinished: {
                launcherWindow.defaultBrowserDesktopId = text.trim()
                launcherWindow.refreshUnifiedResults()
            }
        }
    }

    Process {
        id: fileSearchProcess
        command: []
        stdout: StdioCollector {
            id: fileSearchOutput
            onStreamFinished: {
                // Ignore output from a cancelled search if the query has already changed.
                if (launcherWindow.fileSearchQuery !== launcherWindow.searchQuery) return
                fileResults.clear()
                if (launcherWindow.searchQuery.length < 2) {
                    launcherWindow.refreshUnifiedResults()
                    return
                }
                const lines = fileSearchOutput.text.split("\n")
                for (let i = 0; i < lines.length && i < 80; i++) {
                    const path = lines[i].trim()
                    if (!path) continue
                    const parts = path.split("/")
                    fileResults.append({
                        name: parts[parts.length - 1],
                        path: path,
                        description: path,
                        kind: "file"
                    })
                }
                launcherWindow.refreshUnifiedResults()
            }
        }
    }

    Process { id: openTargetProcess; command: [] }

    Timer {
        id: fileSearchDebounce
        interval: 140
        repeat: false
        onTriggered: launcherWindow.runFileSearch(launcherWindow.searchQuery)
    }

    Connections {
        target: Services.Applications
        ignoreUnknownSignals: true
        function onFilteredAppsChanged() {
            launcherWindow.refreshUnifiedResults()
        }
    }

    function isSelectable(index) {
        if (index < 0 || index >= unifiedResults.length) return false
        const kind = unifiedResults[index].kind
        return kind !== "section" && kind !== "info"
    }

    function firstSelectableIndex() {
        for (let i = 0; i < unifiedResults.length; i++) {
            if (isSelectable(i)) return i
        }
        return -1
    }

    function moveSelection(direction, steps) {
        if (resultList.count <= 0) return
        let index = resultList.currentIndex
        for (let step = 0; step < steps; step++) {
            let candidate = index + direction
            while (candidate >= 0 && candidate < unifiedResults.length && !isSelectable(candidate)) {
                candidate += direction
            }
            if (candidate < 0 || candidate >= unifiedResults.length) break
            index = candidate
        }
        if (isSelectable(index)) {
            resultList.currentIndex = index
            resultList.positionViewAtIndex(index, ListView.Contain)
        }
    }

    function refreshUnifiedResults() {
        const query = searchQuery
        if (!query) {
            unifiedResults = []
            return
        }

        const items = []
        const apps = Services.Applications.filteredApps || []

        items.push({ kind: "section", name: "Applications" })
        if (apps.length > 0) {
            for (let i = 0; i < apps.length; i++) {
                const app = apps[i]
                items.push({
                    kind: "app",
                    name: app.name || app.id || "Application",
                    description: app.description || app.comment || "Application",
                    entry: app
                })
            }
        } else {
            items.push({ kind: "info", name: "No matching applications" })
        }

        items.push({ kind: "section", name: "Web search" })
        items.push({
            kind: "web",
            name: 'Search the web for “' + query + '”',
            description: "Open with " + defaultBrowserName,
            query: query,
            browserIcon: defaultBrowserIcon
        })

        items.push({ kind: "section", name: "Files" })
        if (query.length < 2) {
            items.push({ kind: "info", name: "Type at least 2 characters to search files" })
        } else if (fileResults.count > 0) {
            for (let j = 0; j < fileResults.count; j++) {
                const file = fileResults.get(j)
                items.push({
                    kind: "file",
                    name: file.name,
                    path: file.path,
                    description: file.path
                })
            }
        } else {
            items.push({ kind: "info", name: "No matching files" })
        }

        unifiedResults = items
        if (!isSelectable(resultList.currentIndex)) {
            resultList.currentIndex = firstSelectableIndex()
        }
    }

    function runFileSearch(query) {
        fileResults.clear()
        refreshUnifiedResults()
        if (!query || query.length < 2) return
        // Pass arguments directly to fd; the search text is never evaluated by a shell.
        fileSearchQuery = query
        fileSearchProcess.running = false
        fileSearchProcess.command = ["fd", "--type", "f", "--absolute-path", "--hidden", "--fixed-strings", "--max-results", "80", "--exclude", ".git", "--exclude", ".cache", "--exclude", "node_modules", query, Quickshell.env("HOME")]
        fileSearchProcess.running = true
    }

    function openSelectedResult(item) {
        if (!item) return
        if (item.kind === "web") {
            if (!item.query) return
            // xdg-open delegates to the desktop's currently configured default browser.
            // The search provider is configured separately above (DuckDuckGo by default).
            const url = webSearchUrlPrefix + encodeURIComponent(item.query)
            openTargetProcess.command = ["xdg-open", url]
            openTargetProcess.running = true
            hide()
        } else if (item.kind === "file") {
            if (!item.path) return
            openTargetProcess.command = ["xdg-open", item.path]
            openTargetProcess.running = true
            hide()
        } else if (item.kind === "app" && item.entry && typeof item.entry.execute === "function") {
            hide()
            item.entry.execute()
        }
    }

    function openContextMenu(app, x, y) {
        contextMenuApp = app
        const menuWidth = 220
        const menuHeight = 180
        contextMenuX = Math.max(10, Math.min(x, panel.width - menuWidth - 10))
        contextMenuY = Math.max(10, Math.min(y, panel.height - menuHeight - 10))
    }

    function closeContextMenu() {
        contextMenuApp = null
    }

    function show() {
        closeContextMenu()
        Services.OverlayManager.closeAllExcept(launcherWindow)
        hideTimer.stop()
        visible = true
        isOpen = true
        Services.Applications.query = ""
        fileResults.clear()
        searchField.text = ""
        searchField.forceActiveFocus()
        resultList.currentIndex = 0
        if (resultList.count > 0) {
            resultList.positionViewAtIndex(0, ListView.Beginning)
        }
    }

    function hide() {
        if (!isOpen) return
        closeContextMenu()
        isOpen = false
        hideTimer.restart()
    }

    function toggle() { isOpen ? hide() : show() }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: {
            launcherWindow.visible = false
            Services.Applications.query = ""
        }
    }

    // Click outside panel → close
    MouseArea {
        anchors.fill: parent
        onClicked: launcherWindow.hide()
    }

    // ── Panel ─────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: launcherWindow.isOpen ? -40 : -20

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        width: 540
        height: launcherWindow.isExpanded ? 460 : 58
        clip: true

        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        radius: 16
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: launcherWindow.isOpen ? 1 : 0
        scale: launcherWindow.isOpen ? 1 : 0.97

        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MouseArea { 
            anchors.fill: parent 
            onClicked: {
                if (launcherWindow.isContextMenuOpen) {
                    launcherWindow.closeContextMenu()
                }
            }
        }

        // ── Floating App Context Menu ────────────────────────────────────────
        MouseArea {
            anchors.fill: parent
            visible: launcherWindow.isContextMenuOpen
            z: 98
            onClicked: launcherWindow.closeContextMenu()
        }

        Rectangle {
            id: contextMenuBox
            visible: launcherWindow.isContextMenuOpen
            z: 99
            x: launcherWindow.contextMenuX
            y: launcherWindow.contextMenuY
            width: 220
            height: menuCol.implicitHeight + 16
            radius: 12
            color: Services.Theme.bgElevated
            border.color: Services.Theme.borderHighlight
            border.width: 1

            // Specular top highlight
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                height: 1
                color: Qt.rgba(1, 1, 1, 0.15)
            }

            ColumnLayout {
                id: menuCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                spacing: 4

                // Header with App Title & Desktop ID
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 4
                    spacing: 2

                    Text {
                        text: launcherWindow.contextMenuApp ? (launcherWindow.contextMenuApp.name || "") : ""
                        font.pixelSize: Services.Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Services.Theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: launcherWindow.contextMenuApp ? (launcherWindow.contextMenuApp.id || "Desktop Application") : ""
                        font.family: Services.Theme.fontMono
                        font.pixelSize: 10
                        color: Services.Theme.textDisabled
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Services.Theme.border
                    opacity: 0.6
                }

                // 1. Launch Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    color: launchMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: Services.Icons.play || "▶"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: Services.Theme.accent
                        }
                        Text {
                            text: "Launch"
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: Services.Theme.textPrimary
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: launchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const app = launcherWindow.contextMenuApp
                            launcherWindow.closeContextMenu()
                            launcherWindow.hide()
                            if (app && typeof app.execute === "function") {
                                app.execute()
                            }
                        }
                    }
                }

                // 2. Pin / Unpin Action
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    readonly property bool pinned: (launcherWindow.contextMenuApp && Services.DockService) ? Services.DockService.isPinned(launcherWindow.contextMenuApp.id) : false
                    color: pinMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: Services.Icons.pin || "󰤩"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: parent.parent.pinned ? Services.Theme.danger : Services.Theme.accent
                        }
                        Text {
                            text: parent.parent.pinned ? "Unpin from Dock" : "Pin to Dock"
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: parent.parent.pinned ? Services.Theme.danger : Services.Theme.textPrimary
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: pinMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const app = launcherWindow.contextMenuApp
                            if (app && app.id && Services.DockService) {
                                Services.DockService.togglePin(app.id)
                            }
                            launcherWindow.closeContextMenu()
                        }
                    }
                }

                // 3. Desktop Entry Actions (e.g. New Window, Private Window)
                Repeater {
                    model: (launcherWindow.contextMenuApp && launcherWindow.contextMenuApp.actions) ? launcherWindow.contextMenuApp.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 30
                        radius: 6
                        color: actMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: "✦"
                                font.pixelSize: 10
                                color: Services.Theme.textSecondary
                            }
                            Text {
                                text: modelData.name || "Action"
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                launcherWindow.closeContextMenu()
                                launcherWindow.hide()
                                if (typeof modelData.execute === "function") {
                                    modelData.execute()
                                }
                            }
                        }
                    }
                }

                // 4. Copy Desktop ID
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    radius: 6
                    color: copyMouse.containsMouse ? Services.Theme.bgHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: Services.Icons.disk || "📋"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: Services.Theme.textSecondary
                        }
                        Text {
                            text: "Copy App ID"
                            font.pixelSize: Services.Theme.fontSizeXs
                            color: Services.Theme.textSecondary
                            Layout.fillWidth: true
                        }
                    }

                    Process {
                        id: copyProc
                        command: []
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const app = launcherWindow.contextMenuApp
                            if (app && app.id) {
                                copyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", app.id]
                                copyProc.running = true
                            }
                            launcherWindow.closeContextMenu()
                        }
                    }
                }
            }
        }

        // ── Search Bar ────────────────────────────────────────────
        RowLayout {
            id: searchBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 58
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10
            z: 10

            Text {
                text: Services.Icons.search
                font.family: Services.Theme.fontSymbols
                font.pixelSize: Services.Theme.fontSize2xl
                color: searchField.activeFocus ? Services.Theme.accent : Services.Theme.textDisabled
                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                background: null
                color: Services.Theme.textPrimary
                placeholderText: "Search apps, files, or the web..."
                placeholderTextColor: Services.Theme.textDisabled
                font.pixelSize: Services.Theme.fontSize3xl
                leftPadding: 0
                rightPadding: 0

                onTextChanged: {
                    const query = text.trim()
                    Services.Applications.query = text
                    // Invalidate in-flight results immediately while the next query is debounced.
                    if (query !== launcherWindow.fileSearchQuery) {
                        launcherWindow.fileSearchQuery = ""
                        fileResults.clear()
                    }
                    if (query.length >= 2) {
                        fileSearchDebounce.restart()
                    } else {
                        fileSearchDebounce.stop()
                        fileSearchProcess.running = false
                        fileResults.clear()
                    }
                    launcherWindow.refreshUnifiedResults()
                    resultList.currentIndex = launcherWindow.firstSelectableIndex()
                    if (resultList.currentIndex >= 0) {
                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Beginning)
                    }
                }

                Keys.onPressed: (event) => {
                    // Global Settings Shortcut: Ctrl+, or Ctrl+S or Alt+S
                    if ((event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_Comma || event.key === Qt.Key_S)) ||
                        (event.modifiers & Qt.AltModifier && event.key === Qt.Key_S)) {
                        launcherWindow.hide()
                        Services.OverlayManager.openSettings()
                        event.accepted = true
                        return
                    }

                    if (event.key === Qt.Key_Down) {
                        launcherWindow.moveSelection(1, 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        launcherWindow.moveSelection(-1, 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageDown) {
                        launcherWindow.moveSelection(1, 5)
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageUp) {
                        launcherWindow.moveSelection(-1, 5)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        const selected = resultList.currentItem ? resultList.currentItem.result : null
                        if (selected && launcherWindow.isSelectable(resultList.currentIndex)) {
                            launcherWindow.openSelectedResult(selected)
                        }
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        if (launcherWindow.isContextMenuOpen) {
                            launcherWindow.closeContextMenu()
                            event.accepted = true
                            return
                        }
                        launcherWindow.hide()
                        event.accepted = true
                    }
                }
            }

            // Clear button
            Text {
                text: "✕"
                font.pixelSize: Services.Theme.fontSizeLg
                color: clearMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textDisabled
                visible: searchField.text.length > 0
                Layout.alignment: Qt.AlignVCenter

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: {
                        searchField.text = ""
                        searchField.forceActiveFocus()
                    }
                }
            }

            // Dedicated Quick Settings Button
            Rectangle {
                width: 26; height: 26; radius: 6
                color: settingsBtnMouse.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                Layout.alignment: Qt.AlignVCenter
                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                Text {
                    anchors.centerIn: parent
                    text: Services.Icons.settings
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: Services.Theme.fontSizeMd
                    color: settingsBtnMouse.containsMouse ? Services.Theme.accent : Services.Theme.textDisabled
                    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: settingsBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        launcherWindow.hide()
                        Services.OverlayManager.openSettings()
                    }
                }
            }
        }

        // Hairline divider
        Rectangle {
            id: hairlineDivider
            anchors.top: searchBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Services.Theme.border
            opacity: launcherWindow.isExpanded ? 0.6 : 0
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            z: 10
        }

        // ═════════════════════════════════════════════════════════════════
        // ── APPLICATIONS LIST VIEW CONTAINER (Fixed Geometry for Smooth GPU Clip)
        // ═════════════════════════════════════════════════════════════════
        Item {
            id: resultsContainer
            anchors.top: hairlineDivider.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 367
            visible: launcherWindow.isExpanded || panel.height > 60
            opacity: launcherWindow.isExpanded ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            ListView {
                id: resultList
                anchors.fill: parent
                clip: true
                spacing: 3
                model: launcherWindow.unifiedResults
                currentIndex: 0
                keyNavigationEnabled: false
                reuseItems: true
                cacheBuffer: 96
                topMargin: 6; bottomMargin: 6
                leftMargin: 8; rightMargin: 8
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: appItem
                    required property var modelData
                    required property int index
                    readonly property var result: modelData
                    readonly property var entry: result && result.kind === "app" ? result.entry : result
                    width: resultList.width - 16
                    height: result && result.kind === "section" ? 25 : (result && result.kind === "info" ? 32 : 48)
                    radius: result && result.kind === "section" ? 0 : 10

                    readonly property bool isCurrent: launcherWindow.isSelectable(appItem.index) && appItem.index === resultList.currentIndex

                    color: isCurrent
                        ? Services.Theme.surfaceVariant
                        : (hoverArea.containsMouse && launcherWindow.isSelectable(appItem.index) ? Services.Theme.bgHover : "transparent")
                    border.color: isCurrent ? Services.Theme.accent : "transparent"
                    border.width: isCurrent ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10
                        visible: appItem.result && appItem.result.kind === "section"

                        Text {
                            text: appItem.result ? appItem.result.name.toUpperCase() : ""
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Services.Theme.border
                            opacity: 0.8
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: appItem.result && appItem.result.kind === "info"
                        text: appItem.result ? appItem.result.name : ""
                        color: Services.Theme.textDisabled
                        font.pixelSize: Services.Theme.fontSizeSm
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 12
                        visible: appItem.result && appItem.result.kind !== "section" && appItem.result.kind !== "info"

                        // App Icon
                        Item {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter

                            // Fallback letter if icon cannot be loaded
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appItem.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
                                visible: !ico.source || ico.status !== Image.Ready || !ico.visible

                                Text {
                                    anchors.centerIn: parent
                                    text: (appItem.result && appItem.result.name ? appItem.result.name : "?").charAt(0).toUpperCase()
                                    color: appItem.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textDisabled
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.bold: true
                                }
                            }

                            Image {
                                id: ico
                                anchors.fill: parent
                                source: {
                                    if (!appItem.result) return ""
                                    if (appItem.result.kind === "web") {
                                        return launcherWindow.iconSourceForDesktopIcon(appItem.result.browserIcon, "web-browser")
                                    }
                                    if (appItem.result.kind === "file") {
                                        return Services.SystemTheme ? Services.SystemTheme.getIcon("text-x-generic") : ""
                                    }
                                    const app = appItem.result.entry
                                    if (!app) return ""
                                    if (app.resolvedIcon) return app.resolvedIcon
                                    const rawIcon = typeof app.icon === "string" ? app.icon : (app.icon?.name || "")
                                    return Services.SystemTheme ? Services.SystemTheme.getIcon(rawIcon) : ""
                                }
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(64, 64)
                                mipmap: true
                                smooth: true
                                visible: ico.status === Image.Ready && ico.source.toString().length > 0
                            }

                            Rectangle {
                                visible: appItem.result && appItem.result.kind === "web"
                                width: 15
                                height: 15
                                radius: 8
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                color: Services.Theme.surface
                                border.color: Services.Theme.border
                                z: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.search
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 8
                                    color: Services.Theme.accent
                                }
                            }
                        }

                        // App Name & Description
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                text: appItem.result ? (appItem.result.name || "") : ""
                                color: appItem.isCurrent ? Services.Theme.accent : Services.Theme.textPrimary
                                font.pixelSize: Services.Theme.fontSizeXl
                                font.weight: appItem.isCurrent ? Font.Medium : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            Text {
                                text: appItem.result ? (appItem.result.description || "") : ""
                                color: Services.Theme.textSecondary
                                font.pixelSize: Services.Theme.fontSizeMd
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (launcherWindow.isSelectable(appItem.index) && resultList.currentIndex !== appItem.index) {
                                resultList.currentIndex = appItem.index
                            }
                        }
                        onClicked: (mouse) => {
                            if (!launcherWindow.isSelectable(appItem.index)) return
                            if (mouse.button === Qt.RightButton) {
                                if (appItem.result.kind !== "app") return
                                const pt = mapToItem(panel, mouse.x, mouse.y)
                                launcherWindow.openContextMenu(appItem.entry, pt.x, pt.y)
                            } else {
                                launcherWindow.closeContextMenu()
                                launcherWindow.openSelectedResult(appItem.result)
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: resultList.count === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: Services.Icons.search
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSize8xl
                            color: Services.Theme.textDisabled
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "Search applications, files, or the web"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXl
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }

        // ── Bottom Action Strip ──────────────────────────────────────
        Rectangle {
            id: bottomStrip
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 34
            color: Services.Theme.bgDeep
            radius: 12
            border.width: 0
            visible: panel.height > 90
            opacity: launcherWindow.isExpanded ? Math.max(0, Math.min(1, (panel.height - 90) / 60)) : 0
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            z: 10

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14; anchors.rightMargin: 14
                spacing: 12

                // App count info
                Text {
                    text: {
                        const appCount = Services.Applications.filteredApps ? Services.Applications.filteredApps.length : 0
                        return appCount + " apps  ·  Web search  ·  " + fileResults.count + " files"
                    }
                    color: Services.Theme.textDisabled
                    font.pixelSize: Services.Theme.fontSizeSm
                }

                Item { Layout.fillWidth: true }

                // Navigation Hints
                RowLayout {
                    spacing: 10

                    RowLayout {
                        spacing: 4
                        Text {
                            text: "↑↓"
                            color: Services.Theme.textSecondary
                            font.pixelSize: Services.Theme.fontSizeXs
                            font.family: Services.Theme.fontMono
                        }
                        Text {
                            text: "Navigate"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }
                    }

                    RowLayout {
                        spacing: 4
                        Text {
                            text: "↵"
                            color: Services.Theme.accent
                            font.pixelSize: Services.Theme.fontSizeSm
                            font.bold: true
                        }
                        Text {
                            text: "Open"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }
                    }

                    RowLayout {
                        spacing: 4
                        Text {
                            text: "Ctrl+,"
                            color: Services.Theme.textSecondary
                            font.pixelSize: Services.Theme.fontSizeXs
                            font.family: Services.Theme.fontMono
                        }
                        Text {
                            text: "Settings"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }
                    }

                    RowLayout {
                        spacing: 4
                        Text {
                            text: "Esc"
                            color: Services.Theme.textSecondary
                            font.pixelSize: Services.Theme.fontSizeXs
                            font.family: Services.Theme.fontMono
                        }
                        Text {
                            text: "Close"
                            color: Services.Theme.textDisabled
                            font.pixelSize: Services.Theme.fontSizeXs
                        }
                    }
                }
            }
        }
    }
}
