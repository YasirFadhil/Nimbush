pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    property var entries: []
    property string query: ""
    property string filterType: "all" // "all", "text", "image", "pinned"
    property var pinnedPreviews: []
    property var pinnedIds: pinnedPreviews
    property var _buffer: []

    Process {
        id: loadPinnedProc
        command: ["sh", "-c", "cat ~/.cache/quickshell/clipboard_pinned.json 2>/dev/null || echo '[]'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data || data.length === 0) return
                try {
                    const parsed = JSON.parse(data)
                    if (Array.isArray(parsed)) {
                        root.pinnedPreviews = parsed
                    }
                } catch (e) {}
            }
        }
    }

    Process { id: savePinnedProc }

    Component.onCompleted: {
        loadPinnedProc.running = true
    }

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

    function savePinned() {
        const jsonStr = JSON.stringify(pinnedPreviews)
        const b64 = Qt.btoa(jsonStr)
        savePinnedProc.command = ["sh", "-c", "mkdir -p ~/.cache/quickshell && echo '" + b64 + "' | base64 -d > ~/.cache/quickshell/clipboard_pinned.json"]
        savePinnedProc.running = true
    }

    function togglePin(entry) {
        if (!entry || !entry.preview) return
        const idx = pinnedPreviews.indexOf(entry.preview)
        if (idx !== -1) {
            pinnedPreviews.splice(idx, 1)
        } else {
            pinnedPreviews.push(entry.preview)
        }
        pinnedPreviews = pinnedPreviews.slice() // re-assign to trigger binding update
        savePinned()
    }

    function isPinned(entry) {
        return entry && entry.preview ? pinnedPreviews.indexOf(entry.preview) !== -1 : false
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
        if (query.length > 0) {
            const q = query.toLowerCase()
            list = list.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
        }

        if (filterType !== "pinned") {
            const pinnedList = list.filter(e => isPinned(e))
            const unpinnedList = list.filter(e => !isPinned(e))
            return pinnedList.concat(unpinnedList)
        }
        return list
    }

    function select(entry) {
        selectProc.command = ["sh", "-c", "cliphist decode '" + entry.id + "' | wl-copy"]
        selectProc.running = true
    }

    Process {
        id: clearAllProc
        onExited: root.refresh()
    }

    function clearAll(includePinned) {
        if (includePinned) {
            pinnedPreviews = []
            savePinned()
            clearAllProc.command = ["cliphist", "wipe"]
            clearAllProc.running = true
            return
        }
        const unpinned = entries.filter(e => !isPinned(e))
        if (unpinned.length === 0) return
        const ids = unpinned.map(e => e.id).join("\n")
        const b64 = Qt.btoa(ids)
        clearAllProc.command = ["sh", "-c", "echo '" + b64 + "' | base64 -d | while read -r id; do [ -n \"$id\" ] && cliphist delete-query \"$id\"; done"]
        clearAllProc.running = true
    }

    function deleteEntry(entry) {
        if (!entry) return
        if (isPinned(entry)) {
            const idx = pinnedPreviews.indexOf(entry.preview)
            if (idx !== -1) {
                pinnedPreviews.splice(idx, 1)
                pinnedPreviews = pinnedPreviews.slice()
                savePinned()
            }
        }
        deleteProc.command = ["cliphist", "delete-query", entry.id]
        deleteProc.running = true
    }

    function isImageEntry(entry) {
        return /binary data.*\b(png|jpe?g|gif|bmp|webp)\b/i.test(entry.preview)
    }
}