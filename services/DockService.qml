pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    // ── Public State ─────────────────────────────────────────────────────────
    property var dockItems: []
    property var pinnedDockItems: []
    property var unpinnedDockItems: []
    property var runningClients: []
    property string activeWindowAddress: ""
    property string activeWindowClass: ""

    // Context Menu State
    property var contextMenuItem: null
    property real contextMenuX: 0
    property real contextMenuY: 0
    readonly property bool isMenuOpen: Boolean(contextMenuItem)

    function openMenu(item, x, y) {
        if (Services.OverlayManager) Services.OverlayManager.closeAllExcept("dockMenu")
        contextMenuItem = item
        contextMenuX = x
        contextMenuY = y
    }

    function closeMenu() {
        contextMenuItem = null
    }

    // ── Factory for Reactive Dock Items ──────────────────────────────────────
    Component {
        id: dockItemFactory
        QtObject {
            property string desktopId: ""
            property string name: ""
            property var icon: ""
            property string comment: ""
            property var app: null
            property var actions: []
            property bool isPinned: false
            property bool isRunning: false
            property bool isActive: false
            property bool isLaunching: false
            property int windowCount: 0
            property var windows: []
        }
    }

    // ── Debounced Event Timers ───────────────────────────────────────────────
    Timer {
        id: clientDebounceTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (!clientsProc.running) {
                clientsProc.output = ""
                clientsProc.running = true
            }
        }
    }

    Timer {
        id: rebuildDebounceTimer
        interval: 30
        repeat: false
        onTriggered: root._rebuildPinnedItems()
    }

    // React to pinned apps list changes in Config
    Connections {
        target: Services.Config || null
        function onDockPinnedAppsChanged() {
            rebuildDebounceTimer.restart()
        }
    }

    // React to DesktopEntries index updates
    Connections {
        target: DesktopEntries.applications || null
        function onValuesChanged() { rebuildDebounceTimer.restart() }
        function onRowsInserted() { rebuildDebounceTimer.restart() }
        function onRowsRemoved() { rebuildDebounceTimer.restart() }
    }

    // React to Applications service indexing
    Connections {
        target: Services.Applications || null
        function onFilteredAppsChanged() { rebuildDebounceTimer.restart() }
    }

    Component.onCompleted: {
        _rebuildPinnedItems()
        refreshClients()
        activeWinProc.running = true
    }

    function refreshClients() {
        clientDebounceTimer.restart()
    }

    // ── Hyprland Queries ─────────────────────────────────────────────────────

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: chunk => clientsProc.output += chunk
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && clientsProc.output.length > 0) {
                try {
                    const data = JSON.parse(clientsProc.output)
                    if (Array.isArray(data)) {
                        // Filter mapped and non-hidden windows with valid class
                        root.runningClients = data.filter(c => c && c.mapped && !c.hidden && c.class && c.class.length > 0)
                        root._syncRunningClients()
                    }
                } catch (e) {}
            }
            clientsProc.output = ""
        }
    }

    Process {
        id: activeWinProc
        command: ["hyprctl", "activewindow", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: chunk => activeWinProc.output += chunk
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && activeWinProc.output.length > 0) {
                try {
                    const data = JSON.parse(activeWinProc.output)
                    if (data && data.address) {
                        root.activeWindowAddress = data.address
                        root.activeWindowClass = data.class || ""
                        root._updateActiveState()
                    }
                } catch (e) {}
            }
            activeWinProc.output = ""
        }
    }

    // ── Hyprland Dispatcher ───────────────────────────────────────────────────

    function _hyprDispatch(standardArgs) {
        var p = Qt.createQmlObject('import Quickshell.Io; Process { running: false }', root)
        p.command = ["hyprctl", "dispatch"].concat(standardArgs)
        p.onExited.connect(() => p.destroy())
        p.running = true
    }

    // ── Hyprland Live Socket2 Stream ─────────────────────────────────────────

    Process {
        id: hyprSocketProc
        command: ["sh", "-c", "socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = data.trim()
                if (!line) return

                if (line.startsWith("openwindow>>") || line.startsWith("closewindow>>") || line.startsWith("movewindow>>")) {
                    clientDebounceTimer.restart()
                } else if (line.startsWith("activewindowv2>>")) {
                    const rawAddr = line.substring("activewindowv2>>".length).trim()
                    const addr = "0x" + rawAddr.replace(/^0x/, '')
                    root.activeWindowAddress = addr
                    root._updateActiveState()
                } else if (line.startsWith("activewindow>>")) {
                    const rest = line.substring("activewindow>>".length)
                    const comma = rest.indexOf(",")
                    if (comma !== -1) {
                        root.activeWindowClass = rest.substring(0, comma)
                    }
                }
            }
        }
        onExited: (code) => {
            reconnectTimer.restart()
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!hyprSocketProc.running) {
                hyprSocketProc.running = true
            }
        }
    }

    // ── Window Matching Logic ────────────────────────────────────────────────

    function findAppByDesktopId(id) {
        if (!id) return null
        const idClean = id.toLowerCase().replace(/\.desktop$/, '')

        if (idClean === "quickshell-settings" || idClean === "org.quickshell") {
            return {
                id: "quickshell-settings.desktop",
                name: "Quickshell Settings",
                icon: "preferences-system",
                description: "Nimbush Shell Settings & Preferences",
                execute: function() {
                    if (Services.OverlayManager && typeof Services.OverlayManager.openSettings === "function") {
                        Services.OverlayManager.openSettings()
                    }
                }
            }
        }

        // 1. Check indexed apps from Applications service if available
        if (Services.Applications && Services.Applications._indexedApps && Services.Applications._indexedApps.length > 0) {
            const indexed = Services.Applications._indexedApps
            for (let i = 0; i < indexed.length; i++) {
                const item = indexed[i]
                if (!item || !item.app) continue
                const aId = item.idLower ? item.idLower.replace(/\.desktop$/, '') : ""
                if (aId === idClean) return item.app
            }
            for (let j = 0; j < indexed.length; j++) {
                const item = indexed[j]
                if (!item || !item.app) continue
                const aId = item.idLower ? item.idLower.replace(/\.desktop$/, '') : ""
                if (aId.includes(idClean) || (aId.length > 0 && idClean.includes(aId))) return item.app
            }
        }

        // 2. Direct lookup in DesktopEntries
        const raw = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []

        for (let i = 0; i < raw.length; i++) {
            const a = raw[i]
            if (!a) continue
            const aId = (a.id || "").toLowerCase().replace(/\.desktop$/, '')
            if (aId === idClean) return a
        }

        // Second pass: check filename / prefix
        for (let j = 0; j < raw.length; j++) {
            const b = raw[j]
            if (!b) continue
            const bId = (b.id || "").toLowerCase()
            if (bId.includes(idClean) || idClean.includes(bId.replace(/\.desktop$/, ''))) return b
        }
        return null
    }

    function findAppForClient(client) {
        if (!client) return null
        const cls = (client.class || "").toLowerCase()
        const initCls = (client.initialClass || "").toLowerCase()

        if (cls === "org.quickshell" || initCls === "org.quickshell" || cls === "quickshell-settings" || initCls === "quickshell-settings") {
            return findAppByDesktopId("quickshell-settings.desktop")
        }

        // 1. Check indexed apps from Applications service
        if (Services.Applications && Services.Applications._indexedApps && Services.Applications._indexedApps.length > 0) {
            const indexed = Services.Applications._indexedApps
            for (let i = 0; i < indexed.length; i++) {
                const item = indexed[i]
                if (!item || !item.app) continue
                const aId = item.idLower ? item.idLower.replace(/\.desktop$/, '') : ""
                if (aId === cls || (initCls && aId === initCls)) return item.app
            }
            for (let j = 0; j < indexed.length; j++) {
                const item = indexed[j]
                if (!item || !item.app) continue
                const aId = item.idLower ? item.idLower.replace(/\.desktop$/, '') : ""
                if (aId.endsWith("." + cls) || (initCls && aId.endsWith("." + initCls))) return item.app
                if (cls.endsWith("." + aId) || (initCls && initCls.endsWith("." + aId))) return item.app
            }
            for (let k = 0; k < indexed.length; k++) {
                const item = indexed[k]
                if (!item || !item.app) continue
                if (item.nameLower === cls || (initCls && item.nameLower === initCls)) return item.app
            }
        }

        const raw = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []

        // 2. Direct match with id
        for (let i = 0; i < raw.length; i++) {
            const a = raw[i]
            if (!a || !a.id) continue
            const aId = a.id.toLowerCase().replace(/\.desktop$/, '')
            if (aId === cls || (initCls && aId === initCls)) return a
        }

        // 3. Suffix match (e.g. org.wezfurlong.wezterm -> wezterm)
        for (let j = 0; j < raw.length; j++) {
            const b = raw[j]
            if (!b || !b.id) continue
            const bId = b.id.toLowerCase().replace(/\.desktop$/, '')
            if (bId.endsWith("." + cls) || (initCls && bId.endsWith("." + initCls))) return b
            if (cls.endsWith("." + bId) || (initCls && initCls.endsWith("." + bId))) return b
        }

        // 4. Name match
        for (let k = 0; k < raw.length; k++) {
            const c = raw[k]
            if (!c || !c.name) continue
            const cName = c.name.toLowerCase()
            if (cName === cls || (initCls && cName === initCls)) return c
        }

        // 5. Substring in ID
        for (let m = 0; m < raw.length; m++) {
            const d = raw[m]
            if (!d || !d.id) continue
            const dId = d.id.toLowerCase().replace(/\.desktop$/, '')
            if (dId.includes(cls) || (initCls && dId.includes(initCls))) return d
        }

        return null
    }

    // ── Rebuild Pinned Items (Only when configuration changes) ─────────────────

    function _rebuildPinnedItems() {
        const pinnedList = (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps : []
        const currentPinned = root.pinnedDockItems || []
        const newPinned = []

        for (let p = 0; p < pinnedList.length; p++) {
            const dId = pinnedList[p]
            if (!dId) continue
            const dIdClean = dId.toLowerCase().replace(/\.desktop$/, '')

            // Check if we can reuse an existing QtObject to preserve identity
            let itemObj = currentPinned.find(item => item && item.desktopId.toLowerCase().replace(/\.desktop$/, '') === dIdClean)

            const app = findAppByDesktopId(dId)
            const fallbackName = dIdClean.charAt(0).toUpperCase() + dIdClean.slice(1)
            const resolvedName = app ? (app.name || fallbackName) : fallbackName
            const resolvedIcon = app ? (typeof app.icon === "string" ? app.icon : (app.icon?.name || dIdClean)) : dIdClean
            const resolvedComment = app ? (app.description || app.comment || "") : ""
            const resolvedActions = (app && app.actions) ? app.actions : []

            if (!itemObj) {
                itemObj = dockItemFactory.createObject(root, {
                    desktopId: dId,
                    name: resolvedName,
                    icon: resolvedIcon,
                    comment: resolvedComment,
                    app: app,
                    actions: resolvedActions,
                    isPinned: true,
                    isRunning: false,
                    isActive: false,
                    isLaunching: false,
                    windowCount: 0,
                    windows: []
                })
            } else {
                itemObj.name = resolvedName
                itemObj.icon = resolvedIcon
                itemObj.comment = resolvedComment
                itemObj.app = app
                itemObj.actions = resolvedActions
                itemObj.isPinned = true
            }

            if (itemObj) {
                newPinned.push(itemObj)
            }
        }

        // Clean up any old pinned items that were removed
        for (let c = 0; c < currentPinned.length; c++) {
            const old = currentPinned[c]
            if (old && !newPinned.includes(old)) {
                old.destroy()
            }
        }

        root.pinnedDockItems = newPinned
        root._syncRunningClients()
    }

    // ── Update Active Window State (Fast & In-Place) ──────────────────────────

    function _updateActiveState() {
        const currentAddr = root.activeWindowAddress
        for (let i = 0; i < root.pinnedDockItems.length; i++) {
            const p = root.pinnedDockItems[i]
            if (p) {
                p.isActive = p.windows.some(w => w.address === currentAddr)
            }
        }
        for (let j = 0; j < root.unpinnedDockItems.length; j++) {
            const u = root.unpinnedDockItems[j]
            if (u) {
                u.isActive = u.windows.some(w => w.address === currentAddr)
            }
        }
    }

    // ── Sync Running Clients With Dock Items ──────────────────────────────────

    function _syncRunningClients() {
        const clients = root.runningClients || []
        const claimedClientAddresses = {}

        // 1. Match against Pinned Apps (in-place property updates)
        for (let p = 0; p < root.pinnedDockItems.length; p++) {
            const item = root.pinnedDockItems[p]
            if (!item) continue

            const dIdClean = item.desktopId.toLowerCase().replace(/\.desktop$/, '')
            const app = item.app
            const matchedClients = []

            for (let c = 0; c < clients.length; c++) {
                const client = clients[c]
                if (!client || !client.address) continue
                if (claimedClientAddresses[client.address]) continue

                const cCls = (client.class || "").toLowerCase()
                const cInit = (client.initialClass || "").toLowerCase()

                let isMatch = false
                if (app && app.id) {
                    const appIdClean = app.id.toLowerCase().replace(/\.desktop$/, '')
                    if (cCls === appIdClean || cInit === appIdClean || appIdClean.endsWith("." + cCls)) {
                        isMatch = true
                    }
                }
                if (!isMatch && (cCls === dIdClean || cInit === dIdClean || dIdClean.endsWith("." + cCls))) {
                    isMatch = true
                }

                if (isMatch) {
                    matchedClients.push(client)
                    claimedClientAddresses[client.address] = true
                }
            }

            matchedClients.sort((a, b) => (a.focusHistoryID || 0) - (b.focusHistoryID || 0))

            item.windows = matchedClients
            item.windowCount = matchedClients.length
            item.isRunning = matchedClients.length > 0
            if (item.isRunning) {
                item.isLaunching = false
            }
            item.isActive = matchedClients.some(w => w.address === root.activeWindowAddress)
        }

        // 2. Match unclaimed clients into Unpinned Apps
        const unpinnedMap = {}
        for (let c = 0; c < clients.length; c++) {
            const client = clients[c]
            if (!client || !client.address) continue
            if (claimedClientAddresses[client.address]) continue

            const app = findAppForClient(client)
            const groupKey = app ? (app.id || client.class) : client.class

            if (!unpinnedMap[groupKey]) {
                const fallbackName = client.class.charAt(0).toUpperCase() + client.class.slice(1)
                unpinnedMap[groupKey] = {
                    groupKey: groupKey,
                    desktopId: app ? app.id : (client.class + ".desktop"),
                    name: app ? (app.name || fallbackName) : fallbackName,
                    icon: app ? (typeof app.icon === "string" ? app.icon : (app.icon?.name || client.class.toLowerCase())) : client.class.toLowerCase(),
                    comment: app ? (app.description || app.comment || "") : "",
                    app: app,
                    actions: (app && app.actions) ? app.actions : [],
                    windows: []
                }
            }
            unpinnedMap[groupKey].windows.push(client)
        }

        // Reconcile unpinned list
        const currentUnpinned = root.unpinnedDockItems || []
        const newUnpinned = []
        const unpinnedKeys = Object.keys(unpinnedMap)

        for (let u = 0; u < unpinnedKeys.length; u++) {
            const key = unpinnedKeys[u]
            const info = unpinnedMap[key]
            info.windows.sort((a, b) => (a.focusHistoryID || 0) - (b.focusHistoryID || 0))

            // Check if already in currentUnpinned
            let existingItem = currentUnpinned.find(item => item && (item.desktopId === info.desktopId || item.name === info.name))
            if (!existingItem) {
                existingItem = dockItemFactory.createObject(root, {
                    desktopId: info.desktopId,
                    name: info.name,
                    icon: info.icon,
                    comment: info.comment,
                    app: info.app,
                    actions: info.actions,
                    isPinned: false,
                    isRunning: true,
                    isActive: info.windows.some(w => w.address === root.activeWindowAddress),
                    windowCount: info.windows.length,
                    windows: info.windows
                })
            } else {
                existingItem.windows = info.windows
                existingItem.windowCount = info.windows.length
                existingItem.isRunning = true
                existingItem.isActive = info.windows.some(w => w.address === root.activeWindowAddress)
            }

            if (existingItem) {
                newUnpinned.push(existingItem)
            }
        }

        // Clean up closed unpinned items
        for (let o = 0; o < currentUnpinned.length; o++) {
            const oldItem = currentUnpinned[o]
            if (oldItem && !newUnpinned.includes(oldItem)) {
                oldItem.destroy()
            }
        }

        // Only assign if array membership/order actually changed
        let unpinnedChanged = (currentUnpinned.length !== newUnpinned.length)
        if (!unpinnedChanged) {
            for (let k = 0; k < currentUnpinned.length; k++) {
                if (currentUnpinned[k] !== newUnpinned[k]) {
                    unpinnedChanged = true
                    break
                }
            }
        }

        if (unpinnedChanged) {
            root.unpinnedDockItems = newUnpinned
        }

        root.dockItems = root.pinnedDockItems.concat(root.unpinnedDockItems)
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    function launchApp(item) {
        if (!item) return
        item.isLaunching = true
        if (item.app && typeof item.app.execute === "function") {
            item.app.execute()
            return
        }
        const targetId = (item.desktopId || "").replace(/\.desktop$/, '')
        if (targetId.length > 0) {
            _hyprDispatch(['exec', targetId])
        }
    }

    function focusApp(item) {
        if (!item) return

        if (item.isRunning && item.windows && item.windows.length > 0) {
            // If already active and multiple windows exist, cycle to next window
            if (item.isActive && item.windows.length > 1) {
                let curIdx = item.windows.findIndex(w => w.address === root.activeWindowAddress)
                let nextIdx = (curIdx + 1) % item.windows.length
                const targetWin = item.windows[nextIdx]
                if (targetWin && targetWin.address) {
                    focusWindow(targetWin.address)
                    return
                }
            }

            // Focus the top window
            const primaryWin = item.windows[0]
            if (primaryWin && primaryWin.address) {
                focusWindow(primaryWin.address)
                return
            }
        }

        // If not running, launch it
        launchApp(item)
    }

    function focusWindow(address) {
        if (!address) return
        _hyprDispatch(['focuswindow', 'address:' + address])
        root.activeWindowAddress = address
        root._updateActiveState()
    }

    function closeWindow(address) {
        if (!address) return
        _hyprDispatch(['closewindow', 'address:' + address])
        clientDebounceTimer.restart()
    }

    function closeApp(item) {
        if (!item || !item.windows || item.windows.length === 0) return
        for (let i = 0; i < item.windows.length; i++) {
            closeWindow(item.windows[i].address)
        }
    }

    // ── Pin Management ───────────────────────────────────────────────────────

    function isPinned(desktopId) {
        if (!desktopId) return false
        const pinnedList = (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps : []
        const cleanTarget = desktopId.toLowerCase().replace(/\.desktop$/, '')
        return pinnedList.some(id => (id || "").toLowerCase().replace(/\.desktop$/, '') === cleanTarget)
    }

    function pinApp(desktopId) {
        if (!desktopId) return
        if (isPinned(desktopId)) return

        const fullId = desktopId.endsWith(".desktop") ? desktopId : (desktopId + ".desktop")
        const current = (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps.slice() : []
        current.push(fullId)
        if (Services.Config) {
            Services.Config.setDockPinnedApps(current)
        }
        rebuildDebounceTimer.restart()
    }

    function unpinApp(desktopId) {
        if (!desktopId) return
        const cleanTarget = desktopId.toLowerCase().replace(/\.desktop$/, '')
        const current = (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps.slice() : []
        const filtered = current.filter(id => (id || "").toLowerCase().replace(/\.desktop$/, '') !== cleanTarget)
        if (Services.Config) {
            Services.Config.setDockPinnedApps(filtered)
        }
        rebuildDebounceTimer.restart()
    }

    function togglePin(desktopId) {
        if (isPinned(desktopId)) {
            unpinApp(desktopId)
        } else {
            pinApp(desktopId)
        }
    }

    function movePinned(fromIdx, toIdx) {
        const current = (Services.Config && Services.Config.dockPinnedApps) ? Services.Config.dockPinnedApps.slice() : []
        if (fromIdx < 0 || fromIdx >= current.length || toIdx < 0 || toIdx >= current.length || fromIdx === toIdx) return
        const item = current.splice(fromIdx, 1)[0]
        current.splice(toIdx, 0, item)
        if (Services.Config) {
            Services.Config.setDockPinnedApps(current)
        }
        rebuildDebounceTimer.restart()
    }

    function resetToDefaultPinned() {
        if (Services.Config) {
            const defaults = Services.Config.resolveDefaultPinnedApps()
            Services.Config.setDockPinnedApps(defaults)
        }
        rebuildDebounceTimer.restart()
    }
}
