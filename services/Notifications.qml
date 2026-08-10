pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool doNotDisturb: false
    property bool centerVisible: false
    property alias popupList: popupModel
    property alias historyList: historyModel

    ListModel { id: popupModel }
    ListModel { id: historyModel }
  
    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        actionIconsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true // biar gak keburu di-GC, kita yg atur lifetime-nya

            const entry = {
                notifId: notif.id,
                appName: notif.appName || "Unknown",
                appIcon: notif.appIcon,
                summary: notif.summary,
                body: notif.body,
                image: notif.image,
                urgency: notif.urgency, // NotificationUrgency.Low/Normal/Critical
                time: Date.now(),
                actions: notif.actions.map(a => ({ identifier: a.identifier, text: a.text }))
            }

            historyModel.insert(0, entry)

            if (!root.doNotDisturb) {
                popupModel.insert(0, entry)
                const timeout = notif.urgency === NotificationUrgency.Critical ? 0
                    : (notif.expireTimeout > 0 ? notif.expireTimeout : 5000)
                if (timeout > 0) {
                    dismissTimer.createObject(root, { notifId: notif.id, interval: timeout }).start()
                }
            }

            notif.closed.connect(() => {
                // App closed the notif externally — hanya hapus popup, biarkan di history
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
                // Timeout habis — hanya hapus popup (toast), notif tetap di history
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
        function closeCenter(): void { root.centerVisible = false }
    }

    function removePopup(id) {
        for (let i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).notifId === id) { popupModel.remove(i); break }
        }
    }

    function removeFromHistory(id) {
        for (let i = 0; i < historyModel.count; i++) {
            if (historyModel.get(i).notifId === id) { historyModel.remove(i); break }
        }
    }

    function invokeAction(notifId, actionId) {
        for (const n of server.trackedNotifications.values) {
            if (n.id === notifId) {
                const action = n.actions.find(a => a.identifier === actionId)
                if (action) action.invoke()
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

    // Hapus notif dari history Center saja (dipanggil user dari Center UI)
    function dismissFromCenter(notifId) {
        removeFromHistory(notifId)
    }

    // Hapus semua notif dalam satu group dari history
    function dismissGroupFromCenter(items) {
        for (let i = 0; i < items.length; i++)
            removeFromHistory(items[i].notifId)
    }

    function clearHistory() { historyModel.clear() }
}
