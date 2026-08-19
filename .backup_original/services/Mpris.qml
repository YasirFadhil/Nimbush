pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root
    property var activePlayer: null

    function pickActive() {
        const players = Mpris.players.values
        const playing = players.find(p => p.isPlaying)
        root.activePlayer = playing || players[0] || null
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
