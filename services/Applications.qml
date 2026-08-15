pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    property var appList: DesktopEntries.applications.values
    property string query: ""

    function filtered() {
        // Always sort alphabetically; when query is present, starts-with takes priority
        const q = query.toLowerCase().trim()
        const list = appList.slice() // copy to avoid mutating original list

        if (q.length === 0) {
            // All apps, sorted alphabetically
            return list.sort((a, b) => a.name.localeCompare(b.name))
        }

        return list.filter(app => {
            const name = (app.name || "").toLowerCase()
            const desc = (app.description || "").toLowerCase()
            return name.indexOf(q) !== -1 || desc.indexOf(q) !== -1
        }).sort((a, b) => {
            // Priority: names starting with the query float to top
            const aStarts = a.name.toLowerCase().startsWith(q)
            const bStarts = b.name.toLowerCase().startsWith(q)
            if (aStarts && !bStarts) return -1
            if (!aStarts && bStarts) return 1
            return a.name.localeCompare(b.name)
        })
    }
}