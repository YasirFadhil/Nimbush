import QtQuick
import "../../services" as Services

Item {
    id: root

    property int barCount: 4
    property real barWidth: 2.8
    property real barSpacing: 2.2
    property real minHeight: 3.5
    property real maxHeight: 15.0
    property real barRadius: barWidth / 2.0
    property color barColor: Services.Theme ? Services.Theme.success : "#22c55e"
    property bool isPlaying: false
    property bool active: true

    // True if media source is remote / not from laptop (e.g. phone via KDE Connect)
    readonly property bool isRemote: Services.Mpris ? (Services.Mpris.isRemote ?? false) : false

    implicitWidth: isRemote ? (3 * 3.5 + 2 * 3.0) : (barCount * barWidth + Math.max(0, barCount - 1) * barSpacing)
    implicitHeight: maxHeight

    // ── Remote Mode: "Cuma dot dot" indicator (for phone / non-laptop players) ─
    Row {
        id: remoteDotsRow
        anchors.centerIn: parent
        spacing: 3.0
        visible: root.isRemote

        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 3.5
                height: 3.5
                radius: 1.75
                color: root.barColor
                opacity: root.isPlaying ? 0.85 : 0.4
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    running: root.isPlaying && root.isRemote && root.active
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                    PauseAnimation  { duration: index * 160 }
                    NumberAnimation { to: 0.95; duration: 650; easing.type: Easing.InOutSine }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 250 }
                }
            }
        }
    }

    // ── Local Mode: fake equalizer (same style as the satellite waveform) ─────
    // Per-bar loop: rise to upTo over upMs, fall to downTo over downMs.
    // Bars 0-2 match the satellite; bar 3 is extra for the 4-bar island.
    readonly property var upTo:   [14, 6, 12, 9]
    readonly property var upMs:   [280, 400, 340, 360]
    readonly property var downTo: [4, 14, 4, 13]
    readonly property var downMs: [320, 300, 380, 330]

    Row {
        id: waveBarsRow
        anchors.centerIn: parent
        spacing: root.barSpacing
        visible: !root.isRemote

        Repeater {
            model: root.barCount

            Rectangle {
                id: barRect
                required property int index

                readonly property int k: index % root.upTo.length

                width: root.barWidth
                height: root.minHeight
                radius: root.barRadius
                color: root.barColor
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on height {
                    id: waveAnim
                    running: root.active && root.isPlaying && !root.isRemote
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: Math.min(root.maxHeight, root.upTo[barRect.k])
                        duration: root.upMs[barRect.k]
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: Math.max(root.minHeight, root.downTo[barRect.k])
                        duration: root.downMs[barRect.k]
                        easing.type: Easing.InOutSine
                    }

                    onRunningChanged: {
                        if (running) settleAnim.stop()
                        else settleAnim.start()
                    }
                }

                // When playback stops, ease back down to the resting height
                // instead of freezing mid-wave.
                NumberAnimation {
                    id: settleAnim
                    target: barRect
                    property: "height"
                    to: root.minHeight
                    duration: 150
                    easing.type: Easing.OutCubic
                }

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }
        }
    }
}
