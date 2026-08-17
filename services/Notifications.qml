pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

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

    ListModel { id: popupModel }
    ListModel { id: historyModel }

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

            // Only add/enable inline reply action if the notification is from a messaging app
            if (isMessaging && (notif.hasInlineReply || isKdeConnect) && !actionsList.some(a => a.identifier === "inline-reply" || (a.identifier || "").toLowerCase().includes("reply"))) {
                actionsList.push({ identifier: "inline-reply", text: "Reply" })
            }

            const entry = {
                notifId: notif.id,
                appName: notif.appName || "Unknown",
                appIcon: notif.appIcon,
                summary: notif.summary,
                body: notif.body,
                image: notif.image,
                urgency: notif.urgency,
                time: Date.now(),
                actions: actionsList,
                hasInlineReply: isMessaging && (notif.hasInlineReply || isKdeConnect),
                isMessaging: isMessaging,
                inlineReplyPlaceholder: notif.inlineReplyPlaceholder || "",
                desktopEntry: notif.desktopEntry || ""
            }

            historyModel.insert(0, entry)
            while (historyModel.count > root.maxHistoryCount) {
                historyModel.remove(historyModel.count - 1)
            }
            root.saveHistory()

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
                    : (notif.urgency === NotificationUrgency.Critical ? 7000 : 5000)
                if (timeout > 0) {
                    dismissTimer.createObject(root, { notifId: notif.id, interval: timeout }).start()
                }
            }

            notif.closed.connect(() => {
                root.removePopup(notif.id)
            })
        }
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

        // 2. Package identifiers in appIcon (e.g. TikTok / Instagram / Telegram packages)
        if (appIcon.includes("trill") || appIcon.includes("ugc") || appIcon.includes("musically")) {
            return true
        }

        // 3. For KDE Connect notifications, check summary, body, or hints for messaging keywords
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
        property string replyText: ""
        // KDE Connect's notifications plugin exposes sendReply(replyId, message) as a
        // TWO-argument method on the plugin object at .../devices/<id>/notifications
        // (not one-argument, and not on the per-notification sub-path).
        command: ["sh", "-c",
            "REPLY_ID=\"$1\"\n" +
            "TEXT=\"$2\"\n" +
            "echo \"[kdeconnect-reply] replyId='$REPLY_ID' text='$TEXT'\"\n" +
            "if command -v busctl >/dev/null 2>&1; then\n" +
            "    PATHS=$(busctl --user tree org.kde.kdeconnect 2>&1 | sed 's/^[^/]*//' | grep -E '^/modules/kdeconnect/devices/[^/]+/notifications$')\n" +
            "    echo \"[kdeconnect-reply][busctl] plugin paths found: $PATHS\"\n" +
            "    for p in $PATHS; do\n" +
            "        echo \"[kdeconnect-reply][busctl] calling sendReply on $p\"\n" +
            "        busctl --user call org.kde.kdeconnect \"$p\" org.kde.kdeconnect.device.notifications sendReply ss \"$REPLY_ID\" \"$TEXT\"\n" +
            "    done\n" +
            "elif command -v qdbus >/dev/null 2>&1; then\n" +
            "    for d in $(qdbus org.kde.kdeconnect /modules/kdeconnect devices 2>&1); do\n" +
            "        p=\"/modules/kdeconnect/devices/$d/notifications\"\n" +
            "        echo \"[kdeconnect-reply][qdbus] calling sendReply on $p\"\n" +
            "        qdbus org.kde.kdeconnect \"$p\" sendReply \"$REPLY_ID\" \"$TEXT\"\n" +
            "    done\n" +
            "fi\n",
            "sh", replyId, replyText]
        stdout: SplitParser { onRead: data => console.log("[kdeConnectReplyProc][out]", data) }
        stderr: SplitParser { onRead: data => console.log("[kdeConnectReplyProc][err]", data) }
        onExited: (code, status) => console.log("[kdeConnectReplyProc] exited with code", code)
    }

    function invokeAction(notifId, actionId, text) {
        for (const n of server.trackedNotifications.values) {
            if (n.id === notifId) {
                if ((actionId === "inline-reply" || n.hasInlineReply) && text !== undefined && text !== "") {
                    console.log("[Notifications] sending reply via native sendInlineReply for notif", notifId)
                    n.sendInlineReply(text)
                } else if (isKdeConnectNotif(n) && text !== undefined && text !== "") {
                    console.log("[Notifications] sending reply via KDE Connect DBus, notif", notifId, "actionId", actionId)
                    kdeConnectReplyProc.replyId = actionId || ""
                    kdeConnectReplyProc.replyText = text
                    kdeConnectReplyProc.running = true
                } else {
                    const action = n.actions.find(a => a.identifier === actionId)
                    if (action) {
                        if (text !== undefined && text !== "") action.invoke(text)
                        else action.invoke()
                    }
                }
                break
            }
        }
        removePopup(notifId)
        removeFromHistory(notifId)
    }

    function dismiss(notifId) {
        for (const n of server.trackedNotifications.values) {
            if (n.id === notifId) { n.dismiss(); break }
        }
        removePopup(notifId)
        removeFromHistory(notifId)
    }

    function dismissFromCenter(notifId) {
        removeFromHistory(notifId)
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
            removeFromHistory(ids[i])
        }
    }

    function clearHistory() {
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
            actions: entry.actions || []
        }

        historyModel.insert(0, fullEntry)

        if (!root.doNotDisturb) {
            popupModel.insert(0, fullEntry)
            root.newNotification(fullEntry)
            const timeout = entry.expireTimeout > 0 ? entry.expireTimeout
                : (fullEntry.urgency === 2 ? 6000 : 5000)
            if (timeout > 0) {
                dismissTimer.createObject(root, { notifId: id, interval: timeout }).start()
            }
        }
        root.saveHistory()
        return id
    }

    readonly property string historyCachePath: "/home/yasirfadhil/.cache/quickshell/notification_history.json"

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

    function saveHistory() {
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