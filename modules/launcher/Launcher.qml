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

    // ── Adaptive geometry ───────────────────────────────────────────────
    // Width and max height follow the screen; the panel is pinned near the top
    // (like Spotlight) so the search bar never moves while the list grows/shrinks.
    readonly property real screenW: launcherWindow.screen ? launcherWindow.screen.width : 1920
    readonly property real screenH: launcherWindow.screen ? launcherWindow.screen.height : 1080
    readonly property real panelWidth: Math.round(Math.min(640, Math.max(440, screenW * 0.4)))
    readonly property real panelTop: Math.round(screenH * 0.18)
    readonly property real maxPanelHeight: Math.round(Math.min(560, screenH * 0.6))
    readonly property real searchBarHeight: 58
    readonly property real stripHeight: 34
    readonly property real listPadding: 6
    readonly property real rowSpacing: 3

    // Panel height is computed from the rows themselves (deterministic), not from
    // ListView.contentHeight, which is only an estimate for unbuilt delegates.
    readonly property real listContentHeight: contentHeightFor(unifiedResults)
    readonly property real panelTargetHeight: isExpanded
        ? Math.max(searchBarHeight + 1 + 96,
                   Math.min(maxPanelHeight, searchBarHeight + 1 + listContentHeight + listPadding * 2 + stripHeight))
        : searchBarHeight
    readonly property real listViewportHeight: Math.max(0, panelTargetHeight - searchBarHeight - 1 - stripHeight)

    // One searchable list: intents, applications, a web-search action, and matching files.
    property var unifiedResults: []
    property var fileCandidates: []        // raw fd output (paths) for the latest finished search
    property bool fileSearching: false
    property string fileSearchQuery: ""    // query the latest fd run was started for
    property bool resetSelection: true     // true after the user edits the query
    property int shownAppCount: 0
    property int shownFileCount: 0
    property double lastKeyNav: 0          // keyboard navigation timestamp (blocks hover steals)
    readonly property int maxApps: 7
    readonly property int maxFiles: 8
    readonly property string summaryText: shownAppCount + " apps  ·  " + shownFileCount + " files  ·  web"

    property string defaultBrowserDesktopId: ""
    // The provider and the browser handler are independent settings.
    // Change this prefix to change the search engine without hardcoding a browser.
    readonly property string webSearchUrlPrefix: "https://duckduckgo.com/?q="

    // "> command" runs in this terminal. Edit to taste.
    readonly property var terminalCommand: ["kitty", "--directory", Quickshell.env("HOME"), "--hold"]

    // "yt lofi", "nix firefox", ... → straight to that site's search.
    readonly property var webShortcuts: ({
        "yt":   { label: "YouTube",        url: "https://www.youtube.com/results?search_query=" },
        "gh":   { label: "GitHub",         url: "https://github.com/search?q=" },
        "nix":  { label: "NixOS Packages", url: "https://search.nixos.org/packages?query=" },
        "nixo": { label: "NixOS Options",  url: "https://search.nixos.org/options?query=" },
        "aw":   { label: "ArchWiki",       url: "https://wiki.archlinux.org/index.php?search=" },
        "w":    { label: "Wikipedia",      url: "https://en.wikipedia.org/w/index.php?search=" },
        "maps": { label: "Google Maps",    url: "https://www.google.com/maps/search/" }
    })

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

    ListModel { id: rowModel }

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
                // Only accept output that belongs to the query that's still on screen.
                if (launcherWindow.fileSearchQuery !== launcherWindow.searchQuery) return
                const lines = fileSearchOutput.text.split("\n")
                const paths = []
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].trim()
                    if (p) paths.push(p)
                }
                launcherWindow.fileCandidates = paths
                launcherWindow.fileSearching = false
                launcherWindow.scheduleRefresh()
            }
        }
        onExited: fileFollowUp.restart()
    }

    Process { id: openTargetProcess; command: [] }

    Process { id: copyTextProcess; command: [] }

    Timer {
        id: fileSearchDebounce
        interval: 90
        repeat: false
        onTriggered: launcherWindow.runFileSearch(launcherWindow.searchQuery)
    }

    // fd finished: if the user kept typing meanwhile, search again for the latest query.
    // The short delay lets the previous run's stdout finish delivering first.
    Timer {
        id: fileFollowUp
        interval: 30
        repeat: false
        onTriggered: {
            const q = launcherWindow.searchQuery
            if (launcherWindow.fileEligible(q) && launcherWindow.fileSearchQuery !== q) {
                launcherWindow.runFileSearch(q)
            }
        }
    }

    // Smooth keyboard scrolling (we drive contentY ourselves instead of snapping).
    NumberAnimation {
        id: scrollAnim
        target: resultList
        property: "contentY"
        duration: 170
        easing.type: Easing.OutCubic
    }

    Connections {
        target: Services.Applications
        ignoreUnknownSignals: true
        function onFilteredAppsChanged() {
            launcherWindow.scheduleRefresh()
        }
    }

    // ── Row geometry (single source of truth for list + panel height) ────
    function rowHeight(kind) {
        return kind === "section" ? 25 : (kind === "info" ? 32 : 48)
    }

    function contentHeightFor(items) {
        let h = 0
        for (let i = 0; i < items.length; i++) h += rowHeight(items[i].kind)
        if (items.length > 1) h += rowSpacing * (items.length - 1)
        return h
    }

    function yOf(index) {
        let y = 0
        for (let i = 0; i < index && i < unifiedResults.length; i++) {
            y += rowHeight(unifiedResults[i].kind) + rowSpacing
        }
        return y
    }

    function selectableKind(kind) {
        return kind !== "section" && kind !== "info"
    }

    function isSelectable(index) {
        if (index < 0 || index >= unifiedResults.length) return false
        return selectableKind(unifiedResults[index].kind)
    }

    function firstSelectableIndex() {
        for (let i = 0; i < unifiedResults.length; i++) {
            if (isSelectable(i)) return i
        }
        return -1
    }

    // Animate the list so `index` (plus its section header when it's the first
    // row of a section) is fully inside the viewport.
    function ensureVisible(index) {
        if (index < 0 || index >= unifiedResults.length) return
        const anchorIndex = (index > 0 && unifiedResults[index - 1].kind === "section") ? index - 1 : index
        const top = yOf(anchorIndex)
        const bottom = yOf(index) + rowHeight(unifiedResults[index].kind)
        const viewH = listViewportHeight
        const minY = -listPadding
        const maxY = Math.max(minY, contentHeightFor(unifiedResults) + listPadding - viewH)

        let target = scrollAnim.running ? scrollAnim.to : resultList.contentY
        if (top - target < listPadding) target = top - listPadding
        else if (bottom - target > viewH - listPadding) target = bottom + listPadding - viewH
        target = Math.max(minY, Math.min(maxY, target))

        if (!scrollAnim.running && Math.abs(target - resultList.contentY) < 0.5) return
        scrollAnim.stop()
        scrollAnim.to = target
        scrollAnim.start()
    }

    function moveSelection(direction, steps) {
        if (unifiedResults.length <= 0) return
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
            lastKeyNav = Date.now()
            resultList.currentIndex = index
            ensureVisible(index)
        }
    }

    // ── Smart intents ────────────────────────────────────────────────────
    function parseShortcut(q) {
        const m = /^(\S+)\s+(.+)$/.exec(q)
        if (!m) return null
        const id = m[1].toLowerCase()
        if (!Object.prototype.hasOwnProperty.call(webShortcuts, id)) return null
        const sc = webShortcuts[id]
        return { id: id, label: sc.label, rest: m[2].trim(), url: sc.url }
    }

    // Tiny recursive-descent evaluator: numbers, + - * / ^, unary minus, parentheses.
    // Never uses eval, so arbitrary text can't run as code.
    function evalMath(src) {
        const s = src.replace(/\s+/g, "").replace(/×/g, "*").replace(/÷/g, "/")
        let pos = 0
        function peek() { return s.charAt(pos) }
        function parseExpr() {
            let v = parseTerm()
            while (peek() === "+" || peek() === "-") {
                const op = s.charAt(pos++)
                const r = parseTerm()
                v = op === "+" ? v + r : v - r
            }
            return v
        }
        function parseTerm() {
            let v = parsePow()
            while (peek() === "*" || peek() === "/") {
                const op = s.charAt(pos++)
                const r = parsePow()
                v = op === "*" ? v * r : v / r
            }
            return v
        }
        function parsePow() {
            const b = parseUnary()
            if (peek() === "^") {
                pos++
                return Math.pow(b, parsePow())
            }
            return b
        }
        function parseUnary() {
            if (peek() === "-") { pos++; return -parseUnary() }
            if (peek() === "+") { pos++; return parseUnary() }
            return parsePrimary()
        }
        function parsePrimary() {
            if (peek() === "(") {
                pos++
                const v = parseExpr()
                if (peek() !== ")") throw new Error("paren")
                pos++
                return v
            }
            const m = /^(\d+(\.\d+)?|\.\d+)/.exec(s.slice(pos))
            if (!m) throw new Error("num")
            pos += m[0].length
            return parseFloat(m[0])
        }
        try {
            const v = parseExpr()
            if (pos !== s.length) return null
            return v
        } catch (e) {
            return null
        }
    }

    function calcIntent(q) {
        let value = null
        const pct = /^(\d+(?:\.\d+)?)\s*%\s*(?:of|dari)\s*(\d+(?:\.\d+)?)$/i.exec(q)
        if (pct) {
            value = parseFloat(pct[1]) / 100 * parseFloat(pct[2])
        } else {
            if (!/^[\d\s+\-*/^().×÷]+$/.test(q)) return null
            if (!/\d/.test(q)) return null
            if (/^\d{1,4}-\d{1,2}-\d{1,4}$/.test(q)) return null           // looks like a date
            if (!/[+*/^×÷]/.test(q) && !/\d\s*-\s*[\d(.]/.test(q)) return null   // needs an operator
            value = evalMath(q)
        }
        if (value === null || !isFinite(value)) return null
        const text = String(Number(value.toPrecision(12)))
        return {
            kind: "calc", key: "calc",
            name: "= " + text,
            description: q + "  ·  Enter to copy",
            resultText: text,
            glyph: "="
        }
    }

    function urlIntent(q) {
        if (/\s/.test(q)) return null
        let url = ""
        if (/^https?:\/\/\S+$/i.test(q)) {
            url = q
        } else if (/^www\.\S+\.\S+$/i.test(q)
                   || /^[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|dev|id|app|xyz|edu|gov)(\/\S*)?$/i.test(q)) {
            url = "https://" + q
        } else {
            return null
        }
        return {
            kind: "url", key: "url",
            name: "Open " + q,
            description: "Open with " + defaultBrowserName,
            url: url,
            browserIcon: defaultBrowserIcon
        }
    }

    function genericWebItem(query) {
        return {
            kind: "web", key: "web",
            name: 'Search the web for “' + query + '”',
            description: "Open with " + defaultBrowserName,
            query: query,
            browserIcon: defaultBrowserIcon
        }
    }

    // ── Files ────────────────────────────────────────────────────────────
    function fileEligible(q) {
        return q.length >= 2 && !q.startsWith(">") && !parseShortcut(q) && !calcIntent(q) && !urlIntent(q)
    }

    function fileIconName(path) {
        const dot = path.lastIndexOf(".")
        const ext = dot >= 0 ? path.slice(dot + 1).toLowerCase() : ""
        switch (ext) {
        case "png": case "jpg": case "jpeg": case "gif": case "webp": case "svg": case "bmp": case "avif":
            return "image-x-generic"
        case "mp4": case "mkv": case "webm": case "avi": case "mov":
            return "video-x-generic"
        case "mp3": case "flac": case "ogg": case "wav": case "opus": case "m4a":
            return "audio-x-generic"
        case "pdf":
            return "application-pdf"
        case "zip": case "tar": case "gz": case "xz": case "zst": case "7z": case "rar":
            return "package-x-generic"
        case "doc": case "docx": case "odt":
            return "x-office-document"
        case "xls": case "xlsx": case "ods": case "csv":
            return "x-office-spreadsheet"
        case "ppt": case "pptx": case "odp":
            return "x-office-presentation"
        case "sh": case "py": case "js": case "ts": case "qml": case "nix": case "c": case "cpp":
        case "rs": case "go": case "lua": case "json": case "toml": case "yaml": case "yml":
            return "text-x-script"
        default:
            return "text-x-generic"
        }
    }

    function displayDir(path) {
        const home = Quickshell.env("HOME")
        const dir = path.slice(0, path.lastIndexOf("/"))
        return (home && dir.startsWith(home)) ? "~" + dir.slice(home.length) : dir
    }

    // Re-ranks the last fd output against the *current* query, so results narrow
    // instantly while the next fd run is still in flight.
    function rankFiles(query) {
        const tokens = query.toLowerCase().split(/\s+/).filter(t => t.length > 0)
        if (tokens.length === 0) return []
        const home = Quickshell.env("HOME")
        const scored = []

        for (let i = 0; i < fileCandidates.length; i++) {
            const path = fileCandidates[i]
            const lower = path.toLowerCase()
            const slash = lower.lastIndexOf("/")
            const name = lower.slice(slash + 1)

            let total = 0
            let ok = true
            for (let t = 0; t < tokens.length; t++) {
                const tok = tokens[t]
                let s = 0
                if (name === tok) {
                    s = 100
                } else if (name.startsWith(tok)) {
                    s = 80
                } else if (name.indexOf(tok) !== -1) {
                    const at = name.indexOf(tok)
                    s = /[^a-z0-9]/.test(name.charAt(at - 1)) ? 60 : 45
                } else if (lower.indexOf(tok) !== -1) {
                    s = 12                                   // matched only in the folder path
                }
                if (s === 0) { ok = false; break }
                total += s
            }
            if (!ok) continue

            let score = total / tokens.length
            score -= (lower.split("/").length - 1) * 0.6     // shallower first
            const rel = (home && path.startsWith(home)) ? path.slice(home.length) : path
            if (rel.indexOf("/.") !== -1 && tokens[0].charAt(0) !== ".") score -= 15   // hidden stuff last
            scored.push({ path: path, name: path.slice(slash + 1), score: score })
        }

        scored.sort((a, b) => b.score - a.score)
        return scored.slice(0, maxFiles)
    }

    function runFileSearch(query) {
        if (!query || query.length < 2) return
        // Never kill a running fd (that races with its output); the follow-up timer
        // re-runs for the latest query once the current run exits.
        if (fileSearchProcess.running) return
        fileSearchQuery = query

        // Tokens become an ordered regex ("foo bar" → foo.*bar), escaped so the text
        // is never interpreted. Arguments go to fd directly; no shell is involved.
        const tokens = query.split(/\s+/).filter(t => t.length > 0)
        const pattern = tokens.map(t => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*")
        fileSearchProcess.command = [
            "fd", "--type", "f", "--absolute-path", "--hidden",
            "--max-results", "200",
            "--exclude", ".git", "--exclude", ".cache", "--exclude", "node_modules",
            "--exclude", ".local/share/Trash",
            "--", pattern, Quickshell.env("HOME")
        ]
        fileSearchProcess.running = true
    }

    // ── Results ──────────────────────────────────────────────────────────
    // Any number of triggers in one event-loop turn collapse into ONE rebuild.
    function scheduleRefresh() {
        Qt.callLater(refreshUnifiedResults)
    }

    function handleQueryEdited() {
        resetSelection = true
        const q = searchQuery
        if (fileEligible(q)) {
            fileSearching = true
            fileSearchDebounce.restart()
        } else {
            fileSearchDebounce.stop()
            fileSearching = false
            fileCandidates = []
        }
        scheduleRefresh()
    }

    function refreshUnifiedResults() {
        const query = searchQuery
        const prevKey = (!resetSelection && resultList.currentIndex >= 0 && resultList.currentIndex < unifiedResults.length)
            ? unifiedResults[resultList.currentIndex].key : ""

        const items = []
        let appCount = 0
        let fileCount = 0

        if (query) {
            if (query.startsWith(">")) {
                const cmd = query.slice(1).trim()
                items.push({ kind: "section", key: "sec:cmd", name: "Run command" })
                if (cmd) {
                    items.push({
                        kind: "cmd", key: "cmd",
                        name: "Run “" + cmd + "”",
                        description: "Opens in the terminal  ·  Enter to run",
                        command: cmd,
                        glyph: ">"
                    })
                } else {
                    items.push({ kind: "info", key: "info:cmd", name: "Type a command to run in the terminal" })
                }
            } else {
                const shortcut = parseShortcut(query)
                if (shortcut) {
                    items.push({ kind: "section", key: "sec:web", name: "Web search" })
                    items.push({
                        kind: "web", key: "web:" + shortcut.id,
                        name: "Search " + shortcut.label + " for “" + shortcut.rest + "”",
                        description: "Open with " + defaultBrowserName,
                        url: shortcut.url + encodeURIComponent(shortcut.rest),
                        browserIcon: defaultBrowserIcon
                    })
                    items.push(genericWebItem(query))
                } else {
                    const calc = calcIntent(query)
                    const url = urlIntent(query)
                    const quiet = !!(calc || url)
                    if (calc) items.push(calc)
                    if (url) items.push(url)

                    const apps = Services.Applications.filteredApps || []
                    const shown = Math.min(apps.length, maxApps)
                    if (shown > 0 || !quiet) {
                        items.push({ kind: "section", key: "sec:apps", name: "Applications" })
                        if (shown > 0) {
                            for (let i = 0; i < shown; i++) {
                                const app = apps[i]
                                items.push({
                                    kind: "app",
                                    key: "app:" + (app.id || app.name),
                                    name: app.name || app.id || "Application",
                                    description: app.description || app.comment || "Application",
                                    entry: app
                                })
                            }
                        } else {
                            items.push({ kind: "info", key: "info:apps", name: "No matching applications" })
                        }
                    }
                    appCount = shown

                    items.push({ kind: "section", key: "sec:web", name: "Web search" })
                    items.push(genericWebItem(query))

                    if (!quiet) {
                        items.push({ kind: "section", key: "sec:files", name: "Files" })
                        if (query.length < 2) {
                            items.push({ kind: "info", key: "info:files-short", name: "Type at least 2 characters to search files" })
                        } else {
                            const ranked = rankFiles(query)
                            if (ranked.length > 0) {
                                for (let j = 0; j < ranked.length; j++) {
                                    const f = ranked[j]
                                    items.push({
                                        kind: "file",
                                        key: "file:" + f.path,
                                        name: f.name,
                                        path: f.path,
                                        description: displayDir(f.path),
                                        iconName: fileIconName(f.path)
                                    })
                                }
                                fileCount = ranked.length
                            } else if (fileSearching) {
                                items.push({ kind: "info", key: "info:files-searching", name: "Searching files…" })
                            } else {
                                items.push({ kind: "info", key: "info:files-none", name: "No matching files" })
                            }
                        }
                    }
                }
            }
        }

        unifiedResults = items
        shownAppCount = appCount
        shownFileCount = fileCount
        syncRows(items)

        // Keep the same row selected when async results land; jump to the top
        // result only after the user actually edited the query.
        let sel = -1
        if (prevKey) {
            for (let k = 0; k < items.length; k++) {
                if (items[k].key === prevKey && selectableKind(items[k].kind)) { sel = k; break }
            }
        }
        if (sel < 0) sel = firstSelectableIndex()
        resultList.currentIndex = sel

        if (resetSelection) {
            scrollAnim.stop()
            resultList.positionViewAtBeginning()
        }
        resetSelection = false
    }

    // Minimal keyed diff into the ListModel so unchanged rows keep their delegate
    // (no flicker) and real inserts/removals/moves play the ListView transitions.
    function syncRows(items) {
        for (let i = 0; i < items.length; i++) {
            const k = items[i].key
            if (i < rowModel.count && rowModel.get(i).rowKey === k) continue

            let found = -1
            for (let j = i + 1; j < rowModel.count; j++) {
                if (rowModel.get(j).rowKey === k) { found = j; break }
            }
            if (found !== -1) {
                rowModel.remove(i, found - i)
            } else {
                rowModel.insert(i, { rowKey: k, kind: items[i].kind })
            }
        }
        if (rowModel.count > items.length) {
            rowModel.remove(items.length, rowModel.count - items.length)
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────
    function openSelectedResult(item) {
        if (!item) return
        if (item.kind === "web") {
            if (!item.url && !item.query) return
            // xdg-open delegates to the desktop's currently configured default browser.
            const url = item.url || (webSearchUrlPrefix + encodeURIComponent(item.query))
            openTargetProcess.command = ["xdg-open", url]
            openTargetProcess.running = true
            hide()
        } else if (item.kind === "url") {
            openTargetProcess.command = ["xdg-open", item.url]
            openTargetProcess.running = true
            hide()
        } else if (item.kind === "file") {
            if (!item.path) return
            openTargetProcess.command = ["xdg-open", item.path]
            openTargetProcess.running = true
            hide()
        } else if (item.kind === "calc") {
            copyTextProcess.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", item.resultText]
            copyTextProcess.running = true
            hide()
        } else if (item.kind === "cmd") {
            if (!item.command) return
            Quickshell.execDetached(terminalCommand.concat(["sh", "-c", item.command]))
            hide()
        } else if (item.kind === "app" && item.entry && typeof item.entry.execute === "function") {
            hide()
            Services.Applications.launch(item.entry)
        }
    }

    function openContextMenu(app, x, y) {
        contextMenuApp = app
        const menuWidth = 220
        const menuHeight = 180
        contextMenuX = Math.max(10, Math.min(x, panel.width - menuWidth - 10))
        contextMenuY = Math.max(10, Math.min(y, panelTargetHeight - menuHeight - 10))
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
        fileCandidates = []
        fileSearching = false
        resetSelection = true
        searchField.text = ""
        searchField.forceActiveFocus()
        scheduleRefresh()
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
        anchors.horizontalCenter: parent.horizontalCenter
        // Pinned near the top: the search bar stays put while the list grows downward.
        y: launcherWindow.panelTop + (launcherWindow.isOpen ? 0 : -14)
        transformOrigin: Item.Top

        Behavior on y {
            NumberAnimation {
                duration: launcherWindow.isOpen ? 260 : 140
                easing.type: launcherWindow.isOpen ? Easing.OutCubic : Easing.InCubic
            }
        }

        width: launcherWindow.panelWidth
        height: launcherWindow.panelTargetHeight
        clip: true

        // Slightly springy so growth/shrink while typing feels liquid, not mechanical.
        Behavior on height {
            SpringAnimation { spring: 4.2; damping: 0.5; epsilon: 0.5 }
        }

        radius: 16
        color: Services.Theme.surface
        border.color: Services.Theme.border
        border.width: 1

        opacity: launcherWindow.isOpen ? 1 : 0
        scale: launcherWindow.isOpen ? 1 : 0.95

        Behavior on opacity {
            NumberAnimation {
                duration: launcherWindow.isOpen ? 180 : 120
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: launcherWindow.isOpen ? 280 : 140
                easing.type: launcherWindow.isOpen ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.15
            }
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
                                Services.Applications.launch(app)
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
                                    Services.Applications.launch(modelData)
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
                    // Setting the query updates Applications.filteredApps synchronously;
                    // every trigger below is coalesced into a single list rebuild.
                    Services.Applications.query = text
                    launcherWindow.handleQueryEdited()
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

                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0

                    if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                        launcherWindow.moveSelection(1, 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                        launcherWindow.moveSelection(-1, 1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageDown) {
                        launcherWindow.moveSelection(1, 5)
                        event.accepted = true
                    } else if (event.key === Qt.Key_PageUp) {
                        launcherWindow.moveSelection(-1, 5)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        const selected = launcherWindow.unifiedResults[resultList.currentIndex]
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
        // ── RESULTS LIST (rows are diffed into rowModel; data lives in unifiedResults)
        // ═════════════════════════════════════════════════════════════════
        Item {
            id: resultsContainer
            anchors.top: hairlineDivider.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            // Follows the (spring-animated) panel height, so the strip and list stay glued together.
            height: Math.max(0, panel.height - launcherWindow.searchBarHeight - 1 - launcherWindow.stripHeight)
            visible: launcherWindow.isExpanded || panel.height > 60
            opacity: launcherWindow.isExpanded ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            ListView {
                id: resultList
                anchors.fill: parent
                clip: true
                spacing: launcherWindow.rowSpacing
                model: rowModel
                currentIndex: -1
                keyNavigationEnabled: false
                reuseItems: false
                cacheBuffer: 200
                topMargin: launcherWindow.listPadding; bottomMargin: launcherWindow.listPadding
                leftMargin: 8; rightMargin: 8
                boundsBehavior: Flickable.StopAtBounds

                // One highlight that glides between rows (same idea as the tab-menu pill)
                // instead of every row blinking its own background.
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 150
                highlightMoveVelocity: -1
                highlightResizeDuration: 150
                highlight: Rectangle {
                    width: resultList.width - 16
                    height: resultList.currentItem ? resultList.currentItem.height : 48
                    radius: 10
                    color: Services.Theme.surfaceVariant
                    border.color: Services.Theme.accent
                    border.width: 1
                    visible: resultList.currentIndex >= 0
                }

                // Wheel / touch scrolling takes over from the keyboard scroll animation.
                onMovementStarted: scrollAnim.stop()

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 90; easing.type: Easing.OutCubic }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic }
                }

                delegate: Rectangle {
                    id: appItem
                    // Roles stay valid while a row plays its remove transition.
                    required property int index
                    required property string rowKey
                    required property string kind

                    // Content comes from unifiedResults, matched by key. When the row is
                    // leaving (key no longer at this index) the last value is kept, so it
                    // fades out with its real content instead of going blank.
                    property var result: null
                    Binding {
                        target: appItem
                        property: "result"
                        value: launcherWindow.unifiedResults[appItem.index]
                        when: {
                            const r = launcherWindow.unifiedResults[appItem.index]
                            return !!r && r.key === appItem.rowKey
                        }
                        restoreMode: Binding.RestoreNone
                    }

                    readonly property var entry: result && result.kind === "app" ? result.entry : result
                    readonly property bool selectable: launcherWindow.selectableKind(kind)
                    readonly property bool isCurrent: selectable && index === resultList.currentIndex

                    width: resultList.width - 16
                    height: launcherWindow.rowHeight(kind)
                    radius: kind === "section" ? 0 : 10

                    // The moving highlight draws the selection; rows only add a hover tint.
                    color: (selectable && !isCurrent && hoverArea.containsMouse) ? Services.Theme.bgHover : "transparent"
                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    function hoverSelect() {
                        if (!appItem.selectable) return
                        // Keyboard scrolling moves rows under a still mouse; don't let that steal the selection.
                        if (Date.now() - launcherWindow.lastKeyNav < 250) return
                        if (resultList.currentIndex !== appItem.index) resultList.currentIndex = appItem.index
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10
                        visible: appItem.kind === "section"

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
                        visible: appItem.kind === "info"
                        text: appItem.result ? appItem.result.name : ""
                        color: Services.Theme.textDisabled
                        font.pixelSize: Services.Theme.fontSizeSm
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 12
                        visible: appItem.selectable

                        // Icon
                        Item {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter

                            // Fallback glyph/letter if no icon can be loaded
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appItem.isCurrent ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                                visible: !ico.source || ico.status !== Image.Ready || !ico.visible

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        if (!appItem.result) return "?"
                                        if (appItem.result.glyph) return appItem.result.glyph
                                        return (appItem.result.name ? appItem.result.name : "?").charAt(0).toUpperCase()
                                    }
                                    color: appItem.isCurrent ? Services.Theme.accent : Services.Theme.textDisabled
                                    font.pixelSize: Services.Theme.fontSizeXl
                                    font.bold: true
                                }
                            }

                            Image {
                                id: ico
                                anchors.fill: parent
                                source: {
                                    if (!appItem.result) return ""
                                    const k = appItem.result.kind
                                    if (k === "web" || k === "url") {
                                        return launcherWindow.iconSourceForDesktopIcon(appItem.result.browserIcon, "web-browser")
                                    }
                                    if (k === "file") {
                                        return Services.SystemTheme ? Services.SystemTheme.getIcon(appItem.result.iconName || "text-x-generic") : ""
                                    }
                                    if (k === "calc" || k === "cmd") return ""
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
                                visible: appItem.kind === "web"
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

                        // Name & Description
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
                                // Paths are most readable with the middle trimmed, descriptions with the end.
                                elide: appItem.kind === "file" ? Text.ElideMiddle : Text.ElideRight
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
                        onEntered: appItem.hoverSelect()
                        onPositionChanged: appItem.hoverSelect()
                        onClicked: (mouse) => {
                            if (!appItem.selectable || !appItem.result) return
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
            }

            // Empty state (only visible for the brief moment before the first rows arrive)
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
                    text: launcherWindow.summaryText
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
