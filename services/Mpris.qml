pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root
    property var activePlayer: null
    property var playersList: Mpris.players.values
    readonly property int playerCount: Mpris.players.values ? Mpris.players.values.length : 0
    property bool manualOverride: false

    // Signals for instant reactive awareness across the desktop
    signal trackChanged(var player)
    signal playbackStarted(var player)

    function isPlayerRemote(p) {
        if (!p) return false
        const id = (p.identity || "").toLowerCase()
        const desk = (p.desktopEntry || "").toLowerCase()
        const bus = (p.dbusName || "").toLowerCase()
        return id.includes("kdeconnect") || desk.includes("kdeconnect") || bus.includes("kdeconnect")
            || id.includes("gsconnect") || desk.includes("gsconnect") || bus.includes("gsconnect")
            || id.includes("vivo") || id.includes("samsung") || id.includes("xiaomi")
            || id.includes("oppo") || id.includes("pixel") || id.includes("iphone")
            || id.includes("phone") || id.includes("android")
            || desk.includes("phone") || desk.includes("android")
    }

    // True if active player is from a remote device / phone (e.g. KDE Connect, GSConnect)
    readonly property bool isRemote: isPlayerRemote(root.activePlayer)
    readonly property bool isLocal: !root.isRemote

    function pickActive() {
        const players = Mpris.players.values
        root.playersList = players
        if (!players || players.length === 0) {
            root.activePlayer = null
            root.manualOverride = false
            return
        }
        if (root.manualOverride && root.activePlayer && players.includes(root.activePlayer)) {
            return
        }
        root.manualOverride = false

        // 1. If currently active player is still playing, keep it
        if (root.activePlayer && players.includes(root.activePlayer) && (root.activePlayer.isPlaying ?? false)) {
            return
        }

        // 2. Prioritize currently playing local players (e.g. browser, spotify, mpv on this PC)
        const localPlaying = players.find(p => (p.isPlaying ?? false) && !root.isPlayerRemote(p))
        if (localPlaying) {
            root.activePlayer = localPlaying
            return
        }

        // 3. Fallback to any playing player (including remote/phone)
        const anyPlaying = players.find(p => (p.isPlaying ?? false))
        if (anyPlaying) {
            root.activePlayer = anyPlaying
            return
        }

        // 4. Fallback to current player if still in list
        if (root.activePlayer && players.includes(root.activePlayer)) {
            return
        }

        // 5. Fallback to local players first, then first available
        const localPlayer = players.find(p => !root.isPlayerRemote(p))
        root.activePlayer = localPlayer || players[0] || null
    }

    function selectPlayer(player) {
        if (player) {
            root.manualOverride = true
            root.activePlayer = player
        }
    }

    function nextPlayer() {
        const list = Mpris.players.values
        if (!list || list.length <= 1) return
        const idx = list.indexOf(root.activePlayer)
        const nextIdx = (idx + 1) % list.length
        selectPlayer(list[nextIdx])
    }

    function prevPlayer() {
        const list = Mpris.players.values
        if (!list || list.length <= 1) return
        const idx = list.indexOf(root.activePlayer)
        const prevIdx = (idx - 1 + list.length) % list.length
        selectPlayer(list[prevIdx])
    }

    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Timer {
        id: posHeartbeatTimer
        interval: 250
        repeat: true
        running: (root.activePlayer !== null) && (root.activePlayer.isPlaying ?? false)
        onTriggered: {
            if (root.activePlayer && (root.activePlayer.isPlaying ?? false)) {
                root.activePlayer.positionChanged()
            }
        }
    }

    Component.onCompleted: pickActive()

    Connections {
        target: Mpris.players
        function onValuesChanged() { 
            const players = Mpris.players.values
            root.playersList = players
            const localPlaying = players ? players.find(p => (p.isPlaying ?? false) && !root.isPlayerRemote(p)) : null
            if (localPlaying && (!root.activePlayer || !root.activePlayer.isPlaying || root.activePlayer !== localPlaying)) {
                root.activePlayer = localPlaying
                root.playbackStarted(localPlaying)
                root.trackChanged(localPlaying)
            } else {
                root.pickActive()
            }
            if (root.activePlayer) root.activePlayer.positionChanged()
        }
    }

    Instantiator {
        model: Mpris.players.values
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true

            function onIsPlayingChanged() { 
                if (modelData && (modelData.isPlaying ?? false)) {
                    root.activePlayer = modelData
                    root.playbackStarted(modelData)
                    root.trackChanged(modelData)
                } else {
                    root.pickActive()
                }
                if (modelData) modelData.positionChanged()
            }
            function onTrackTitleChanged() { 
                if (modelData && (modelData.isPlaying ?? false)) {
                    root.activePlayer = modelData
                }
                if (root.activePlayer === modelData) {
                    root.trackChanged(modelData)
                }
                if (modelData) modelData.positionChanged()
            }
            function onTrackArtistChanged() {
                if (modelData && (modelData.isPlaying ?? false)) {
                    root.activePlayer = modelData
                }
                if (root.activePlayer === modelData) {
                    root.trackChanged(modelData)
                }
                if (modelData) modelData.positionChanged()
            }
            function onTrackArtUrlChanged() {
                if (modelData && (modelData.isPlaying ?? false)) {
                    root.activePlayer = modelData
                }
                if (root.activePlayer === modelData) {
                    root.trackChanged(modelData)
                }
                if (modelData) modelData.positionChanged()
            }
            function onTrackChanged() {
                if (modelData && (modelData.isPlaying ?? false)) {
                    root.activePlayer = modelData
                }
                if (root.activePlayer === modelData) {
                    root.trackChanged(modelData)
                }
                if (modelData) modelData.positionChanged()
            }
            function onMetadataChanged() {
                if (modelData && (modelData.isPlaying ?? false)) {
                    root.activePlayer = modelData
                }
                if (root.activePlayer === modelData) {
                    root.trackChanged(modelData)
                }
                if (modelData) modelData.positionChanged()
            }
            function onPlaybackStateChanged() {
                if (modelData && (modelData.isPlaying ?? false)) {
                    if (root.activePlayer !== modelData) {
                        root.activePlayer = modelData
                        root.playbackStarted(modelData)
                        root.trackChanged(modelData)
                    }
                } else {
                    root.pickActive()
                }
                if (modelData) modelData.positionChanged()
            }
        }
    }
}
