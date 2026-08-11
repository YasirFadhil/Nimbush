pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var entries: []
    property string query: ""
    property string filterType: "all" // "all", "text", "image", "pinned"
    property var pinnedIds: []
    property var _buffer: []

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.length === 0) return
                const tabIdx = data.indexOf("\t")
                if (tabIdx === -1) return
                root._buffer.push({
                    id: data.substring(0, tabIdx),
                    preview: data.substring(tabIdx + 1)
                })
            }
        }
        onExited: {
            root.entries = root._buffer
            root._buffer = []
        }
    }

    // fix: reusable Process instead of Qt.createQmlObject tiap panggil
    Process { id: selectProc }
    Process {
        id: deleteProc
        onExited: root.refresh()   // auto-refresh list abis delete
    }

    function refresh() {
        _buffer = []
        listProc.running = true
    }

    function togglePin(entry) {
        if (!entry || !entry.id) return
        const idx = pinnedIds.indexOf(entry.id)
        if (idx !== -1) {
            pinnedIds.splice(idx, 1)
        } else {
            pinnedIds.push(entry.id)
        }
        pinnedIds = pinnedIds.slice() // re-assign to trigger binding update
    }

    function isPinned(entry) {
        return entry && entry.id ? pinnedIds.indexOf(entry.id) !== -1 : false
    }

    function filtered() {
        let list = entries
        if (filterType === "text") {
            list = list.filter(e => !isImageEntry(e))
        } else if (filterType === "image") {
            list = list.filter(e => isImageEntry(e))
        } else if (filterType === "pinned") {
            list = list.filter(e => isPinned(e))
        }
        if (query.length === 0) return list
        const q = query.toLowerCase()
        return list.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
    }

    function select(entry) {
        selectProc.command = ["sh", "-c", "cliphist decode '" + entry.id + "' | wl-copy"]
        selectProc.running = true
    }

    function deleteEntry(entry) {
        deleteProc.command = ["cliphist", "delete-query", entry.id]
        deleteProc.running = true
    }
// adad

    function isImageEntry(entry) {
        return /binary data.*\b(png|jpe?g|gif|bmp|webp)\b/i.test(entry.preview)
    }
}