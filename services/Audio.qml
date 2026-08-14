pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? true
    readonly property string sinkDescription: sink?.description ?? sink?.name ?? "Default Output"

    // true when sink is a Bluetooth TWS / wireless earbuds (bluez_output.*)
    readonly property bool isTws: {
        const name = (sink?.name ?? "").toLowerCase()
        return name.includes("bluez")
    }

    // true when sink is a wired headphone/headset/jack output
    readonly property bool isHeadphone: {
        const name = (sink?.name ?? "").toLowerCase()
        const desc = (sink?.description ?? "").toLowerCase()
        const combined = name + " " + desc
        return !root.isTws && (
               combined.includes("headphone") ||
               combined.includes("headset")   ||
               combined.includes("earphone")  ||
               combined.includes("earbuds")   ||
               combined.includes("tws")        ||
               combined.includes("a2dp")      ||
               combined.includes("hfp")       ||
               combined.includes("hsp")       ||
               combined.includes("jack"))
    }

    property var sinks: []

    PwObjectTracker { objects: [sink] }

    Process {
        id: getSinksProc
        command: ["pactl", "-f", "json", "list", "sinks"]
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    const parsed = JSON.parse(data)
                    const list = []
                    for (let i = 0; i < parsed.length; i++) {
                        const item = parsed[i]
                        const desc = item.description || item.properties?.["node.nick"] || item.name
                        const isCurrent = (item.name === root.sink?.name)
                        list.push({
                            name: item.name,
                            description: desc,
                            isCurrent: isCurrent
                        })
                    }
                    root.sinks = list
                } catch(e) {}
            }
        }
    }

    Process {
        id: setSinkProc
        property string targetSink: ""
        command: ["pactl", "set-default-sink", targetSink]
        onExited: refreshSinks()
    }

    function refreshSinks() {
        getSinksProc.running = true
    }

    function setSink(name) {
        setSinkProc.targetSink = name
        setSinkProc.running = true
    }

    function setVolume(v) {
        if (sink?.ready && sink?.audio) sink.audio.volume = Math.max(0, Math.min(1, v))
    }
    function toggleMute() {
        if (sink?.ready && sink?.audio) sink.audio.muted = !sink.audio.muted
    }

    Component.onCompleted: refreshSinks()
}
