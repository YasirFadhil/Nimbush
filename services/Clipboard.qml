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
    property var filteredEntries: []

    onEntriesChanged: updateFiltered()
    onFilterTypeChanged: updateFiltered()
    onQueryChanged: updateFiltered()
    onPinnedPreviewsChanged: updateFiltered()

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

    // Automatic Clipboard Daemon Watchers (Ensures cliphist stores text & images automatically)
    Process {
        id: clipWatcherText
        command: ["sh", "-c", "pgrep -f 'wl-paste --type text --watch cliphist store' >/dev/null 2>&1 || exec wl-paste --type text --watch cliphist store"]
    }

    Process {
        id: clipWatcherImage
        command: ["sh", "-c", "pgrep -f 'wl-paste --type image --watch cliphist store' >/dev/null 2>&1 || exec wl-paste --type image --watch cliphist store"]
    }

    Component.onCompleted: {
        loadPinnedProc.running = true
        clipWatcherText.running = true
        clipWatcherImage.running = true
        refresh()
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

    Process { id: selectProc }
    Process {
        id: deleteProc
        onExited: root.refresh()   // auto-refresh list abis delete
    }

    function refresh() {
        _buffer = []
        listProc.running = true
    }

    function toBase64(str) {
        if (!str) return ""
        try {
            return Qt.btoa(unescape(encodeURIComponent(str)))
        } catch (e) {
            return Qt.btoa(str)
        }
    }

    function savePinned() {
        const jsonStr = JSON.stringify(pinnedPreviews)
        const b64 = toBase64(jsonStr)
        savePinnedProc.command = ["sh", "-c", "mkdir -p ~/.cache/quickshell && printf '%s' \"$1\" | base64 -d > ~/.cache/quickshell/clipboard_pinned.json", "sh", b64]
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

    function updateFiltered() {
        let list = entries || []
        if (filterType === "pinned") {
            list = list.filter(e => isPinned(e))
        } else if (filterType === "text") {
            list = list.filter(e => !isPinned(e) && !isImageEntry(e))
        } else if (filterType === "image") {
            list = list.filter(e => !isPinned(e) && isImageEntry(e))
        } else {
            // "all": only unpinned items
            list = list.filter(e => !isPinned(e))
        }

        if (query.length > 0) {
            const q = query.toLowerCase()
            list = list.filter(e => e.preview.toLowerCase().indexOf(q) !== -1)
        }

        filteredEntries = list
    }

    function filtered() {
        return filteredEntries
    }

    function select(entry) {
        if (!entry || entry.id === undefined) return
        selectProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", String(entry.id)]
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
        const lines = unpinned.map(e => e.id + "\t" + e.preview).join("\n")
        const b64 = toBase64(lines)
        clearAllProc.command = ["sh", "-c", "printf '%s' \"$1\" | base64 -d | cliphist delete", "sh", b64]
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
        const line = entry.id + "\t" + entry.preview
        const b64 = toBase64(line)
        deleteProc.command = ["sh", "-c", "printf '%s' \"$1\" | base64 -d | cliphist delete", "sh", b64]
        deleteProc.running = true
    }

    function isImageEntry(entry) {
        return /binary data.*\b(png|jpe?g|gif|bmp|webp)\b/i.test(entry.preview)
    }
}