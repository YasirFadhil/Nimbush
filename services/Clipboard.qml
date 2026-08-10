pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var entries: []
    property string query: ""
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

    function filtered() {
        if (query.length === 0) return entries
        const q = query.toLowerCase()
        return entries.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
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