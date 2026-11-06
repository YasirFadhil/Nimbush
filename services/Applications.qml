pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "." as Services

Singleton {
    id: root

    property var appList: (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []
    property string query: ""
    property var filteredApps: []

    // Internal cache of preprocessed search tokens
    property var _indexedApps: []
    property var _allApps: []
    property var _known: ({})

    // ── Frecency (learns what you launch, and for which query) ───────────
    // key -> { count, last, q: { "<query typed>": count } }
    readonly property string _stateFile: Quickshell.env("HOME") + "/.local/state/nimbush/launcher-frecency.json"
    property var _usage: ({})
    property bool _usageLoaded: false

    // Quickshell is started from its config directory. Explicitly set Kitty's
    // working directory so a terminal opened by the shell still starts at home.
    function launch(app) {
        if (!app) return
        recordLaunch(app)
        const appId = String(app.id || "").toLowerCase().replace(/\.desktop$/, "")
        if (appId === "kitty") {
            Quickshell.execDetached(["kitty", "--directory", Quickshell.env("HOME")])
            return
        }
        if (typeof app.execute === "function") app.execute()
    }

    onAppListChanged: debounceTimer.restart()
    onQueryChanged: updateFiltered()

    Timer {
        id: debounceTimer
        interval: 60
        repeat: false
        onTriggered: root._rebuildIndex()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { debounceTimer.restart() }
        function onRowsInserted() { debounceTimer.restart() }
        function onRowsRemoved() { debounceTimer.restart() }
        function onModelReset() { debounceTimer.restart() }
    }

    Component.onCompleted: {
        _rebuildIndex()
        debounceTimer.restart()
    }

    // ── Persistence ──────────────────────────────────────────────────────
    Process {
        id: usageReader
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", root._stateFile]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    if (parsed && typeof parsed === "object") root._usage = parsed
                } catch (e) {}
                root._usageLoaded = true
                if (root.query.trim().length > 0) root.updateFiltered()
            }
        }
    }

    Process { id: usageWriter; command: [] }

    Timer {
        id: saveTimer
        interval: 1500
        repeat: false
        onTriggered: root._saveUsage()
    }

    function _saveUsage() {
        if (usageWriter.running) {
            saveTimer.restart()
            return
        }
        usageWriter.command = [
            "sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "sh", root._stateFile, JSON.stringify(root._usage)
        ]
        usageWriter.running = true
    }

    function _keyFor(app) {
        return String((app && (app.id || app.name)) || "").toLowerCase().replace(/\.desktop$/, "")
    }

    function recordLaunch(app) {
        const key = _keyFor(app)
        // Only learn real applications (not desktop actions like "New Window").
        if (!key || !_known[key]) return

        const q = query.toLowerCase().trim()
        const u = _usage[key] || { count: 0, last: 0, q: {} }
        u.count = (u.count || 0) + 1
        u.last = Date.now()
        if (q.length > 0 && q.length <= 24) {
            if (!u.q) u.q = {}
            u.q[q] = (u.q[q] || 0) + 1
            const qs = Object.keys(u.q)
            if (qs.length > 12) {
                qs.sort((a, b) => u.q[a] - u.q[b])
                delete u.q[qs[0]]
            }
        }
        _usage[key] = u
        saveTimer.restart()
    }

    // Recent + frequent apps float up; apps you launched with this exact
    // query prefix before get an extra push.
    function _frecencyBoost(key, q) {
        const u = _usage[key]
        if (!u) return 0
        const ageDays = Math.max(0, (Date.now() - (u.last || 0)) / 86400000)
        const decayed = (u.count || 0) * Math.pow(0.5, ageDays / 21)
        let boost = Math.min(25, 9 * Math.log(1 + decayed) / Math.LN2)
        if (u.q) {
            for (const sq in u.q) {
                if (sq.indexOf(q) === 0) boost += Math.min(22, 8 * u.q[sq])
            }
        }
        return Math.min(45, boost)
    }

    // ── Index ────────────────────────────────────────────────────────────
    function _rebuildIndex() {
        const raw = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []
        const indexed = []
        const known = {}

        for (let i = 0; i < raw.length; i++) {
            const app = raw[i]
            if (!app || !app.name) continue
            const idLower = (app.id || "").toLowerCase()
            if (idLower === "quickshell-settings.desktop" || idLower === "quickshell-settings") continue
            const nameLower = (app.name || "").toLowerCase()
            const descLower = (app.description || app.comment || "").toLowerCase()
            const genericLower = String(app.genericName || "").toLowerCase()

            // Build searchable keyword tokens
            let keywords = []
            if (app.keywords && Array.isArray(app.keywords)) {
                keywords = app.keywords.map(k => String(k).toLowerCase())
            }
            if (app.categories && Array.isArray(app.categories)) {
                keywords = keywords.concat(app.categories.map(c => String(c).toLowerCase()))
            }

            // Pre-resolve icon once during indexing so delegates don't do disk lookups
            let rawIcon = ""
            if (typeof app.icon === "string") {
                rawIcon = app.icon
            } else if (app.icon && app.icon.name) {
                rawIcon = app.icon.name
            }
            if (rawIcon && Services.SystemTheme) {
                app.resolvedIcon = Services.SystemTheme.getIcon(rawIcon)
            } else {
                app.resolvedIcon = ""
            }

            const key = _keyFor(app)
            known[key] = true
            indexed.push({
                app: app,
                key: key,
                name: app.name || "",
                nameLower: nameLower,
                initials: _initials(nameLower),
                genericLower: genericLower,
                descLower: descLower,
                idLower: idLower,
                keywordsPad: " " + keywords.join(" ")
            })
        }

        // Built-in Quickshell system shortcuts
        const settingsIcon = Services.SystemTheme ? Services.SystemTheme.getIcon("preferences-system") : ""
        const builtinApp = {
            name: "Quickshell Settings",
            description: "Configure theme, wallpaper, dynamic island, bar & widgets",
            icon: "preferences-system",
            resolvedIcon: settingsIcon,
            execute: function() { Services.OverlayManager.openSettings() }
        }
        const builtinKey = _keyFor(builtinApp)
        known[builtinKey] = true
        indexed.push({
            app: builtinApp,
            key: builtinKey,
            name: "Quickshell Settings",
            nameLower: "quickshell settings",
            initials: "qs",
            genericLower: "",
            descLower: "configure theme wallpaper dynamic island bar widgets preferences options quickshell pengaturan setelan konfigurasi opsi",
            idLower: "quickshell-settings",
            keywordsPad: " settings config theme preferences island bar lockscreen quickshell pengaturan setelan opsi"
        })

        // Sort base alphabetically (also the tie-break order for equal scores)
        indexed.sort((a, b) => a.name.localeCompare(b.name))

        const all = new Array(indexed.length)
        for (let k = 0; k < indexed.length; k++) {
            all[k] = indexed[k].app
        }
        _allApps = all
        _indexedApps = indexed
        _known = known
        updateFiltered()
    }

    // "Visual Studio Code" -> "vsc"
    function _initials(nameLower) {
        const words = nameLower.split(/[^a-z0-9]+/)
        let out = ""
        for (let i = 0; i < words.length; i++) {
            if (words[i]) out += words[i].charAt(0)
        }
        return out
    }

    // Subsequence match ("ffx" -> "firefox"); tighter spans score higher.
    function _fuzzy(text, t) {
        let ti = 0
        let first = -1
        let last = -1
        for (let i = 0; i < text.length && ti < t.length; i++) {
            if (text.charAt(i) === t.charAt(ti)) {
                if (first < 0) first = i
                last = i
                ti++
            }
        }
        if (ti < t.length) return 0
        const span = last - first + 1
        return 6 + Math.round(12 * t.length / span)
    }

    function _tokenScore(item, t) {
        const n = item.nameLower
        if (n === t) return 100
        if (n.startsWith(t)) return 90
        if (n.indexOf(" " + t) !== -1 || n.indexOf("-" + t) !== -1) return 75
        if (t.length >= 2 && item.initials.startsWith(t)) return 70
        if (n.indexOf(t) !== -1) return 55
        if (item.genericLower.indexOf(t) !== -1) return item.genericLower.startsWith(t) ? 48 : 42
        if (item.keywordsPad.indexOf(t) !== -1) return item.keywordsPad.indexOf(" " + t) !== -1 ? 38 : 32
        if (item.idLower.indexOf(t) !== -1) return 28
        if (item.descLower.indexOf(t) !== -1) return 22
        if (t.length >= 3) return _fuzzy(n, t)
        return 0
    }

    function updateFiltered() {
        const q = query.toLowerCase().trim()
        if (!_indexedApps || _indexedApps.length === 0) {
            filteredApps = []
            return
        }

        if (q.length === 0) {
            if (filteredApps !== _allApps) {
                filteredApps = _allApps
            }
            return
        }

        // Every whitespace-separated token must match something; the final
        // score is the average token score + frecency boost.
        const tokens = q.split(/\s+/)
        const matches = []

        for (let i = 0; i < _indexedApps.length; i++) {
            const item = _indexedApps[i]
            let total = 0
            let ok = true
            for (let t = 0; t < tokens.length; t++) {
                const s = _tokenScore(item, tokens[t])
                if (s <= 0) { ok = false; break }
                total += s
            }
            if (!ok) continue

            const score = total / tokens.length + _frecencyBoost(item.key, q) - item.nameLower.length * 0.05
            matches.push({ app: item.app, name: item.name, score: score })
        }

        matches.sort((a, b) => (b.score - a.score) || a.name.localeCompare(b.name))

        const out = new Array(matches.length)
        for (let m = 0; m < matches.length; m++) out[m] = matches[m].app
        filteredApps = out
    }

    function filtered() {
        return filteredApps
    }
}
