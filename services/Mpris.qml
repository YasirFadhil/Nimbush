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
        const playing = players.find(p => p.isPlaying)
        root.activePlayer = playing || players[0] || null
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
            root.pickActive()
            if (root.activePlayer) root.activePlayer.positionChanged()
        }
    }

    Instantiator {
        model: Mpris.players.values
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { 
                root.pickActive()
                if (modelData) modelData.positionChanged()
            }
            function onTrackTitleChanged() { 
                root.pickActive()
                if (modelData) modelData.positionChanged()
            }
            function onPlaybackStateChanged() {
                root.pickActive()
                if (modelData) modelData.positionChanged()
            }
        }
    }
}
