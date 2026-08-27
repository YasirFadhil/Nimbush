pragma Singleton
import Quickshell
import QtQuick
import "." as Services

Singleton {
    id: root

    property var appList: DesktopEntries.applications.values
    property string query: ""
    property var filteredApps: []

    // Internal cache of preprocessed search tokens
    property var _indexedApps: []

    onAppListChanged: _rebuildIndex()
    onQueryChanged: updateFiltered()

    Connections {
        target: Services.SystemTheme
        function onIconThemeRevChanged() {
            root._rebuildIndex()
        }
    }

    Component.onCompleted: _rebuildIndex()

    function _rebuildIndex() {
        const raw = DesktopEntries.applications.values || []
        const indexed = []

        for (let i = 0; i < raw.length; i++) {
            const app = raw[i]
            if (!app || !app.name) continue
            const idLower = (app.id || "").toLowerCase()
            if (idLower === "quickshell-settings.desktop" || idLower === "quickshell-settings") continue
            const nameLower = (app.name || "").toLowerCase()
            const descLower = (app.description || app.comment || "").toLowerCase()

            // Build searchable keyword tokens
            let keywords = []
            if (app.keywords && Array.isArray(app.keywords)) {
                keywords = app.keywords.map(k => String(k).toLowerCase())
            }
            if (app.categories && Array.isArray(app.categories)) {
                keywords = keywords.concat(app.categories.map(c => String(c).toLowerCase()))
            }

            indexed.push({
                app: app,
                name: app.name || "",
                nameLower: nameLower,
                descLower: descLower,
                idLower: idLower,
                keywordsLower: keywords.join(" ")
            })
        }

        // Built-in Quickshell system shortcuts
        const builtins = [
            {
                app: {
                    name: "Quickshell Settings",
                    description: "Configure theme, wallpaper, dynamic island, bar & widgets",
                    icon: "preferences-system",
                    execute: function() { Services.OverlayManager.openSettings() }
                },
                name: "Quickshell Settings",
                nameLower: "quickshell settings",
                descLower: "configure theme wallpaper dynamic island bar widgets preferences options quickshell pengaturan setelan konfigurasi opsi",
                idLower: "quickshell-settings",
                keywordsLower: "settings config theme preferences island bar lockscreen quickshell pengaturan setelan opsi"
            }
        ]

        for (let b = 0; b < builtins.length; b++) {
            indexed.push(builtins[b])
        }

        // Sort base alphabetically
        indexed.sort((a, b) => a.name.localeCompare(b.name))
        _indexedApps = indexed
        updateFiltered()
    }

    function updateFiltered() {
        const q = query.toLowerCase().trim()
        if (!_indexedApps || _indexedApps.length === 0) {
            filteredApps = []
            return
        }

        if (q.length === 0) {
            const res = new Array(_indexedApps.length)
            for (let i = 0; i < _indexedApps.length; i++) {
                res[i] = _indexedApps[i].app
            }
            filteredApps = res
            return
        }

        // Score-based fast matching:
        // 1. Name starts with query (e.g. "term" -> "Terminal")
        // 2. Word in name starts with query (e.g. "code" -> "Visual Studio Code")
        // 3. Name contains query substring
        // 4. Keyword / Category / Description / ID match
        const exactStarts = []
        const wordStarts = []
        const nameContains = []
        const descMatches = []

        const qWord = " " + q

        for (let i = 0; i < _indexedApps.length; i++) {
            const item = _indexedApps[i]
            const n = item.nameLower

            if (n.startsWith(q)) {
                exactStarts.push(item.app)
            } else if (n.indexOf(qWord) !== -1) {
                wordStarts.push(item.app)
            } else if (n.indexOf(q) !== -1) {
                nameContains.push(item.app)
            } else if (item.keywordsLower.indexOf(q) !== -1 || item.descLower.indexOf(q) !== -1 || item.idLower.indexOf(q) !== -1) {
                descMatches.push(item.app)
            }
        }

        filteredApps = exactStarts.concat(wordStarts, nameContains, descMatches)
    }

    function filtered() {
        return filteredApps
    }
}