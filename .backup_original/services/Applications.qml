pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    property var appList: DesktopEntries.applications.values
    property string query: ""
    property var filteredApps: []

    onAppListChanged: updateFiltered()
    onQueryChanged: updateFiltered()

    Component.onCompleted: updateFiltered()

    function updateFiltered() {
        const q = query.toLowerCase().trim()
        const list = (appList || []).slice()

        if (q.length === 0) {
            filteredApps = list.sort((a, b) => (a.name || "").localeCompare(b.name || ""))
            return
        }

        filteredApps = list.filter(app => {
            const name = (app.name || "").toLowerCase()
            const desc = (app.description || "").toLowerCase()
            return name.indexOf(q) !== -1 || desc.indexOf(q) !== -1
        }).sort((a, b) => {
            const aStarts = (a.name || "").toLowerCase().startsWith(q)
            const bStarts = (b.name || "").toLowerCase().startsWith(q)
            if (aStarts && !bStarts) return -1
            if (!aStarts && bStarts) return 1
            return (a.name || "").localeCompare(b.name || "")
        })
    }

    function filtered() {
        return filteredApps
    }
}