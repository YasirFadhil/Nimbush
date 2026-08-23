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
            kdeRestartTimer.restart()
        }
    }

    Timer {
        id: kdeRestartTimer
        interval: 3000
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
            const actionsList = notif.actions.map(a => ({ identifier: a.identifier, text: a.text }))

            // Add inline reply action if messaging or hasInlineReply or KDE Connect
            if ((isMessaging || notif.hasInlineReply || isKdeConnect) && !actionsList.some(a => a.identifier === "inline-reply" || (a.identifier || "").toLowerCase().includes("reply") || (a.text || "").toLowerCase().includes("reply") || (a.text || "").toLowerCase().includes("balas"))) {
                actionsList.push({ identifier: "inline-reply", text: "Reply" })
            }

            const entry = {
                notifId: notif.id,
                appName: notif.appName || "Unknown",
                appIcon: notif.appIcon,
                summary: notif.summary || "",
                body: notif.body || "",
                image: notif.image || "",
                urgency: notif.urgency,
                time: Date.now(),
                actions: actionsList,
                hasInlineReply: isMessaging || notif.hasInlineReply || isKdeConnect,
                isMessaging: isMessaging,
                isKdeConnect: isKdeConnect,
                kdeNotifId: "",
                kdeReplyId: "",
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

                if (notif.urgency === NotificationUrgency.Critical)
                    SoundFeedback.playError()
                else if (notif.urgency === NotificationUrgency.Low)
                    SoundFeedback.playInfo()
                else
                    SoundFeedback.playNotification()

                const timeout = notif.expireTimeout > 0 ? notif.expireTimeout
                    : (notif.urgency === NotificationUrgency.Critical ? 7000 : (Services.Config ? (Services.Config.notificationTimeout * 1000) : 5000))
                if (timeout > 0) {
                    dismissTimer.createObject(root, { notifId: notif.id, interval: timeout }).start()
                }
            }

            notif.closed.connect(() => {
                root.removePopup(notif.id)
                root.removeFromHistory(notif.id)
            })
        }
    }

    Process {
        id: kdeLinkProc
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
                            const sMatch = (k.app && kdeLinkProc.targetSummary.includes(k.app)) || (k.title && kdeLinkProc.targetSummary.includes(k.title))
                            const bMatch = (k.text && kdeLinkProc.targetBody.includes(k.text.substring(0, 15))) || (k.title && kdeLinkProc.targetBody.includes(k.title))
                            if (sMatch || bMatch || list.length === 1) {
                                for (let h = 0; h < historyModel.count; h++) {
                                    const hItem = historyModel.get(h)
                                    if (hItem && hItem.notifId === kdeLinkProc.targetNotifId) {
                                        hItem.kdeNotifId = String(k.id)
                                        hItem.kdeReplyId = String(k.replyId || "")
                                        root.saveHistory()
                                        break
                                    }
                                }
                                for (let p = 0; p < popupModel.count; p++) {
                                    const pItem = popupModel.get(p)
                                    if (pItem && pItem.notifId === kdeLinkProc.targetNotifId) {
                                        pItem.kdeNotifId = String(k.id)
                                        pItem.kdeReplyId = String(k.replyId || "")
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

    function isKdeConnectNotif(n) {
        if (!n) return false
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
        stdout: SplitParser { onRead: data => console.log("[kdeConnectReplyProc][out]", data) }
        stderr: SplitParser { onRead: data => console.log("[kdeConnectReplyProc][err]", data) }
        onExited: (code, status) => console.log("[kdeConnectReplyProc] exited with code", code)
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
        stdout: SplitParser { onRead: data => console.log("[kdeConnectDismissProc][out]", data) }
        stderr: SplitParser { onRead: data => console.log("[kdeConnectDismissProc][err]", data) }
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
                dismissTimer.createObject(root, { notifId: id, interval: timeout }).start()
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
                            historyModel.append(parsed[i])
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
                image: item.image || "",
                urgency: item.urgency !== undefined ? item.urgency : 1,
                time: item.time || Date.now(),
                actions: actions,
                hasInlineReply: item.hasInlineReply || false,
                isMessaging: item.isMessaging || false,
                isKdeConnect: item.isKdeConnect || false,
                kdeNotifId: item.kdeNotifId || "",
                kdeReplyId: item.kdeReplyId || "",
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
