pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    // ── Default Output Sink ──
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? _fallbackVolume
    readonly property bool muted: sink?.audio?.muted ?? _fallbackMuted
    readonly property string sinkDescription: sink?.description ?? sink?.name ?? "Default Output"

    // ── Default Input Source ──
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real sourceVolume: source?.audio?.volume ?? _fallbackSourceVolume
    readonly property bool sourceMuted: source?.audio?.muted ?? _fallbackSourceMuted
    readonly property string sourceDescription: source?.description ?? source?.name ?? "Default Input"

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
    property var sources: []
    property var streams: []

    // Per-application volume updates are throttled so slider dragging stays smooth
    // without rebuilding the Repeater model on every pointer movement.
    property int _pendingStreamIndex: -1
    property real _pendingStreamVolume: 1.0
    property bool _streamVolumeNeedsDispatch: false
    property bool _streamVolumeCommitPending: false
    property bool _streamVolumeUiDragging: false
    property bool _refreshAfterStreamCommit: false

    // Current (default) sink and source derived from the arrays
    readonly property var currentSink: {
        if (!sinks || sinks.length === 0) return null
        for (let i = 0; i < sinks.length; i++) {
            if (sinks[i].isCurrent) return sinks[i]
        }
        return sinks[0] ?? null
    }
    readonly property var currentSource: {
        if (!sources || sources.length === 0) return null
        for (let i = 0; i < sources.length; i++) {
            if (sources[i].isCurrent) return sources[i]
        }
        return sources[0] ?? null
    }

    property real _fallbackVolume: 0.8
    property bool _fallbackMuted: false
    property real _fallbackSourceVolume: 1.0
    property bool _fallbackSourceMuted: false

    PwObjectTracker { objects: [sink, source] }

    Process {
        id: getAudioDevicesProc
        command: [
            "python3", "-c",
            "import json, subprocess\n" +
            "try:\n" +
            "    sinks_raw = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sinks']).decode()\n" +
            "    sources_raw = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sources']).decode()\n" +
            "    try:\n" +
            "        streams_raw = subprocess.check_output(['pactl', '-f', 'json', 'list', 'sink-inputs']).decode()\n" +
            "    except Exception:\n" +
            "        streams_raw = '[]'\n" +
            "    def_sink = subprocess.check_output(['pactl', 'get-default-sink']).decode().strip()\n" +
            "    def_source = subprocess.check_output(['pactl', 'get-default-source']).decode().strip()\n" +
            "    sinks = []\n" +
            "    for s in json.loads(sinks_raw):\n" +
            "        desc = s.get('description') or s.get('properties', {}).get('node.nick') or s.get('name')\n" +
            "        nick = s.get('properties', {}).get('node.nick') or s.get('properties', {}).get('device.profile.description') or desc\n" +
            "        sinks.append({\n" +
            "            'name': s['name'],\n" +
            "            'description': desc,\n" +
            "            'nick': nick,\n" +
            "            'isCurrent': (s['name'] == def_sink),\n" +
            "            'muted': s.get('mute', False),\n" +
            "            'icon': s.get('properties', {}).get('device.icon_name', '')\n" +
            "        })\n" +
            "    sources = []\n" +
            "    for s in json.loads(sources_raw):\n" +
            "        name = s.get('name', '')\n" +
            "        if name.endswith('.monitor') or s.get('properties', {}).get('device.class') == 'monitor':\n" +
            "            continue\n" +
            "        desc = s.get('description') or s.get('properties', {}).get('node.nick') or name\n" +
            "        nick = s.get('properties', {}).get('node.nick') or s.get('properties', {}).get('device.profile.description') or desc\n" +
            "        sources.append({\n" +
            "            'name': name,\n" +
            "            'description': desc,\n" +
            "            'nick': nick,\n" +
            "            'isCurrent': (name == def_source),\n" +
            "            'muted': s.get('mute', False),\n" +
            "            'icon': s.get('properties', {}).get('device.icon_name', '')\n" +
            "        })\n" +
            "    streams = []\n" +
            "    for st in json.loads(streams_raw):\n" +
            "        props = st.get('properties', {})\n" +
            "        name = props.get('application.name') or props.get('media.name') or 'Audio Stream'\n" +
            "        vol_dict = st.get('volume', {})\n" +
            "        vol_val = 1.0\n" +
            "        for ch, ch_data in vol_dict.items():\n" +
            "            if isinstance(ch_data, dict) and 'value' in ch_data:\n" +
            "                vol_val = ch_data['value'] / 65536.0\n" +
            "                break\n" +
            "        streams.append({\n" +
            "            'index': st['index'],\n" +
            "            'name': name,\n" +
            "            'binary': props.get('application.process.binary', ''),\n" +
            "            'icon': props.get('application.icon_name', ''),\n" +
            "            'volume': max(0.0, min(1.5, vol_val)),\n" +
            "            'muted': st.get('mute', False)\n" +
            "        })\n" +
            "    print(json.dumps({'sinks': sinks, 'sources': sources, 'streams': streams}))\n" +
            "except Exception as e:\n" +
            "    print('{}')"
        ]
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (parsed.sinks) root.sinks = parsed.sinks
                    if (parsed.sources) root.sources = parsed.sources
                    // Do not replace the Repeater model while a stream slider is being dragged.
                    if (parsed.streams && !root._streamVolumeUiDragging)
                        root.streams = parsed.streams
                } catch(e) {}
            }
        }
        onExited: (code, status) => {
            running = false
            if (root._refreshAfterStreamCommit) {
                root._refreshAfterStreamCommit = false
                root.refreshDevices()
            }
        }
    }

    Process {
        id: setSinkProc
        property string targetSink: ""
        command: ["pactl", "set-default-sink", targetSink]
        onExited: (code, status) => { running = false; refreshDevices() }
    }

    Process {
        id: setSourceProc
        property string targetSource: ""
        command: ["pactl", "set-default-source", targetSource]
        onExited: (code, status) => { running = false; refreshDevices() }
    }

    Process {
        id: setStreamVolProc
        property int targetIndex: 0
        property real targetVol: 1.0
        command: ["pactl", "set-sink-input-volume", String(targetIndex), Math.round(targetVol * 100) + "%"]
        onExited: (code, status) => root._onStreamVolumeProcessExited()
    }

    // Throttle stream volume commands to roughly 16 updates/sec while dragging.
    // If pactl is still running, the latest requested value is sent when it exits.
    Timer {
        id: streamVolumeDispatch
        interval: 60
        repeat: false
        onTriggered: root._dispatchStreamVolume()
    }

    // Refresh the stream model only after the final drag update has been applied.
    Timer {
        id: streamVolumeRefresh
        interval: 180
        repeat: false
        onTriggered: {
            // If a device snapshot is already running, request one more after it exits.
            if (getAudioDevicesProc.running)
                root._refreshAfterStreamCommit = true
            else
                root.refreshDevices()
        }
    }

    Process {
        id: setStreamMuteProc
        property int targetIndex: 0
        command: ["pactl", "set-sink-input-mute", String(targetIndex), "toggle"]
        onExited: (code, status) => { running = false; refreshDevices() }
    }

    Process {
        id: setVolFallbackProc
        onExited: (code, status) => { running = false }
    }
    Process {
        id: setMuteFallbackProc
        onExited: (code, status) => { running = false }
    }

    function refreshDevices() {
        if (!getAudioDevicesProc.running) getAudioDevicesProc.running = true
    }
    function refreshSinks() { refreshDevices() }
    function refreshSources() { refreshDevices() }
    function refreshAll() { refreshDevices() }

    function setSink(name) {
        if (!name) return
        if (setSinkProc.running) setSinkProc.running = false
        setSinkProc.targetSink = name
        setSinkProc.running = true
    }

    function setSource(name) {
        if (!name) return
        if (setSourceProc.running) setSourceProc.running = false
        setSourceProc.targetSource = name
        setSourceProc.running = true
    }

    function beginStreamVolumeDrag() {
        root._streamVolumeUiDragging = true
        streamVolumeRefresh.stop()
    }

    function setStreamVolume(index, v, commit = true) {
        if (index === undefined || index === null || Number(index) < 0)
            return

        const numericVolume = Number(v)
        const val = Math.max(0, Math.min(1.5, Number.isFinite(numericVolume) ? numericVolume : 0))

        // Keep only the newest requested value. Never replace root.streams here:
        // doing so resets the Repeater delegates and breaks mouse dragging.
        root._pendingStreamIndex = Number(index)
        root._pendingStreamVolume = val
        root._streamVolumeNeedsDispatch = true
        streamVolumeRefresh.stop()

        if (commit) {
            root._streamVolumeCommitPending = true
            root._streamVolumeUiDragging = false
        }

        if (!setStreamVolProc.running && !streamVolumeDispatch.running)
            streamVolumeDispatch.start()
    }

    function _dispatchStreamVolume() {
        if (!root._streamVolumeNeedsDispatch || root._pendingStreamIndex < 0)
            return
        if (setStreamVolProc.running)
            return

        const index = root._pendingStreamIndex
        const volume = root._pendingStreamVolume
        root._streamVolumeNeedsDispatch = false

        setStreamVolProc.targetIndex = index
        setStreamVolProc.targetVol = volume
        setStreamVolProc.running = true
    }

    function _onStreamVolumeProcessExited() {
        setStreamVolProc.running = false

        if (root._streamVolumeNeedsDispatch) {
            if (!streamVolumeDispatch.running)
                streamVolumeDispatch.start()
            return
        }

        if (root._streamVolumeCommitPending) {
            root._streamVolumeCommitPending = false
            streamVolumeRefresh.restart()
        }
    }

    function toggleStreamMute(index) {
        if (root.streams) {
            const arr = [...root.streams]
            const item = arr.find(s => s.index === index)
            if (item) {
                item.muted = !item.muted
                root.streams = arr
            }
        }
        if (setStreamMuteProc.running) setStreamMuteProc.running = false
        setStreamMuteProc.targetIndex = index
        setStreamMuteProc.running = true
    }

    function setVolume(v) {
        const val = Math.max(0, Math.min(1, v))
        if (sink?.ready && sink?.audio) {
            sink.audio.volume = val
        } else {
            root._fallbackVolume = val
            setVolFallbackProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", Math.round(val * 100) + "%"]
            setVolFallbackProc.running = true
        }
    }

    function toggleMute() {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = !sink.audio.muted
        } else {
            root._fallbackMuted = !root._fallbackMuted
            setMuteFallbackProc.command = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
            setMuteFallbackProc.running = true
        }
    }

    function setSourceVolume(v) {
        const val = Math.max(0, Math.min(1, v))
        if (source?.ready && source?.audio) {
            source.audio.volume = val
        } else {
            root._fallbackSourceVolume = val
            setVolFallbackProc.command = ["pactl", "set-source-volume", "@DEFAULT_SOURCE@", Math.round(val * 100) + "%"]
            setVolFallbackProc.running = true
        }
    }

    function toggleSourceMute() {
        if (source?.ready && source?.audio) {
            source.audio.muted = !source.audio.muted
        } else {
            root._fallbackSourceMuted = !root._fallbackSourceMuted
            setMuteFallbackProc.command = ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"]
            setMuteFallbackProc.running = true
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshDevices()
    }

    Component.onCompleted: refreshDevices()
}
