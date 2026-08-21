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

    Component.onCompleted: pickActive()

    Connections {
        target: Mpris.players
        function onValuesChanged() { root.pickActive() }
    }

    Instantiator {
        model: Mpris.players.values
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { root.pickActive() }
            function onTrackTitleChanged() { root.pickActive() }
        }
    }
}
