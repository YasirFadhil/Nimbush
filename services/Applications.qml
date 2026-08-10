pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    property var appList: DesktopEntries.applications.values
    property string query: ""

    function filtered() {
        // Selalu sort abjad; saat ada query, starts-with naik ke atas
        const q = query.toLowerCase().trim()
        const list = appList.slice() // copy agar tidak mutate

        if (q.length === 0) {
            // Semua app, urut abjad
            return list.sort((a, b) => a.name.localeCompare(b.name))
        }

        return list.filter(app => {
            const name = (app.name || "").toLowerCase()
            const desc = (app.description || "").toLowerCase()
            return name.indexOf(q) !== -1 || desc.indexOf(q) !== -1
        }).sort((a, b) => {
            // Prioritas: nama yang mulai dengan query naik ke atas
            const aStarts = a.name.toLowerCase().startsWith(q)
            const bStarts = b.name.toLowerCase().startsWith(q)
            if (aStarts && !bStarts) return -1
            if (!aStarts && bStarts) return 1
            return a.name.localeCompare(b.name)
        })
    }
}