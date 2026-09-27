pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "." as Services

Singleton {
    id: root

    signal newNotification(var entry)

    property bool doNotDisturb: false
    property bool centerVisible: false
    property int replyingNotifId: -1
    property alias popupList: popupModel
    property alias historyList: historyModel
    property int maxHistoryCount: 50
    property int maxPopupCount: 10

    readonly property int retentionDays: Services.Config ? Services.Config.notificationRetentionDays : 7
    onRetentionDaysChanged: pruneExpiredHistory()

    ListModel { id: popupModel }
    ListModel { id: historyModel }

    readonly property string kdeHelperPath: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.config/quickshell/scripts/kdeconnect-helper.py"

    property var _activeTimers: ({})
    property int _kdeRestartDelay: 3000
    property int _kdeRestartCount: 0

    function _startDismissTimer(id, interval) {
        if (!id || interval <= 0) return
        if (_activeTimers[id]) {
            try { _activeTimers[id].destroy() } catch (e) {}
            delete _activeTimers[id]
        }
        const t = dismissTimer.createObject(root, { notifId: id, interval: interval })
        if (t) {
            _activeTimers[id] = t
            t.start()
        }
    }

    // ── Retention Pruner (1 to 7 days) ──────────────────────────────────────
    function pruneExpiredHistory() {
        const days = Math.max(1, Math.min(7, root.retentionDays || 7))
        const cutoff = Date.now() - (days * 86400000)
        let changed = false
        for (let i = historyModel.count - 1; i >= 0; i--) {
            const item = historyModel.get(i)
            if (item && item.time && item.time < cutoff) {
                historyModel.remove(i)
                changed = true
            }
        }
        while (historyModel.count > root.maxHistoryCount) {
            historyModel.remove(historyModel.count - 1)
            changed = true
        }
        if (changed) {
            root.saveHistory()
        }
    }

    Timer {
        id: pruneTimer
        interval: 300000 // 5 minutes
        repeat: true
        running: true
        onTriggered: root.pruneExpiredHistory()
    }

    // ── Live KDE Connect DBus Watcher & Auto-Dismissal Sync ─────────────────
    Process {
        id: kdeWatcherProc
        command: [root.kdeHelperPath, "watch"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                root._kdeRestartCount = 0
                root._kdeRestartDelay = 3000
                try {
                    const data = JSON.parse(line.trim())
                    if (data.event === "removed") {
                        if (data.removedIds && data.removedIds.length > 0) {
                            root.removeKdeNotificationsByIds(data.removedIds)
                        }
                    } else if (data.event === "sync") {
                        if (data.removedIds && data.removedIds.length > 0) {
                            root.removeKdeNotificationsByIds(data.removedIds)
                        }
                        if (data.activeIds && Array.isArray(data.activeIds)) {
                            root.syncKdeNotificationsWithActive(data.activeIds, data.notifications || [])
                        }
                    } else if (data.event === "all_removed") {
                        root.removeAllKdeNotifications()
                    }
                } catch (e) { }
            }
        }
        onExited: (code, status) => {
            root._kdeRestartCount++
            root._kdeRestartDelay = Math.min(60000, Math.floor(3000 * Math.pow(1.5, Math.min(root._kdeRestartCount, 8))))
            kdeRestartTimer.interval = root._kdeRestartDelay
            kdeRestartTimer.restart()
        }
    }

    Timer {
        id: kdeRestartTimer
        interval: root._kdeRestartDelay
        repeat: false
        onTriggered: kdeWatcherProc.running = true
    }

    function removeKdeNotificationsByIds(removedIds) {
        if (!removedIds || removedIds.length === 0) return
        const removedSet = {}
        for (let i = 0; i < removedIds.length; i++) removedSet[String(removedIds[i])] = true

        for (let i = popupModel.count - 1; i >= 0; i--) {
            const item = popupModel.get(i)
            if (item && item.isKdeConnect && item.kdeNotifId && removedSet[String(item.kdeNotifId)]) {
                popupModel.remove(i)
            }
        }
        let changed = false
        for (let i = historyModel.count - 1; i >= 0; i--) {
            const item = historyModel.get(i)
            if (item && item.isKdeConnect && item.kdeNotifId && removedSet[String(item.kdeNotifId)]) {
                historyModel.remove(i)
                changed = true
            }
        }
        if (changed) root.saveHistory()
    }

    function removeAllKdeNotifications() {
        for (let i = popupModel.count - 1; i >= 0; i--) {
            const item = popupModel.get(i)
            if (item && item.isKdeConnect) popupModel.remove(i)
        }
        let changed = false
        for (let i = historyModel.count - 1; i >= 0; i--) {
            const item = historyModel.get(i)
            if (item && item.isKdeConnect) {
                historyModel.remove(i)
                changed = true
            }
        }
        if (changed) root.saveHistory()
    }

    function syncKdeNotificationsWithActive(activeIds, kdeNotifs) {
        if (!activeIds) return
        const activeSet = {}
        for (let i = 0; i < activeIds.length; i++) activeSet[String(activeIds[i])] = true

        for (let i = popupModel.count - 1; i >= 0; i--) {
            const item = popupModel.get(i)
            if (item && item.isKdeConnect && item.kdeNotifId && !activeSet[String(item.kdeNotifId)]) {
                popupModel.remove(i)
            }
        }
        let changed = false
        for (let i = historyModel.count - 1; i >= 0; i--) {
            const item = historyModel.get(i)
            if (item && item.isKdeConnect && item.kdeNotifId && !activeSet[String(item.kdeNotifId)]) {
                historyModel.remove(i)
                changed = true
            }
        }

        if (Array.isArray(kdeNotifs) && kdeNotifs.length > 0) {
            // Build fast lookup maps to replace nested O(N^3) loops with O(1) lookups
            const popupMap = {}
            for (let p = 0; p < popupModel.count; p++) {
                const pItem = popupModel.get(p)
                if (pItem && pItem.notifId) popupMap[pItem.notifId] = pItem
            }

            const kdeHistoryMap = {}
            for (let h = 0; h < historyModel.count; h++) {
                const hItem = historyModel.get(h)
                if (hItem && hItem.isKdeConnect && hItem.kdeNotifId) {
                    kdeHistoryMap[String(hItem.kdeNotifId)] = hItem
                }
            }

            for (let k = 0; k < kdeNotifs.length; k++) {
                const kn = kdeNotifs[k]
                const knId = String(kn.id)
                const item = kdeHistoryMap[knId]
                if (item) {
                    const newSummary = root.decodeOctalString(kn.title || item.summary)
                    const newBody = root.decodeOctalString(kn.text || item.body)
                    const newApp = (kn.app && kn.app.length > 0) ? root.decodeOctalString(kn.app) : item.appName
                    const newIcon = (kn.app && kn.app.length > 0) ? root.resolveAppIcon(newApp, item.appIcon) : item.appIcon

                    if (item.summary !== newSummary || item.body !== newBody || item.appName !== newApp) {
                        item.summary = newSummary
                        item.body = newBody
                        if (newApp && (item.appName === "KDE Connect" || !item.appName || item.appName !== newApp)) {
                            item.appName = newApp
                            item.appIcon = newIcon
                        }
                        item.time = Date.now()
                        changed = true

                        const pItem = popupMap[item.notifId]
                        if (pItem) {
                            pItem.summary = newSummary
                            pItem.body = newBody
                            if (newApp) {
                                pItem.appName = newApp
                                pItem.appIcon = newIcon
                            }
                            pItem.time = Date.now()
                        } else if (!root.doNotDisturb) {
                            popupModel.insert(0, item)
                            while (popupModel.count > root.maxPopupCount) {
                                popupModel.remove(popupModel.count - 1)
                            }
                            root.newNotification(item)
                            SoundFeedback.playNotification()
                            root._startDismissTimer(item.notifId, 5000)
                        }
                    }
                }
            }
        }

        if (changed) root.saveHistory()
    }

    // ── Desktop Notification Server ─────────────────────────────────────────
    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        actionIconsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        inlineReplySupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true

            const isKdeConnect = root.isKdeConnectNotif(notif)
            const isMessaging = root.isMessagingApp(notif)
            const isBattery = root.isBatteryNotification(notif)
            const actionsList = notif.actions.map(a => ({ identifier: a.identifier, text: a.text }))

            // Add inline reply action if messaging or hasInlineReply or KDE Connect
            if ((isMessaging || notif.hasInlineReply || isKdeConnect) && !actionsList.some(a => a.identifier === "inline-reply" || (a.identifier || "").toLowerCase().includes("reply") || (a.text || "").toLowerCase().includes("reply") || (a.text || "").toLowerCase().includes("balas"))) {
                actionsList.push({ identifier: "inline-reply", text: "Reply" })
            }

            // Resolve KDE Connect app name, origin device, sender summary and message body
            const kdeInfo = isKdeConnect ? root.resolveKdeNotificationInfo(notif) : null
            const finalAppName = (kdeInfo && kdeInfo.appName) ? kdeInfo.appName : (notif.appName || "Unknown")
            const finalAppIcon = (kdeInfo && kdeInfo.appIcon) ? kdeInfo.appIcon : notif.appIcon
            const finalSummary = root.decodeOctalString((kdeInfo && kdeInfo.summary !== undefined) ? kdeInfo.summary : (notif.summary || ""))
            const finalBody = root.decodeOctalString((kdeInfo && kdeInfo.body !== undefined) ? kdeInfo.body : (notif.body || ""))
            const originDevice = (kdeInfo && kdeInfo.originDevice) ? kdeInfo.originDevice : ""

            const entry = {
                notifId: notif.id,
                appName: finalAppName,
                appIcon: finalAppIcon,
                summary: finalSummary,
                body: finalBody,
                image: notif.image || "",
                urgency: notif.urgency,
                time: Date.now(),
                actions: actionsList,
                hasInlineReply: isMessaging || notif.hasInlineReply || isKdeConnect,
                isMessaging: isMessaging,
                isKdeConnect: isKdeConnect,
                isBattery: isBattery,
                kdeNotifId: "",
                kdeReplyId: "",
                originDevice: originDevice,
                inlineReplyPlaceholder: notif.inlineReplyPlaceholder || "",
                desktopEntry: notif.desktopEntry || ""
            }

            if (isKdeConnect) {
                root.linkKdeNotification(entry)
            }

            historyModel.insert(0, entry)
            root.pruneExpiredHistory()

            if (!root.doNotDisturb) {
                popupModel.insert(0, entry)
                while (popupModel.count > root.maxPopupCount) {
                    popupModel.remove(popupModel.count - 1)
                }
                root.newNotification(entry)

                const isFullscreen = Services.Workspaces ? Services.Workspaces.isFullscreen : false
                const allowSoundInFullscreen = (Services.Config && Services.Config.notificationShowInFullscreen) || isBattery
                if (!isFullscreen || allowSoundInFullscreen) {
                    if (notif.urgency === NotificationUrgency.Critical)
                        SoundFeedback.playError()
                    else if (notif.urgency === NotificationUrgency.Low)
                        SoundFeedback.playInfo()
                    else
                        SoundFeedback.playNotification()
                }

                const timeout = notif.expireTimeout > 0 ? notif.expireTimeout
                    : (notif.urgency === NotificationUrgency.Critical ? 7000 : (Services.Config ? (Services.Config.notificationTimeout * 1000) : 5000))
                if (timeout > 0) {
                    root._startDismissTimer(notif.id, timeout)
                }
            }

            // Connect to dynamic updates (e.g. WhatsApp/KDE Connect follow-up messages replacing the notification)
            const onUpdate = () => root.handleNotificationUpdate(notif)
            notif.summaryChanged.connect(onUpdate)
            notif.bodyChanged.connect(onUpdate)
            notif.imageChanged.connect(onUpdate)
            notif.urgencyChanged.connect(onUpdate)

            notif.closed.connect(() => {
                root.removePopup(notif.id)
                root.removeFromHistory(notif.id)
            })
        }
    }

    function handleNotificationUpdate(notif) {
        if (!notif) return
        const isKdeConnect = root.isKdeConnectNotif(notif)
        const isMessaging = root.isMessagingApp(notif)
        const isBattery = root.isBatteryNotification(notif)
        const actionsList = notif.actions.map(a => ({ identifier: a.identifier, text: a.text }))

        if ((isMessaging || notif.hasInlineReply || isKdeConnect) && !actionsList.some(a => a.identifier === "inline-reply" || (a.identifier || "").toLowerCase().includes("reply") || (a.text || "").toLowerCase().includes("reply") || (a.text || "").toLowerCase().includes("balas"))) {
            actionsList.push({ identifier: "inline-reply", text: "Reply" })
        }

        const kdeInfo = isKdeConnect ? root.resolveKdeNotificationInfo(notif) : null
        const finalAppName = (kdeInfo && kdeInfo.appName) ? kdeInfo.appName : (notif.appName || "Unknown")
        const finalAppIcon = (kdeInfo && kdeInfo.appIcon) ? kdeInfo.appIcon : notif.appIcon
        const finalSummary = root.decodeOctalString((kdeInfo && kdeInfo.summary !== undefined) ? kdeInfo.summary : (notif.summary || ""))
        const finalBody = root.decodeOctalString((kdeInfo && kdeInfo.body !== undefined) ? kdeInfo.body : (notif.body || ""))
        const originDevice = (kdeInfo && kdeInfo.originDevice) ? kdeInfo.originDevice : ""

        let existingEntry = null
        for (let i = 0; i < historyModel.count; i++) {
            const h = historyModel.get(i)
            if (h && h.notifId === notif.id) {
                h.appName = finalAppName || h.appName
                h.appIcon = finalAppIcon || h.appIcon
                h.summary = finalSummary
                h.body = finalBody
                h.image = notif.image || ""
                if (originDevice) h.originDevice = originDevice
                h.time = Date.now()
                h.actions = actionsList
                existingEntry = h
                root.saveHistory()
                break
            }
        }

        let inPopupIndex = -1
        for (let i = 0; i < popupModel.count; i++) {
            const p = popupModel.get(i)
            if (p && p.notifId === notif.id) {
                p.appName = finalAppName || p.appName
                p.appIcon = finalAppIcon || p.appIcon
                p.summary = finalSummary
                p.body = finalBody
                p.image = notif.image || ""
                if (originDevice) p.originDevice = originDevice
                p.time = Date.now()
                p.actions = actionsList
                inPopupIndex = i
                existingEntry = p
                break
            }
        }

        const entry = existingEntry ? {
            notifId: existingEntry.notifId,
            appName: existingEntry.appName || finalAppName,
            appIcon: existingEntry.appIcon || finalAppIcon,
            summary: finalSummary,
            body: finalBody,
            image: notif.image || "",
            urgency: notif.urgency,
            time: Date.now(),
            actions: actionsList,
            hasInlineReply: isMessaging || notif.hasInlineReply || isKdeConnect,
            isMessaging: isMessaging,
            isKdeConnect: isKdeConnect,
            isBattery: isBattery,
            kdeNotifId: existingEntry.kdeNotifId || "",
            kdeReplyId: existingEntry.kdeReplyId || "",
            originDevice: existingEntry.originDevice || originDevice,
            inlineReplyPlaceholder: notif.inlineReplyPlaceholder || "",
            desktopEntry: notif.desktopEntry || ""
        } : {
            notifId: notif.id,
            appName: finalAppName,
            appIcon: finalAppIcon,
            summary: finalSummary,
            body: finalBody,
            image: notif.image || "",
            urgency: notif.urgency,
            time: Date.now(),
            actions: actionsList,
            hasInlineReply: isMessaging || notif.hasInlineReply || isKdeConnect,
            isMessaging: isMessaging,
            isKdeConnect: isKdeConnect,
            isBattery: isBattery,
            kdeNotifId: "",
            kdeReplyId: "",
            originDevice: originDevice,
            inlineReplyPlaceholder: notif.inlineReplyPlaceholder || "",
            desktopEntry: notif.desktopEntry || ""
        }

        if (isKdeConnect) {
            root.linkKdeNotification(entry)
        }

        if (inPopupIndex >= 0) {
            popupModel.remove(inPopupIndex)
        }

        if (!root.doNotDisturb) {
            popupModel.insert(0, entry)
            while (popupModel.count > root.maxPopupCount) {
                popupModel.remove(popupModel.count - 1)
            }
            root.newNotification(entry)

            const isFullscreen = Services.Workspaces ? Services.Workspaces.isFullscreen : false
            const allowSoundInFullscreen = (Services.Config && Services.Config.notificationShowInFullscreen) || isBattery
            if (!isFullscreen || allowSoundInFullscreen) {
                if (notif.urgency === NotificationUrgency.Critical)
                    SoundFeedback.playError()
                else if (notif.urgency === NotificationUrgency.Low)
                    SoundFeedback.playInfo()
                else
                    SoundFeedback.playNotification()
            }

            const timeout = notif.expireTimeout > 0 ? notif.expireTimeout
                : (notif.urgency === NotificationUrgency.Critical ? 7000 : (Services.Config ? (Services.Config.notificationTimeout * 1000) : 5000))
            if (timeout > 0) {
                root._startDismissTimer(notif.id, timeout)
            }
        }
    }

    Process {
        id: kdeLinkProc
        property string targetAppName: ""
        property string targetSummary: ""
        property string targetBody: ""
        property int targetNotifId: -1
        command: [root.kdeHelperPath, "list"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const list = JSON.parse(data.trim())
                    if (Array.isArray(list)) {
                        for (let i = 0; i < list.length; i++) {
                            const k = list[i]
                            const kApp = (k.app || "").toLowerCase()
                            const kTitle = (k.title || "").toLowerCase()
                            const kText = (k.text || "").toLowerCase()

                            const tApp = (kdeLinkProc.targetAppName || "").toLowerCase()
                            const tSum = (kdeLinkProc.targetSummary || "").toLowerCase()
                            const tBod = (kdeLinkProc.targetBody || "").toLowerCase()

                            const appMatch = kApp.length > 0 && (tApp === kApp || tSum.includes(kApp) || tBod.includes(kApp))
                            const sMatch = (kApp && tSum.includes(kApp)) || (kTitle && (tSum.includes(kTitle) || tBod.includes(kTitle)))
                            const bMatch = (kText && (tBod.includes(kText.substring(0, 15)) || (kTitle && tBod.includes(kTitle))))

                            if (appMatch || sMatch || bMatch || list.length === 1) {
                                for (let h = 0; h < historyModel.count; h++) {
                                    const hItem = historyModel.get(h)
                                    if (hItem && hItem.notifId === kdeLinkProc.targetNotifId) {
                                        hItem.kdeNotifId = String(k.id)
                                        hItem.kdeReplyId = String(k.replyId || "")
                                        if (k.app && (hItem.appName === "KDE Connect" || !hItem.appName)) {
                                            hItem.appName = k.app
                                            hItem.appIcon = root.resolveAppIcon(k.app, hItem.appIcon)
                                        }
                                        if (k.title && k.title.length > 0 && hItem.summary === k.app) {
                                            hItem.summary = root.decodeOctalString(k.title)
                                        }
                                        if (k.text && k.text.length > 0 && hItem.body.startsWith(k.title + ": ")) {
                                            hItem.body = root.decodeOctalString(k.text)
                                        }
                                        root.saveHistory()
                                        break
                                    }
                                }
                                for (let p = 0; p < popupModel.count; p++) {
                                    const pItem = popupModel.get(p)
                                    if (pItem && pItem.notifId === kdeLinkProc.targetNotifId) {
                                        pItem.kdeNotifId = String(k.id)
                                        pItem.kdeReplyId = String(k.replyId || "")
                                        if (k.app && (pItem.appName === "KDE Connect" || !pItem.appName)) {
                                            pItem.appName = k.app
                                            pItem.appIcon = root.resolveAppIcon(k.app, pItem.appIcon)
                                        }
                                        if (k.title && k.title.length > 0 && pItem.summary === k.app) {
                                            pItem.summary = root.decodeOctalString(k.title)
                                        }
                                        if (k.text && k.text.length > 0 && pItem.body.startsWith(k.title + ": ")) {
                                            pItem.body = root.decodeOctalString(k.text)
                                        }
                                        break
                                    }
                                }
                                break
                            }
                        }
                    }
                } catch (e) { }
            }
        }
    }

    function linkKdeNotification(entry) {
        if (!entry) return
        kdeLinkProc.targetAppName = entry.appName || ""
        kdeLinkProc.targetSummary = entry.summary || ""
        kdeLinkProc.targetBody = entry.body || ""
        kdeLinkProc.targetNotifId = entry.notifId
        kdeLinkProc.running = true
    }

    Component {
        id: dismissTimer
        Timer {
            property int notifId
            repeat: false
            onTriggered: {
                if (root.replyingNotifId === notifId) {
                    interval = 4000
                    start()
                    return
                }
                if (root._activeTimers[notifId] === this) {
                    delete root._activeTimers[notifId]
                }
                root.removePopup(notifId)
                destroy()
            }
        }
    }

    IpcHandler {
        target: "notifications"

        function count(): int { return popupModel.count }
        function historyCount(): int { return historyModel.count }
        function dnd(): bool { return root.doNotDisturb }
        function toggleDnd(): void { root.doNotDisturb = !root.doNotDisturb }
        function clearHistory(): void { root.clearHistory() }
        function toggleCenter(): void { root.centerVisible = !root.centerVisible }
        function closeCenter(): void { root.closeCenter() }
    }

    function removePopup(id) {
        if (_activeTimers[id]) {
            try { _activeTimers[id].destroy() } catch (e) {}
            delete _activeTimers[id]
        }
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).notifId === id) { popupModel.remove(i); break }
        }
    }

    function removeFromHistory(id) {
        for (let i = 0; i < historyModel.count; i++) {
            if (historyModel.get(i).notifId === id) {
                historyModel.remove(i)
                root.saveHistory()
                break
            }
        }
    }

    function findEntry(id) {
        for (let i = 0; i < historyModel.count; i++) {
            if (historyModel.get(i).notifId === id) return historyModel.get(i)
        }
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).notifId === id) return popupModel.get(i)
        }
        return null
    }

    function isBatteryNotification(entry) {
        if (!entry) return false
        if (entry.isBattery) return true
        const app = (entry.appName || "").toLowerCase()
        const summary = (entry.summary || "").toLowerCase()
        const body = (entry.body || "").toLowerCase()
        const icon = (entry.appIcon || "").toLowerCase()
        if (app.includes("battery") || app.includes("power") || app.includes("upower")) return true
        if (summary.includes("battery") || summary.includes("baterai") || summary.includes("daya baterai")) return true
        if (icon.includes("battery")) return true
        try {
            const hints = entry.hints || {}
            for (const k in hints) {
                if (k.toLowerCase().includes("battery")) return true
            }
        } catch (e) { }
        return false
    }

    function isKdeConnectNotif(n) {
        if (!n) return false
        if (n.isKdeConnect) return true
        const appName = (n.appName || "").toLowerCase()
        const desktopEntry = (n.desktopEntry || "").toLowerCase()
        const appIcon = (n.appIcon || "").toLowerCase()
        if (appName.includes("kde") || appName.includes("connect")) return true
        if (desktopEntry.includes("kdeconnect") || desktopEntry.includes("kde")) return true
        if (appIcon.includes("kdeconnect") || appIcon.includes("kde")) return true
        try {
            const hints = n.hints || {}
            for (const k in hints) {
                if (k.toLowerCase().includes("kde")) return true
            }
        } catch (e) { }
        return false
    }

    function decodeOctalString(str) {
        if (!str || typeof str !== "string") return str || ""
        if (!str.includes("\\")) return str

        try {
            if (/\\([0-7]{1,3})/.test(str)) {
                const bytes = []
                let i = 0
                let out = ""
                while (i < str.length) {
                    if (str[i] === '\\' && i + 1 < str.length) {
                        const match = str.substring(i + 1).match(/^([0-7]{1,3})/)
                        if (match) {
                            const byteVal = parseInt(match[1], 8)
                            bytes.push(byteVal)
                            i += 1 + match[1].length
                            continue
                        }
                    }
                    if (bytes.length > 0) {
                        try {
                            out += new TextDecoder("utf-8").decode(new Uint8Array(bytes))
                        } catch (e) {
                            out += String.fromCharCode(...bytes)
                        }
                        bytes.length = 0
                    }
                    out += str[i]
                    i++
                }
                if (bytes.length > 0) {
                    try {
                        out += new TextDecoder("utf-8").decode(new Uint8Array(bytes))
                    } catch (e) {
                        out += String.fromCharCode(...bytes)
                    }
                }
                str = out
            }
        } catch (e) { }

        return str
            .replace(/\\n/g, "\n")
            .replace(/\\r/g, "\r")
            .replace(/\\t/g, "\t")
            .replace(/\\'/g, "'")
            .replace(/\\"/g, '"')
            .replace(/\\\\/g, "\\")
    }

    function resolveAppIcon(appName, fallbackIcon) {
        if (!appName) return fallbackIcon || "kdeconnect"
        const app = appName.toLowerCase().trim()

        if (app.includes("whatsapp")) return "whatsapp"
        if (app.includes("telegram")) return "telegram"
        if (app.includes("discord")) return "discord"
        if (app.includes("instagram")) return "instagram"
        if (app.includes("reddit")) return "reddit"
        if (app.includes("threads")) return "threads"
        if (app.includes("tiktok")) return "tiktok"
        if (app.includes("twitter") || app === "x") return "twitter"
        if (app.includes("slack")) return "slack"
        if (app.includes("signal")) return "signal"
        if (app.includes("spotify")) return "spotify"
        if (app.includes("youtube")) return "youtube"
        if (app.includes("gmail") || app.includes("email") || app.includes("mail")) return "internet-mail"
        if (app.includes("messages") || app.includes("message") || app.includes("sms")) return "internet-chat"
        if (app.includes("call") || app.includes("dialer") || app.includes("phone")) return "call-start"

        if (Services.SystemTheme && Services.SystemTheme.getIcon) {
            const test = Services.SystemTheme.getIcon(app)
            if (test && test.length > 0) return app
        }

        return fallbackIcon || "kdeconnect"
    }

    function resolveKdeNotificationInfo(notif) {
        if (!notif) return null
        const isKde = root.isKdeConnectNotif(notif)
        if (!isKde) return null

        const shouldSplit = (Services.Config && Services.Config.notificationSplitKdeApps !== undefined)
            ? Services.Config.notificationSplitKdeApps : true
        if (!shouldSplit) return null

        let originDevice = ""
        try {
            const hints = notif.hints || {}
            if (hints["x-kde-origin-name"]) originDevice = String(hints["x-kde-origin-name"])
            else if (hints["x-kdeconnect-source-device"]) originDevice = String(hints["x-kdeconnect-source-device"])
        } catch (e) { }

        let hintApp = ""
        try {
            const hints = notif.hints || {}
            if (hints["x-kde-display-appname"]) hintApp = String(hints["x-kde-display-appname"]).trim()
        } catch (e) { }

        const rawSummary = root.decodeOctalString(notif.summary || "").trim()
        const rawBody = root.decodeOctalString(notif.body || "").trim()

        let appName = ""
        let summary = rawSummary
        let body = rawBody

        if (hintApp && hintApp.length > 0) {
            appName = root.decodeOctalString(hintApp).trim()
            summary = rawSummary
            body = rawBody
        } else {
            const lowSummary = rawSummary.toLowerCase()
            const isKdeInternal = rawSummary === "" ||
                                  lowSummary === "kde connect" ||
                                  lowSummary === "kdeconnect" ||
                                  lowSummary === "ping" ||
                                  lowSummary === "find my phone" ||
                                  lowSummary === "pairing request" ||
                                  lowSummary === "battery"

            if (isKdeInternal) {
                return {
                    appName: "KDE Connect",
                    summary: rawSummary || "KDE Connect",
                    body: rawBody,
                    appIcon: notif.appIcon || "kdeconnect",
                    originDevice: originDevice
                }
            }

            appName = rawSummary

            const colonIdx = rawBody.indexOf(": ")
            if (colonIdx > 0 && colonIdx < 80) {
                summary = rawBody.substring(0, colonIdx).trim()
                body = rawBody.substring(colonIdx + 2).trim()
            } else if (rawBody.length > 0) {
                summary = rawSummary
                body = rawBody
            }
        }

        const appIcon = root.resolveAppIcon(appName, notif.appIcon)

        return {
            appName: appName,
            summary: summary,
            body: body,
            appIcon: appIcon,
            originDevice: originDevice
        }
    }

    function isMessagingApp(n) {
        if (!n) return false

        const messagingKeywords = [
            "whatsapp", "tiktok", "instagram", "telegram", "signal",
            "discord", "slack", "element", "messenger", "sms",
            "messages", "chat", "skype", "viber", "line", "wechat",
            "weixin", "snapchat", "twitter", "reddit", "teams"
        ]

        const appName = (n.appName || "").toLowerCase()
        const desktopEntry = (n.desktopEntry || "").toLowerCase()
        const appIcon = (n.appIcon || "").toLowerCase()
        const summary = (n.summary || "").toLowerCase()
        const body = (n.body || "").toLowerCase()

        // 1. Direct check on primary app identifiers
        for (let i = 0; i < messagingKeywords.length; i++) {
            const kw = messagingKeywords[i]
            if (appName.includes(kw) || desktopEntry.includes(kw) || appIcon.includes(kw)) {
                return true
            }
        }

        // 2. Package identifiers in appIcon
        if (appIcon.includes("trill") || appIcon.includes("ugc") || appIcon.includes("musically")) {
            return true
        }

        // 3. For KDE Connect notifications, check summary or body
        if (root.isKdeConnectNotif(n)) {
            for (let i = 0; i < messagingKeywords.length; i++) {
                const kw = messagingKeywords[i]
                if (summary.includes(kw) || body.includes(kw)) {
                    return true
                }
            }

            try {
                const hints = n.hints || {}
                for (const k in hints) {
                    const val = String(hints[k]).toLowerCase()
                    for (let i = 0; i < messagingKeywords.length; i++) {
                        if (val.includes(messagingKeywords[i])) return true
                    }
                }
            } catch (e) { }
        }

        return false
    }

    Process {
        id: kdeConnectReplyProc
        property string replyId: ""
        property string notifId: ""
        property string summary: ""
        property string body: ""
        property string replyText: ""
        command: [
            root.kdeHelperPath, "reply",
            "--reply-id", replyId,
            "--notif-id", notifId,
            "--summary", summary,
            "--body", body,
            "--message", replyText
        ]
        stdout: SplitParser { onRead: data => {} }
        stderr: SplitParser { onRead: data => {} }
    }

    Process {
        id: kdeConnectDismissProc
        property string notifId: ""
        property string summary: ""
        property string body: ""
        command: [
            root.kdeHelperPath, "dismiss",
            "--notif-id", notifId,
            "--summary", summary,
            "--body", body
        ]
        stdout: SplitParser { onRead: data => {} }
        stderr: SplitParser { onRead: data => {} }
    }

    function invokeAction(notifId, actionId, text) {
        const item = root.findEntry(notifId)
        const isKde = item ? (item.isKdeConnect || (item.appName || "").toLowerCase().includes("kde") || (item.desktopEntry || "").toLowerCase().includes("kdeconnect")) : false

        let trackedNotif = null
        for (const n of server.trackedNotifications.values) {
            if (n.id === notifId) { trackedNotif = n; break }
        }

        if (text !== undefined && text !== "") {
            // Inline Reply execution
            if (isKde) {
                // KDE Connect must use KDE Connect DBus helper to send the text message payload
                console.log("[Notifications] sending reply via KDE Connect DBus helper, notif", notifId, "actionId", actionId)
                kdeConnectReplyProc.replyId = (item && item.kdeReplyId) ? item.kdeReplyId : (actionId || "")
                kdeConnectReplyProc.notifId = (item && item.kdeNotifId) ? item.kdeNotifId : ""
                kdeConnectReplyProc.summary = item ? (item.summary || "") : ""
                kdeConnectReplyProc.body = item ? (item.body || "") : ""
                kdeConnectReplyProc.replyText = text
                kdeConnectReplyProc.running = true
            } else if (trackedNotif) {
                // Native freedesktop inline reply (e.g. desktop messaging apps)
                if (trackedNotif.hasInlineReply) {
                    console.log("[Notifications] sending reply via native sendInlineReply for notif", notifId)
                    try {
                        trackedNotif.sendInlineReply(text)
                    } catch (e) { }
                } else if (actionId && actionId !== "inline-reply") {
                    const act = trackedNotif.actions.find(a => a.identifier === actionId)
                    if (act) {
                        try {
                            act.invoke()
                        } catch (e) { }
                    }
                }
            }
        } else {
            // Regular Action click (without text payload)
            if (isKde && (actionId === "1" || actionId === "mark-as-read" || actionId === "dismiss")) {
                kdeConnectDismissProc.notifId = (item && item.kdeNotifId) ? item.kdeNotifId : ""
                kdeConnectDismissProc.summary = item ? (item.summary || "") : ""
                kdeConnectDismissProc.body = item ? (item.body || "") : ""
                kdeConnectDismissProc.running = true
            }
            if (trackedNotif) {
                const act = trackedNotif.actions.find(a => a.identifier === actionId)
                if (act) {
                    try {
                        act.invoke()
                    } catch (e) { }
                }
            }
        }

        if (trackedNotif) {
            try {
                trackedNotif.dismiss()
            } catch (e) { }
        }

        root.removePopup(notifId)
        root.removeFromHistory(notifId)
    }

    function dismiss(notifId) {
        const item = root.findEntry(notifId)
        const isKde = item ? (item.isKdeConnect || (item.appName || "").toLowerCase().includes("kde") || (item.desktopEntry || "").toLowerCase().includes("kdeconnect")) : false
        if (isKde) {
            kdeConnectDismissProc.notifId = (item && item.kdeNotifId) ? item.kdeNotifId : ""
            kdeConnectDismissProc.summary = item ? (item.summary || "") : ""
            kdeConnectDismissProc.body = item ? (item.body || "") : ""
            kdeConnectDismissProc.running = true
        }

        for (const n of server.trackedNotifications.values) {
            if (n.id === notifId) {
                try {
                    n.dismiss()
                } catch (e) { }
                break
            }
        }
        root.removePopup(notifId)
        root.removeFromHistory(notifId)
    }

    function dismissFromCenter(notifId) {
        root.dismiss(notifId)
    }

    function dismissGroupFromCenter(items) {
        if (!items) return
        const ids = []
        const count = items.length !== undefined ? items.length : items.count
        for (let i = 0; i < count; i++) {
            const item = items.get ? items.get(i) : items[i]
            if (item && item.notifId !== undefined)
                ids.push(item.notifId)
        }
        for (let i = 0; i < ids.length; i++) {
            root.dismiss(ids[i])
        }
    }

    function clearHistory() {
        // Also dismiss any active KDE Connect notifications
        for (let i = 0; i < historyModel.count; i++) {
            const item = historyModel.get(i)
            if (item && item.isKdeConnect) {
                kdeConnectDismissProc.notifId = item.kdeNotifId || ""
                kdeConnectDismissProc.summary = item.summary || ""
                kdeConnectDismissProc.body = item.body || ""
                kdeConnectDismissProc.running = true
            }
        }
        historyModel.clear()
        root.saveHistory()
    }

    property int nextSystemNotifId: 900000

    function addSystemNotification(entry) {
        if (!entry) return -1
        const id = entry.notifId || (++nextSystemNotifId)
        const isBattery = entry.isBattery !== undefined ? entry.isBattery : root.isBatteryNotification(entry)
        const fullEntry = {
            notifId: id,
            appName: entry.appName || "System Warning",
            appIcon: entry.appIcon || "battery-caution",
            summary: entry.summary || "",
            body: entry.body || "",
            image: entry.image || "",
            urgency: entry.urgency !== undefined ? entry.urgency : 2,
            time: Date.now(),
            actions: entry.actions || [],
            hasInlineReply: false,
            isMessaging: false,
            isKdeConnect: false,
            isBattery: isBattery,
            kdeNotifId: "",
            kdeReplyId: "",
            inlineReplyPlaceholder: "",
            desktopEntry: ""
        }

        historyModel.insert(0, fullEntry)
        root.pruneExpiredHistory()

        if (!root.doNotDisturb) {
            popupModel.insert(0, fullEntry)
            root.newNotification(fullEntry)
            const timeout = entry.expireTimeout > 0 ? entry.expireTimeout
                : (fullEntry.urgency === 2 ? 6000 : (Services.Config ? (Services.Config.notificationTimeout * 1000) : 5000))
            if (timeout > 0) {
                root._startDismissTimer(id, timeout)
            }
        }
        root.saveHistory()
        return id
    }

    readonly property string historyCachePath: (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.cache/quickshell/notification_history.json"

    Process {
        id: loadHistoryProc
        command: ["sh", "-c", "mkdir -p ~/.cache/quickshell && if [ -f \"" + historyCachePath + "\" ]; then cat \"" + historyCachePath + "\"; else echo '[]'; fi"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        historyModel.clear()
                        for (let i = 0; i < parsed.length; i++) {
                            const entry = parsed[i]
                            if (entry.image && entry.image.startsWith("image://qsimage/")) {
                                entry.image = ""
                            }
                            entry.summary = root.decodeOctalString(entry.summary || "")
                            entry.body = root.decodeOctalString(entry.body || "")
                            if (entry.isKdeConnect && (entry.appName === "KDE Connect" || !entry.appName) && entry.summary && entry.summary !== "KDE Connect") {
                                const resolved = root.resolveKdeNotificationInfo(entry)
                                if (resolved) {
                                    entry.appName = resolved.appName
                                    entry.appIcon = resolved.appIcon
                                    entry.summary = resolved.summary
                                    entry.body = resolved.body
                                    if (resolved.originDevice && !entry.originDevice) entry.originDevice = resolved.originDevice
                                }
                            }
                            historyModel.append(entry)
                        }
                        root.pruneExpiredHistory()
                    }
                } catch (e) {
                    console.log("[Notifications] failed to parse history cache:", e)
                }
            }
        }
    }

    Process {
        id: saveHistoryProc
        property string jsonPayload: "[]"
        command: ["sh", "-c", "mkdir -p ~/.cache/quickshell && printf '%s' \"$1\" > \"" + historyCachePath + "\"", "sh", jsonPayload]
    }

    Timer {
        id: saveHistoryDebounce
        interval: 400
        repeat: false
        onTriggered: root._doSaveHistory()
    }

    function saveHistory() {
        saveHistoryDebounce.restart()
    }

    function _doSaveHistory() {
        const arr = []
        for (let i = 0; i < historyModel.count; i++) {
            const item = historyModel.get(i)
            const actions = []
            if (item.actions) {
                const actCount = item.actions.count !== undefined ? item.actions.count : item.actions.length
                for (let j = 0; j < actCount; j++) {
                    const a = item.actions.get ? item.actions.get(j) : item.actions[j]
                    actions.push({ identifier: a.identifier || "", text: a.text || "" })
                }
            }

            arr.push({
                notifId: item.notifId,
                appName: item.appName || "",
                appIcon: item.appIcon || "",
                summary: item.summary || "",
                body: item.body || "",
                image: (item.image && !item.image.startsWith("image://qsimage/")) ? item.image : "",
                urgency: item.urgency !== undefined ? item.urgency : 1,
                time: item.time || Date.now(),
                actions: actions,
                hasInlineReply: item.hasInlineReply || false,
                isMessaging: item.isMessaging || false,
                isKdeConnect: item.isKdeConnect || false,
                isBattery: item.isBattery || false,
                kdeNotifId: item.kdeNotifId || "",
                kdeReplyId: item.kdeReplyId || "",
                originDevice: item.originDevice || "",
                inlineReplyPlaceholder: item.inlineReplyPlaceholder || "",
                desktopEntry: item.desktopEntry || ""
            })
        }
        saveHistoryProc.jsonPayload = JSON.stringify(arr)
        saveHistoryProc.running = true
    }

    Component.onCompleted: {
        loadHistoryProc.running = true
    }
}
