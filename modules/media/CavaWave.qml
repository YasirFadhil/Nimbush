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

    readonly property bool needsCava: root.active && !root.isRemote
    readonly property bool useCava: (!root.isRemote && Services.Cava && Services.Cava.isAvailable && Services.Cava.hasAudio && (Services.Config ? Services.Config.islandCavaWave : true))

    Component.onCompleted: {
        if (root.needsCava && Services.Cava) Services.Cava.activeConsumers++
    }
    Component.onDestruction: {
        if (root.needsCava && Services.Cava) Services.Cava.activeConsumers = Math.max(0, Services.Cava.activeConsumers - 1)
    }
    onNeedsCavaChanged: {
        if (Services.Cava) {
            if (root.needsCava) Services.Cava.activeConsumers++
            else Services.Cava.activeConsumers = Math.max(0, Services.Cava.activeConsumers - 1)
        }
    }

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

    // ── Local Mode: Animated Equalizer Bars (CAVA / Wave) ─────────────────────
    // Organic Multi-Harmonic Idle Animation (when local audio is silent/paused)
    property real idleTick: 0.0
    NumberAnimation on idleTick {
        running: root.active && root.isPlaying && !root.useCava && !root.isRemote
        loops: Animation.Infinite
        from: 0.0
        to: Math.PI * 2
        duration: 1600
    }

    // Baseline resting heights and peak ceilings per bar (curved natural equalizer arch)
    readonly property var defaultBaseHeights: [4.0, 7.5, 5.5, 3.5]
    readonly property var defaultMaxHeights:  [13.0, 16.5, 14.5, 11.5]

    function idleWave(idx) {
        const t = root.idleTick
        if (idx === 0) {
            return (Math.sin(t * 1.3) * 0.5 + Math.cos(t * 0.7) * 0.5 + 1.0) / 2.0
        } else if (idx === 1) {
            return (Math.sin(t * 1.8 + 0.8) * 0.6 + Math.cos(t * 1.1) * 0.4 + 1.0) / 2.0
        } else if (idx === 2) {
            return (Math.sin(t * 1.5 + 1.9) * 0.5 + Math.cos(t * 0.9 + 0.4) * 0.5 + 1.0) / 2.0
        } else {
            return (Math.sin(t * 2.1 + 2.7) * 0.55 + Math.cos(t * 1.4) * 0.45 + 1.0) / 2.0
        }
    }

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

                width: root.barWidth
                radius: root.barRadius
                color: root.barColor
                anchors.verticalCenter: parent.verticalCenter

                readonly property real baseH: (index < root.defaultBaseHeights.length) ? root.defaultBaseHeights[index] : root.minHeight
                readonly property real maxH:  (index < root.defaultMaxHeights.length)  ? root.defaultMaxHeights[index]  : root.maxHeight

                readonly property real targetHeight: {
                    if (!root.isPlaying) {
                        return root.minHeight
                    }
                    if (root.useCava) {
                        const val = Services.Cava.sample(index, root.barCount)
                        return Math.max(root.minHeight, Math.min(maxH, baseH + val * (maxH - baseH)))
                    }
                    const idleFactor = root.idleWave(index)
                    return Math.max(root.minHeight, Math.min(maxH, baseH + idleFactor * (maxH - baseH)))
                }

                readonly property bool isRising: targetHeight > height

                height: targetHeight

                Behavior on height {
                    NumberAnimation {
                        duration: root.useCava ? (barRect.isRising ? 45 : 125) : 110
                        easing.type: barRect.isRising ? Easing.OutQuad : Easing.OutCubic
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }
        }
    }
}
