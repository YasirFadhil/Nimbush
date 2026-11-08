// DynamicIsland.qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../../../services" as Services
import "../../media" as MediaModule

Item {
    id: root

    // ----- Public API & State -----
    property bool pinned: false
    property bool autoExpanded: false
    property bool mediaCollapsedReady: false
    // Remembers the compact peek shape for its automatic close transition.
    property bool mediaWasPeek: false
    // One normalized timeline drives media-card content and artwork in both directions.
    // 0 = expanded media view, 1 = collapsed pill.
    property bool mediaTransitionActive: false

    // Flip to true to trace the media/peek state machine in the Quickshell log.
    property bool debugMedia: false
    function dbg(msg) { if (debugMedia) console.log("[island " + (Date.now() % 100000) + "] " + msg) }
    onAutoExpandedChanged: dbg("autoExpanded=" + autoExpanded + " ready=" + mediaCollapsedReady)
    onMediaCollapsedReadyChanged: dbg("mediaCollapsedReady=" + mediaCollapsedReady + " autoExpanded=" + autoExpanded)
    onMediaWasPeekChanged: dbg("mediaWasPeek=" + mediaWasPeek)
    onMediaTransitionActiveChanged: dbg("transitionActive=" + mediaTransitionActive + " progress=" + mediaTransitionProgress.toFixed(2) + " collapsing=" + mediaTransitionCollapsing)
    property real mediaTransitionProgress: 1.0
    // True when collapsing (progress goes 0→1), false when expanding (progress goes 1→0).
    property bool mediaTransitionCollapsing: true
    // Direction-aware handoff blend for collapsed elements (music icon, track text, cover thumbnail).
    // Collapsing → elements appear only in the last 20% so island has already shrunk.
    // Expanding  → elements disappear immediately in the first 15% so they never overlap
    //              the expanding full-view canvas.
    readonly property real mediaHandoffBlend: {
        if (mediaTransitionCollapsing) {
            // Smooth crossfade across 0.35 -> 0.85 of the collapse
            const t = Math.max(0.0, Math.min(1.0, (mediaTransitionProgress - 0.35) / 0.50))
            return t * t * (3.0 - 2.0 * t)
        } else {
            // Expanding: progress goes 1→0. Crossfade smoothly across 1.00 -> 0.65
            const t = Math.max(0.0, Math.min(1.0, (mediaTransitionProgress - 0.65) / 0.35))
            return t * t * (3.0 - 2.0 * t)
        }
    }
    // The artwork is ONE shared element in a collapsed <-> media morph: the card cover scales/moves
    // onto the pill thumbnail's exact slot (centre x 20, 16px), so it stays fully visible for the
    // whole flight and only hands over to the real thumbnail in the last 12% (where both are
    // pixel-identical). The old wide crossfade left two covers on screen at once mid-flight.
    readonly property real mediaCoverHandoff: {
        const t = Math.max(0.0, Math.min(1.0, (mediaTransitionProgress - 0.88) / 0.12))
        return t * t * (3.0 - 2.0 * t)
    }
    // ===================== Vector media icons (real morphing) =====================
    // Every control icon is exactly two quads (8 numbers each: x0,y0 .. x3,y3, relative to the icon
    // centre; order TL, TR, BR, BL). A triangle is a quad with two coincident corners. Because every
    // icon has the same vertex layout, ANY icon can morph into any other by interpolating vertices:
    // play <-> pause is a real shape change, and prev/next/pause turn into cava bars the same way.
    component QuadIcon: Shape {
        id: qi
        property var qa: [0, 0, 0, 0, 0, 0, 0, 0]
        property var qb: [0, 0, 0, 0, 0, 0, 0, 0]
        property color iconColor: "white"
        // Explicit size on purpose: a Shape overwrites its implicit size from its path bounds, which
        // let each icon settle into a slightly different box and sit off-centre.
        width: 24
        height: 24
        layer.enabled: true
        layer.samples: 4
        function pts(a) {
            const cx = width / 2
            const cy = height / 2
            return [Qt.point(cx + a[0], cy + a[1]), Qt.point(cx + a[2], cy + a[3]),
                    Qt.point(cx + a[4], cy + a[5]), Qt.point(cx + a[6], cy + a[7]),
                    Qt.point(cx + a[0], cy + a[1])]
        }
        ShapePath {
            fillColor: qi.iconColor
            strokeColor: "transparent"
            PathPolyline { path: qi.pts(qi.qa) }
        }
        ShapePath {
            fillColor: qi.iconColor
            strokeColor: "transparent"
            PathPolyline { path: qi.pts(qi.qb) }
        }
    }

    // Alarm clock, drawn from primitives (no icon-font dependency). Bells + feet + ring + hands.
    component AlarmIcon: Item {
        id: ai
        property color c: "white"
        property bool active: false
        width: 14
        height: 14
        onActiveChanged: if (active) wiggle.restart()
        SequentialAnimation {
            id: wiggle
            NumberAnimation { target: ai; property: "rotation"; to: -11; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: ai; property: "rotation"; to: 11; duration: 110; easing.type: Easing.InOutQuad }
            NumberAnimation { target: ai; property: "rotation"; to: -7; duration: 100; easing.type: Easing.InOutQuad }
            NumberAnimation { target: ai; property: "rotation"; to: 5; duration: 90; easing.type: Easing.InOutQuad }
            NumberAnimation { target: ai; property: "rotation"; to: 0; duration: 80; easing.type: Easing.OutQuad }
        }
        // bells
        Rectangle { x: 0.2; y: 0.6; width: 5; height: 2.4; radius: 1.2; rotation: -38; color: ai.c; antialiasing: true }
        Rectangle { x: 8.8; y: 0.6; width: 5; height: 2.4; radius: 1.2; rotation: 38; color: ai.c; antialiasing: true }
        // feet
        Rectangle { x: 2.3; y: 11.4; width: 1.4; height: 2.6; radius: 0.7; rotation: 32; color: ai.c; antialiasing: true }
        Rectangle { x: 10.3; y: 11.4; width: 1.4; height: 2.6; radius: 0.7; rotation: -32; color: ai.c; antialiasing: true }
        // face
        Rectangle {
            x: 1.5; y: 2.5; width: 11; height: 11; radius: 5.5
            color: "transparent"; border.color: ai.c; border.width: 1.5; antialiasing: true
        }
        // hands
        Rectangle { x: 6.35; y: 4.9; width: 1.3; height: 3.5; radius: 0.65; color: ai.c; antialiasing: true }
        Rectangle { x: 6.35; y: 7.4; width: 3.1; height: 1.3; radius: 0.65; color: ai.c; antialiasing: true }
    }

    // previous = skip-back: a bar + a left-pointing triangle (apex = TL/BL, base = TR/BR).
    // The old double-triangle read as rewind/fast-forward (which -10/+10 already cover) and looked lopsided.
    // next is the EXACT mirror of previous (generated, not hand-typed), so the pair is symmetric by construction.
    readonly property var icoPrevA: [-5.5, -6, -3.1, -6, -3.1, 6, -5.5, 6]
    readonly property var icoPrevB: [-2.4, 0, 5.5, -6, 5.5, 6, -2.4, 0]
    function mirrorQuad(q) { return [-q[2], q[3], -q[0], q[1], -q[6], q[7], -q[4], q[5]] }
    readonly property var icoNextA: mirrorQuad(icoPrevA)
    readonly property var icoNextB: mirrorQuad(icoPrevB)
    // pause: two bars.  play: trapezoid + triangle (same vertex order, so they morph into each other)
    readonly property var icoPauseA: [-5.5, -7, -1.5, -7, -1.5, 7, -5.5, 7]
    readonly property var icoPauseB: [1.5, -7, 5.5, -7, 5.5, 7, 1.5, 7]
    readonly property var icoPlayA: [-5.5, -7, -0.5, -3.5, -0.5, 3.5, -5.5, 7]
    readonly property var icoPlayB: [-0.5, -3.5, 5.5, 0, 5.5, 0, -0.5, 3.5]

    function mixQuad(a, b, k) {
        const r = []
        for (let i = 0; i < 8; i++) r.push(a[i] + (b[i] - a[i]) * k)
        return r
    }
    // 0 = play, 1 = pause. Animated, shared by the real button and the flight overlay.
    property real mediaPlayIconT: mediaPlaying ? 1.0 : 0.0
    Behavior on mediaPlayIconT { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    function playIconA(t) { return mixQuad(icoPlayA, icoPauseA, t) }
    function playIconB(t) { return mixQuad(icoPlayB, icoPauseB, t) }

    // ===================== Media control features =====================
    property bool mediaShowRemaining: false          // tap the right-hand time to flip total <-> remaining
    property bool mediaVolHudOpen: false             // scroll over the card (or tap the speaker) to open
    property bool mediaVolDragging: false
    property real mediaVolRestore: 0.5
    // Volume is the SYSTEM output volume. The MPRIS per-player Volume is ignored by many players
    // (browsers especially), so a slider on it looked alive but changed nothing.
    // Per-APP first: the card controls the PipeWire playback stream(s) of the player that is on screen
    // (found by matching the MPRIS player against pw-dump), so turning Spotify down leaves your other
    // audio alone. Only when no stream matches does it fall back to the master volume.
    property var mediaVolIds: []              // PipeWire node ids of the active player's playback streams
    property real mediaAppVol: -1             // 0..1, -1 = not resolved yet
    property bool mediaAppMuted: false
    readonly property bool mediaVolPerApp: mediaVolIds.length > 0 && mediaAppVol >= 0
    readonly property real mediaVolume: mediaVolPerApp
        ? Math.max(0.0, Math.min(1.0, mediaAppVol))
        : Math.max(0.0, Math.min(1.0, Services.Audio.volume || 0.0))
    readonly property bool mediaMuted: mediaVolPerApp ? mediaAppMuted : (Services.Audio.muted ?? false)
    property bool mediaVolSuppressHud: false     // mute toggled from the card must not pop the "Audio Muted" HUD over it
    property real mediaVolPending: -1

    function seekBy(delta) {
        const pl = root.activePlayer
        if (!pl || !(pl.canSeek ?? false)) return
        const len = pl.length ?? 0
        let pos = (pl.position ?? 0) + delta
        pos = Math.max(0, len > 0 ? Math.min(len - 0.5, pos) : pos)
        pl.position = pos
        pl.positionChanged()
    }
    function showMediaVolHud() {
        if (!root.mediaVolHudOpen) root.refreshMediaVolTargets()
        root.mediaVolHudOpen = true
        mediaVolHudTimer.restart()
    }
    function normStr(x) { return (x === undefined || x === null) ? "" : String(x).toLowerCase().trim() }
    // Names this MPRIS player might go by in PipeWire (identity, desktop entry, dbus name tail).
    function mediaPlayerKeys() {
        const pl = root.activePlayer
        if (!pl) return []
        const keys = []
        const add = (v) => {
            const n = root.normStr(v)
            if (n.length >= 3 && keys.indexOf(n) < 0) keys.push(n)
        }
        add(pl.identity)
        add(pl.desktopEntry)
        const m = String(pl.dbusName ?? "").match(/MediaPlayer2\.([^.]+)/)
        if (m) add(m[1])
        return keys
    }
    function refreshMediaVolTargets() {
        if (!root.activePlayer) { root.mediaVolIds = []; root.mediaAppVol = -1; return }
        if (!mediaPwDump.running) mediaPwDump.running = true
    }
    function onMediaPwDump(text) {
        let objs = []
        try { objs = JSON.parse(text) } catch (e) { root.mediaVolIds = []; root.mediaAppVol = -1; return }
        const keys = root.mediaPlayerKeys()
        const matches = []
        for (const o of objs) {
            if (o.type !== "PipeWire:Interface:Node") continue
            const pr = (o.info && o.info.props) ? o.info.props : null
            if (!pr || pr["media.class"] !== "Stream/Output/Audio") continue
            const cands = [pr["application.name"], pr["application.process.binary"], pr["application.id"],
                           pr["pipewire.access.portal.app_id"], pr["node.name"]]
                .map(root.normStr).filter(c => c.length >= 3)
            let hit = false
            for (const k of keys) {
                for (const c of cands) {
                    if (c.indexOf(k) >= 0 || k.indexOf(c) >= 0) { hit = true; break }
                }
                if (hit) break
            }
            if (hit) matches.push({ id: o.id, running: o.info.state === "running" })
        }
        const running = matches.filter(m => m.running)
        const use = running.length > 0 ? running : matches
        root.mediaVolIds = use.map(m => m.id)
        if (root.mediaVolIds.length > 0) {
            mediaVolGet.command = ["wpctl", "get-volume", String(root.mediaVolIds[0])]
            mediaVolGet.running = true
        } else {
            root.mediaAppVol = -1
        }
    }
    function onMediaVolGet(text) {
        const m = String(text).match(/Volume:\s*([0-9.]+)/)
        if (!m) { root.mediaAppVol = -1; return }
        root.mediaAppVol = parseFloat(m[1])
        root.mediaAppMuted = /MUTED/.test(text)
    }

    function setMediaVolume(v) {
        const vol = Math.max(0.0, Math.min(1.0, v))
        if (root.mediaVolPerApp) {
            root.mediaAppVol = vol                       // optimistic: the slider must not wait for wpctl
        } else {
            const node = Services.Audio.sink
            if (node && node.audio) node.audio.volume = vol
        }
        root.mediaVolPending = vol
        if (!mediaVolApplyTimer.running) mediaVolApplyTimer.start()
        root.showMediaVolHud()
    }
    function setMediaMuted(m) {
        if (root.mediaVolPerApp) {
            root.mediaAppMuted = m
            for (const id of root.mediaVolIds)
                Quickshell.execDetached(["wpctl", "set-mute", String(id), m ? "1" : "0"])
            return
        }
        root.mediaVolSuppressHud = true
        mediaVolSuppressTimer.restart()
        const node = Services.Audio.sink
        if (node && node.audio) node.audio.muted = m
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", m ? "1" : "0"])
    }
    function adjustMediaVolume(delta) { root.setMediaVolume(root.mediaVolume + delta) }
    function toggleMediaMute() {
        root.setMediaMuted(!root.mediaMuted)
        root.showMediaVolHud()
    }
    Process {
        id: mediaPwDump
        command: ["pw-dump"]
        stdout: StdioCollector { onStreamFinished: root.onMediaPwDump(text) }
    }
    Process {
        id: mediaVolGet
        stdout: StdioCollector { onStreamFinished: root.onMediaVolGet(text) }
    }
    onActivePlayerChanged: root.refreshMediaVolTargets()
    Timer {
        id: mediaVolApplyTimer
        interval: 60
        onTriggered: {
            if (root.mediaVolPending >= 0) {
                const v = root.mediaVolPending.toFixed(2)
                if (root.mediaVolPerApp) {
                    for (const id of root.mediaVolIds)
                        Quickshell.execDetached(["wpctl", "set-volume", String(id), v])
                } else {
                    Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v])
                }
                root.mediaVolPending = -1
            }
        }
    }
    Timer { id: mediaVolSuppressTimer; interval: 900; onTriggered: root.mediaVolSuppressHud = false }
    Timer {
        id: mediaVolHudTimer
        interval: 1500
        onTriggered: {
            if (root.mediaVolDragging) restart()
            else root.mediaVolHudOpen = false
        }
    }

    // ===================== Sleep timer =====================
    property int mediaSleepMinutes: 0       // selected preset (0 = off)
    property real mediaSleepEndMs: 0
    property int mediaSleepTick: 0
    readonly property int mediaSleepLeft: {
        mediaSleepTick
        return mediaSleepMinutes > 0 ? Math.max(1, Math.ceil((mediaSleepEndMs - Date.now()) / 60000)) : 0
    }
    function cycleMediaSleep() {
        const steps = [0, 15, 30, 60]
        const next = steps[(steps.indexOf(root.mediaSleepMinutes) + 1) % steps.length]
        root.mediaSleepMinutes = next
        root.mediaSleepEndMs = Date.now() + next * 60000
        root.mediaSleepTick++
    }
    Timer {
        id: mediaSleepTimer
        interval: 5000
        repeat: true
        running: root.mediaSleepMinutes > 0
        onTriggered: {
            if (Date.now() >= root.mediaSleepEndMs) {
                root.mediaSleepMinutes = 0
                root.activePlayer?.pause()
            }
            root.mediaSleepTick++
        }
    }

    // Tempo of the whole media morph (shell, cover/title flights, controls<->cava, satellite). Everything
    // that has to move together reads this one number. 440 felt slow, the old 380 InOutCubic felt jumpy.
    readonly property int mediaFlightMs: 340

    // Controls <-> cava morph (full card only; the peek has no control row).
    // mediaTransitionProgress is eased (InOutSine). This inverts that easing to recover plain linear
    // time t (0 = card controls, 1 = pill cava), so the morph runs on its own, evenly spread timeline.
    readonly property real mediaFlightT: {
        const q = Math.max(0.0, Math.min(1.0, mediaTransitionProgress))
        // progress = (1 - cos(pi t)) / 2  (InOutSine)  =>  t = acos(1 - 2 progress) / pi
        return Math.acos(1.0 - 2.0 * q) / Math.PI
    }
    readonly property bool mediaCtrlFlightActive: mediaFlightActive && !isMediaPeek && !mediaWasPeek
    // Real audio-driven cava: fully in by t=0.92, i.e. UNDER the overlay, which only then lets go.
    readonly property real mediaBarHandoff: {
        const x = Math.max(0.0, Math.min(1.0, (mediaFlightT - 0.86) / 0.06))
        return x * x * (3.0 - 2.0 * x)
    }
    // Real prev/play/next: fully in by t=0.05, under the overlay (which lets go over 0.05 -> 0).
    readonly property real mediaCtrlRealOpacity: {
        if (!mediaCtrlFlightActive) return 1.0
        const x = Math.max(0.0, Math.min(1.0, (0.09 - mediaFlightT) / 0.04))
        return x * x * (3.0 - 2.0 * x)
    }
    // Reveal curve for the expanded title/artist/controls block while expanding
    // (progress 1 -> 0). The island is still short during the first part of the morph,
    // and the media layer is vertically centered, so showing text early makes it pop
    // in clipped at the island's top edge. Hold it back until the shell is mostly open
    // (progress 0.60 -> 0.20), then fade + slide it in, matching the artwork's
    // left-to-right flight.
    readonly property real mediaTextReveal: {
        const t = Math.max(0.0, Math.min(1.0, (0.60 - mediaTransitionProgress) / 0.40))
        return t * t * (3.0 - 2.0 * t)
    }
    // ---- Shared title/artist flight (collapsed pill <-> expanded card) ----
    // While the media transition runs, one pair of labels (mediaTextFlight) travels
    // between the pill's single "Title • Artist" line and the card's title with the
    // artist underneath, so the text reads as one object changing shape. The real
    // labels on both sides stay hidden until the flight lands (within 3% of the end).
    property real mediaFlightStartRatio: 0.0
    readonly property bool mediaFlightEnabled: !!activePlayer && stableTrackTitle !== "" && stableTrackArtist !== ""
        && !notifActive && !isMediaPeek && !mediaWasPeek && !wallpaperMode && !dropWorkflowActive
    readonly property bool mediaFlightActive: mediaTransitionActive && mediaFlightEnabled
        && (mediaTransitionCollapsing ? mediaTransitionProgress < 0.97 : mediaTransitionProgress > 0.03)
    // The artwork shrinks its visual transform to 16px during the flight; its
    // RowLayout slot stays fixed to avoid relayout on every animation frame.
    // the collapsed horizontal offset is always 10px - 8px = 2px.
    property real mediaArtFlightX: 0.0
    property real mediaArtFlightY: 0.0
    property int activeNotifIndex: 0

    // Inline Reply Type Zone State
    property bool replyMode: false
    property string activeReplyActionId: ""

    // Wallpaper Studio State inside Dynamic Island
    property bool wallpaperMode: false
    property int wallpaperIndex: 0

    // Drop & Send Hub State inside Dynamic Island
    property bool dropSendMode: false
    property string dropHoverTarget: "" // "kde" | "local" | ""
    property var dropUrls: []
    property string dropPreviewUrl: ""
    property int dropFileCount: 0
    property string dropFileName: ""
    property bool dropStagedChoice: false
    // True when a KDE Connect transfer is genuinely in-flight or confirmed.
    readonly property bool isDropSending: Services.DeviceShare
        ? (Services.DeviceShare.transferBackend !== "localsend"
            && (Services.DeviceShare.transferState === "sending" || Services.DeviceShare.transferState === "success"))
        : false

    // True for the entire sharing workflow: chooser, LocalSend preparing/handoff, and real transfers.
    // Use this flag to keep the island expanded and to gate satellite/demand/timer logic.
    readonly property bool dropWorkflowActive: Services.DeviceShare
        ? (root.dropSendMode || Services.DeviceShare.transferState === "preparing"
            || Services.DeviceShare.transferState === "handoff"
            || Services.DeviceShare.transferState === "sending"
            || Services.DeviceShare.transferState === "success"
            || Services.DeviceShare.transferState === "error")
        : root.dropSendMode

    // LocalSend-specific: preparing or handed off but not a real tracked transfer
    readonly property bool isLocalSendHandoff: Services.DeviceShare
        ? (Services.DeviceShare.transferBackend === "localsend"
            && (Services.DeviceShare.transferState === "preparing"
                || Services.DeviceShare.transferState === "handoff"
                // Defensive fallback: older service revisions briefly called
                // these states "sending" / "success" even though no transfer was tracked.
                || Services.DeviceShare.transferState === "sending"
                || Services.DeviceShare.transferState === "success"))
        : false

    // Only the destination chooser is pointer-dismissable. A real transfer or
    // LocalSend handoff owns its feedback state and must not be interrupted.
    function dismissDropChooser() {
        if (!root.showDropChooser) return
        root.dropSendMode = false
        root.dropStagedChoice = false
        root.dropHoverTarget = ""
        root.dropUrls = []
        root.dropPreviewUrl = ""
        root.dropFileCount = 0
        root.dropFileName = ""
    }

    Timer {
        id: dropExitDebounceTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (root.showDropChooser && !dropHubHoverHandler.hovered) {
                root.dismissDropChooser()
            }
        }
    }

    Timer {
        id: dropStagedAutoCollapseTimer
        interval: 3500
        repeat: false
        onTriggered: {
            if (root.showDropChooser && root.dropStagedChoice && !dropHubHoverHandler.hovered) {
                root.dismissDropChooser()
            }
        }
    }

    Connections {
        target: Services.DeviceShare
        function onTransferStateChanged() {
            if (Services.DeviceShare && Services.DeviceShare.transferState === "idle") {
                root.dropSendMode = false
                root.dropStagedChoice = false
                root.dropUrls = []
                root.dropPreviewUrl = ""
            }
        }
    }

    function extractDropDetails(urls) {
        if (!urls || urls.length === 0) return
        root.dropUrls = urls
        root.dropFileCount = urls.length
        let path = urls[0].toString()
        if (path.startsWith("file://")) path = path.substring(7)
        try { path = decodeURIComponent(path) } catch (e) {}
        root.dropFileName = path.substring(path.lastIndexOf("/") + 1)

        let lower = path.toLowerCase()
        if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".webp") || lower.endsWith(".gif") || lower.endsWith(".svg") ||
            lower.endsWith(".ico") || lower.endsWith(".bmp")) {
            root.dropPreviewUrl = "file://" + path
        } else {
            root.dropPreviewUrl = ""
        }
    }

    function handleDropOnKde(urls) {
        extractDropDetails(urls)
        if (Services.DeviceShare) {
            Services.DeviceShare.sendKdeConnect(Services.DeviceShare.defaultDevice ? Services.DeviceShare.defaultDevice.id : "", urls)
        }
        root.dropHoverTarget = ""
        root.dropStagedChoice = false
    }

    function handleDropOnLocalSend(urls) {
        extractDropDetails(urls)
        if (Services.DeviceShare) {
            Services.DeviceShare.sendLocalSend(urls)
        }
        root.dropHoverTarget = ""
        root.dropStagedChoice = false
    }

    function handleDropGeneral(urls) {
        extractDropDetails(urls)
        root.dropStagedChoice = true
        root.dropHoverTarget = ""
        dropStagedAutoCollapseTimer.restart()
    }

    onWallpaperIndexChanged: {
        if (wallpaperMode && islandWallList) {
            islandWallList.positionViewAtIndex(wallpaperIndex, ListView.Contain)
        }
    }

    onWallpaperModeChanged: {
        if (wallpaperMode) {
            Qt.callLater(() => {
                if (islandWallList) {
                    islandWallList.forceActiveFocus()
                    islandWallList.positionViewAtIndex(wallpaperIndex, ListView.Contain)
                }
            })
        }
    }

    readonly property var wallpaperList: {
        const all = (Services.Wallpaper && Services.Wallpaper.allWallpapers) ? Services.Wallpaper.allWallpapers : []
        return all.concat([{ isAddAction: true }])
    }

    // Island visual dimensions for window masking
    readonly property bool isBottom: Services.Config ? (Services.Config.barPosition === "bottom") : false
    readonly property int islandWidth: island.width
    readonly property int islandHeight: island.height

    // Lockscreen compatibility
    property bool allowOnLockscreen: true
    readonly property bool lockBlocked: Boolean(Services.OverlayManager && (Services.OverlayManager.isLocked || Services.OverlayManager.isLockAbsorbing))
    property bool isUnlockHoldActive: false
    property bool isUnlockGlideActive: false
    readonly property bool isUnlockActive: false
    readonly property bool isUnlockDisplaying: false
    readonly property bool isUnlockSettleActive: false

    Binding {
        target: Services.OverlayManager
        property: "desktopIslandIsWide"
        value: (island.width > 150) || root.expanded || root.mediaPlaying || root.notifActive
        when: Services.OverlayManager !== null
    }

    // Notification model shortcuts
    readonly property var popupList: Services.Notifications.popupList
    readonly property int notifCount: popupList ? popupList.count : 0
    readonly property bool notifActive: !(Services.Workspaces && Services.Workspaces.isFullscreen) && (notifCount > 0)
    property int previousNotifCount: 0
    // Briefly hold a new notification so the privacy dot can begin its
    // satellite handoff before the notification takes over the main island.
    property bool privacyNotifHandoffPending: false

    // System HUD Alert State (Mute, DnD, Charging, Camera)
    property bool sysHudActive: false
    property string sysHudIcon: ""
    property string sysHudTitle: ""
    property string sysHudDetail: ""
    property color sysHudColor: Services.Theme.accent
    property bool hudReady: false
    property var lastAudioSink: null
    property bool lastAudioMuted: false

    // Camera and screen-recording activity state.
    property bool cameraActive: false
    property bool recordingActive: false
    readonly property color recordingColor: "#ff5b36"

    // CapsLock Active State & Monitoring
    property bool capsLockActive: false

    // ── Smart Chronological 3-Dynamic System (Utama: Tengah, Sebelum: Kanan, Sebelumnya Lagi: Kiri) ──
    property double mediaActiveTime: 0
    property double sysHudActiveTime: 0
    property double cameraActiveTime: 0
    property double recordingActiveTime: 0
    property double capsLockActiveTime: 0
    property string manualCenterId: ""

    // Fluid Dynamic Island reactive impulses for water splitting animation
    property real rightIslandBulge: 0.0
    property real leftIslandBulge: 0.0

    // All candidates gathered and sorted strictly newest to oldest
    readonly property var allSortedCandidates: {
        const list = []

        // Modal overrides: add dropsend/wallpaper as the center candidate but
        // continue building the rest of the list so that camera and recording
        // can still reach a satellite slot while a modal panel is shown.
        if (root.dropWorkflowActive) {
            list.push({ id: "dropsend", type: "dropsend", time: 9999999999999 })
        } else if (root.wallpaperMode) {
            list.push({ id: "wallpaper", type: "wallpaper", time: 9999999999999 })
        }

        // In modal modes only allow privacy candidates (camera/recording) into
        // the satellite, not notifications, media, or system HUD that could
        // produce unintended extra satellites while the panel is open.
        const modalActive = root.dropWorkflowActive || root.wallpaperMode

        // 1. SysHUD (volume, brightness, mute, etc.) — only when not in a modal
        if (root.sysHudActive && !modalActive) {
            list.push({
                id: "syshud",
                type: "syshud",
                icon: root.sysHudIcon,
                title: root.sysHudTitle,
                color: root.sysHudColor,
                time: root.sysHudActiveTime || Date.now()
            })
        }

        // 2. Notifications — only when not in a modal
        // Modal panels retain the center slot, while incoming notifications
        // are immediately eligible for a satellite slot instead of being hidden.
        // Outside modal modes, preserve the short privacy-dot handoff delay.
        if (root.notifActive && root.popupList && (modalActive || !root.privacyNotifHandoffPending)) {
            for (let i = 0; i < root.popupList.count; i++) {
                const n = root.popupList.get(i)
                if (n) {
                    const t = (n.time || Date.now()) - (i * 10)
                    list.push({
                        id: "notif_" + (n.notifId !== undefined ? n.notifId : i),
                        type: "notif",
                        index: i,
                        notif: n,
                        time: t
                    })
                }
            }
        }

        // 3. Media playback — only when not in a modal
        if (!modalActive && ((root.mediaPlaying && !root.mediaStopping) || (root.mediaStopping && !root.mediaIconTransformed))) {
            if (!Services.OverlayManager.isLocked) {
                list.push({
                    id: "media",
                    type: "media",
                    time: root.mediaActiveTime || 1
                })
            }
        }

        // 4. Camera privacy activity — always included, satellite during modals
        if (root.cameraActive) {
            list.push({
                id: "camera",
                type: "camera",
                time: root.cameraActiveTime || 0
            })
        }

        // 5. Screen recording — always included, satellite during modals
        if (root.recordingActive) {
            list.push({
                id: "recording",
                type: "recording",
                time: root.recordingActiveTime || 0
            })
        }

        // 6. CapsLock active — only when not in a modal
        if (root.capsLockActive && !modalActive) {
            list.push({
                id: "capslock",
                type: "capslock",
                time: root.capsLockActiveTime || 0
            })
        }

        // Sort candidates strictly newest to oldest (highest time first)
        list.sort((a, b) => (b.time || 0) - (a.time || 0))
        return list
    }

    // Allocate into 3 slots with optional manual swap support
    readonly property var slotDistribution: {
        const candidates = root.allSortedCandidates
        if (!candidates || candidates.length === 0) {
            return { center: { type: "idle" }, right: null, left: null }
        }

        // Privacy indicators use the main island while it is otherwise idle.
        // If another activity owns the main island, move privacy activity to
        // satellites so it stays visible without competing with that content.
        const centerEligible = []
        const satelliteOnly = []
        const privacyCandidates = []
        for (let i = 0; i < candidates.length; i++) {
            const c = candidates[i]
            if (c.type === "capslock") {
                satelliteOnly.push(c)
            } else if (c.type === "camera" || c.type === "recording") {
                privacyCandidates.push(c)
            } else {
                centerEligible.push(c)
            }
        }

        // With no primary content, cameraIndicator renders privacy dots inside
        // the island. Otherwise, reserve satellite slots for them.
        if (centerEligible.length > 0 || root.privacyNotifHandoffPending) {
            for (let i = 0; i < privacyCandidates.length; i++) {
                satelliteOnly.push(privacyCandidates[i])
            }
        }

        let centerItem = { type: "idle" }
        const remaining = []

        if (centerEligible.length > 0) {
            let centerIdx = 0
            const modalOwnsCenter = root.dropWorkflowActive || root.wallpaperMode
            if (!modalOwnsCenter && root.manualCenterId !== "") {
                const foundIdx = centerEligible.findIndex(c => c.id === root.manualCenterId)
                if (foundIdx !== -1) {
                    centerIdx = foundIdx
                }
            }
            centerItem = centerEligible[centerIdx]
            for (let i = 0; i < centerEligible.length; i++) {
                if (i !== centerIdx) remaining.push(centerEligible[i])
            }
        }

        // CapsLock always remains detached. Privacy candidates arrive here
        // only while another activity occupies the main island.
        for (let j = 0; j < satelliteOnly.length; j++) {
            remaining.push(satelliteOnly[j])
        }

        // Privacy indicators have priority: camera/recording must not be
        // displaced by an older media or CapsLock satellite.
        remaining.sort((a, b) => {
            const aPrivacy = (a.type === "camera" || a.type === "recording") ? 1 : 0
            const bPrivacy = (b.type === "camera" || b.type === "recording") ? 1 : 0
            if (aPrivacy !== bPrivacy) return bPrivacy - aPrivacy
            return (b.time || 0) - (a.time || 0)
        })

        // "sebelum baru ke kanan"
        const rightItem = remaining.length > 0 ? remaining[0] : null
        // "dan sebelumnya lagi ke kiri gitu"
        const leftItem = remaining.length > 1 ? remaining[1] : null

        return { center: centerItem, right: rightItem, left: leftItem }
    }

    readonly property var slotCenterItem: slotDistribution.center
    readonly property var slotRightItem: slotDistribution.right
    readonly property var slotLeftItem: slotDistribution.left

    readonly property string slot0Activity: slotCenterItem ? slotCenterItem.type : "idle"
    readonly property string slotRightType: slotRightItem ? slotRightItem.type : ""
    readonly property string slotLeftType: slotLeftItem ? slotLeftItem.type : ""

    readonly property bool isMediaSatellite: (slotRightType === "media" || slotLeftType === "media")
    readonly property bool isCameraSatellite: (slotRightType === "camera" || slotLeftType === "camera")
    readonly property bool isRecordingSatellite: (slotRightType === "recording" || slotLeftType === "recording")
    readonly property bool isCapsLockSatellite: (slotRightType === "capslock" || slotLeftType === "capslock")

    // A notification takes over the island: cancel any in-flight auto peek so it
    // doesn't resurface once the notification goes away. Peek only belongs to
    // track changes / playback start, so it is simply dropped. `pinned` is a
    // deliberate user action and stays untouched.
    onNotifActiveChanged: {
        if (!notifActive) return
        autoCollapseTimer.stop()
        autoExpanded = false
        mediaWasPeek = false
    }

    onNotifCountChanged: {
        const firstNotification = notifCount > 0 && previousNotifCount === 0
        const privacyWasAlone = !sysHudActive && !mediaPlaying && !mediaStopping &&
            !wallpaperMode && !dropWorkflowActive
        if (firstNotification && privacyWasAlone && (cameraActive || recordingActive)) {
            privacyNotifHandoffPending = true
            privacyNotifHandoffTimer.restart()
        }
        previousNotifCount = notifCount
    }

    readonly property int leftExtraWidth: (slotLeftType !== "") ? 40 : 0
    readonly property int rightExtraWidth: (slotRightType !== "") ? 40 : 0
    readonly property int satelliteExtraWidth: Math.max(leftExtraWidth, rightExtraWidth) * 2

    function resolveNotifIcon(n) {
        if (!n) return ""
        let src = n.appIcon || n.image || ""
        const appName = (n.appName || "").toLowerCase()
        const summary = (n.summary || "").toLowerCase()
        if (!src || src === "kdeconnect" || src.includes("kdeconnect")) {
            if (appName.includes("whatsapp") || summary.includes("whatsapp")) src = "whatsapp"
            else if (appName.includes("telegram") || summary.includes("telegram")) src = "telegram"
            else if (appName.includes("discord") || summary.includes("discord")) src = "discord"
            else if (appName.includes("signal") || summary.includes("signal")) src = "signal"
            else if (appName.includes("slack") || summary.includes("slack")) src = "slack"
            else if (appName.includes("instagram") || summary.includes("instagram")) src = "instagram"
            else if (appName.includes("tiktok") || summary.includes("tiktok")) src = "tiktok"
            else if (appName.includes("messages") || appName.includes("sms")) src = "message"
        }
        if (!src) src = n.image || ""
        if (!src) return ""
        if (src.startsWith("file://") || src.startsWith("http://") || src.startsWith("https://"))
            return src
        if (src.startsWith("/"))
            return "file://" + src
        if (Services.SystemTheme) {
            const res = Services.SystemTheme.getIcon(src)
            if (res && res.length > 0) return res
        }
        const qp = Quickshell.iconPath(src, true)
        return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
    }

    function handleSatelliteClick(item) {
        if (!item) return
        if (item.type === "notif") {
            if (root.dropWorkflowActive || root.wallpaperMode) return
            root.manualCenterId = item.id
            notifTimer.restart()
        } else if (item.type === "media") {
            root.manualCenterId = "media"
        } else if (item.type === "camera") {
            root.showSysHud("󰄀", "Camera Active", "Webcam in use", Services.Theme.success)
        } else if (item.type === "recording") {
            root.showSysHud("●", "Screen Recording", "Screen capture is active", root.recordingColor)
        } else if (item.type === "capslock") {
            // Persistent indicator - no HUD popup
        } else if (item.type === "transfer") {
            root.dropSendMode = true
        } else if (item.type === "syshud") {
            root.manualCenterId = "syshud"
        }
    }

    function selectNotifIndex(idx) {
        if (idx >= 0 && idx < root.notifCount && root.popupList) {
            const n = root.popupList.get(idx)
            if (n) {
                root.manualCenterId = "notif_" + (n.notifId !== undefined ? n.notifId : idx)
                notifTimer.restart()
            }
        }
    }

    function swapNotifications() {
        if (slotRightItem) {
            root.handleSatelliteClick(slotRightItem)
        } else if (slotLeftItem) {
            root.handleSatelliteClick(slotLeftItem)
        }
    }

    // NetworkManager / Wi-Fi State Monitoring
    property bool wifiLastConnected: false
    property string wifiLastSsid: ""

    // Bluetooth Devices State Monitoring
    property var btConnectedDevices: ({})
    property bool btInitialized: false

    // Initial baseline state guards to prevent false HUD triggers on reload/startup
    property bool lastChargingState: false
    property bool lastSaverEnabled: false
    property string lastPowerProfile: ""
    property string lastWallpaperPath: ""
    property bool lastDnd: false

    // Media Stop & Motion Animation Choreography
    property bool isNextTrack: true
    property bool mediaStopping: false
    property bool mediaTextCollapsed: false
    property bool mediaIconTransformed: false

    Timer {
        id: mediaStopPhase1Timer
        interval: 200
        repeat: false
        onTriggered: {
            root.mediaTextCollapsed = true
            mediaStopPhase2Timer.restart()
        }
    }

    Timer {
        id: mediaStopPhase2Timer
        interval: 380
        repeat: false
        onTriggered: {
            root.mediaIconTransformed = true
            root.mediaStopping = false
            root.mediaCollapsedReady = false
        }
    }

    Timer {
        id: postUnlockMediaTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (root.mediaPlaying && !root.autoExpanded && !root.expanded && !Services.OverlayManager.isLocked) {
                root.mediaCollapsedReady = true
            }
        }
    }

    function triggerLockAbsorption() {
        // Only run the media-stopping choreography if media is actually playing;
        // otherwise the music note icon would show up during lock with no media.
        const wasPlaying = root.mediaPlaying
        globalMediaMarqueeAnim.stop()
        mediaStopPhase1Timer.stop()
        mediaStopPhase2Timer.stop()
        root.mediaStopping = wasPlaying
        root.mediaTextCollapsed = true
        root.mediaIconTransformed = true
        root.autoExpanded = false
        root.pinned = false
    }

    function triggerMediaStop() {
        globalMediaMarqueeAnim.stop()
        root.mediaStopping = true
        root.mediaTextCollapsed = false
        root.mediaIconTransformed = false
        mediaStopPhase1Timer.restart()
    }

    Timer {
        id: cameraPollTimer
        interval: 1800
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cameraProc.running) cameraProc.running = true
        }
    }

    Process {
        id: cameraProc
        // Camera use and screen recording deliberately use separate evidence.
        // A PipeWire screen node can also mean a video call or a screen share;
        // it is not, by itself, a recording.
        command: [
            "python3", "-c",
            "import glob\n" +
            "import json\n" +
            "import os\n" +
            "import re\n" +
            "import shutil\n" +
            "import stat\n" +
            "import subprocess\n" +
            "\n" +
            "result = {'camera': False, 'recording': False, 'reasons': [], 'camera_fd_users': [], 'obs_output_files': [], 'active_video_nodes': [], 'pw_dump_path': '', 'pw_dump_ok': False, 'pw_dump_error': ''}\n" +
            "\n" +
            "def is_recorder_process(comm, cmdline):\n" +
            "    comm = (comm or '').strip().lower()\n" +
            "    clean_comm = comm.lstrip('.').removesuffix('-wrapped')\n" +
            "    cmdline = (cmdline or '').lower()\n" +
            "    names = ('obs', 'obs-studio', 'obs-studio-bin', 'wf-recorder', 'wl-screenrec', 'gpu-screen-recorder', 'kooha', 'peek', 'kazam', 'vokoscreen', 'vokoscreenng', 'simplescreenrecorder', 'blue-recorder', 'green-recorder', 'recordmydesktop')\n" +
            "    if clean_comm in names or any(n == clean_comm or n in comm for n in names) or 'com.obsproject.studio' in cmdline:\n" +
            "        return True\n" +
            "    if any(f'/{n}' in cmdline or f' {n}' in cmdline or cmdline.endswith(n) for n in names):\n" +
            "        return True\n" +
            "    return clean_comm == 'ffmpeg' and any(h in cmdline for h in ('x11grab', 'pipewire', 'kmsgrab', 'wayland'))\n" +
            "\n" +
            "def process_snapshot():\n" +
            "    \"\"\"Find direct V4L2 clients and writable output from known recorders.\"\"\"\n" +
            "    camera_users = []\n" +
            "    recording_files = []\n" +
            "    ignored_video_fd_owners = {\n" +
            "        'pipewire', 'wireplumber', 'systemd', 'systemd-udevd', 'udevd',\n" +
            "        'xdg-desktop-portal', 'xdg-desktop-portal-wlr', 'xdg-desktop-portal-gtk',\n" +
            "        'pipewire-media-session'\n" +
            "    }\n" +
            "    video_file_exts = ('.mkv', '.mp4', '.mov', '.flv', '.ts', '.avi', '.webm', '.m4v', '.mpeg', '.mpg')\n" +
            "    try:\n" +
            "        proc_entries = os.listdir('/proc')\n" +
            "    except Exception:\n" +
            "        return camera_users, recording_files\n" +
            "    own_uid = os.getuid()\n" +
            "    for pid in proc_entries:\n" +
            "        if not pid.isdigit():\n" +
            "            continue\n" +
            "        proc_dir = '/proc/' + pid\n" +
            "        try:\n" +
            "            if os.stat(proc_dir).st_uid != own_uid:\n" +
            "                continue\n" +
            "            with open(proc_dir + '/comm', 'r', errors='ignore') as f:\n" +
            "                comm = f.read().strip()\n" +
            "            try:\n" +
            "                with open(proc_dir + '/cmdline', 'rb') as f:\n" +
            "                    cmdline = f.read().replace(b'\\x00', b' ').decode('utf-8', errors='ignore')\n" +
            "            except Exception:\n" +
            "                cmdline = ''\n" +
            "        except Exception:\n" +
            "            continue\n" +
            "\n" +
            "        is_recorder = is_recorder_process(comm, cmdline)\n" +
            "        comm_lower = comm.lower()\n" +
            "        if comm_lower in ignored_video_fd_owners and not is_recorder:\n" +
            "            continue\n" +
            "\n" +
            "        fd_dir = proc_dir + '/fd'\n" +
            "        try:\n" +
            "            fds = os.listdir(fd_dir)\n" +
            "        except Exception:\n" +
            "            continue\n" +
            "        for fd in fds:\n" +
            "            fd_path = fd_dir + '/' + fd\n" +
            "            try:\n" +
            "                target = os.readlink(fd_path)\n" +
            "            except Exception:\n" +
            "                continue\n" +
            "            target_plain = target.removesuffix(' (deleted)')\n" +
            "            if re.fullmatch(r'/dev/video[0-9]+', target_plain) and comm_lower not in ignored_video_fd_owners:\n" +
            "                camera_users.append({'pid': int(pid), 'comm': comm[:80], 'device': target_plain})\n" +
            "            if not is_recorder:\n" +
            "                continue\n" +
            "            ext = os.path.splitext(target_plain)[1].lower()\n" +
            "            if ext not in video_file_exts:\n" +
            "                continue\n" +
            "            try:\n" +
            "                fd_stat = os.stat(fd_path)\n" +
            "                if not stat.S_ISREG(fd_stat.st_mode):\n" +
            "                    continue\n" +
            "                flags = None\n" +
            "                with open(proc_dir + '/fdinfo/' + fd, 'r', errors='ignore') as f:\n" +
            "                    for line in f:\n" +
            "                        if line.startswith('flags:'):\n" +
            "                            flags = int(line.split(':', 1)[1].strip(), 8)\n" +
            "                            break\n" +
            "                if flags is not None and (flags & os.O_ACCMODE) == os.O_RDONLY:\n" +
            "                    continue\n" +
            "                recording_files.append({'pid': int(pid), 'file': target_plain})\n" +
            "            except Exception:\n" +
            "                continue\n" +
            "    return camera_users, recording_files\n" +
            "\n" +
            "camera_fd_users, obs_output_files = process_snapshot()\n" +
            "result['camera_fd_users'] = camera_fd_users\n" +
            "result['obs_output_files'] = obs_output_files\n" +
            "if camera_fd_users:\n" +
            "    result['camera'] = True\n" +
            "    result['reasons'].append('active_v4l2_fd')\n" +
            "if obs_output_files:\n" +
            "    result['recording'] = True\n" +
            "    result['reasons'].append('recorder_output_file_open')\n" +
            "\n" +
            "# PipeWire covers portal-based capture and devices consumed by PipeWire clients.\n" +
            "pw_dump = shutil.which('pw-dump')\n" +
            "if not pw_dump:\n" +
            "    for candidate in ('/run/current-system/sw/bin/pw-dump', '/usr/bin/pw-dump'):\n" +
            "        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):\n" +
            "            pw_dump = candidate\n" +
            "            break\n" +
            "if pw_dump:\n" +
            "    result['pw_dump_path'] = pw_dump\n" +
            "    try:\n" +
            "        raw = subprocess.check_output([pw_dump], stderr=subprocess.DEVNULL, timeout=2)\n" +
            "        objects = json.loads(raw.decode('utf-8', errors='replace'))\n" +
            "        result['pw_dump_ok'] = True\n" +
            "        clients = {}\n" +
            "        for obj in objects:\n" +
            "            if obj.get('type') == 'PipeWire:Interface:Client':\n" +
            "                cid = obj.get('id')\n" +
            "                cprops = (obj.get('info') or {}).get('props') or obj.get('props') or {}\n" +
            "                if cid is not None:\n" +
            "                    clients[cid] = cprops\n" +
            "        screen_hints = (\n" +
            "            'screen capture', 'screen-capture', 'screencast', 'screen cast',\n" +
            "            'desktop capture', 'desktop-capture', 'window capture', 'window-capture',\n" +
            "            'monitor capture', 'monitor-capture', 'display capture', 'display-capture',\n" +
            "            'pipewire-screen-capture', 'portal.screen', 'screen recording', 'screen-recording'\n" +
            "        )\n" +
            "        camera_hints = ('camera', 'webcam', 'web cam', 'v4l2', 'uvc', 'video4linux', 'integrated camera')\n" +
            "        known_browser_hints = ('firefox', 'chromium', 'chrome', 'helium', 'brave', 'vivaldi', 'zen-browser')\n" +
            "        recorder_hints = ('obs', 'wf-recorder', 'wl-screenrec', 'gpu-screen-recorder', 'kooha', 'peek', 'kazam', 'vokoscreen', 'simplescreenrecorder', 'blue-recorder', 'green-recorder', 'recordmydesktop', 'ffmpeg')\n" +
            "        for obj in objects:\n" +
            "            if obj.get('type') != 'PipeWire:Interface:Node':\n" +
            "                continue\n" +
            "            info = obj.get('info') or {}\n" +
            "            props = info.get('props') or obj.get('props') or {}\n" +
            "            state = str(info.get('state', '')).lower()\n" +
            "            if state != 'running':\n" +
            "                continue\n" +
            "            media_class = str(props.get('media.class', '')).lower()\n" +
            "            role = str(props.get('media.role', '')).lower()\n" +
            "            client_id = props.get('client.id')\n" +
            "            cprops = clients.get(client_id, {})\n" +
            "            detail_keys = (\n" +
            "                'node.name', 'node.description', 'node.nick', 'media.name', 'media.title',\n" +
            "                'media.comment', 'media.category', 'media.role', 'media.filename',\n" +
            "                'device.description', 'device.product.name', 'device.nick', 'api.v4l2.path'\n" +
            "            )\n" +
            "            details = ' '.join(str(props.get(k, '')) for k in detail_keys).lower()\n" +
            "            app_keys = (\n" +
            "                'application.name', 'application.id', 'application.process.binary',\n" +
            "                'portal.app_id', 'pipewire.access.portal.app_id', 'stream.name'\n" +
            "            )\n" +
            "            app_identity = ' '.join(str(props.get(k, '') or cprops.get(k, '')) for k in app_keys).lower()\n" +
            "            all_text = details + ' ' + app_identity\n" +
            "            is_video_related = ('video' in media_class) or ('video' in role)\n" +
            "            if is_video_related:\n" +
            "                result['active_video_nodes'].append({\n" +
            "                    'state': state, 'class': media_class, 'role': role,\n" +
            "                    'node': str(props.get('node.name', '') or props.get('node.description', ''))[:120],\n" +
            "                    'app': str(props.get('application.name', '') or cprops.get('application.name', '') or props.get('application.process.binary', ''))[:120]\n" +
            "                })\n" +
            "            is_screen = role in ('screen', 'screencast', 'screen-capture') or any(h in all_text for h in screen_hints)\n" +
            "            is_obs = 'obs' in app_identity or 'obs' in all_text or 'com.obsproject.studio' in app_identity\n" +
            "            is_recorder = any(h in all_text or h in app_identity for h in recorder_hints)\n" +
            "            is_stream_input = media_class.startswith('stream/input/video')\n" +
            "            is_camera_source = media_class.startswith(('video/source', 'device/video'))\n" +
            "            has_camera_hint = role == 'camera' or any(h in all_text for h in camera_hints)\n" +
            "            if is_video_related and is_screen:\n" +
            "                # A portal/meeting screen stream is sharing, not evidence of recording.\n" +
            "                # A known recorder with an active PipeWire screen stream is\n" +
            "                # recording even when it writes through a temporary/nameless FD.\n" +
            "                if is_recorder:\n" +
            "                    result['recording'] = True\n" +
            "                    if 'known_recorder_pipewire_screen' not in result['reasons']:\n" +
            "                        result['reasons'].append('known_recorder_pipewire_screen')\n" +
            "                continue\n" +
            "            if is_camera_source and has_camera_hint and not is_screen:\n" +
            "                result['camera'] = True\n" +
            "                if 'identified_pipewire_camera_source' not in result['reasons']:\n" +
            "                    result['reasons'].append('identified_pipewire_camera_source')\n" +
            "            elif is_stream_input:\n" +
            "                if has_camera_hint:\n" +
            "                    result['camera'] = True\n" +
            "                    if 'camera_metadata' not in result['reasons']:\n" +
            "                        result['reasons'].append('camera_metadata')\n" +
            "                elif is_recorder:\n" +
            "                    # A recorder preview/input is not proof that it is recording.\n" +
            "                    # Its writable output file is checked independently above.\n" +
            "                    pass\n" +
            "                elif any(h in app_identity for h in known_browser_hints):\n" +
            "                    # Browser webcam tests often expose no camera name on the client stream;\n" +
            "                    # direct /dev/video access is checked independently above as well.\n" +
            "                    result['camera'] = True\n" +
            "                    if 'browser_video_input' not in result['reasons']:\n" +
            "                        result['reasons'].append('browser_video_input')\n" +
            "    except Exception as e:\n" +
            "        # Keep process-FD detections even if PipeWire's dump is unavailable.\n" +
            "        result['pw_dump_error'] = type(e).__name__ + ': ' + str(e)[:180]\n" +
            "\n" +
            "print(json.dumps(result))\n"
        ]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const status = JSON.parse(data.trim())
                    const hasCamera = status.camera === true
                    const isRecording = status.recording === true
                    if (root.cameraActive !== hasCamera) root.cameraActive = hasCamera
                    if (root.recordingActive !== isRecording) root.recordingActive = isRecording
                } catch (e) {
                    // Keep the last valid state if a partial process output arrives.
                }
            }
        }
    }
    Timer {
        id: capsLockPollTimer
        interval: 1200
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!capsLockProc.running) capsLockProc.running = true
        }
    }

    Process {
        id: capsLockProc
        command: ["sh", "-c", "grep -qh 1 /sys/class/leds/*capslock*/brightness 2>/dev/null && echo 1 || echo 0"]
        stdout: SplitParser {
            onRead: data => {
                const isActive = data.trim() === "1"
                if (root.capsLockActive !== isActive) {
                    root.capsLockActive = isActive
                }
            }
        }
    }

    // ── USB Plug/Unplug Sound Feedback ───────────────────────────────────────
    // Monitor udev USB events and play freedesktop device-added/removed sounds.
    // Filter to UDEV (processed) events only on usb_device (not hub ports).
    property bool usbSoundReady: false
    property string lastUsbAction: ""
    Timer {
        id: usbSoundThrottle
        interval: 800   // debounce — USB enumeration fires many events at once
        repeat: false
        onTriggered: {
            if (root.lastUsbAction === "add")
                Services.SoundFeedback.playDeviceAdded()
            else if (root.lastUsbAction === "remove")
                Services.SoundFeedback.playDeviceRemoved()
            root.lastUsbAction = ""
        }
    }

    Process {
        id: usbMonitorProc
        // udevadm --property emits blocks like:
        //   UDEV  [...]
        //   ACTION=add
        //   DEVTYPE=usb_device
        // We grab ACTION= lines and DEVTYPE= lines, filter only usb_device actions.
        command: ["sh", "-c",
            "udevadm monitor --udev --subsystem-match=usb --property 2>/dev/null" +
            " | stdbuf -oL awk '/^ACTION=/{act=$0} /^DEVTYPE=usb_device/{print act}'" +
            " | stdbuf -oL sed 's/ACTION=//'"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (!root.hudReady) return
                const action = data.trim()
                if (action === "add" || action === "remove") {
                    root.lastUsbAction = action
                    usbSoundThrottle.restart()
                }
            }
        }
    }

    onCameraActiveChanged: {
        if (cameraActive) cameraActiveTime = Date.now()
    }

    onRecordingActiveChanged: {
        if (recordingActive) recordingActiveTime = Date.now()
    }

    onCapsLockActiveChanged: {
        if (capsLockActive) capsLockActiveTime = Date.now()
    }

    function showSysHud(icon, title, detail, iconColor, customDuration) {
        if (root.wallpaperMode) return
        sysHudIcon = icon
        sysHudTitle = title
        sysHudDetail = detail || ""
        sysHudColor = iconColor || Services.Theme.accent
        sysHudActiveTime = Date.now()
        sysHudActive = true
        sysHudTimer.interval = customDuration || 2200
        sysHudTimer.restart()
    }

    Timer {
        id: sysHudTimer
        interval: 2200
        onTriggered: root.sysHudActive = false
    }

    Timer {
        id: hudInitTimer
        interval: 2200
        running: true
        repeat: false
        onTriggered: {
            root.hudReady = true
            if (root.mediaPlaying && !root.autoExpanded) {
                root.mediaCollapsedReady = true
            }
            welcomeProc.running = true
        }
    }

    Process {
        id: welcomeProc
        command: ["sh", "-c", "marker=\"/tmp/qs-welcomed-${USER}\"; if [ ! -f \"$marker\" ]; then touch \"$marker\"; whoami || echo $USER; fi"]
        stdout: SplitParser {
            onRead: data => {
                const rawUser = data.trim()
                if (rawUser.length === 0) return
                const user = rawUser.charAt(0).toUpperCase() + rawUser.slice(1)
                const icon = Services.OsInfo.logoGlyph || "󰀉"
                root.showSysHud(icon, "Welcome back!", "Logged in as " + user, Services.Theme.accent, 3500)
            }
        }
    }

    Component.onCompleted: {
        root.syncMediaMetadataNow()
        root.lastAudioSink = Services.Audio.sink
        if (Services.Audio.sink) {
            root.lastAudioMuted = Services.Audio.muted
        }
        if (Services.Power) {
            root.lastChargingState = Services.Power.charging
        }
        if (Services.PowerProfile) {
            root.lastSaverEnabled = Services.PowerProfile.saverEnabled
            root.lastPowerProfile = Services.PowerProfile.profile || "balanced"
        }
        if (Services.Wallpaper) {
            root.lastWallpaperPath = Services.Wallpaper.currentWallpaper || ""
        }
        if (Services.Notifications) {
            root.lastDnd = Services.Notifications.doNotDisturb
        }
        if (Services.Wifi) {
            root.wifiLastConnected = Services.Wifi.connected
            root.wifiLastSsid = Services.Wifi.ssid
        }
        if (root.mediaPlaying) {
            root.mediaCollapsedReady = true
        }
    }

    // Connections for System Events
    Connections {
        target: Services.Audio
        function onMutedChanged() {
            if (root.mediaVolSuppressHud) {
                root.lastAudioMuted = Services.Audio.muted
                return
            }
            if (!Services.Audio.sink) return

            const currentSink = Services.Audio.sink
            // If sink changed (e.g. bluetooth disconnect/connect), update sink ref and ignore fake mute notification
            if (root.lastAudioSink !== currentSink) {
                root.lastAudioSink = currentSink
                root.lastAudioMuted = Services.Audio.muted
                return
            }

            const isMuted = Services.Audio.muted
            if (!root.hudReady) {
                root.lastAudioMuted = isMuted
                return
            }
            if (root.lastAudioMuted === isMuted) return
            root.lastAudioMuted = isMuted

            const vol = Services.Audio.volume || 0
            const icon = Services.Icons.volumeIcon(vol, isMuted, Services.Audio.isHeadphone, Services.Audio.isTws)
            const title = isMuted ? "Audio Muted" : "Audio Unmuted"
            const detail = Math.round(vol * 100) + "%"
            root.showSysHud(icon, title, detail, isMuted ? Services.Theme.danger : Services.Theme.success)
        }

        function onSinkChanged() {
            if (root.lastAudioSink !== Services.Audio.sink) {
                root.lastAudioSink = Services.Audio.sink
                if (Services.Audio.sink) {
                    root.lastAudioMuted = Services.Audio.muted
                }
            }
        }
    }

    Connections {
        target: Services.Notifications
        function onDoNotDisturbChanged() {
            const dnd = Services.Notifications.doNotDisturb
            if (!root.hudReady) {
                root.lastDnd = dnd
                return
            }
            if (dnd === root.lastDnd) return
            root.lastDnd = dnd
            const icon = dnd ? "󰂛" : "󰂚"
            const title = dnd ? "Do Not Disturb" : "Notifications On"
            const detail = dnd ? "On" : "Off"
            root.showSysHud(icon, title, detail, dnd ? Services.Theme.danger : Services.Theme.accent)
        }
    }

    Connections {
        target: Services.Power
        function onChargingChanged() {
            const isCharging = Services.Power.charging
            if (!root.hudReady || !Services.Power.ready) {
                root.lastChargingState = isCharging
                return
            }
            if (isCharging === root.lastChargingState) return
            root.lastChargingState = isCharging

            const rawPct = Services.Power.percentage || 0
            const pct = Math.round(rawPct > 1 ? rawPct : rawPct * 100)
            const icon = Services.Icons.powerIcon(isCharging, pct)
            const title = isCharging ? "Charging" : "Discharging"
            const detail = pct + "%"
            root.showSysHud(icon, title, detail, isCharging ? Services.Theme.success : Services.Theme.accent)
            // Sound feedback for charge/discharge
            if (isCharging) Services.SoundFeedback.playPowerPlug()
            else Services.SoundFeedback.playPowerUnplug()
        }

        function onBatteryWarning(level, title, message) {
            if (!root.hudReady) return
            const icon = Services.Icons.powerIcon(false, level)
            const color = level <= 10 ? Services.Theme.danger : "#ff9800"
            root.showSysHud(icon, title, message, color)
        }
    }

    Connections {
        target: Services.PowerProfile
        function onProfileChanged() {
            const current = Services.PowerProfile.profile
            if (!root.hudReady) {
                root.lastPowerProfile = current
                root.lastSaverEnabled = Services.PowerProfile.saverEnabled
                return
            }
            if (!current || current === root.lastPowerProfile) return
            root.lastPowerProfile = current
            root.lastSaverEnabled = Services.PowerProfile.saverEnabled

            let icon = Services.Icons.balance
            let title = "Switch to Balanced"
            let detail = "Standard performance"
            let color = Services.Theme.accent

            if (current === "power-saver") {
                icon = Services.Icons.tree
                title = "Power Saver On"
                detail = "Battery saver active"
                color = "#ff9800"
            } else if (current === "performance") {
                icon = Services.Icons.speed
                title = "Switch to Performance"
                detail = "High performance active"
                color = Services.Theme.danger || "#ef4444"
            } else if (current === "balanced") {
                icon = Services.Icons.balance
                title = "Switch to Balanced"
                detail = "Standard performance"
                color = Services.Theme.accent
            }

            root.showSysHud(icon, title, detail, color)
        }
    }

    Connections {
        target: Services.Wifi
        function onConnectedChanged() {
            const isConn = Services.Wifi.connected
            const currentSsid = Services.Wifi.ssid

            if (!root.hudReady) {
                root.wifiLastConnected = isConn
                if (currentSsid) root.wifiLastSsid = currentSsid
                return
            }

            if (isConn && !root.wifiLastConnected) {
                const name = currentSsid || root.wifiLastSsid || "Network"
                root.showSysHud("󰤨", "Wi-Fi Connected", name, Services.Theme.success)
                if (currentSsid) root.wifiLastSsid = currentSsid
            } else if (!isConn && root.wifiLastConnected) {
                const name = root.wifiLastSsid || "Network"
                root.showSysHud("󰤭", "Wi-Fi Disconnected", name, Services.Theme.danger)
            }
            root.wifiLastConnected = isConn
        }

        function onSsidChanged() {
            if (!root.hudReady) {
                if (Services.Wifi.ssid) root.wifiLastSsid = Services.Wifi.ssid
                return
            }
            if (Services.Wifi.ssid && Services.Wifi.ssid !== "") {
                if (Services.Wifi.connected && root.wifiLastConnected && root.wifiLastSsid !== "" && root.wifiLastSsid !== Services.Wifi.ssid) {
                    root.showSysHud("󰤨", "Wi-Fi Switched", Services.Wifi.ssid, Services.Theme.accent)
                }
                root.wifiLastSsid = Services.Wifi.ssid
            }
        }

        function onEnabledChanged() {
            if (!root.hudReady) return
            const isEnabled = Services.Wifi.enabled
            const icon = isEnabled ? "󰤨" : "󰤭"
            const title = isEnabled ? "Wi-Fi On" : "Wi-Fi Off"
            const detail = isEnabled ? "Wi-Fi enabled" : "Wi-Fi disabled"
            root.showSysHud(icon, title, detail, isEnabled ? Services.Theme.accent : Services.Theme.danger)
        }
    }

    Connections {
        target: Services.Bluetooth
        function onDevicesChanged() {
            const currentDevices = Services.Bluetooth.devices || []
            const newMap = {}

            for (let i = 0; i < currentDevices.length; i++) {
                const dev = currentDevices[i]
                if (dev && dev.connected && dev.mac) {
                    const mac = dev.mac.toLowerCase()
                    newMap[mac] = {
                        name: dev.name || dev.mac,
                        battery: (dev.battery !== undefined && dev.battery >= 0) ? dev.battery : -1,
                        icon: dev.icon || ""
                    }
                }
            }

            if (!root.hudReady) {
                root.btConnectedDevices = newMap
                root.btInitialized = true
                return
            }

            // Detect newly connected devices
            for (const mac in newMap) {
                if (!root.btConnectedDevices[mac]) {
                    const devInfo = newMap[mac]
                    const devName = typeof devInfo === "string" ? devInfo : devInfo.name
                    const battery = typeof devInfo === "object" ? devInfo.battery : -1
                    const devIconType = (typeof devInfo === "object" ? (devInfo.icon || "") : "").toLowerCase()

                    // Select HUD icon based on device type / name
                    let hudIcon = "󰂱"
                    if (devIconType.includes("headset") || devIconType.includes("headphone") || devName.toLowerCase().includes("tws") || devName.toLowerCase().includes("earbuds") || devName.toLowerCase().includes("airpods")) {
                        hudIcon = "󰋋"
                    } else if (devIconType.includes("speaker") || devIconType.includes("audio")) {
                        hudIcon = "󰓃"
                    } else if (devIconType.includes("phone") || devIconType.includes("cellphone")) {
                        hudIcon = "󰄋"
                    } else if (devIconType.includes("computer") || devIconType.includes("laptop")) {
                        hudIcon = "󰌢"
                    } else if (devIconType.includes("gamepad") || devIconType.includes("gaming")) {
                        hudIcon = "󰊴"
                    }

                    // Detail text with battery level if available
                    let detailText = devName
                    if (battery >= 0) {
                        detailText += " • " + battery + "%"
                    }

                    root.showSysHud(hudIcon, "Bluetooth Connected", detailText, Services.Theme.success)
                }
            }

            // Detect disconnected devices
            for (const mac in root.btConnectedDevices) {
                if (!newMap[mac]) {
                    const prevDev = root.btConnectedDevices[mac]
                    const devName = typeof prevDev === "string" ? prevDev : prevDev.name
                    root.showSysHud("󰂲", "Bluetooth Disconnected", devName, Services.Theme.danger)
                }
            }

            root.btConnectedDevices = newMap
        }

        function onEnabledChanged() {
            if (!root.hudReady) return
            const isEnabled = Services.Bluetooth.enabled
            if (!isEnabled) {
                root.btConnectedDevices = {}
            }
            const icon = isEnabled ? "󰂯" : "󰂲"
            const title = isEnabled ? "Bluetooth On" : "Bluetooth Off"
            const detail = isEnabled ? "Bluetooth enabled" : "Bluetooth disabled"
            root.showSysHud(icon, title, detail, isEnabled ? Services.Theme.accent : Services.Theme.danger)
        }
    }

    Connections {
        target: Services.Wallpaper
        function onCurrentWallpaperChanged() {
            if (!Services.Wallpaper || !Services.Wallpaper.currentWallpaper) return
            const path = Services.Wallpaper.currentWallpaper
            if (!root.hudReady) {
                root.lastWallpaperPath = path
                return
            }
            if (path === root.lastWallpaperPath) return
            root.lastWallpaperPath = path
            const name = path.substring(path.lastIndexOf("/") + 1)
            root.showSysHud(Services.Icons.image || "󰋩", "Wallpaper Applied", name, Services.Theme.accent, 2600)
        }
    }

    // MPRIS shortcuts
    readonly property var activePlayer: Services.Mpris.activePlayer
    readonly property bool mediaPlaying: activePlayer !== null && activePlayer.isPlaying
    readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle !== "" || mediaPlaying)

    // Track metadata from browser MPRIS providers can arrive in several signals.
    // Keep the currently displayed metadata stable until the burst has settled.
    // Keep the cached track fields in one object so they change atomically.
    // Separate assignments can briefly combine the new title with the old artist.
    property var stableMedia: ({ title: "", artist: "", identity: "", player: null })
    readonly property string stableTrackTitle: String(stableMedia.title || "")
    readonly property string stableTrackArtist: String(stableMedia.artist || "")
    readonly property string stableTrackIdentity: String(stableMedia.identity || "")
    property bool mediaPeekPending: false
    property double blankTrackTitleSince: 0

    function scheduleMediaMetadataSync(requestPeek) {
        if (requestPeek === true) root.mediaPeekPending = true
        mediaMetadataSettleTimer.restart()
    }

    function syncMediaMetadataNow() {
        const player = root.activePlayer
        root.stableMedia = {
            title: String(player?.trackTitle || "").trim(),
            artist: String(player?.trackArtist || "").trim(),
            identity: String(player?.identity || "").trim(),
            player: player
        }
    }

    Timer {
        id: mediaMetadataSettleTimer
        interval: 350
        repeat: false
        onTriggered: {
            const player = root.activePlayer
            const previous = root.stableMedia || {}
            const samePlayer = player === previous.player
            const title = String(player?.trackTitle || "").trim()
            const artist = String(player?.trackArtist || "").trim()
            const identity = String(player?.identity || "").trim()

            // Allow a short metadata grace period when the same browser player
            // clears the title between tracks. Never keep stale metadata forever.
            if (samePlayer && root.mediaPlaying && title === "" && root.stableTrackTitle !== "") {
                if (root.blankTrackTitleSince === 0) root.blankTrackTitleSince = Date.now()
                if (Date.now() - root.blankTrackTitleSince < 1200) {
                    mediaMetadataSettleTimer.restart()
                    return
                }
            } else {
                root.blankTrackTitleSince = 0
            }

            root.blankTrackTitleSince = 0
            const requestPeek = root.mediaPeekPending
            root.mediaPeekPending = false
            root.stableMedia = {
                title: title,
                artist: artist,
                identity: identity,
                player: player
            }

            if (requestPeek && root.mediaPlaying && root.hudReady && root.notifCount === 0 && !root.pinned && !root.lockBlocked) {
                root.triggerMediaPeek(false)
            }
        }
    }

    readonly property bool hasExpandContent: ((slot0Activity !== "idle") || wallpaperMode || dropWorkflowActive)
    readonly property bool expanded: !lockBlocked && hasExpandContent && (pinned || autoExpanded || (slot0Activity === "notif") || (slot0Activity === "syshud") || wallpaperMode || dropWorkflowActive)
    readonly property bool isMediaPeek: !lockBlocked && autoExpanded && !pinned && (slot0Activity === "media") && !wallpaperMode && !dropWorkflowActive && hasMedia
    onIsMediaPeekChanged: {
        if (isMediaPeek) mediaWasPeek = true
    }
    onPinnedChanged: {
        if (pinned) mediaWasPeek = false
    }

    property int autoExpandDuration: 3000
    property int notifDuration: 5000

    // Safe retrieval of current notification entry from the center slot
    readonly property var currentNotif: {
        if (slotCenterItem && slotCenterItem.type === "notif" && slotCenterItem.notif) {
            return slotCenterItem.notif
        }
        return null
    }

    onCurrentNotifChanged: {
        replyMode = false
        activeReplyActionId = ""
        if (currentNotif && popupList) {
            for (let i = 0; i < popupList.count; i++) {
                if (popupList.get(i).notifId === currentNotif.notifId) {
                    activeNotifIndex = i
                    break
                }
            }
        } else {
            activeNotifIndex = 0
        }
    }

    onReplyModeChanged: {
        if (replyMode) {
            if (currentNotif) {
                Services.Notifications.replyingNotifId = currentNotif.notifId
            }
            Qt.callLater(() => replyInput.forceActiveFocus())
        } else {
            Services.Notifications.replyingNotifId = -1
        }
    }

    function isReplyAction(act) {
        if (!act) return false
        const id = (act.identifier || "").toLowerCase()
        const txt = (act.text || "").toLowerCase()
        return id.includes("reply") || id.includes("inline") || id.includes("respond") ||
               txt.includes("reply") || txt.includes("balas") || txt.includes("jawab") || txt.includes("respond")
    }

    readonly property bool isCritical: currentNotif !== null && currentNotif.urgency === 2
    readonly property bool hasNotifBody: currentNotif !== null && currentNotif.body !== undefined && currentNotif.body.length > 0
    readonly property bool hasNotifActions: currentNotif !== null && currentNotif.actions !== undefined && (currentNotif.actions.count > 0 || (currentNotif.actions.length !== undefined && currentNotif.actions.length > 0))

    readonly property string currentMediaText: {
        if (!activePlayer) return ""
        const title = root.stableTrackTitle
        const artist = root.stableTrackArtist
        if (title !== "" && artist !== "") return title + " • " + artist
        return title || artist || "Playing"
    }

    property string lastTrackText: ""
    property string lastPeekKey: ""

    function triggerMediaPeek(force) {
        if (root.lockBlocked || Services.OverlayManager.isLocked) return
        if (root.pinned) return
        if (root.notifActive && root.notifCount > 0) return
        if (root.wallpaperMode || root.dropWorkflowActive) return
        if (!root.mediaPlaying) return

        const curKey = (root.stableTrackIdentity || root.activePlayer?.identity || "") + "::" + (root.stableTrackTitle || "") + "::" + (root.stableTrackArtist || "")
        if (!force && curKey === root.lastPeekKey && root.autoExpanded) {
            autoCollapseTimer.restart()
            return
        }
        root.lastPeekKey = curKey

        mediaStopPhase1Timer.stop()
        mediaStopPhase2Timer.stop()
        root.manualCenterId = ""
        root.mediaActiveTime = Date.now()
        root.mediaStopping = false
        root.mediaTextCollapsed = false
        root.mediaIconTransformed = false
        root.restartGlobalMarquee()

        // QML bindings re-evaluate synchronously on every assignment. Setting
        // mediaCollapsedReady first made collapsedTextContainer.activeState true (autoExpanded
        // was still false) for one evaluation, so the pill label popped in at full opacity and
        // then faded out as the peek opened. Open the peek first; the label stays inactive.
        if (root.autoExpanded) {
            root.mediaCollapsedReady = true
            autoCollapseTimer.restart()
            return
        }
        root.autoExpanded = true
        root.mediaCollapsedReady = true
        autoCollapseTimer.restart()
    }

    onMediaPlayingChanged: {
        if (mediaPlaying) {
            mediaActiveTime = Date.now()
            root.scheduleMediaMetadataSync(true)
            if (root.hudReady && root.notifCount === 0 && !root.pinned && !root.lockBlocked) {
                root.mediaCollapsedReady = false
            } else {
                root.mediaCollapsedReady = true
            }
            mediaStopPhase1Timer.stop()
            mediaStopPhase2Timer.stop()
            root.mediaStopping = false
            root.mediaTextCollapsed = false
            root.mediaIconTransformed = false
            if (currentMediaText !== "") {
                lastTrackText = currentMediaText
            }
        } else {
            mediaMetadataSettleTimer.stop()
            root.mediaPeekPending = false
            root.lastPeekKey = ""
            if (root.hudReady && !root.notifActive && !root.lockBlocked) {
                root.triggerMediaStop()
            } else {
                root.mediaCollapsedReady = false
            }
        }
    }
    onCurrentMediaTextChanged: {
        if (mediaPlaying && currentMediaText !== "") {
            mediaActiveTime = Date.now()
            lastTrackText = currentMediaText
            root.restartGlobalMarquee()
        }
    }
    // When a notif/syshud that owned the island ends, slot0Activity flips back to
    // "media" at the same moment `expanded` drops to false. onExpandedChanged would
    // then read that as the media card collapsing and flash the full media card
    // (seek bar + controls) while the island shrinks from the notif size. This flag
    // marks that handoff so the media collapse transition is skipped for it.
    property string lastSlot0Activity: "idle"
    property bool overlayHandoffToMedia: false
    onSlot0ActivityChanged: {
        const prev = lastSlot0Activity
        lastSlot0Activity = slot0Activity
        if (slot0Activity !== "media" || (prev !== "notif" && prev !== "syshud")) return
        overlayHandoffToMedia = true
        // Signal order vs. onExpandedChanged isn't guaranteed: if the transition
        // already started, undo it.
        if (!expanded) {
            mediaTransitionAnim.stop()
            mediaTransitionActive = false
            mediaTransitionProgress = 1.0
            mediaTransitionCollapsing = true
        }
        // Same event-loop turn only, so a later real media collapse is unaffected.
        Qt.callLater(function() { root.overlayHandoffToMedia = false })
    }
    onExpandedChanged: {
        if (!expanded) {
            mediaVolHudOpen = false
            mediaVolDragging = false
        } else if (slot0Activity === "media") {
            refreshMediaVolTargets()
        }
        if (expanded && !autoExpanded) {
            mediaWasPeek = false
        }
        // The media card and its artwork share one timeline. This avoids competing
        // title, cover, and collapsed-label animations during the same state change.
        if (root.slot0Activity === "media" && root.hasMedia && root.mediaPlaying && !root.lockBlocked && !root.overlayHandoffToMedia) {
            const wasAnimating = mediaTransitionAnim.running || root.mediaTransitionActive
            mediaTransitionAnim.stop()
            // Title/artist x is pinned to 0 while the transition runs and then snaps to the
            // marquee offset. Restarting the driver parks the ratio at 0 (1.8 s pause), so
            // both the expanded and collapsed labels settle without a jump.
            // Remember how far the pill label was scrolled so the flight starts exactly
            // where the text visibly is; the collapse target is always the unscrolled label.
            root.mediaFlightStartRatio = root.expanded ? root.globalMediaMarqueeRatio : 0.0
            root.restartGlobalMarquee()
            // Track direction: expanded=false means we are collapsing (going toward pill).
            root.mediaTransitionCollapsing = !root.expanded
            if (!wasAnimating) root.mediaTransitionProgress = root.expanded ? 1.0 : 0.0
            root.mediaTransitionActive = true
            mediaInfoCol.prepareArtworkFlight()
            mediaTransitionAnim.to = root.expanded ? 0.0 : 1.0
            mediaTransitionAnim.restart()
        } else {
            mediaTransitionAnim.stop()
            root.mediaTransitionActive = false
            root.mediaTransitionProgress = root.expanded ? 0.0 : 1.0
            root.mediaTransitionCollapsing = !root.expanded
        }
    }

    NumberAnimation {
        id: mediaTransitionAnim
        target: root
        property: "mediaTransitionProgress"
        // Must match the island shell morph (Behaviors below) so artwork flight, label crossfade,
        // controls<->cava morph and capsule resize all finish together.
        // InOutCubic idled for ~25% of the flight and then rushed through the middle (peak speed 3x the
        // average): in a 30 fps recording the card sat still for ~6 frames, then jumped in 2, which is
        // what made the morph look choppy. InOutSine peaks at ~1.6x average, so the same motion spreads
        // over far more frames. mediaFlightT inverts exactly this curve.
        duration: root.mediaFlightMs
        easing.type: Easing.InOutSine
        onFinished: {
            root.mediaTransitionActive = false
            root.mediaTransitionProgress = root.expanded ? 0.0 : 1.0
            if (!root.expanded) {
                root.mediaWasPeek = false
                if (root.mediaPlaying) root.mediaCollapsedReady = true
            }
        }
    }

    // ==================== Master Continuous Media Marquee Driver ====================
    property real globalMediaMarqueeRatio: 0.0
    property real globalMediaMarqueeDuration: 4200

    function restartGlobalMarquee() {
        globalMediaMarqueeAnim.stop()
        globalMediaMarqueeRatio = 0.0
        const tLen = (root.stableTrackTitle || "").length
        const aLen = (root.stableTrackArtist || "").length
        const maxLen = Math.max(tLen, aLen, (root.currentMediaText || "").length)
        const approxOverflow = Math.max(40, (maxLen * 7.5) - 130)
        globalMediaMarqueeDuration = Math.max(3000, Math.min(8500, approxOverflow * 35))
        if (root.mediaPlaying && !root.lockBlocked) {
            globalMediaMarqueeAnim.start()
        }
    }

    SequentialAnimation {
        id: globalMediaMarqueeAnim
        running: root.mediaPlaying && !root.lockBlocked
        loops: Animation.Infinite

        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "globalMediaMarqueeRatio"
            from: 0.0
            to: 1.0
            duration: root.globalMediaMarqueeDuration
            easing.type: Easing.InOutQuad
        }
        PauseAnimation { duration: 1800 }
        NumberAnimation {
            target: root
            property: "globalMediaMarqueeRatio"
            from: 1.0
            to: 0.0
            duration: root.globalMediaMarqueeDuration
            easing.type: Easing.InOutQuad
        }
    }

    // Island Dimensions
    readonly property bool showCollapsedText: !lockBlocked && !root.mediaStopping && ((slot0Activity === "notif") || (mediaPlaying && mediaCollapsedReady))
    // Collapsed width bounds while media is playing (tweak these two to taste)
    readonly property int mediaCollapsedMinWidth: 190
    readonly property int mediaCollapsedMaxWidth: 260

    readonly property int calculatedCollapsedWidth: {
        if (showCollapsedText || (mediaStopping && !mediaTextCollapsed)) {
            const isMedia = mediaPlaying || mediaStopping
            const extraPadding = isMedia ? 72 : 52
            const wanted = collapsedTextContainer.currentSlotImplicitWidth + extraPadding
            if (isMedia) return Math.min(mediaCollapsedMaxWidth, Math.max(mediaCollapsedMinWidth, wanted))
            return Math.min(260, Math.max(140, wanted))
        }
        return 140
    }
    property int collapsedWidth: 140
    property int collapsedHeight: 32

    // ── Adaptive sharing panel dimensions (per stage) ──
    // chooser: two destination cards — compact but both fit comfortably
    // preparing/handoff: single-row status strip (no destination cards needed)
    // transfer (KDE Connect): thumbnail 44px + margins 12px each side = 68px min
    // success/error: reuse transfer height unless content overflows
    readonly property string dropTransferState: Services.DeviceShare ? Services.DeviceShare.transferState : "idle"
    readonly property bool showDropChooser: root.dropSendMode && !root.showDropTransfer && !root.isLocalSendHandoff
    readonly property bool showDropTransfer: Services.DeviceShare
        ? (dropTransferState === "error" || (Services.DeviceShare.transferBackend !== "localsend"
            && (dropTransferState === "sending" || dropTransferState === "success")))
        : root.isDropSending
    readonly property bool showDropHandoff: root.isLocalSendHandoff

    // ── System HUD adaptive width ──
    // Measures the same fonts used by the HUD title/detail Text items so the
    // island hugs its content instead of using one fixed width.
    TextMetrics {
        id: sysHudTitleMetrics
        text: root.sysHudTitle
        font.pixelSize: 12
        font.bold: true
    }
    TextMetrics {
        id: sysHudDetailMetrics
        text: root.sysHudDetail
        font.pixelSize: 10
    }
    // RowLayout margins (10*2) + bubble (32) + spacing (10) + text + small safety buffer
    readonly property int sysHudAdaptiveWidth: {
        const textW = Math.max(sysHudTitleMetrics.advanceWidth, sysHudDetailMetrics.advanceWidth)
        return Math.min(320, Math.max(180, Math.ceil(62 + textW + 8)))
    }

    // ── Media peek adaptive width ──
    // Same text/fonts as the peek title/artist in mediaView (12px bold / 10px).
    TextMetrics {
        id: mediaPeekTitleMetrics
        text: root.activePlayer ? (root.stableTrackTitle || "Playing") : "Playing"
        font.pixelSize: 12
        font.bold: true
    }
    TextMetrics {
        id: mediaPeekArtistMetrics
        text: root.activePlayer ? (root.stableTrackArtist || root.stableTrackIdentity || "Now Playing") : "Now Playing"
        font.pixelSize: 10
    }
    // margins (10*2) + art (34) + spacing (10) + text + right padding (12) + buffer (no visualizer)
    readonly property int mediaPeekAdaptiveWidth: {
        const textW = Math.max(mediaPeekTitleMetrics.advanceWidth, mediaPeekArtistMetrics.advanceWidth)
        return Math.min(340, Math.max(190, Math.ceil(76 + textW + 8)))
    }

    readonly property int calculatedExpandedWidth: {
        if (slot0Activity === "notif") return replyMode ? 390 : 360
        if (showDropChooser) return 440
        if (showDropHandoff) return 360
        if (showDropTransfer) return 360
        if (dropWorkflowActive) return 360
        if (wallpaperMode) return 480
        if (slot0Activity === "syshud") return sysHudAdaptiveWidth
        if (isMediaPeek) return mediaPeekAdaptiveWidth
        if (hasMedia) return 360
        return 260
    }

    readonly property int calculatedExpandedHeight: {
        if (slot0Activity === "notif") {
            if (replyMode) return 146
            let h = 72
            if (hasNotifBody) h += 24
            if (hasNotifActions) h += 32
            return h
        }
        if (showDropChooser) return 120
        if (showDropHandoff) return 80
        if (showDropTransfer) return 76
        if (dropWorkflowActive) return 76
        if (wallpaperMode) return 120
        if (slot0Activity === "syshud") return 54
        if (isMediaPeek) return 54
        if (hasMedia) return 144
        return 52
    }

    // ── Bar layout negotiation ────────────────────────────────────
    // Lebar yang di-"klaim" island dari bar, sudah termasuk ruang satellite.
    // Easing is now OutCubic (settles exactly at target) so overshootAllowance
    // is kept small — just a safety buffer for rounding.
    readonly property real reservedWidth: {
        const base = expanded ? calculatedExpandedWidth : calculatedCollapsedWidth
        return base + satelliteExtraWidth + (expanded ? overshootAllowance : 0)
    }

    readonly property real overshootAllowance: 8

    readonly property string demand: {
        if (!expanded) return "idle"
        if (dropWorkflowActive || wallpaperMode) return "greedy"
        if (isMediaPeek) return "peek"
        return "normal"
    }

    // Format seconds → "m:ss"
    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    function pulse() {
        if (pinned || notifActive || lockBlocked) {
            root.mediaCollapsedReady = true
            return
        }
        root.triggerMediaPeek(true)
    }

    function togglePin() {
        if (!hasExpandContent) return
        if (isMediaPeek) {
            pinned = true
            autoExpanded = false
            autoCollapseTimer.stop()
        } else if (expanded) {
            collapse()
        } else {
            pinned = true
        }
    }

    function collapse() {
        if (root.isMediaPeek) {
            root.mediaWasPeek = true
        }
        pinned = false
        autoExpanded = false
        if (root.mediaPlaying) root.mediaCollapsedReady = true
        replyMode = false
        wallpaperMode = false
        dropSendMode = false
        dropStagedChoice = false
        dropHoverTarget = ""
        if (notifActive && currentNotif) {
            Services.Notifications.dismiss(currentNotif.notifId)
        }
    }

    function toggleWallpaperMode() {
        if (lockBlocked) return
        if (wallpaperMode) {
            collapse()
        } else {
            pinned = false
            autoExpanded = false
            autoCollapseTimer.stop()
            replyMode = false
            sysHudActive = false
            sysHudTimer.stop()
            manualCenterId = ""
            wallpaperMode = true
            if (Services.Wallpaper && Services.Wallpaper.currentWallpaper) {
                const cur = Services.Wallpaper.currentWallpaper
                const list = wallpaperList || []
                for (let i = 0; i < list.length; i++) {
                    if (list[i].path === cur || (list[i].isDynamic && Services.Wallpaper.isWallblerActive)) {
                        wallpaperIndex = i
                        break
                    }
                }
            }
        }
    }

    Connections {
        target: Services.OverlayManager
        function onWallpaperToggleRequested() { root.toggleWallpaperMode() }
        function onWallpaperShowRequested() { root.toggleWallpaperMode() }
        function onIsLockedChanged() {
            if (Services.OverlayManager.isLocked) {
                if (root.sysHudActive && root.sysHudTitle === "Camera Active") {
                    root.sysHudActive = false
                }
            } else {
                if (root.sysHudActive && root.sysHudTitle === "Camera Active") {
                    root.sysHudActive = false
                }
                if (!cameraProc.running) cameraProc.running = true
            }
        }
    }

    function nextNotif() {
        if (notifCount > 0) {
            activeNotifIndex = (activeNotifIndex + 1) % notifCount
            notifTimer.restart()
        }
    }

    function prevNotif() {
        if (notifCount > 0) {
            activeNotifIndex = (activeNotifIndex - 1 + notifCount) % notifCount
            notifTimer.restart()
        }
    }

    Timer {
        id: mprisRefreshTimer
        interval: 500
        running: root.mediaPlaying
        repeat: true
        onTriggered: root.activePlayer?.positionChanged?.()
    }

    Timer {
        id: autoCollapseTimer
        interval: root.autoExpandDuration
        onTriggered: {
            if (root.isMediaPeek) {
                root.mediaWasPeek = true
            }
            root.autoExpanded = false
            if (root.mediaPlaying) root.mediaCollapsedReady = true
        }
    }

    Timer {
        id: notifTimer
        interval: root.notifDuration
        repeat: false
        onTriggered: {
            if (root.replyMode) return
            // Slot stability: no auto-incrementing
        }
    }

    Timer {
        id: privacyNotifHandoffTimer
        // Let camera/recording start its satellite split before the incoming
        // notification is allowed to occupy the main island. This matches the
        // 430ms flight plus the final 130ms handoff fade of the privacy dot.
        interval: 560
        repeat: false
        onTriggered: root.privacyNotifHandoffPending = false
    }

    Connections {
        target: Services.Notifications
        function onNewNotification(entry) {
            // Keep modal panels open. allSortedCandidates routes the notification
            // to a satellite while wallpaper or the sharing chooser owns center.
            root.sysHudActive = false
            sysHudTimer.stop()
            root.manualCenterId = ""
            root.activeNotifIndex = 0
            root.replyMode = false
            notifTimer.restart()
        }
    }

    Connections {
        target: Services.Mpris
        ignoreUnknownSignals: true
        function onActivePlayerChanged() { root.scheduleMediaMetadataSync(true) }
        function onPlaybackStarted(player) { root.scheduleMediaMetadataSync(true) }
    }

    Connections {
        target: root.activePlayer
        ignoreUnknownSignals: true
        function onIsPlayingChanged() {
            if (root.activePlayer && (root.activePlayer.isPlaying ?? false)) {
                root.scheduleMediaMetadataSync(true)
            }
        }
        function onTrackTitleChanged() { root.scheduleMediaMetadataSync(true) }
        function onTrackArtistChanged() { root.scheduleMediaMetadataSync(true) }
        function onTrackChanged() { root.scheduleMediaMetadataSync(true) }
        function onPostTrackChanged() { root.scheduleMediaMetadataSync(true) }
        function onMetadataChanged() { root.scheduleMediaMetadataSync(true) }
        function onTrackArtUrlChanged() { root.scheduleMediaMetadataSync(false) }
    }
    // Click outside area to collapse expanded island
    MouseArea {
        id: outsideMouseArea
        anchors.fill: parent
        enabled: root.expanded
        visible: root.expanded
        z: -1
        propagateComposedEvents: true
        onClicked: mouse => {
            root.collapse()
            mouse.accepted = false
        }
    }

    // ── Seamless Adaptive Morphing Capsule Island ──
    Rectangle {
        id: island
        z: 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.isBottom ? (parent.height - height - 6) : 6
        // The privacy dot must be allowed to leave this clipped capsule during
        // its handoff to a satellite; otherwise it looks stranded inside an
        // incoming notification while its destination is outside the island.
        clip: !cameraIndicator.transferringToSatellite

        // Direct Reactive Dimensions adapting to content type
        width: root.expanded ? root.calculatedExpandedWidth : root.calculatedCollapsedWidth
        height: root.expanded ? root.calculatedExpandedHeight : root.collapsedHeight

        readonly property bool isCapsuleShape: !root.expanded || (!root.notifActive && (root.sysHudActive || root.isMediaPeek))
        // Animate toward the *final* capsule radius instead of deriving it from
        // the live animated height. A live height/2 binding turns the whole card
        // into an oval as soon as collapse starts.
        readonly property real targetRadius: isCapsuleShape
            ? (root.expanded ? root.calculatedExpandedHeight / 2 : root.collapsedHeight / 2)
            : Services.Theme.radiusLg
        radius: targetRadius

        color: Services.Theme.bgPure
        border.color: {
            if (root.isCritical) return Services.Theme.danger
            if (root.expanded) return Services.Theme.borderHighlight
            return Services.Theme.borderSubtle
        }
        border.width: root.isCritical ? 1.5 : 1

        property real entranceScale: 1.0

        scale: entranceScale

        transform: [
            Translate {
                x: (root.rightIslandBulge - root.leftIslandBulge) * 0.5
            },
            Scale {
                origin.x: island.width / 2
                origin.y: island.height / 2
                xScale: 1.0 + ((root.rightIslandBulge + root.leftIslandBulge) / Math.max(1, island.width))
            }
        ]

        Connections {
            target: Services.OverlayManager
            function onIsLockAbsorbingChanged() {
                if (Services.OverlayManager && Services.OverlayManager.isLockAbsorbing) {
                    postUnlockMediaTimer.stop()
                    swallowPulseTimer.restart()
                    root.triggerLockAbsorption()
                }
            }
            function onIsLockedChanged() {
                if (Services.OverlayManager.isLocked) {
                    postUnlockMediaTimer.stop()
                    root.mediaCollapsedReady = false
                } else {
                    root.autoExpanded = false
                    root.pinned = false
                    root.mediaStopping = false
                    root.mediaTextCollapsed = false
                    root.mediaIconTransformed = false
                    root.mediaCollapsedReady = false
                    postUnlockMediaTimer.restart()
                    mediaStopPhase1Timer.stop()
                    mediaStopPhase2Timer.stop()
                    entranceAnim.restart()
                }
            }
        }

        Timer {
            id: swallowPulseTimer
            interval: 150
            repeat: false
            onTriggered: swallowPulseAnim.restart()
        }

        SequentialAnimation {
            id: swallowPulseAnim
            NumberAnimation {
                target: island
                property: "entranceScale"
                from: 1.0
                to: 1.05
                duration: 90
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: island
                property: "entranceScale"
                from: 1.05
                to: 1.0
                duration: 160
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
        }

        SequentialAnimation {
            id: entranceAnim
            NumberAnimation {
                target: island
                property: "entranceScale"
                from: 1.0
                to: 1.06
                duration: 140
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: island
                property: "entranceScale"
                from: 1.06
                to: 1.0
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.15
            }
        }

        // Media uses a balanced in/out curve so opening and closing feel like
        // two directions of the same shape morph. Other island modes keep the
        // original OutCubic timing.
        Behavior on width {
            NumberAnimation {
                // 380 ms for media keeps the shell morph in sync with
                // mediaTransitionAnim so artwork flight and label crossfade
                // all finish at the same moment.
                duration: root.lockBlocked ? 240 : (root.slot0Activity === "media" ? root.mediaFlightMs : (root.expanded ? 300 : 260))
                easing.type: root.slot0Activity === "media" ? Easing.InOutSine : Easing.OutCubic
            }
        }
        Behavior on height {
            NumberAnimation {
                duration: root.lockBlocked ? 240 : (root.slot0Activity === "media" ? root.mediaFlightMs : (root.expanded ? 300 : 260))
                easing.type: root.slot0Activity === "media" ? Easing.InOutSine : Easing.OutCubic
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: root.lockBlocked ? 240 : (root.slot0Activity === "media" ? root.mediaFlightMs : (root.expanded ? 280 : 240))
                easing.type: root.slot0Activity === "media" ? Easing.InOutSine : Easing.OutCubic
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }
        Behavior on border.width {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            id: islandMouseArea
            anchors.fill: parent
            z: 0
            enabled: root.hasExpandContent && !root.dropWorkflowActive
            cursorShape: (root.hasExpandContent && !root.dropWorkflowActive) ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.togglePin()
        }

        // Global DropArea over Island
        DropArea {
            id: islandDropArea
            anchors.fill: parent
            z: 5
            onEntered: (drag) => {
                dropExitDebounceTimer.stop()
                root.extractDropDetails(drag.urls)
                root.dropStagedChoice = false
                root.manualCenterId = ""
                root.dropSendMode = true
            }
            onPositionChanged: (drag) => {
                dropExitDebounceTimer.stop()
                if (!root.dropSendMode) root.dropSendMode = true
            }
            onExited: () => {
                dropExitDebounceTimer.restart()
            }
            onDropped: (drop) => {
                dropExitDebounceTimer.stop()
                root.extractDropDetails(drop.urls)
                if (root.dropHoverTarget === "kde") {
                    root.handleDropOnKde(drop.urls)
                } else if (root.dropHoverTarget === "local") {
                    root.handleDropOnLocalSend(drop.urls)
                } else {
                    root.handleDropGeneral(drop.urls)
                }
            }
        }

        // Observe the complete expanded island, not only the inner content box.
        // Leaving the island dismisses the temporary destination chooser.
        HoverHandler {
            id: dropHubHoverHandler
            enabled: root.showDropChooser
            onHoveredChanged: {
                if (hovered) {
                    dropExitDebounceTimer.stop()
                    dropStagedAutoCollapseTimer.stop()
                } else {
                    dropExitDebounceTimer.restart()
                }
            }
        }

        // ==================== Privacy / Recording Indicators (Main Island Corner) ====================
        Item {
            id: cameraIndicator
            // Do not collapse these into one dot: both can be active at once and
            // each colour is a distinct privacy/status signal.
            readonly property bool privacyActivity: (root.cameraActive && !root.isCameraSatellite) ||
                (root.recordingActive && !root.isRecordingSatellite)
            readonly property bool shouldShow: !root.lockBlocked && privacyActivity
            readonly property bool privacySatelliteActive: root.isCameraSatellite || root.isRecordingSatellite
            // In wide modal panels, the satellites are the source of truth. Do not animate
            // the combined two-dot row across the whole panel: each satellite has its own icon.
            readonly property bool modalSatelliteMode: privacySatelliteActive && (root.wallpaperMode || root.dropWorkflowActive)
            readonly property bool satelliteLeavesRight: root.slotRightType === "camera" || root.slotRightType === "recording"
            readonly property bool notificationOwnsIsland: root.slot0Activity === "notif"
            // Satellite bubbles are 32px wide with an 8px final gap. Aim for
            // their centre, not their edge, so the coloured dot hands over to
            // the satellite content without a visible jump.
            readonly property real satelliteTargetX: satelliteLeavesRight
                ? island.width + 8 + (32 - width) / 2
                : -8 - 32 + (32 - width) / 2
            // Keep the final active dot alive until it has travelled back to
            // the idle position. Without this, the source state becomes false
            // first and the dot disappears before its return animation starts.
            property bool returningToIdle: false
            property bool transferringToSatellite: false
            property bool cameraWasActive: false
            property bool recordingWasActive: false
            readonly property bool cameraDotVisible: root.cameraActive || (returningToIdle && cameraWasActive)
            readonly property bool recordingDotVisible: root.recordingActive || (returningToIdle && recordingWasActive)
            // Never leave a second privacy dot inside an already occupied
            // notification island. During the pre-notification handoff, the
            // transfer dot remains visible; once notification owns the centre,
            // the satellite is the single source of truth.
            readonly property bool showMainDot: !modalSatelliteMode && ((!privacySatelliteActive && shouldShow) ||
                returningToIdle || (transferringToSatellite && !notificationOwnsIsland))
            anchors.verticalCenter: island.verticalCenter
            implicitWidth: indicatorRow.implicitWidth
            implicitHeight: 14
            width: indicatorRow.width
            // A privacy dot returns to idle through the centre, but when it
            // becomes a satellite it continues out through that satellite's
            // side of the island instead of snapping back to the middle.
            x: shouldShow ? island.width - width - 10
                : (privacySatelliteActive
                    ? satelliteTargetX
                    : (island.width - width) / 2)
            z: 4
            visible: showMainDot || (!notificationOwnsIsland && opacity > 0.01)
            opacity: showMainDot ? 1.0 : 0.0
            scale: showMainDot ? 1.0 : 0.72

            onShouldShowChanged: {
                if (shouldShow) {
                    returnToIdleTimer.stop()
                    returningToIdle = false
                } else if (!root.cameraActive && !root.recordingActive) {
                    returningToIdle = true
                    returnToIdleTimer.restart()
                }
            }

            onPrivacySatelliteActiveChanged: {
                if (privacySatelliteActive) {
                    satelliteTransferTimer.restart()
                } else {
                    satelliteTransferTimer.stop()
                    transferringToSatellite = false
                }
            }

            Connections {
                target: root

                function onCameraActiveChanged() {
                    if (root.cameraActive) {
                        cameraIndicator.cameraWasActive = true
                    } else if (root.recordingActive) {
                        // Camera ended while recording continues: do not bring
                        // the old camera dot back when recording later ends.
                        cameraIndicator.cameraWasActive = false
                    }
                }

                function onRecordingActiveChanged() {
                    if (root.recordingActive) {
                        cameraIndicator.recordingWasActive = true
                    } else if (root.cameraActive) {
                        // Recording ended while camera continues.
                        cameraIndicator.recordingWasActive = false
                    }
                }
            }

            Timer {
                id: returnToIdleTimer
                interval: 390
                repeat: false
                onTriggered: {
                    cameraIndicator.returningToIdle = false
                    cameraIndicator.cameraWasActive = false
                    cameraIndicator.recordingWasActive = false
                }
            }

            Timer {
                id: satelliteTransferTimer
                // Match the full satellite detach timeline:
                //   Phase 1 extrusion: 200ms + longest Phase 2 branch: 320ms = 520ms.
                // Keep clipping disabled until the satellite's icon has completed its bloom.
                interval: 520
                repeat: false
                onTriggered: cameraIndicator.transferringToSatellite = false
                onRunningChanged: {
                    if (running) cameraIndicator.transferringToSatellite = true
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: cameraIndicator.privacySatelliteActive ? 130 : 380; easing.type: Easing.InOutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: cameraIndicator.shouldShow ? 300 : 180; easing.type: Easing.OutCubic }
            }
            // The satellite is slaved to the island's width, so while media owns the island it must run
            // the island's exact curve (mediaFlightMs, InOutSine), otherwise it drifts off the capsule edge.
            Behavior on width {
                NumberAnimation {
                    duration: root.slot0Activity === "media" ? root.mediaFlightMs : 380
                    easing.type: root.slot0Activity === "media" ? Easing.InOutSine : Easing.InOutCubic
                }
            }
            Behavior on x {
                // Same duration/curve as width above; mismatched ones stretched the capsule into a
                // ghost oval while it moved to its satellite slot.
                NumberAnimation {
                    duration: root.slot0Activity === "media" ? root.mediaFlightMs : 380
                    easing.type: root.slot0Activity === "media" ? Easing.InOutSine : Easing.InOutCubic
                }
            }

            Row {
                id: indicatorRow
                anchors.centerIn: parent
                width: implicitWidth
                height: implicitHeight
                // Keep the gap itself animated, so a single dot recentres
                // smoothly when the other privacy activity ends.
                spacing: (cameraIndicator.cameraDotVisible && cameraIndicator.recordingDotVisible) ? 4 : 0

                Behavior on spacing {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    width: cameraIndicator.cameraDotVisible ? 8 : 0
                    height: 8
                    radius: 4
                    color: Services.Theme.success

                    Behavior on width {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on x {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }

                    SequentialAnimation on opacity {
                        running: cameraIndicator.cameraDotVisible && cameraIndicator.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                Rectangle {
                    width: cameraIndicator.recordingDotVisible ? 8 : 0
                    height: 8
                    radius: 4
                    color: root.recordingColor

                    Behavior on width {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on x {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }

                    SequentialAnimation on opacity {
                        running: cameraIndicator.recordingDotVisible && cameraIndicator.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        // ==================== Collapsed Status Icon (Left Edge / Centered when Idle) ====================
        Item {
            id: statusIconContainer
            anchors.verticalCenter: island.verticalCenter
            width: 16
            height: 16
            z: 3

            readonly property bool privacyOnly: root.slot0Activity === "idle" &&
                (root.cameraActive || root.recordingActive || cameraIndicator.returningToIdle) && !root.notifActive &&
                !root.mediaPlaying && !root.mediaStopping
            readonly property bool activeState: !root.expanded && !root.autoExpanded && !privacyOnly
            visible: activeState || opacity > 0.01
            // During collapse the container fades in with the handoff blend.
            // During expansion it starts at 0 so the music icon never overlaps
            // the expanding full-view canvas.
            opacity: root.mediaTransitionActive
                ? root.mediaCoverHandoff
                : (activeState ? 1.0 : 0.0)
            // Full size for the whole flight: the shared cover lands on this exact 16px slot, so the
            // thumbnail must not be pre-shrunk (0.4) when it takes over or hands back.
            scale: root.mediaTransitionActive
                ? 1.0
                : (activeState ? 1.0 : 0.4)
            transformOrigin: Item.Center

            Behavior on opacity {
                enabled: !root.mediaTransitionActive
                // Appear slower (OutCubic) so icon settles after the island opens;
                // disappear quickly (InQuad) before the island starts expanding.
                NumberAnimation { duration: statusIconContainer.activeState ? 260 : 180; easing.type: statusIconContainer.activeState ? Easing.OutCubic : Easing.InQuad }
            }
            Behavior on scale {
                enabled: !root.mediaTransitionActive
                NumberAnimation { duration: statusIconContainer.activeState ? 340 : 180; easing.type: Easing.OutCubic }
            }

            states: [
                State {
                    name: "ICON_LEFT"
                    when: !root.lockBlocked && (
                        (!root.expanded && !root.autoExpanded && (
                            root.mediaPlaying ||
                            root.mediaStopping ||
                            root.notifActive
                        )) ||
                        (root.mediaTransitionActive && root.mediaPlaying && !root.notifActive)
                    )
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: undefined
                        anchors.left: island.left
                        anchors.right: undefined
                    }
                    PropertyChanges {
                        statusIconContainer.anchors.leftMargin: 12
                    }
                },
                State {
                    name: "IDLE_CENTER"
                    when: root.lockBlocked ||
                        ((root.expanded || root.autoExpanded) && !root.mediaTransitionActive) ||
                        (!root.mediaPlaying && !root.mediaStopping && !root.notifActive)
                    AnchorChanges {
                        target: statusIconContainer
                        anchors.horizontalCenter: island.horizontalCenter
                        anchors.left: undefined
                        anchors.right: undefined
                    }
                }
            ]

            transitions: [
                Transition {
                    enabled: !root.mediaTransitionActive
                    from: "ICON_LEFT"; to: "IDLE_CENTER"
                    AnchorAnimation { duration: 320; easing.type: Easing.InOutCubic }
                    NumberAnimation { properties: "anchors.leftMargin"; duration: 320; easing.type: Easing.OutCubic }
                },
                Transition {
                    enabled: !root.mediaTransitionActive
                    AnchorAnimation { duration: 320; easing.type: Easing.InOutCubic }
                    NumberAnimation { properties: "anchors.rightMargin"; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "anchors.leftMargin"; duration: 320; easing.type: Easing.OutCubic }
                }
            ]

            Text {
                id: statusIconTxt
                anchors.centerIn: parent
                text: {
                    if (root.notifActive) return "󰂚"
                    if ((root.expanded || root.autoExpanded) && !root.mediaTransitionActive) return "●"
                    if (root.mediaPlaying || root.mediaStopping) return "󰎈"
                    return "●"
                }
                font.family: Services.Theme.fontSymbols
                font.pixelSize: (text === "●") ? 10 : 13
                color: {
                    if (root.notifActive) return Services.Theme.accent
                    if ((root.expanded || root.autoExpanded) && !root.mediaTransitionActive) return Services.Theme.textDisabled
                    if (root.mediaPlaying || root.mediaStopping) return Services.Theme.success
                    if (root.slot0Activity === "idle" && root.recordingActive && !root.isRecordingSatellite) return root.recordingColor
                    if (root.slot0Activity === "idle" && root.cameraActive && !root.isCameraSatellite) return Services.Theme.success
                    return Services.Theme.textDisabled
                }
                scale: textScale
                opacity: statusCoverWrap.showCover
                    ? 0.0
                    : (root.mediaTransitionActive
                        ? (root.mediaTransitionCollapsing ? root.mediaHandoffBlend : 0.0)
                        : 1.0)
                visible: opacity > 0.01
                Behavior on opacity {
                    enabled: !root.mediaTransitionActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                }

                property real textScale: 1.0

                onTextChanged: {
                    if (statusIconTxt.text === "●") {
                        statusIconTxt.rotation = 0
                    }
                    if (statusIconContainer.activeState && !root.expanded && !root.autoExpanded) {
                        iconScaleAnim.restart()
                    }
                }

                SequentialAnimation {
                    id: iconScaleAnim
                    NumberAnimation { target: statusIconTxt; property: "textScale"; to: 0.7; duration: 90; easing.type: Easing.InQuad }
                    NumberAnimation { target: statusIconTxt; property: "textScale"; to: 1.0; duration: 220; easing.type: Easing.OutQuad }
                }

                // Privacy activity is represented by the blinking dot in the main island's corner.

                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Behavior on rotation {
                    RotationAnimation {
                        direction: RotationAnimation.Clockwise
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }

                RotationAnimation on rotation {
                    from: 0; to: 360
                    duration: 4000
                    loops: Animation.Infinite
                    running: !root.lockBlocked && root.mediaPlaying && !root.expanded && !root.autoExpanded && statusIconContainer.state === "ICON_LEFT" && !statusCoverWrap.showCover
                }
            }

            // Album cover replaces the music note glyph in the collapsed island.
            // Falls back to the note automatically when there is no artwork.
            Item {
                id: statusCoverWrap
                anchors.centerIn: parent
                width: 16
                height: 16

                readonly property string liveArt: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
                property string cachedArt: ""
                onLiveArtChanged: if (liveArt !== "") cachedArt = liveArt
                Component.onCompleted: if (liveArt !== "") cachedArt = liveArt

                readonly property bool showCover: !root.notifActive
                    && (root.mediaPlaying || root.mediaStopping)
                    && (liveArt !== "" || cachedArt !== "")
                    && (statusCoverImg.source.toString() !== "")
                    && (statusCoverImg.status !== Image.Error)

                opacity: showCover ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity {
                    enabled: !root.mediaTransitionActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: statusCoverMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.5
                    }

                    Item {
                        id: statusCoverSpin
                        anchors.fill: parent

                        Rectangle { anchors.fill: parent; color: Services.Theme.surfaceVariant }

                        Image {
                            id: statusCoverImg
                            anchors.fill: parent
                            source: statusCoverWrap.liveArt !== ""
                                ? statusCoverWrap.liveArt
                                : statusCoverWrap.cachedArt
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true
                            sourceSize: Qt.size(48, 48)
                        }
                    }
                }

                Item {
                    id: statusCoverMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    layer.smooth: true
                    Rectangle {
                        anchors.fill: parent
                        radius: width * 0.3  // squircle-ish rounded square
                        color: "#ffffff"
                        antialiasing: true
                    }
                }
            }
        }

        // ==================== Mini Audio Wave Visualizer (Right Edge) ====================
        MediaModule.CavaWave {
            id: mediaVisualizer
            anchors.right: island.right
            anchors.rightMargin: 12
            anchors.verticalCenter: island.verticalCenter
            z: 3
            barCount: 4
            barWidth: 2.8
            barSpacing: 2.2
            minHeight: 3.5
            maxHeight: 16.0
            barColor: Services.Theme.success
            isPlaying: root.mediaPlaying
            active: visible
            readonly property bool activeState: !root.lockBlocked && root.mediaPlaying && !root.expanded && !root.autoExpanded && root.mediaCollapsedReady && !root.notifActive && !cameraIndicator.privacyActivity
            visible: activeState || root.mediaTransitionActive || opacity > 0.01
            opacity: root.mediaTransitionActive
                ? (root.mediaCtrlFlightActive
                    ? root.mediaBarHandoff
                    : (root.mediaTransitionCollapsing ? root.mediaHandoffBlend : 0.0))
                : (activeState ? 1.0 : 0.0)
            scale: root.mediaTransitionActive
                ? (root.mediaCtrlFlightActive
                    ? 1.0
                    : (0.5 + 0.5 * (root.mediaTransitionCollapsing ? root.mediaHandoffBlend : 0.0)))
                : (activeState ? 1.0 : 0.3)
            transformOrigin: Item.Center

            // Match the collapsed-text fade timing so visualizer and label arrive together.
            Behavior on opacity {
                enabled: !root.mediaTransitionActive
                NumberAnimation { duration: mediaVisualizer.activeState ? 220 : 180; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !root.mediaTransitionActive
                NumberAnimation { duration: mediaVisualizer.activeState ? 260 : 180; easing.type: Easing.OutCubic }
            }
        }

        // ==================== Dedicated Collapsed Track Title / Notif Text Zone ====================
        Item {
            id: collapsedTextContainer
            anchors.left: statusIconContainer.right
            anchors.leftMargin: 6
            anchors.verticalCenter: island.verticalCenter
            anchors.verticalCenterOffset: 0
            // Lock width bounded to collapsed dimension to prevent stretching while expanding
            width: Math.max(40, ((root.mediaTransitionActive || root.expanded) ? root.calculatedCollapsedWidth : island.width) - 12 - 16 - 6 - (mediaVisualizer.visible ? 34 : (cameraIndicator.visible ? 34 : 12)))
            height: 16
            z: 3

            readonly property bool showCollapsedText: !root.lockBlocked && (root.notifActive || root.mediaPlaying)
            readonly property bool activeState: !root.lockBlocked && !root.expanded && !root.autoExpanded && root.mediaCollapsedReady && showCollapsedText && !root.mediaStopping

            clip: true
            transformOrigin: Item.Left
            // The collapsed label appears only when collapsing (last 20% of animation).
            // During expansion it is immediately hidden so it never overlaps the full view.
            opacity: root.mediaTransitionActive
                ? (root.mediaTransitionCollapsing
                    ? (root.mediaFlightEnabled ? (root.mediaFlightActive ? 0.0 : 1.0) : root.mediaHandoffBlend)
                    : 0.0)
                : (activeState ? 1.0 : 0.0)
            scale: (activeState || (root.mediaTransitionActive && root.mediaTransitionCollapsing)) ? 1.0 : 0.95
            visible: activeState || opacity > 0.01

            Behavior on opacity {
                // mediaFlightEnabled is known before the transition flag flips, so the
                // label cuts out/in exactly when the flight takes over/lands instead of
                // fading on its own (that fade showed up as a ghost under the flight).
                enabled: !root.mediaTransitionActive && !root.mediaFlightEnabled
                NumberAnimation {
                    // Fade in after island has started expanding (OutCubic),
                    // fade out quickly before island collapses (InQuad).
                    duration: root.mediaStopping ? 200 : (collapsedTextContainer.activeState ? 260 : 180)
                    easing.type: root.mediaStopping ? Easing.InQuad : (collapsedTextContainer.activeState ? Easing.OutCubic : Easing.InCubic)
                }
            }
            Behavior on scale {
                enabled: !root.mediaTransitionActive
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            transform: Translate {
                x: (collapsedTextContainer.activeState || root.mediaTransitionActive) ? 0 : (root.mediaStopping ? -24 : 24)
                Behavior on x {
                    enabled: !root.mediaTransitionActive
                    NumberAnimation { duration: root.mediaStopping ? 200 : 200; easing.type: root.mediaStopping ? Easing.InCubic : Easing.OutCubic }
                }
            }

            readonly property string targetText: (root.notifActive ? ("Notif (" + root.notifCount + ")") : (root.mediaPlaying ? root.currentMediaText : root.lastTrackText))

            property string displayedText: ""
            property bool useSlotA: true
            // The outgoing slot direction is captured for each transition so
            // a subsequent metadata signal cannot change a running animation.
            property int pushOutY: -18
            readonly property real currentSlotImplicitWidth: useSlotA ? slotA.implicitWidth : slotB.implicitWidth
            readonly property alias collapsedText: slotA

            Component.onCompleted: {
                displayedText = targetText
                slotA.text = targetText
                slotA.y = 0
                slotA.opacity = 1.0
                slotB.y = 18
                slotB.opacity = 0.0
                useSlotA = true
            }

            // Stop any in-flight crossfade and restore exactly one visible
            // slot. Browser MPRIS providers can emit several metadata signals
            // for one track change; overlapping slot animations made the old
            // and new titles render over each other.
            function settleTrackSlots() {
                slotPushAnimA.stop()
                slotPushAnimB.stop()
                if (useSlotA) {
                    slotA.y = 0
                    slotA.opacity = 1.0
                    slotB.y = 18
                    slotB.opacity = 0.0
                } else {
                    slotB.y = 0
                    slotB.opacity = 1.0
                    slotA.y = 18
                    slotA.opacity = 0.0
                }
            }

            function updateTrackPush(newTitle, isNext) {
                if (!newTitle || newTitle === displayedText) return

                // The previous transition's destination is represented by
                // useSlotA. Snap to it before assigning the next destination.
                settleTrackSlots()

                if (!activeState || opacity <= 0.5 || root.expanded || root.autoExpanded) {
                    displayedText = newTitle
                    if (useSlotA)
                        slotA.text = newTitle
                    else
                        slotB.text = newTitle
                    settleTrackSlots()
                    return
                }

                displayedText = newTitle
                pushOutY = isNext ? -18 : 18
                const incomingY = -pushOutY

                if (useSlotA) {
                    slotB.text = newTitle
                    slotB.y = incomingY
                    slotB.opacity = 0.0
                    useSlotA = false
                    slotPushAnimB.restart()
                } else {
                    slotA.text = newTitle
                    slotA.y = incomingY
                    slotA.opacity = 0.0
                    useSlotA = true
                    slotPushAnimA.restart()
                }
            }

            onActiveStateChanged: {
                if (!activeState) settleTrackSlots()
            }

            onTargetTextChanged: {
                root.restartGlobalMarquee()
                updateTrackPush(targetText, root.isNextTrack)
                root.isNextTrack = true
            }

            ParallelAnimation {
                id: slotPushAnimB
                NumberAnimation {
                    target: slotA
                    property: "y"
                    to: collapsedTextContainer.pushOutY
                    duration: 220
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotA
                    property: "opacity"
                    to: 0.0
                    duration: 200
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotB
                    property: "y"
                    to: 0
                    duration: 320
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.15
                }
                NumberAnimation {
                    target: slotB
                    property: "opacity"
                    to: 1.0
                    duration: 280
                    easing.type: Easing.OutQuad
                }
            }

            ParallelAnimation {
                id: slotPushAnimA
                NumberAnimation {
                    target: slotB
                    property: "y"
                    to: collapsedTextContainer.pushOutY
                    duration: 220
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotB
                    property: "opacity"
                    to: 0.0
                    duration: 200
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: slotA
                    property: "y"
                    to: 0
                    duration: 320
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.15
                }
                NumberAnimation {
                    target: slotA
                    property: "opacity"
                    to: 1.0
                    duration: 280
                    easing.type: Easing.OutQuad
                }
            }

            Text {
                id: slotA
                text: collapsedTextContainer.targetText
                font.pixelSize: 11
                font.bold: true
                color: Services.Theme.textPrimary
                width: Math.max(implicitWidth, collapsedTextContainer.width)
                horizontalAlignment: (implicitWidth > collapsedTextContainer.width) ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 1.0
                y: 0
                readonly property real maxScroll: Math.max(0, implicitWidth - collapsedTextContainer.width + 8)
                x: (maxScroll > 0 && collapsedTextContainer.useSlotA && !slotPushAnimA.running && !slotPushAnimB.running) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                elide: Text.ElideNone
            }

            Text {
                id: slotB
                text: ""
                font.pixelSize: 11
                font.bold: true
                color: Services.Theme.textPrimary
                width: Math.max(implicitWidth, collapsedTextContainer.width)
                horizontalAlignment: (implicitWidth > collapsedTextContainer.width) ? Text.AlignLeft : Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                opacity: 0.0
                y: 18
                readonly property real maxScroll: Math.max(0, implicitWidth - collapsedTextContainer.width + 8)
                x: (maxScroll > 0 && !collapsedTextContainer.useSlotA && !slotPushAnimA.running && !slotPushAnimB.running) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                elide: Text.ElideNone
            }
        }

        // ==================== Expanded: Notifications ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && (root.slot0Activity === "notif") && !root.dropWorkflowActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.35 } }

            // Header: Icon, AppName, Queue Indicator, Controls & Close
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // App Icon / Image
                Item {
                    implicitWidth: 20
                    implicitHeight: 20
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: appIconImg
                        anchors.fill: parent
                        source: {
                            if (!root.currentNotif) return ""
                            const src = root.currentNotif.image || root.currentNotif.appIcon || ""
                            if (!src) return ""
                            if (src.startsWith("file://") || src.startsWith("http://") || src.startsWith("https://"))
                                return src
                            if (src.startsWith("/"))
                                return "file://" + src
                            if (Services.SystemTheme) {
                                const res = Services.SystemTheme.getIcon(src)
                                if (res && res.length > 0) return res
                            }
                            const qp = Quickshell.iconPath(src, true)
                            return (qp && qp.startsWith("/")) ? ("file://" + qp) : (qp || "")
                        }
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        sourceSize: Qt.size(40, 40)
                        visible: status === Image.Ready && source.toString().length > 0
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰂚"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 14
                        color: Services.Theme.accent
                        visible: !appIconImg.visible
                    }
                }

                // App Name
                Text {
                    text: root.currentNotif ? root.currentNotif.appName : ""
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Queue indicator & Navigation if multiple notifications
                RowLayout {
                    spacing: 4
                    visible: root.notifCount > 1 && !root.replyMode
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        color: Services.Theme.surfaceVariant
                        radius: 8
                        implicitWidth: queueText.implicitWidth + 10
                        implicitHeight: 18

                        Text {
                            id: queueText
                            anchors.centerIn: parent
                            text: (root.activeNotifIndex + 1) + "/" + root.notifCount
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: true
                        }
                    }

                    // Prev Notif Button
                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20
                        radius: 10
                        color: prevMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: "‹"; color: Services.Theme.textPrimary; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => { root.prevNotif(); mouse.accepted = true }
                        }
                    }

                    // Next Notif Button
                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20
                        radius: 10
                        color: nextMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Text { anchors.centerIn: parent; text: "›"; color: Services.Theme.textPrimary; font.pixelSize: 14; font.bold: true }
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => { root.nextNotif(); mouse.accepted = true }
                        }
                    }
                }

                // Dismiss Button (X)
                Rectangle {
                    implicitWidth: 20; implicitHeight: 20
                    radius: 10
                    color: dismissBtnMouse.containsMouse ? Services.Theme.danger : Services.Theme.surfaceVariant
                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: dismissBtnMouse.containsMouse ? "#ffffff" : Services.Theme.textPrimary
                        font.pixelSize: 10
                        font.bold: true
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: dismissBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (root.currentNotif) {
                                root.replyMode = false
                                Services.Notifications.dismiss(root.currentNotif.notifId)
                            }
                            mouse.accepted = true
                        }
                    }
                }
            }

            // Summary & Body (Only when NOT in Reply Mode)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: !root.replyMode

                Text {
                    text: root.currentNotif ? (root.currentNotif.summary || "") : ""
                    color: Services.Theme.textPrimary
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.hasNotifBody
                    text: root.currentNotif ? (root.currentNotif.body || "") : ""
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Action Buttons (Only when NOT in Reply Mode)
            RowLayout {
                id: notifActionsRow
                visible: root.hasNotifActions && !root.replyMode
                spacing: 6
                Layout.topMargin: 2
                Layout.fillWidth: true

                Repeater {
                    model: root.currentNotif ? root.currentNotif.actions : null
                    delegate: Rectangle {
                        id: actBtn
                        required property string identifier
                        required property string text

                        implicitHeight: 24
                        implicitWidth: actLabel.implicitWidth + 16
                        radius: Services.Theme.radiusSm
                        color: actMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.surfaceVariant

                        Text {
                            id: actLabel
                            anchors.centerIn: parent
                            text: actBtn.text
                            color: Services.Theme.textPrimary
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                if (root.currentNotif) {
                                    if (root.isReplyAction(actBtn)) {
                                        root.activeReplyActionId = actBtn.identifier
                                        root.replyMode = true
                                    } else {
                                        Services.Notifications.invokeAction(root.currentNotif.notifId, actBtn.identifier)
                                    }
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }

            // ==================== Type Zone (Inline Reply Mode) ====================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.replyMode

                Text {
                    text: root.currentNotif ? ("Reply: " + (root.currentNotif.summary || root.currentNotif.appName)) : "Reply Notification"
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 8
                    color: Services.Theme.surfaceVariant
                    border.color: replyInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                    border.width: 1

                    TextInput {
                        id: replyInput
                        anchors.fill: parent
                        anchors.margins: 6
                        color: Services.Theme.textPrimary
                        font.pixelSize: 12
                        clip: true
                        focus: root.replyMode

                        Text {
                            text: (root.currentNotif && root.currentNotif.inlineReplyPlaceholder) ? root.currentNotif.inlineReplyPlaceholder : "Write a reply..."
                            color: Services.Theme.textDisabled
                            font.pixelSize: 12
                            visible: replyInput.text.length === 0 && !replyInput.activeFocus
                        }

                        Keys.onReturnPressed: {
                            if (root.currentNotif && replyInput.text.trim().length > 0) {
                                const msg = replyInput.text.trim()
                                const nId = root.currentNotif.notifId
                                const aId = root.activeReplyActionId
                                root.replyMode = false
                                replyInput.text = ""
                                Services.Notifications.invokeAction(nId, aId, msg)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    // Cancel Button
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: cancelTxt.implicitWidth + 14
                        radius: 6
                        color: cancelMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.surfaceVariant

                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.bold: true
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                root.replyMode = false
                                replyInput.text = ""
                                mouse.accepted = true
                            }
                        }
                    }

                    // Send Button
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: sendRow.implicitWidth + 16
                        radius: 6
                        color: sendMouse.containsMouse ? Qt.lighter(Services.Theme.accent, 1.1) : Services.Theme.accent

                        RowLayout {
                            id: sendRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Send"
                                font.family: Services.Theme.fontMono
                                color: Services.Theme.bgOnAccent
                                font.pixelSize: 10
                                font.bold: true
                            }

                            Text {
                                text: Services.Icons.send || "\uf1d8"
                                font.family: Services.Theme.fontSymbols
                                color: Services.Theme.bgOnAccent
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (root.currentNotif && replyInput.text.trim().length > 0) {
                                    const msg = replyInput.text.trim()
                                    const nId = root.currentNotif.notifId
                                    const aId = root.activeReplyActionId
                                    root.replyMode = false
                                    replyInput.text = ""
                                    Services.Notifications.invokeAction(nId, aId, msg)
                                }
                                mouse.accepted = true
                            }
                        }
                    }
                }
            }
        }

        // ==================== Expanded: System HUD Alert (Mute, DnD, Charging, CapsLock) ====================
        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10
            readonly property bool activeState: (root.sysHudTitle.includes("Caps Lock") || root.sysHudTitle.includes("Welcome") || !Services.OverlayManager.isLocked) && root.expanded && (root.slot0Activity === "syshud") && !root.wallpaperMode && !root.dropWorkflowActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.7
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            Rectangle {
                id: sysHudBubble
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: Services.Theme.surfaceVariant
                Layout.alignment: Qt.AlignVCenter
                clip: true

                transform: Scale {
                    id: sysHudBubbleScale
                    origin.x: 16
                    origin.y: 16
                    xScale: 1.0
                    yScale: 1.0
                }

                SequentialAnimation {
                    id: sysHudBubblePunch
                    ParallelAnimation {
                        NumberAnimation { target: sysHudBubbleScale; property: "xScale"; to: 1.15; duration: 90; easing.type: Easing.OutQuad }
                        NumberAnimation { target: sysHudBubbleScale; property: "yScale"; to: 1.15; duration: 90; easing.type: Easing.OutQuad }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: sysHudBubbleScale; property: "xScale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                        NumberAnimation { target: sysHudBubbleScale; property: "yScale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                    }
                }

                property string hudCurrentIcon: root.sysHudIcon
                property color hudCurrentColor: root.sysHudColor
                property bool hudUseSlotA: true

                onHudCurrentIconChanged: {
                    sysHudBubblePunch.restart()
                    if (hudUseSlotA) {
                        hudSlotB.text = hudCurrentIcon
                        hudSlotB.color = hudCurrentColor
                        hudSlotAAnimOut.restart()
                        hudSlotBAnimIn.restart()
                        hudUseSlotA = false
                    } else {
                        hudSlotA.text = hudCurrentIcon
                        hudSlotA.color = hudCurrentColor
                        hudSlotBAnimOut.restart()
                        hudSlotAAnimIn.restart()
                        hudUseSlotA = true
                    }
                }

                onHudCurrentColorChanged: {
                    if (hudUseSlotA) {
                        hudSlotA.color = hudCurrentColor
                    } else {
                        hudSlotB.color = hudCurrentColor
                    }
                }

                Text {
                    id: hudSlotA
                    anchors.centerIn: parent
                    text: root.sysHudIcon
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 15
                    color: root.sysHudColor
                    opacity: 1.0
                    scale: 1.0
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                Text {
                    id: hudSlotB
                    anchors.centerIn: parent
                    text: ""
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 15
                    color: root.sysHudColor
                    opacity: 0.0
                    scale: 0.4
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                ParallelAnimation {
                    id: hudSlotAAnimIn
                    NumberAnimation { target: hudSlotA; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hudSlotA; property: "scale"; from: 0.4; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    id: hudSlotAAnimOut
                    NumberAnimation { target: hudSlotA; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
                    NumberAnimation { target: hudSlotA; property: "scale"; to: 0.4; duration: 160; easing.type: Easing.InQuad }
                }

                ParallelAnimation {
                    id: hudSlotBAnimIn
                    NumberAnimation { target: hudSlotB; property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hudSlotB; property: "scale"; from: 0.4; to: 1.0; duration: 260; easing.type: Easing.OutBack }
                }
                ParallelAnimation {
                    id: hudSlotBAnimOut
                    NumberAnimation { target: hudSlotB; property: "opacity"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
                    NumberAnimation { target: hudSlotB; property: "scale"; to: 0.4; duration: 160; easing.type: Easing.InQuad }
                }

                // Red Cross overlay when Caps Lock is Off with smooth rotation & spring pop
                Text {
                    id: capsOffCross
                    anchors.centerIn: parent
                    text: "✕"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 12
                    font.bold: true
                    color: Services.Theme.danger
                    readonly property bool isCapsOff: root.sysHudTitle === "Caps Lock Off"
                    opacity: isCapsOff ? 1.0 : 0.0
                    scale: isCapsOff ? 1.0 : 0.1
                    rotation: isCapsOff ? 0 : -45
                    visible: opacity > 0.01

                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Text {
                    text: root.sysHudTitle
                    color: Services.Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: root.sysHudDetail.length > 0
                    text: root.sysHudDetail
                    color: Services.Theme.textSecondary
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // ==================== Expanded: Media View (Adaptive Peek & Full Controls) ====================
        Item {
            id: mediaView
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter

            width: (root.isMediaPeek || (root.mediaWasPeek && !root.expanded))
                ? (root.mediaPeekAdaptiveWidth - 24)
                : 336
            height: (root.isMediaPeek || (root.mediaWasPeek && !root.expanded))
                ? 34
                : 120

            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && (root.slot0Activity === "media") && !root.wallpaperMode && !root.dropWorkflowActive
            // True for the peek capsule AND for its closing morph. Everything that changes the
            // row's layout height must key off this, not off isMediaPeek alone: isMediaPeek goes
            // false on the very first frame of the close.
            readonly property bool peekShape: root.isMediaPeek || (root.mediaWasPeek && !root.expanded)
            visible: activeState || root.mediaTransitionActive || opacity > 0.01
            // Keep this canvas opaque while it is clipped by the changing island shell.
            // The album artwork itself is the single moving object; text fades separately.
            opacity: (activeState || root.mediaTransitionActive) ? 1.0 : 0.0
            scale: 1.0
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            // Peek only: during the shell morph the canvas was sitting at the centre of the FINAL
            // 54px capsule while the capsule was still 32px tall (cover hung out of the bottom on
            // open and dragged down on close). Re-centre it on the live shell height. This is 0
            // whenever the anchor already tracks the shell, so it cannot over-correct.
            transform: Translate {
                y: ((root.isMediaPeek || root.mediaWasPeek) && root.mediaTransitionActive)
                    ? (island.height / 2 - (mediaView.y + mediaView.height / 2))
                    : 0
            }
            onYChanged: root.dbg("mediaView.y=" + y.toFixed(1) + " island.h=" + island.height.toFixed(1) + " peek=" + root.isMediaPeek + " active=" + root.mediaTransitionActive)

            // Scroll anywhere on the card to change the player's volume (opens the inline volume HUD).
            WheelHandler {
                enabled: mediaView.activeState && !root.isMediaPeek && !root.mediaTransitionActive
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => { root.adjustMediaVolume(event.angleDelta.y > 0 ? 0.05 : -0.05) }
            }

            // Row 1: Track Art (left) + Info column (title, artist, progress, controls) + peek visualizer
            ColumnLayout {
                anchors.fill: parent
                spacing: 0

            // Header: cover + (title, artist, quick actions)
            RowLayout {
                id: mediaHeaderRow
                Layout.fillWidth: true
                Layout.preferredHeight: mediaView.peekShape ? 34 : 60
                spacing: (root.isMediaPeek || (root.mediaWasPeek && !root.expanded)) ? 10 : 12
                Behavior on spacing { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }

                // Artwork Container: Morphs between a 34px peek tile and a 60px full cover.
                Item {
                    id: mediaArtWrapper
                    readonly property real restingSize: (root.isMediaPeek || (root.mediaWasPeek && !root.expanded)) ? 34.0 : 60.0

                    // ── Art URL caching ──────────────────────────────────────────────
                    // Keep the last valid art URL so the artwork never goes blank when
                    // the MPRIS provider clears trackArtUrl between tracks or during a
                    // transition. The image is only truly replaced, never blanked.
                    readonly property string liveArtSource: root.activePlayer
                        ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "")
                        : ""
                    property string cachedArtSource: ""
                    onLiveArtSourceChanged: if (liveArtSource !== "") cachedArtSource = liveArtSource
                    Component.onCompleted: if (liveArtSource !== "") cachedArtSource = liveArtSource

                    // Keep the layout slot at its resting size. Only the visual
                    // transform changes during collapsed<->media handoff, so the
                    // parent RowLayout does not need to solve a new layout per frame.
                    implicitWidth: restingSize
                    implicitHeight: restingSize
                    Layout.alignment: Qt.AlignVCenter
                    onOpacityChanged: if (root.debugMedia && (opacity < 0.02 || opacity > 0.98)) root.dbg("art opacity=" + opacity.toFixed(2) + " visible=" + visible + " progress=" + root.mediaTransitionProgress.toFixed(2) + " active=" + root.mediaTransitionActive + " wasPeek=" + root.mediaWasPeek + " peek=" + root.isMediaPeek)

                    // Click the cover to bring the player window forward (only when the player supports it).
                    Rectangle {
                        anchors.fill: parent
                        z: 9
                        radius: mediaArtWrapper.artRadius
                        color: "#000000"
                        opacity: coverOpenArea.containsMouse ? 0.34 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u2197"
                            color: "#ffffff"
                            font.pixelSize: 20
                            font.bold: true
                        }
                    }
                    MouseArea {
                        id: coverOpenArea
                        anchors.fill: parent
                        z: 10
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: mediaView.activeState && !root.isMediaPeek && !root.mediaTransitionActive && (root.activePlayer?.canRaise ?? false)
                        onClicked: (mouse) => { root.activePlayer.raise(); mouse.accepted = true }
                    }
                    opacity: root.mediaTransitionActive
                        ? (1.0 - root.mediaCoverHandoff)
                        : (mediaView.activeState ? 1.0 : 0.0)

                    // Corner radius follows the flight so it lands exactly on the thumbnail's
                    // squircle (0.3 * size) once the scale is applied: no shape pop at handoff.
                    readonly property real artRadius: {
                        const peekShape = root.isMediaPeek || (root.mediaWasPeek && !root.expanded)
                        const base = peekShape ? (width / 2) : 16.0
                        if (!root.mediaTransitionActive) return base
                        return base + ((0.3 * restingSize) - base) * root.mediaTransitionProgress
                    }
                    scale: root.mediaTransitionActive
                        ? (16.0 + ((restingSize - 16.0) * (1.0 - root.mediaTransitionProgress))) / restingSize
                        : 1.0
                    transformOrigin: (root.isMediaPeek || (root.mediaWasPeek && !root.expanded)) ? Item.Left : Item.Center

                    // Keep a gentle size transition for peek <-> full mode, but
                    // disable it during collapsed <-> media handoff because the
                    // shared progress already animates implicitWidth/Height.
                    Behavior on implicitWidth {
                        enabled: !root.mediaTransitionActive
                        NumberAnimation { duration: 380; easing.type: Easing.InOutCubic }
                    }
                    Behavior on implicitHeight {
                        enabled: !root.mediaTransitionActive
                        NumberAnimation { duration: 380; easing.type: Easing.InOutCubic }
                    }

                    // The cover now sits at the TOP of the card, so the old fixed deltas (-22, 0) are
                    // gone. Start = where the cover really is (island coordinates, read live from its
                    // parent so this Translate cannot feed back into itself); end = the pill thumbnail's
                    // slot (centre x 20, 16px, vertically centred on the island). Scaling about the same
                    // reference point (centre, or left-centre for the peek tile) keeps the handoff exact.
                    transform: Translate {
                        id: artSlideTranslate
                        readonly property bool peekish: root.isMediaPeek || root.mediaWasPeek
                        readonly property point cur: {
                            island.height; island.width; root.mediaTransitionProgress
                            return mediaArtWrapper.parent.mapToItem(island,
                                mediaArtWrapper.x + (peekish ? 0 : mediaArtWrapper.width / 2),
                                mediaArtWrapper.y + mediaArtWrapper.height / 2)
                        }
                        x: root.mediaTransitionActive
                            ? (12 + (peekish ? 0 : 8) - cur.x) * root.mediaTransitionProgress
                            : 0
                        y: root.mediaTransitionActive
                            ? (island.height / 2 - cur.y) * root.mediaTransitionProgress
                            : 0
                    }

                    // 1. Layer Konten Gambar + MSAA Buffer
                    Item {
                        id: mediaArtContent
                        anchors.fill: parent
                        layer.enabled: true
                        layer.smooth: true
                        layer.mipmap: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: mediaArtMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 0.5
                        }

                        // Inner spinning disc (Artwork spins smoothly in peek mode, resets to 0deg in full controls)
                        Item {
                            id: mediaArtSpinContainer
                            anchors.fill: parent
                            transformOrigin: Item.Center
                            rotation: 0

                            readonly property bool shouldSpin: root.mediaPlaying && root.isMediaPeek && !root.mediaTransitionActive && (mediaArtImg.status === Image.Ready)

                            function startSpinFromCurrentAngle() {
                                spinAnim.from = mediaArtSpinContainer.rotation
                                spinAnim.to = mediaArtSpinContainer.rotation + 360
                                spinAnim.start()
                            }

                            onShouldSpinChanged: {
                                if (shouldSpin) {
                                    spinAnim.stop()
                                    startSpinFromCurrentAngle()
                                } else {
                                    spinAnim.stop()
                                    resetRotationAnim.restart()
                                }
                            }

                            NumberAnimation {
                                id: resetRotationAnim
                                target: mediaArtSpinContainer
                                property: "rotation"
                                to: 0
                                duration: 320
                                easing.type: Easing.OutCubic
                            }

                            Component.onCompleted: {
                                if (shouldSpin) startSpinFromCurrentAngle()
                            }

                            // Base background fallback
                            Rectangle {
                                anchors.fill: parent
                                color: Services.Theme.surfaceVariant
                            }

                            // High-Res Resampled Album Artwork
                            // Source prefers the live URL; falls back to the cached URL so
                            // the artwork frame is never blank while a new image is loading.
                            Image {
                                id: mediaArtImg
                                anchors.fill: parent
                                source: mediaArtWrapper.liveArtSource !== ""
                                    ? mediaArtWrapper.liveArtSource
                                    : mediaArtWrapper.cachedArtSource
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                                mipmap: true
                                antialiasing: true
                                sourceSize: Qt.size(102, 102)
                                // Show as soon as ready; also show while loading (status
                                // = Image.Loading) so the cached frame stays visible and
                                // the music-note fallback never flickers through.
                                opacity: (source !== "" && (status === Image.Ready || status === Image.Loading)) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                            }

                            // Smooth subtle vinyl rotation while in peek
                            RotationAnimation {
                                id: spinAnim
                                target: mediaArtSpinContainer
                                property: "rotation"
                                from: 0
                                to: 360
                                direction: RotationAnimation.Clockwise
                                duration: 12000
                                loops: Animation.Infinite
                            }

                            // The current angle is intentionally preserved outside peek.
                        }

                        // Fallback Music Symbol — only shows when there is genuinely
                        // no artwork (neither loading nor ready). During Image.Loading
                        // the cached frame is already visible, so this never flickers.
                        Text {
                            anchors.centerIn: parent
                            text: (root.activePlayer && root.activePlayer.identity) ? Services.Icons.playerIcon(root.activePlayer.identity) : "󰎈"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: root.isMediaPeek ? 15 : 28
                            color: Services.Theme.accent
                            // Hidden whenever the image is loading OR ready — only shown
                            // when there is truly no artwork (source empty or Error).
                            opacity: (mediaArtImg.source !== ""
                                && (mediaArtImg.status === Image.Ready
                                    || mediaArtImg.status === Image.Loading)) ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                            Behavior on font.pixelSize { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                    }

                    // 2. High-Precision Mask (Morphs radius width/2 in peek -> 10 in full)
                    Item {
                        id: mediaArtMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        layer.smooth: true

                        Rectangle {
                            anchors.fill: parent
                            radius: mediaArtWrapper.artRadius
                            color: "#ffffff"
                            antialiasing: true
                            smooth: true
                            Behavior on radius {
                                enabled: !root.mediaTransitionActive
                                NumberAnimation { duration: 320; easing.type: Easing.InOutCubic }
                            }
                        }
                    }

                    // 3. Sub-Pixel Rim Overlay (Morphs radius with mask)
                    Rectangle {
                        anchors.fill: parent
                        radius: mediaArtWrapper.artRadius
                        color: "transparent"
                        border.color: Qt.rgba(255, 255, 255, (root.isMediaPeek || (root.mediaWasPeek && !root.expanded)) ? 0.14 : 0.08)
                        border.width: 1
                        antialiasing: true
                        smooth: true
                        z: 3
                        Behavior on radius { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 250 } }
                    }
                }

                // Info (App Badge, Title, Artist)
                ColumnLayout {
                    id: mediaInfoCol
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    // Preserve title/artist geometry through the closing flight.
                    // The whole media layer is hidden after the handoff, so it does
                    // not need to collapse its internal spacing early.
                    spacing: (root.isMediaPeek || (root.mediaWasPeek && !root.expanded)) ? 0 : 2
                    Behavior on spacing { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

                    opacity: root.mediaTransitionActive
                        ? (root.mediaTransitionCollapsing ? (1.0 - root.mediaHandoffBlend) : root.mediaTextReveal)
                        : (mediaView.activeState ? 1.0 : 0.0)

                    readonly property string fullTitle: root.activePlayer ? (root.stableTrackTitle || "Playing") : "Playing"
                    readonly property string fullArtist: root.activePlayer ? (root.stableTrackArtist || root.stableTrackIdentity || "Now Playing") : "Now Playing"

                    property real returnTargetX: 0
                    property real returnTargetY: 0

                    onFullArtistChanged: {
                        if (!mediaTextSwitchAnim.running) {
                            mediaArtistText.text = fullArtist
                        }
                    }

                    onFullTitleChanged: {
                        root.restartGlobalMarquee()
                        const titleChanged = (mediaTitleText.text !== fullTitle)
                        const isRealTitle = (fullTitle !== "" && fullTitle !== "Playing")
                        const isSettled = (mediaView.activeState && mediaView.opacity > 0.95 && !root.autoExpanded && !root.mediaTransitionActive)
                        if (titleChanged && isRealTitle && isSettled) {
                            mediaTextSwitchAnim.restart()
                        } else {
                            mediaTextSwitchAnim.stop()
                            mediaTitleText.text = fullTitle
                            mediaArtistText.text = fullArtist
                            mediaTitleText.y = 0
                            mediaArtistText.y = 0
                            mediaTitleText.opacity = 1.0
                            mediaArtistText.opacity = 1.0
                        }
                    }

                    SequentialAnimation {
                        id: mediaTextSwitchAnim
                        ParallelAnimation {
                            NumberAnimation { target: mediaTitleText; property: "opacity"; to: 0.0; duration: 90; easing.type: Easing.InQuad }
                            NumberAnimation { target: mediaArtistText; property: "opacity"; to: 0.0; duration: 90; easing.type: Easing.InQuad }
                        }
                        ScriptAction {
                            script: {
                                mediaTitleText.text = mediaInfoCol.fullTitle
                                mediaArtistText.text = mediaInfoCol.fullArtist
                                mediaTitleText.y = 0
                                mediaArtistText.y = 0
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: mediaTitleText; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutQuad }
                            NumberAnimation { target: mediaArtistText; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutQuad }
                        }
                    }


                    // Running Title Text (Seamless physical morph across states)
                    Item {
                        id: mediaTitleContainer
                        Layout.fillWidth: true
                        implicitHeight: mediaTitleText.implicitHeight
                        clip: true
                        opacity: root.mediaFlightActive ? 0.0 : 1.0

                        Text {
                            id: mediaTitleText
                            text: mediaInfoCol.fullTitle
                            color: Services.Theme.textPrimary
                            font.pixelSize: (root.isMediaPeek || (root.mediaTransitionActive && root.mediaWasPeek)) ? 12 : 14
                            font.bold: true
                            width: parent.width
                            readonly property real maxScroll: Math.max(0, implicitWidth - parent.width + 8)
                            x: (maxScroll > 0 && !mediaTextSwitchAnim.running && !root.mediaTransitionActive) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                            elide: (maxScroll > 0 || mediaTextSwitchAnim.running) ? Text.ElideNone : Text.ElideRight
                            Behavior on font.pixelSize { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }

                        // Soft edges instead of a hard cut through a glyph while the label
                        // overflows. The right edge fades out as the text runs out of room to
                        // scroll, the left edge appears once it has scrolled.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            width: 22
                            opacity: Math.max(0.0, Math.min(1.0, (mediaTitleText.maxScroll + mediaTitleText.x - 4) / 18))
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(Services.Theme.bgPure.r, Services.Theme.bgPure.g, Services.Theme.bgPure.b, 0.0) }
                                GradientStop { position: 1.0; color: Services.Theme.bgPure }
                            }
                        }
                        Rectangle {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: 22
                            opacity: Math.max(0.0, Math.min(1.0, (-mediaTitleText.x - 2) / 18))
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Services.Theme.bgPure }
                                GradientStop { position: 1.0; color: Qt.rgba(Services.Theme.bgPure.r, Services.Theme.bgPure.g, Services.Theme.bgPure.b, 0.0) }
                            }
                        }
                    }

                    // Running Artist Text (Seamless physical morph across states)
                    Item {
                        id: mediaArtistContainer
                        Layout.fillWidth: true
                        implicitHeight: mediaArtistText.implicitHeight
                        clip: true
                        visible: mediaInfoCol.fullArtist.length > 0
                        // Peek shows the artist under the title too. peekShape keeps it up while the
                        // peek closes, so it fades with the info column instead of snapping off.
                        opacity: ((root.expanded || mediaView.peekShape) && !root.mediaFlightActive) ? 1.0 : 0.0
                        Behavior on opacity {
                            // Off during the media transition: the flight overlay hands over
                            // to this label in one frame, so it must not fade in on its own.
                            enabled: !root.mediaTransitionActive && !root.mediaFlightEnabled
                            NumberAnimation { duration: root.expanded ? 240 : 120; easing.type: root.expanded ? Easing.OutCubic : Easing.InQuad }
                        }

                        Text {
                            id: mediaArtistText
                            text: mediaInfoCol.fullArtist
                            color: Services.Theme.textSecondary
                            font.pixelSize: (root.isMediaPeek || (root.mediaTransitionActive && root.mediaWasPeek)) ? 10 : 11
                            width: parent.width
                            readonly property real maxScroll: Math.max(0, implicitWidth - parent.width + 8)
                            x: (maxScroll > 0 && !mediaTextSwitchAnim.running && !root.mediaTransitionActive) ? -maxScroll * root.globalMediaMarqueeRatio : 0
                            elide: (maxScroll > 0 || mediaTextSwitchAnim.running) ? Text.ElideNone : Text.ElideRight
                            Behavior on font.pixelSize { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }

                        // Soft edges instead of a hard cut through a glyph while the label
                        // overflows. The right edge fades out as the text runs out of room to
                        // scroll, the left edge appears once it has scrolled.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            width: 22
                            opacity: Math.max(0.0, Math.min(1.0, (mediaArtistText.maxScroll + mediaArtistText.x - 4) / 18))
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Qt.rgba(Services.Theme.bgPure.r, Services.Theme.bgPure.g, Services.Theme.bgPure.b, 0.0) }
                                GradientStop { position: 1.0; color: Services.Theme.bgPure }
                            }
                        }
                        Rectangle {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: 22
                            opacity: Math.max(0.0, Math.min(1.0, (-mediaArtistText.x - 2) / 18))
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: Services.Theme.bgPure }
                                GradientStop { position: 1.0; color: Qt.rgba(Services.Theme.bgPure.r, Services.Theme.bgPure.g, Services.Theme.bgPure.b, 0.0) }
                            }
                        }
                    }

                    // Row 2: quick actions under the artist (volume / open player / sleep timer).
                    // The cover block is 60px tall but title + artist only use ~32px, so this costs no height.
                    Row {
                        id: mediaActionsRow
                        Layout.topMargin: (!mediaView.peekShape && root.activePlayer !== null) ? 3 : 0
                        // Row is a positioner: its implicitHeight is read-only, so size it through the layout.
                        Layout.preferredHeight: (!mediaView.peekShape && root.activePlayer !== null) ? 20 : 0
                        clip: true
                        visible: (!mediaView.peekShape && root.activePlayer !== null) || opacity > 0.01
                        opacity: (!root.isMediaPeek && root.expanded) ? 1.0 : 0.0
                        spacing: 4
                        Behavior on opacity {
                            NumberAnimation { duration: root.expanded ? 240 : 120; easing.type: root.expanded ? Easing.OutCubic : Easing.InQuad }
                        }

                        // Volume: opens the inline slider (scrolling over the card does too)
                        Item {
                            width: 26; height: 20
                            Rectangle {
                                anchors.fill: parent; radius: 7
                                color: (volBtnArea.containsMouse || root.mediaVolHudOpen) ? Services.Theme.surfaceVariant : "transparent"
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: Services.Icons.volumeIcon(root.mediaVolume, root.mediaMuted || root.mediaVolume <= 0.001, Services.Audio.isHeadphone, Services.Audio.isTws)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: root.mediaMuted ? Services.Theme.danger : (root.mediaVolHudOpen ? Services.Theme.accent : Services.Theme.textSecondary)
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                id: volBtnArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (root.mediaVolHudOpen) root.mediaVolHudOpen = false
                                    else root.showMediaVolHud()
                                    mouse.accepted = true
                                }
                            }
                        }

                        // Open the player window
                        Item {
                            width: 24; height: 20
                            visible: root.activePlayer?.canRaise ?? false
                            Rectangle {
                                anchors.fill: parent; radius: 7
                                color: opnArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "\u2197"
                                font.pixelSize: 13
                                font.bold: true
                                color: opnArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                id: opnArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => { root.activePlayer.raise(); mouse.accepted = true }
                            }
                        }

                        // Sleep timer: tap to cycle off -> 15 -> 30 -> 60 min; pauses playback when it runs out
                        Item {
                            width: root.mediaSleepMinutes > 0 ? 48 : 26; height: 20
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Rectangle {
                                anchors.fill: parent; radius: 7
                                color: root.mediaSleepMinutes > 0 ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.18)
                                                                   : (slpArea.containsMouse ? Services.Theme.surfaceVariant : "transparent")
                                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                AlarmIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    active: root.mediaSleepMinutes > 0
                                    c: root.mediaSleepMinutes > 0 ? Services.Theme.accent : (slpArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                    Behavior on c { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.mediaSleepMinutes > 0
                                    text: root.mediaSleepLeft + "m"
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Services.Theme.accent
                                }
                            }
                            MouseArea {
                                id: slpArea; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => { root.cycleMediaSleep(); mouse.accepted = true }
                            }
                        }
                    }

                    function prepareArtworkFlight() {
                        const isReturningFromPeek = (root.isMediaPeek || root.mediaWasPeek) && !root.expanded
                        if (root.isMediaPeek || isReturningFromPeek) {
                            // Peek <-> Collapsed:
                            // Both share leftMargin: 12 and verticalCenter: island.verticalCenter.
                            // With transformOrigin: Item.Left, left edge stays fixed at 12 and
                            // vertical center stays at island.verticalCenter. Flight delta is exactly 0!
                            root.mediaArtFlightX = 0.0
                            root.mediaArtFlightY = 0.0
                        } else {
                            // Full Expanded <-> Collapsed:
                            // Centers are horizontally 22px apart (42px in expanded -> 20px in collapsed).
                            // Vertically, both statusIconContainer and mediaArtWrapper are centered
                            // at island.verticalCenter throughout the entire morph animation. Flight delta Y is 0!
                            root.mediaArtFlightX = -22.0
                            root.mediaArtFlightY = 0.0
                        }
                    }
                }
            }

            // Lower rows: progress + controls span the FULL card width, so the transport sits on the
            // island's centre line (it used to be centred in the narrower column right of the cover).
            ColumnLayout {
                id: mediaLowerRows
                Layout.fillWidth: true
                spacing: 0
                // same reveal/hide curve the old info column applied to these rows
                opacity: mediaInfoCol.opacity

                    // Row 2: Progress Bar & Timers. Scroll over the card (or tap the speaker) and a volume
                    // slider takes this row over for a moment; tap the right-hand time to flip total/remaining.
                    Item {
                        id: mediaProgressRow
                        Layout.fillWidth: true
                        implicitHeight: (!mediaView.peekShape && root.activePlayer !== null) ? 18 : 0
                        Layout.topMargin: (!mediaView.peekShape && root.activePlayer !== null) ? 4 : 0
                        visible: (!mediaView.peekShape && root.activePlayer !== null) || opacity > 0.01
                        opacity: (!root.isMediaPeek && root.expanded) ? 1.0 : 0.0
                        clip: true
                        Behavior on opacity {
                            NumberAnimation { duration: root.expanded ? 240 : 120; easing.type: root.expanded ? Easing.OutCubic : Easing.InQuad }
                        }

                        Text {
                            id: posLabel
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: root.fmtTime(wavyBar.livePosition)
                            color: Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.family: Services.Theme.fontMono
                            opacity: root.mediaVolHudOpen ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            id: durLabel
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: {
                                const len = root.activePlayer?.length ?? 0
                                if (len <= 0) return "--:--"
                                return root.mediaShowRemaining
                                    ? "-" + root.fmtTime(Math.max(0, len - wavyBar.livePosition))
                                    : root.fmtTime(len)
                            }
                            color: durArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                            font.pixelSize: 10
                            font.family: Services.Theme.fontMono
                            opacity: root.mediaVolHudOpen ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            MouseArea {
                                id: durArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                enabled: !root.mediaVolHudOpen
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => { root.mediaShowRemaining = !root.mediaShowRemaining; mouse.accepted = true }
                            }
                        }

                        MediaModule.WavyProgressBar {
                            id: wavyBar
                            anchors {
                                left: posLabel.right; right: durLabel.left
                                leftMargin: 8; rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            height: 18
                            isPlaying: root.mediaPlaying && mediaView.activeState
                            waveColor: Services.Theme.accent
                            trackColor: Services.Theme.surfaceVariant
                            lineWidth: 2.4
                            position: root.activePlayer?.position ?? 0
                            duration: root.activePlayer?.length ?? 0
                            opacity: root.mediaVolHudOpen ? 0.0 : 1.0
                            enabled: !root.mediaVolHudOpen
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            onSeekRequested: (ratio) => {
                                const len = root.activePlayer?.length ?? 0
                                if (len > 0 && root.activePlayer) {
                                    root.activePlayer.position = ratio * len
                                    root.activePlayer.positionChanged()
                                }
                            }
                        }

                        // ---- inline volume HUD ----
                        Item {
                            id: volHud
                            anchors.fill: parent
                            z: 5
                            opacity: root.mediaVolHudOpen ? 1.0 : 0.0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Text {
                                id: volIcon
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                width: 16
                                text: Services.Icons.volumeIcon(root.mediaVolume, root.mediaMuted || root.mediaVolume <= 0.001, Services.Audio.isHeadphone, Services.Audio.isTws)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 13
                                color: Services.Theme.textPrimary
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => { root.toggleMediaMute(); mouse.accepted = true }
                                }
                            }
                            Text {
                                id: volPct
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 44
                                horizontalAlignment: Text.AlignRight
                                text: root.mediaMuted ? "mute" : ((root.mediaVolPerApp ? "" : "sys ") + Math.round(root.mediaVolume * 100) + "%")
                                color: Services.Theme.textSecondary
                                font.pixelSize: 10
                                font.family: Services.Theme.fontMono
                            }
                            Item {
                                id: volTrack
                                anchors {
                                    left: volIcon.right; right: volPct.left
                                    leftMargin: 8; rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                height: 20
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 4; radius: 2
                                    color: Services.Theme.surfaceVariant
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * root.mediaVolume; height: 4; radius: 2
                                    color: root.mediaMuted ? Services.Theme.textSecondary : Services.Theme.accent
                                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * root.mediaVolume - width / 2))
                                    width: volDrag.pressed ? 14 : 11; height: width; radius: width / 2
                                    color: "#ffffff"
                                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: volDrag
                                    anchors.fill: parent
                                    preventStealing: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressedChanged: root.mediaVolDragging = pressed
                                    onPressed: (mouse) => { root.setMediaVolume(mouse.x / width); mouse.accepted = true }
                                    onPositionChanged: (mouse) => { if (pressed) root.setMediaVolume(mouse.x / width) }
                                }
                            }
                        }
                    }

                    // Row 3: Controls. Left: shuffle + back 10s. Centre: prev / play / next (always dead
                    // centre, because both side groups share the leftover width equally). Right: forward 10s + repeat.
                    RowLayout {
                        id: mediaControlsRow
                        Layout.fillWidth: true
                        implicitHeight: (!mediaView.peekShape && root.activePlayer !== null) ? 36 : 0
                        Layout.topMargin: (!mediaView.peekShape && root.activePlayer !== null) ? 2 : 0
                        visible: (!mediaView.peekShape && root.activePlayer !== null) || opacity > 0.01
                        opacity: (!root.isMediaPeek && root.expanded) ? 1.0 : 0.0
                        clip: true
                        spacing: 0
                        Behavior on opacity {
                            NumberAnimation { duration: root.expanded ? 240 : 120; easing.type: root.expanded ? Easing.OutCubic : Easing.InQuad }
                        }

                        // ---- left utilities ----
                        Row {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            // Back 10 s
                            Item {
                                implicitWidth: 28; implicitHeight: 26
                                visible: root.activePlayer?.canSeek ?? false
                                Rectangle {
                                    anchors.fill: parent; radius: 8
                                    color: sbArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u221210"
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: sbArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                scale: sbArea.pressed ? 0.9 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                MouseArea {
                                    id: sbArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => { root.seekBy(-10); mouse.accepted = true }
                                }
                            }
                            // Shuffle
                            Item {
                                implicitWidth: 26; implicitHeight: 26
                                visible: root.activePlayer?.shuffleSupported ?? false
                                Rectangle {
                                    anchors.fill: parent; radius: 8
                                    color: shArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.mediaShuffle
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 12
                                    color: (root.activePlayer?.shuffle ?? false) ? Services.Theme.accent : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: shArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.activePlayer?.shuffleSupported ?? false
                                    onClicked: (mouse) => { root.activePlayer.shuffle = !root.activePlayer.shuffle; mouse.accepted = true }
                                }
                            }

                        }

                        // ---- centre transport ----
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 18

                            // Previous
                            Item {
                                id: mediaPrevBtn
                                implicitWidth: 34; implicitHeight: 34
                                opacity: ((root.activePlayer?.canGoPrevious ?? false) ? 1 : 0.3) * root.mediaCtrlRealOpacity
                                scale: prvArea.pressed ? 0.88 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                Rectangle {
                                    anchors.fill: parent; radius: 17
                                    color: prvArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                QuadIcon {
                                    anchors.centerIn: parent
                                    qa: root.icoPrevA
                                    qb: root.icoPrevB
                                    iconColor: prvArea.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                                    Behavior on iconColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: prvArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: (root.activePlayer?.canGoPrevious ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: root.activePlayer?.canGoPrevious ?? false
                                    onClicked: (mouse) => { root.isNextTrack = false; root.activePlayer.previous(); mouse.accepted = true }
                                }
                            }

                            // Play / Pause (accent-filled). The glyph is a vector quad pair that morphs play <-> pause.
                            Rectangle {
                                id: playGlassBtn
                                implicitWidth: 38; implicitHeight: 38
                                opacity: root.mediaCtrlRealOpacity
                                radius: 19
                                color: playArea.pressed
                                    ? Qt.darker(Services.Theme.accent, 1.15)
                                    : (playArea.containsMouse ? Qt.lighter(Services.Theme.accent, 1.08) : Services.Theme.accent)
                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                scale: playArea.pressed ? 0.92 : (playArea.containsMouse ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                QuadIcon {
                                    anchors.centerIn: parent
                                    qa: root.playIconA(root.mediaPlayIconT)
                                    qb: root.playIconB(root.mediaPlayIconT)
                                    iconColor: Services.Theme.bgOnAccent
                                }

                                MouseArea {
                                    id: playArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: (root.activePlayer?.canTogglePlaying ?? true) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: root.activePlayer?.canTogglePlaying ?? true
                                    onClicked: (mouse) => { root.activePlayer?.togglePlaying(); mouse.accepted = true }
                                }
                            }

                            // Next
                            Item {
                                id: mediaNextBtn
                                implicitWidth: 34; implicitHeight: 34
                                opacity: ((root.activePlayer?.canGoNext ?? false) ? 1 : 0.3) * root.mediaCtrlRealOpacity
                                scale: nxtArea.pressed ? 0.88 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                Rectangle {
                                    anchors.fill: parent; radius: 17
                                    color: nxtArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                QuadIcon {
                                    anchors.centerIn: parent
                                    qa: root.icoNextA
                                    qb: root.icoNextB
                                    iconColor: nxtArea.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                                    Behavior on iconColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: nxtArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: (root.activePlayer?.canGoNext ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: root.activePlayer?.canGoNext ?? false
                                    onClicked: (mouse) => { root.isNextTrack = true; root.activePlayer.next(); mouse.accepted = true }
                                }
                            }
                        }

                        // ---- right utilities (RightToLeft: first declared = rightmost) ----
                        Row {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignVCenter
                            layoutDirection: Qt.RightToLeft
                            spacing: 2

                            // Forward 10 s
                            Item {
                                implicitWidth: 28; implicitHeight: 26
                                visible: root.activePlayer?.canSeek ?? false
                                Rectangle {
                                    anchors.fill: parent; radius: 8
                                    color: sfArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "+10"
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: sfArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                scale: sfArea.pressed ? 0.9 : 1.0
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                                MouseArea {
                                    id: sfArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => { root.seekBy(10); mouse.accepted = true }
                                }
                            }
                            // Repeat
                            Item {
                                implicitWidth: 26; implicitHeight: 26
                                visible: root.activePlayer?.loopSupported ?? false
                                Rectangle {
                                    anchors.fill: parent; radius: 8
                                    color: rpArea.containsMouse ? Services.Theme.surfaceVariant : "transparent"
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 12
                                    text: (root.activePlayer?.loop ?? MprisLoopState.None) === MprisLoopState.Track ? Services.Icons.mediaLoopOne : Services.Icons.mediaLoopAll
                                    color: (root.activePlayer?.loop ?? MprisLoopState.None) !== MprisLoopState.None ? Services.Theme.accent : (rpArea.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: rpArea; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: root.activePlayer?.loopSupported ?? false
                                    onClicked: (mouse) => {
                                        const l = root.activePlayer?.loop ?? MprisLoopState.None
                                        if (l === MprisLoopState.None)           root.activePlayer.loop = MprisLoopState.Playlist
                                        else if (l === MprisLoopState.Playlist)  root.activePlayer.loop = MprisLoopState.Track
                                        else                                     root.activePlayer.loop = MprisLoopState.None
                                        mouse.accepted = true
                                    }
                                }
                            }

                        }
                    }

            }
            }

        }

        // ==================== Media Text Flight (collapsed <-> expanded) ====================
        // One shared pair of labels. Collapsed: "Title • Artist" on a single line.
        // Expanded: Title in the card's title slot, Artist beneath it. p is the same
        // eased timeline as the artwork flight (0 = pill, 1 = card), so text and cover
        // travel together. Both ends are anchored to the island's left edge and vertical
        // center, so island-local coordinates stay valid while the shell resizes.
        Item {
            id: mediaTextFlight
            anchors.fill: parent
            z: 6
            visible: root.mediaFlightActive
            enabled: false

            readonly property real p: 1.0 - root.mediaTransitionProgress

            function mix(a, b) { return a + (b - a) * p }
            function sm(t) {
                const c = Math.max(0.0, Math.min(1.0, t))
                return c * c * (3.0 - 2.0 * c)
            }

            // The artist peels off the shared line slightly after the title (and tucks
            // back in slightly before it on collapse), so the two labels don't move in lockstep.
            readonly property real pa: sm((p - 0.10) / 0.90)
            function mixA(a, b) { return a + (b - a) * pa }

            // Artist POSITION uses two separate curves instead of one diagonal: on expand it
            // drops to its own row first (y done by p~0.5) and only then slides left (x),
            // so it never cuts through the title. Collapse is the exact reverse (slides right
            // on the lower row, then rises). pa stays in charge of the bold->regular crossfade.
            readonly property real paY: sm((p - 0.05) / 0.45)
            readonly property real paX: sm((p - 0.30) / 0.70)
            function mixAX(a, b) { return a + (b - a) * paX }
            function mixAY(a, b) { return a + (b - a) * paY }

            // Clip boxes match the real labels' boxes at both ends (so the handoff is
            // identical), but open up to the whole island mid-flight so glyphs are never
            // sliced while they travel.
            readonly property real clipOpen: sm(p / 0.20) * (1.0 - sm((p - 0.80) / 0.20))
            function clipMix(base, full) { return base + (full - base) * clipOpen }

            TextMetrics { id: tmFull;   font.pixelSize: 11; font.bold: true; text: root.currentMediaText }
            TextMetrics { id: tmArtist; font.pixelSize: 11; font.bold: true; text: root.stableTrackArtist }

            // ---- Collapsed end (pill label: icon 12 + 16 + gap 6 = 34 from the left edge) ----
            readonly property real cw: collapsedTextContainer.width
            readonly property real fullW: tmFull.advanceWidth
            readonly property real scrollMax: Math.max(0, fullW - cw + 8)
            readonly property real collX: 34 + (fullW > cw ? 0 : (cw - fullW) / 2) - scrollMax * root.mediaFlightStartRatio
            readonly property real collArtistXRaw: collX + fullW - tmArtist.advanceWidth
            // With a long title the artist sits far past the pill's visible area. Instead
            // of sweeping in from off-screen, it emerges at the pill's right end and fades
            // in while dropping to its own row.
            readonly property bool artistHiddenStart: collArtistXRaw >= 34 + cw - 4
            readonly property real collArtistX: artistHiddenStart ? (34 + cw - tmArtist.advanceWidth) : collArtistXRaw
            readonly property real artistVis: artistHiddenStart ? sm((p - 0.12) / 0.45) : 1.0
            readonly property real collY: height / 2 - 8

            // ---- Expanded end: read live from the real labels. progress/height are read
            // only so the binding re-evaluates every frame while the shell is resizing. ----
            readonly property point expTitlePos: {
                root.mediaTransitionProgress
                height
                return mediaTitleContainer.mapToItem(mediaTextFlight, 0, 0)
            }
            readonly property point expArtistPos: {
                root.mediaTransitionProgress
                height
                return mediaArtistContainer.mapToItem(mediaTextFlight, 0, 0)
            }

            // Title (+ the bullet, which fades out as the artist leaves the line)
            Item {
                id: flightTitleClip
                clip: true
                x: mediaTextFlight.clipMix(mediaTextFlight.mix(34, mediaTextFlight.expTitlePos.x), 0)
                y: mediaTextFlight.clipMix(mediaTextFlight.mix(mediaTextFlight.collY, mediaTextFlight.expTitlePos.y) - 2, 0)
                width: mediaTextFlight.clipMix(mediaTextFlight.mix(mediaTextFlight.cw, mediaTitleContainer.width), mediaTextFlight.width)
                height: mediaTextFlight.clipMix(mediaTextFlight.mix(16, mediaTitleContainer.height) + 4, mediaTextFlight.height)

                Text {
                    id: flightTitleText
                    text: mediaInfoCol.fullTitle
                    color: Services.Theme.textPrimary
                    font.bold: true
                    // pixelSize is an int: animating it made the title step 11->12->13->14,
                    // re-laying out and re-rasterising glyphs on every step (the visible
                    // "pop"). Lay out once at the largest size and scale smoothly instead.
                    font.pixelSize: 14
                    scale: mediaTextFlight.mix(11 / 14, 1.0)
                    transformOrigin: Item.TopLeft
                    x: mediaTextFlight.mix(mediaTextFlight.collX, mediaTextFlight.expTitlePos.x) - flightTitleClip.x
                    y: mediaTextFlight.mix(mediaTextFlight.collY, mediaTextFlight.expTitlePos.y) - flightTitleClip.y
                }

                Text {
                    id: flightBulletText
                    text: " \u2022 "
                    color: Services.Theme.textPrimary
                    font.bold: true
                    font.pixelSize: 14
                    scale: flightTitleText.scale
                    transformOrigin: Item.TopLeft
                    x: flightTitleText.x + flightTitleText.contentWidth * flightTitleText.scale
                    y: flightTitleText.y
                    opacity: 1.0 - mediaTextFlight.sm(mediaTextFlight.p / 0.30)
                }

                // Pill-side artist: it stays glued to the title's right end (same scale, same
                // baseline) and simply dissolves, so it can never travel through the title.
                Text {
                    id: flightArtistInline
                    text: mediaInfoCol.fullArtist
                    color: Services.Theme.textPrimary
                    font.bold: true
                    font.pixelSize: 14
                    scale: flightTitleText.scale
                    transformOrigin: Item.TopLeft
                    x: flightBulletText.x + flightBulletText.contentWidth * flightBulletText.scale
                    y: flightTitleText.y
                    opacity: 1.0 - mediaTextFlight.sm(mediaTextFlight.p / 0.40)
                }

                // Same soft right edge as the real label, fading in as the flight lands.
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: 22
                    opacity: Math.max(0.0, Math.min(1.0, (mediaTitleText.maxScroll - 4) / 18)) * mediaTextFlight.sm(mediaTextFlight.p) * (1.0 - mediaTextFlight.clipOpen)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(Services.Theme.bgPure.r, Services.Theme.bgPure.g, Services.Theme.bgPure.b, 0.0) }
                        GradientStop { position: 1.0; color: Services.Theme.bgPure }
                    }
                }
            }

            // Card-side artist: sits still on its own row and fades/settles in as the flight
            // lands (the pill-side copy above dissolves at the title's end). No travel path means
            // nothing can cross the title in either direction.
            Item {
                id: flightArtistClip
                clip: true
                readonly property real fade: mediaTextFlight.sm((mediaTextFlight.p - 0.35) / 0.65)
                x: mediaTextFlight.expArtistPos.x
                y: mediaTextFlight.expArtistPos.y - 2
                width: mediaArtistContainer.width
                height: mediaArtistContainer.height + 4

                Text {
                    text: mediaInfoCol.fullArtist
                    color: Services.Theme.textSecondary
                    font.pixelSize: 11
                    x: 0
                    y: 2 + 5 * (1.0 - flightArtistClip.fade)
                    opacity: flightArtistClip.fade
                }

                // Same soft right edge as the real label.
                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: 22
                    opacity: Math.max(0.0, Math.min(1.0, (mediaArtistText.maxScroll - 4) / 18)) * flightArtistClip.fade
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(Services.Theme.bgPure.r, Services.Theme.bgPure.g, Services.Theme.bgPure.b, 0.0) }
                        GradientStop { position: 1.0; color: Services.Theme.bgPure }
                    }
                }
            }
        }

        // ==================== Media Controls <-> Cava Flight ====================
        // This is a real shape morph, not pieces fading: the control icons are vector quads (see
        // QuadIcon), so each vertex travels from the icon outline to a cava bar outline.
        //   prev  : two triangles  -> merge into bar 0
        //   play  : pause bars     -> bars 1 and 2   (the accent disc collapses away behind them)
        //   next  : two triangles  -> merge into bar 3
        // Start corners come live from the real controls, end corners live from the real cava
        // (mapToItem), so both handoffs are exact. Runs on linear flight time t (mediaFlightT).
        Item {
            id: mediaCtrlFlight
            anchors.fill: parent
            z: 6
            visible: root.mediaCtrlFlightActive
            enabled: false

            // 0 = card controls, 1 = cava bars
            readonly property real t: root.mediaFlightT
            function sm(x) {
                const c = Math.max(0.0, Math.min(1.0, x))
                return c * c * (3.0 - 2.0 * c)
            }
            function eio(x) {
                const c = Math.max(0.0, Math.min(1.0, x))
                return 0.5 - 0.5 * Math.cos(Math.PI * c)
            }
            function mc(a, b, k) {
                return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, a.a + (b.a - a.a) * k)
            }
            function sq(local, c) {
                return [c.x + local[0], c.y + local[1], c.x + local[2], c.y + local[3],
                        c.x + local[4], c.y + local[5], c.x + local[6], c.y + local[7]]
            }
            // The bars are already "dancing" while they form, so the real audio-driven cava that takes
            // over at the end is not a frozen-to-moving jump.
            property real phase: 0
            NumberAnimation on phase { from: 0; to: Math.PI * 2; duration: 1100; loops: Animation.Infinite; running: mediaCtrlFlight.visible }
            function bq(i) {
                const x = barX(i)
                const y = vizPos.y
                const hw = bw / 2
                const hh = (barH / 2) * (0.72 + 0.28 * Math.sin(phase + i * 1.9))
                return [x - hw, y - hh, x + hw, y - hh, x + hw, y + hh, x - hw, y + hh]
            }
            // Each piece travels on a slight arc (lifts mid-flight, lands at its slot) instead of a ruler line.
            function arc(q, e, lift) {
                const dy = -lift * Math.sin(Math.PI * Math.max(0.0, Math.min(1.0, e)))
                return [q[0], q[1] + dy, q[2], q[3] + dy, q[4], q[5] + dy, q[6], q[7] + dy]
            }
            function pts(a) {
                return [Qt.point(a[0], a[1]), Qt.point(a[2], a[3]), Qt.point(a[4], a[5]),
                        Qt.point(a[6], a[7]), Qt.point(a[0], a[1])]
            }

            // Held fully opaque while real things fade in beneath it; lets go only at the very ends.
            opacity: (1.0 - sm((0.05 - t) / 0.05)) * (1.0 - sm((t - 0.94) / 0.06))

            // One eased progress per quad, staggered so the bars condense one after another.
            // Both pieces of an icon start (almost) together so the icon stays recognisable while it
            // leaves, and the piece NEARER the cava (the right-hand one) always leads. With the old
            // left-to-right stagger the prev bar overtook its own triangle ("|<" turned into "<|") and
            // one pause bar left the disc before the other (half a pause icon).
            readonly property real span: 0.74
            readonly property real e0b: eio(t / span)                 // prev triangle (right) leads
            readonly property real e0a: eio((t - 0.03) / span)        // prev bar (left) follows
            readonly property real e1: eio((t - 0.05) / span)         // pause bars travel as one unit
            readonly property real e2: eio((t - 0.05) / span)
            readonly property real e3b: eio((t - 0.09) / span)        // next bar (right) leads
            readonly property real e3a: eio((t - 0.12) / span)        // next triangle (left) follows

            // ---- live endpoints (island-local). t/height/width are read only to re-evaluate per frame ----
            readonly property point prevPos: {
                t; height; width
                return mediaPrevBtn.mapToItem(mediaCtrlFlight, mediaPrevBtn.width / 2, mediaPrevBtn.height / 2)
            }
            readonly property point playPos: {
                t; height; width
                return playGlassBtn.mapToItem(mediaCtrlFlight, playGlassBtn.width / 2, playGlassBtn.height / 2)
            }
            readonly property point nextPos: {
                t; height; width
                return mediaNextBtn.mapToItem(mediaCtrlFlight, mediaNextBtn.width / 2, mediaNextBtn.height / 2)
            }
            readonly property point vizPos: {
                t; height; width
                return mediaVisualizer.mapToItem(mediaCtrlFlight, mediaVisualizer.width / 2, mediaVisualizer.height / 2)
            }

            // Cava geometry (mirrors mediaVisualizer: barCount 4, barWidth 2.8, barSpacing 2.2).
            readonly property real bw: 2.8
            readonly property real pitch: 5.0
            readonly property real barH: 10.0
            function barX(i) { return vizPos.x + (i - 1.5) * pitch }

            readonly property color cOn: Services.Theme.textPrimary
            readonly property color cAccent: Services.Theme.accent
            readonly property color cDark: Services.Theme.bgOnAccent
            readonly property color cBar: Services.Theme.success

            // Accent disc behind the play icon: it shrinks away while the pause bars leave it.
            Rectangle {
                x: mediaCtrlFlight.playPos.x - width / 2
                y: mediaCtrlFlight.playPos.y - height / 2
                width: playGlassBtn.width
                height: playGlassBtn.height
                radius: playGlassBtn.radius
                color: mediaCtrlFlight.cAccent
                scale: 1.0 - 0.9 * mediaCtrlFlight.sm(mediaCtrlFlight.e1 / 0.50)
                opacity: 1.0 - mediaCtrlFlight.sm((mediaCtrlFlight.e1 - 0.08) / 0.42)
            }

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 4

                // prev: two triangles -> bar 0
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mediaCtrlFlight.mc(mediaCtrlFlight.cOn, mediaCtrlFlight.cBar, mediaCtrlFlight.sm((mediaCtrlFlight.e0a - 0.35) / 0.5))
                    PathPolyline {
                        path: mediaCtrlFlight.pts(mediaCtrlFlight.arc(root.mixQuad(mediaCtrlFlight.sq(root.icoPrevA, mediaCtrlFlight.prevPos), mediaCtrlFlight.bq(0), mediaCtrlFlight.e0a), mediaCtrlFlight.e0a, 5))
                    }
                }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mediaCtrlFlight.mc(mediaCtrlFlight.cOn, mediaCtrlFlight.cBar, mediaCtrlFlight.sm((mediaCtrlFlight.e0b - 0.35) / 0.5))
                    PathPolyline {
                        path: mediaCtrlFlight.pts(mediaCtrlFlight.arc(root.mixQuad(mediaCtrlFlight.sq(root.icoPrevB, mediaCtrlFlight.prevPos), mediaCtrlFlight.bq(0), mediaCtrlFlight.e0b), mediaCtrlFlight.e0b, 5))
                    }
                }

                // play/pause: two bars -> bars 1 and 2 (dark-on-accent first turns accent, then green)
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mediaCtrlFlight.mc(mediaCtrlFlight.mc(mediaCtrlFlight.cDark, mediaCtrlFlight.cAccent, mediaCtrlFlight.sm(mediaCtrlFlight.e1 / 0.40)), mediaCtrlFlight.cBar, mediaCtrlFlight.sm((mediaCtrlFlight.e1 - 0.50) / 0.45))
                    PathPolyline {
                        path: mediaCtrlFlight.pts(mediaCtrlFlight.arc(root.mixQuad(mediaCtrlFlight.sq(root.playIconA(root.mediaPlayIconT), mediaCtrlFlight.playPos), mediaCtrlFlight.bq(1), mediaCtrlFlight.e1), mediaCtrlFlight.e1, 9))
                    }
                }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mediaCtrlFlight.mc(mediaCtrlFlight.mc(mediaCtrlFlight.cDark, mediaCtrlFlight.cAccent, mediaCtrlFlight.sm(mediaCtrlFlight.e2 / 0.40)), mediaCtrlFlight.cBar, mediaCtrlFlight.sm((mediaCtrlFlight.e2 - 0.50) / 0.45))
                    PathPolyline {
                        path: mediaCtrlFlight.pts(mediaCtrlFlight.arc(root.mixQuad(mediaCtrlFlight.sq(root.playIconB(root.mediaPlayIconT), mediaCtrlFlight.playPos), mediaCtrlFlight.bq(2), mediaCtrlFlight.e2), mediaCtrlFlight.e2, 9))
                    }
                }

                // next: two triangles -> bar 3
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mediaCtrlFlight.mc(mediaCtrlFlight.cOn, mediaCtrlFlight.cBar, mediaCtrlFlight.sm((mediaCtrlFlight.e3a - 0.35) / 0.5))
                    PathPolyline {
                        path: mediaCtrlFlight.pts(mediaCtrlFlight.arc(root.mixQuad(mediaCtrlFlight.sq(root.icoNextA, mediaCtrlFlight.nextPos), mediaCtrlFlight.bq(3), mediaCtrlFlight.e3a), mediaCtrlFlight.e3a, 5))
                    }
                }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: mediaCtrlFlight.mc(mediaCtrlFlight.cOn, mediaCtrlFlight.cBar, mediaCtrlFlight.sm((mediaCtrlFlight.e3b - 0.35) / 0.5))
                    PathPolyline {
                        path: mediaCtrlFlight.pts(mediaCtrlFlight.arc(root.mixQuad(mediaCtrlFlight.sq(root.icoNextB, mediaCtrlFlight.nextPos), mediaCtrlFlight.bq(3), mediaCtrlFlight.e3b), mediaCtrlFlight.e3b, 5))
                    }
                }
            }
        }

        // ==================== Expanded: Wallpaper Studio (Minimalist) ====================
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && root.wallpaperMode && !root.dropWorkflowActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.75
            transformOrigin: Item.Center
            enabled: activeState
            z: 1

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }

            // Row 1: Minimal Header
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 6

                Text {
                    text: "󰋩"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: Services.Theme.accent
                }

                Text {
                    text: "Wallpapers"
                    color: Services.Theme.textPrimary
                    font.pixelSize: Services.Theme.fontSizeSm
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Add Custom Button
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: addBtnMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                    border.color: addBtnMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.borderSubtle
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 13
                        font.bold: true
                        color: addBtnMouse.containsMouse ? Services.Theme.accent : Services.Theme.textSecondary
                    }

                    MouseArea {
                        id: addBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.collapse()
                            if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                        }
                    }
                }

                // Close Button
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: closeIslandWallMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.2) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 10
                        color: closeIslandWallMouse.containsMouse ? "#ef4444" : Services.Theme.textDisabled
                    }

                    MouseArea {
                        id: closeIslandWallMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.collapse()
                    }
                }
            }

            // Row 2: Clean 16:9 Wallpaper Cards Carousel
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: islandWallList
                    anchors.fill: parent
                    anchors.topMargin: 3
                    anchors.bottomMargin: 4
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    focus: root.wallpaperMode
                    currentIndex: root.wallpaperIndex
                    keyNavigationEnabled: false

                    model: root.wallpaperList

                    Keys.onPressed: (event) => {
                        const count = root.wallpaperList ? root.wallpaperList.length : 0
                        if (count === 0) return

                        if (event.key === Qt.Key_Right) {
                            root.wallpaperIndex = (root.wallpaperIndex + 1) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left) {
                            root.wallpaperIndex = (root.wallpaperIndex - 1 + count) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                            root.wallpaperIndex = (root.wallpaperIndex - 1 + count) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            root.wallpaperIndex = (root.wallpaperIndex + 1) % count
                            islandWallList.positionViewAtIndex(root.wallpaperIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (root.wallpaperList && root.wallpaperList.length > root.wallpaperIndex) {
                                const item = root.wallpaperList[root.wallpaperIndex]
                                if (item && item.isAddAction) {
                                    root.collapse()
                                    if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                } else if (item && item.path && Services.Wallpaper) {
                                    Services.Wallpaper.setWallpaper(item.path)
                                }
                            }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.collapse()
                            event.accepted = true
                        }
                    }

                    delegate: Item {
                        id: iWallCell
                        required property var modelData
                        required property int index

                        readonly property bool isAdd: iWallCell.modelData && iWallCell.modelData.isAddAction === true
                        width: isAdd ? 72 : 124
                        height: islandWallList.height

                        readonly property bool isSelected: iWallCell.index === root.wallpaperIndex
                        readonly property bool isActive: !isAdd && Services.Wallpaper && (
                            Services.Wallpaper.currentWallpaper === iWallCell.modelData.path ||
                            (iWallCell.modelData.isDynamic === true && Services.Wallpaper.isWallblerActive)
                        )

                        // Wallpaper Card
                        Item {
                            id: iCardRect
                            anchors.fill: parent
                            anchors.margins: 2
                            visible: !iWallCell.isAdd

                            // Base container holding image + gradient, masked to radius 10
                            Item {
                                id: iCardContent
                                anchors.fill: parent
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: iCardMask
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: Services.Theme.surfaceVariant
                                }

                                Image {
                                    anchors.fill: parent
                                    source: (iWallCell.modelData && iWallCell.modelData.path) ? ("file://" + iWallCell.modelData.path) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize: Qt.size(248, 148)
                                }

                                // Bottom shadow gradient for text readability
                                Rectangle {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                    height: 30
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.45) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
                                    }
                                }
                            }

                            // Rounded Mask Shape
                            Item {
                                id: iCardMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: "black"
                                }
                            }

                            // Dynamic Icon Badge (subtle, top-left)
                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left
                                anchors.margins: 6
                                width: 18; height: 18; radius: 9
                                color: Qt.rgba(0, 0, 0, 0.72)
                                border.color: Qt.rgba(255, 255, 255, 0.25)
                                border.width: 1
                                visible: iWallCell.modelData && iWallCell.modelData.isDynamic === true
                                z: 4

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰖔"
                                    color: "#38bdf8"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 9
                                }
                            }

                            // Active Checkmark Pill (top-right)
                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 6
                                width: 18; height: 18; radius: 9
                                color: Services.Theme.accent
                                border.color: Qt.rgba(255, 255, 255, 0.4)
                                border.width: 1
                                visible: iWallCell.isActive
                                z: 4

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Services.Theme.bgOnAccent
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            // Bottom Wallpaper Title (Crisp, perfectly padded from borders)
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.bottomMargin: 6
                                text: (iWallCell.modelData && iWallCell.modelData.name) ? iWallCell.modelData.name : "Wallpaper"
                                color: Services.Theme.white
                                font.pixelSize: 9
                                font.bold: iWallCell.isActive || iWallCell.isSelected
                                elide: Text.ElideRight
                                z: 4
                            }

                            // Outer Border Ring (Exact 10px radius, perfectly aligned on top of mask)
                            Rectangle {
                                id: iCardBorderOverlay
                                anchors.fill: parent
                                radius: 10
                                color: "transparent"
                                z: 6
                                antialiasing: true
                                border.color: iWallCell.isSelected
                                    ? Services.Theme.accent
                                    : (iWallCell.isActive
                                        ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.45)
                                        : (iWallMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.3) : Qt.rgba(255, 255, 255, 0.10)))
                                border.width: iWallCell.isSelected ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on border.width { NumberAnimation { duration: 150 } }
                            }
                        }

                        // Add Image Card
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 10
                            color: (iAddMouse.containsMouse || iWallCell.isSelected) ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.12) : Qt.rgba(255, 255, 255, 0.03)
                            border.color: (iAddMouse.containsMouse || iWallCell.isSelected) ? Services.Theme.accent : Qt.rgba(255, 255, 255, 0.10)
                            border.width: (iAddMouse.containsMouse || iWallCell.isSelected) ? 2 : 1
                            visible: iWallCell.isAdd

                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Behavior on border.width { NumberAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "+"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Services.Theme.accent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Add"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                id: iAddMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.wallpaperIndex = iWallCell.index
                                onClicked: {
                                    root.collapse()
                                    if (Services.Wallpaper) Services.Wallpaper.pickCustomWallpaper()
                                }
                            }
                        }

                        // Click to set wallpaper
                        MouseArea {
                            id: iWallMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            visible: !iWallCell.isAdd
                            onEntered: root.wallpaperIndex = iWallCell.index
                            onClicked: {
                                root.wallpaperIndex = iWallCell.index
                                if (iWallCell.modelData && iWallCell.modelData.path && Services.Wallpaper) {
                                    Services.Wallpaper.setWallpaper(iWallCell.modelData.path)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==================== Expanded: Drop to Send Hub (KDE Connect & LocalSend) ====================
        Item {
            id: dropSendHubContainer
            anchors.fill: parent
            anchors.margins: 12
            readonly property bool activeState: !Services.OverlayManager.isLocked && root.expanded && !root.wallpaperMode && root.dropWorkflowActive
            visible: activeState || opacity > 0.01
            opacity: activeState ? 1 : 0
            scale: activeState ? 1.0 : 0.94
            transformOrigin: Item.Center
            enabled: activeState
            z: 10

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            // ─── Sub-View 1: Compact destination chooser ───
            ColumnLayout {
                id: dropChooserView
                anchors.fill: parent
                spacing: 6
                visible: root.showDropChooser
                enabled: visible

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    spacing: 7

                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 7
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.17)
                        Text {
                            anchors.centerIn: parent
                            text: "󰄶"
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 12
                            color: Services.Theme.accent
                        }
                    }

                    Text {
                        text: root.dropStagedChoice ? "Choose destination" : "Drop to share"
                        color: Services.Theme.textPrimary
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Rectangle {
                        visible: root.dropFileCount > 0
                        Layout.preferredHeight: 18
                        implicitWidth: fileCountText.implicitWidth + 12
                        radius: 9
                        color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15)
                        Text {
                            id: fileCountText
                            anchors.centerIn: parent
                            text: root.dropFileCount + (root.dropFileCount === 1 ? " file" : " files")
                            color: Services.Theme.accent
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        Layout.maximumWidth: 118
                        visible: root.dropFileName !== ""
                        text: root.dropFileName
                        color: Services.Theme.textSecondary
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }

                    Rectangle {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        radius: 11
                        color: closeDropMouse.containsMouse ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.2) : Qt.rgba(255, 255, 255, 0.06)
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: closeDropMouse.containsMouse ? "#ef4444" : Services.Theme.textSecondary
                            font.pixelSize: 15
                        }
                        MouseArea {
                            id: closeDropMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismissDropChooser()
                        }
                    }
                }

                // Destination cards: each card is a single target. The action
                // affordance sits inline at the end rather than in a separate
                // button row that makes the panel feel tall and fragmented.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Rectangle {
                        id: kdeCard
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        clip: true
                        readonly property bool isHovered: root.dropHoverTarget === "kde" || kdeCardMouse.containsMouse
                        readonly property var dev: Services.DeviceShare ? Services.DeviceShare.defaultDevice : null
                        readonly property bool hasDev: Services.DeviceShare ? Services.DeviceShare.hasKdeDevice : false

                        color: isHovered
                            ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.13)
                            : Qt.rgba(255, 255, 255, 0.045)
                        border.width: isHovered ? 1 : 0
                        border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.48)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 10
                                color: kdeCard.isHovered
                                    ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.2)
                                    : Qt.rgba(255, 255, 255, 0.065)
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄡"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 17
                                    color: kdeCard.hasDev ? Services.Theme.accent : Services.Theme.textDisabled
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5
                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: kdeCard.hasDev ? "#22c55e" : "#eab308"
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "KDE Connect"
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: Services.Theme.textPrimary
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: kdeCard.hasDev ? (kdeCard.dev ? kdeCard.dev.name : "Connected device") : "No paired device"
                                    color: kdeCard.hasDev ? Services.Theme.textSecondary : Services.Theme.textDisabled
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: !kdeCard.hasDev
                                        ? "Pair a device first"
                                        : (root.dropHoverTarget === "kde"
                                            ? "Release to send"
                                            : (root.dropStagedChoice ? "Send file" : "Drop file here"))
                                    color: kdeCard.isHovered ? Services.Theme.accent : Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: root.dropStagedChoice || root.dropHoverTarget === "kde"
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                color: kdeCard.isHovered ? Services.Theme.accent : Qt.rgba(255, 255, 255, 0.07)
                                Text {
                                    anchors.centerIn: parent
                                    text: "›"
                                    color: kdeCard.isHovered ? Services.Theme.bgOnAccent : Services.Theme.textSecondary
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }
                        }

                        DropArea {
                            id: kdeDropTarget
                            anchors.fill: parent
                            enabled: kdeCard.hasDev
                            onEntered: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "kde"
                            }
                            onPositionChanged: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "kde"
                            }
                            onExited: {
                                if (root.dropHoverTarget === "kde") root.dropHoverTarget = ""
                                dropExitDebounceTimer.restart()
                            }
                            onDropped: (drop) => {
                                dropExitDebounceTimer.stop()
                                root.handleDropOnKde(drop.urls)
                            }
                        }

                        MouseArea {
                            id: kdeCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: kdeCard.hasDev ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (kdeCard.hasDev && root.dropStagedChoice && root.dropUrls && root.dropUrls.length > 0)
                                    root.handleDropOnKde(root.dropUrls)
                            }
                        }
                    }

                    Rectangle {
                        id: localCard
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        clip: true
                        readonly property bool isHovered: root.dropHoverTarget === "local" || localCardMouse.containsMouse
                        readonly property bool localSendAvailable: Services.DeviceShare ? Services.DeviceShare.hasLocalSend : true

                        color: isHovered
                            ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.13)
                            : Qt.rgba(255, 255, 255, 0.045)
                        border.width: isHovered ? 1 : 0
                        border.color: Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.48)
                        opacity: localCard.localSendAvailable ? 1.0 : 0.65
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 10
                                color: localCard.isHovered
                                    ? Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.2)
                                    : Qt.rgba(255, 255, 255, 0.065)
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅠"
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 17
                                    color: "#38bdf8"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: "LocalSend"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: Services.Theme.textPrimary
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: localCard.localSendAvailable ? "Nearby devices · LAN" : "LocalSend not found"
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: !localCard.localSendAvailable
                                        ? "Unavailable"
                                        : (root.dropHoverTarget === "local"
                                            ? "Release to send"
                                            : (root.dropStagedChoice ? "Open LocalSend" : "Drop file here"))
                                    color: localCard.isHovered ? "#38bdf8" : Services.Theme.textSecondary
                                    font.pixelSize: 9
                                    font.bold: root.dropStagedChoice || root.dropHoverTarget === "local"
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                radius: 12
                                color: localCard.isHovered ? "#38bdf8" : Qt.rgba(255, 255, 255, 0.07)
                                Text {
                                    anchors.centerIn: parent
                                    text: "›"
                                    color: localCard.isHovered ? "#06131b" : Services.Theme.textSecondary
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }
                        }

                        DropArea {
                            id: localDropTarget
                            anchors.fill: parent
                            enabled: localCard.localSendAvailable
                            onEntered: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "local"
                            }
                            onPositionChanged: (drag) => {
                                dropExitDebounceTimer.stop()
                                root.dropHoverTarget = "local"
                            }
                            onExited: {
                                if (root.dropHoverTarget === "local") root.dropHoverTarget = ""
                                dropExitDebounceTimer.restart()
                            }
                            onDropped: (drop) => {
                                dropExitDebounceTimer.stop()
                                root.handleDropOnLocalSend(drop.urls)
                            }
                        }

                        MouseArea {
                            id: localCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: localCard.localSendAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (localCard.localSendAvailable && root.dropStagedChoice && root.dropUrls && root.dropUrls.length > 0)
                                    root.handleDropOnLocalSend(root.dropUrls)
                            }
                        }
                    }
                }
            }

            // ─── Sub-View 2: LocalSend Handoff (preparing / handoff) ───
            // Shows an honest status strip — no progress bar, no false success claim.
            RowLayout {
                id: localSendHandoffView
                anchors.fill: parent
                spacing: 12
                visible: root.showDropHandoff

                readonly property string previewUrl: (Services.DeviceShare && Services.DeviceShare.transferPreviewUrl !== "") ? Services.DeviceShare.transferPreviewUrl : root.dropPreviewUrl
                readonly property bool hasPreview: previewUrl !== ""
                readonly property bool isPreparing: Services.DeviceShare && (
                    Services.DeviceShare.transferState === "preparing" ||
                    (Services.DeviceShare.transferBackend === "localsend" && Services.DeviceShare.transferState === "sending"))

                // Left icon / thumbnail
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 10
                    color: Services.Theme.surfaceVariant
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        anchors.fill: parent
                        visible: localSendHandoffView.hasPreview
                        source: localSendHandoffView.previewUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !localSendHandoffView.hasPreview
                        text: "󰅠"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 22
                        color: "#38bdf8"
                    }
                }

                // Center: status text
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: localSendHandoffView.isPreparing ? "Preparing LocalSend\u2026" : "Continue in LocalSend"
                        font.bold: true
                        font.pixelSize: 12
                        color: Services.Theme.textPrimary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: localSendHandoffView.isPreparing
                            ? "Opening the app\u2026"
                            : "Complete the transfer in the LocalSend window"
                        font.pixelSize: 10
                        color: Services.Theme.textSecondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // Right: spinner while preparing, checkmark-open while handoff
                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    Layout.alignment: Qt.AlignVCenter
                    color: Qt.rgba(56 / 255, 189 / 255, 248 / 255, 0.15)

                    Text {
                        anchors.centerIn: parent
                        text: localSendHandoffView.isPreparing ? "󰑖" : "󰄶"
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 15
                        color: "#38bdf8"
                    }

                    SequentialAnimation on rotation {
                        running: localSendHandoffView.isPreparing && localSendHandoffView.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: 360; duration: 1000; easing.type: Easing.Linear }
                    }
                }
            }

            // ─── Sub-View 3: KDE Connect Transfer Feedback ───
            // Only shown for real tracked transfers (KDE Connect sending/success/error).
            RowLayout {
                id: transferFeedback
                anchors.fill: parent
                spacing: 12
                visible: root.showDropTransfer

                readonly property string previewUrl: (Services.DeviceShare && Services.DeviceShare.transferPreviewUrl !== "") ? Services.DeviceShare.transferPreviewUrl : root.dropPreviewUrl
                readonly property bool hasPreview: previewUrl !== ""
                readonly property bool isSuccess: Services.DeviceShare && Services.DeviceShare.transferState === "success"
                readonly property bool isError: Services.DeviceShare && Services.DeviceShare.transferState === "error"
                readonly property string targetDevice: Services.DeviceShare ? Services.DeviceShare.transferTargetName : (root.dropFileName || "Device")

                // Left Thumbnail / Icon Squircle
                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 10
                    color: Services.Theme.surfaceVariant
                    clip: true
                    Layout.alignment: Qt.AlignVCenter

                    // Image Preview
                    Image {
                        anchors.fill: parent
                        visible: transferFeedback.hasPreview
                        source: transferFeedback.previewUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    // Fallback Icon if not an image
                    Text {
                        anchors.centerIn: parent
                        visible: !transferFeedback.hasPreview
                        text: transferFeedback.isError ? "󰅚" : (transferFeedback.isSuccess ? "󰄬" : "󰄶")
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 22
                        font.bold: true
                        color: transferFeedback.isError ? Services.Theme.danger : (transferFeedback.isSuccess ? Services.Theme.success : Services.Theme.accent)
                    }

                    // Corner Mini Badge
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 2
                        width: 14
                        height: 14
                        radius: 7
                        color: transferFeedback.isError ? Services.Theme.danger : (transferFeedback.isSuccess ? Services.Theme.success : Services.Theme.accent)
                        visible: transferFeedback.hasPreview

                        Text {
                            anchors.centerIn: parent
                            text: transferFeedback.isError ? "!" : (transferFeedback.isSuccess ? "✓" : "󰄶")
                            font.family: (transferFeedback.isError || transferFeedback.isSuccess) ? Services.Theme.fontPrimary : Services.Theme.fontSymbols
                            font.pixelSize: 8
                            font.bold: true
                            color: "#ffffff"
                        }
                    }
                }

                // Center Progress & Info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Layout.alignment: Qt.AlignVCenter

                    // Top Row: Title + Status Done Pill
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: transferFeedback.isError
                                ? ("Couldn't send to " + transferFeedback.targetDevice)
                                : (transferFeedback.isSuccess
                                    ? ("Sent to " + transferFeedback.targetDevice)
                                    : ("Sending to " + transferFeedback.targetDevice + "..."))
                            font.bold: true
                            font.pixelSize: 12
                            color: Services.Theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Success "Done" Badge
                        Rectangle {
                            visible: transferFeedback.isSuccess
                            Layout.preferredHeight: 16
                            implicitWidth: doneText.implicitWidth + 10
                            radius: 8
                            color: Qt.rgba(34 / 255, 197 / 255, 94 / 255, 0.18)

                            Text {
                                id: doneText
                                anchors.centerIn: parent
                                text: "Done"
                                font.pixelSize: 9
                                font.bold: true
                                color: Services.Theme.success
                            }
                        }
                    }

                    // Animated Glowing Progress Bar (Borderless)
                    Rectangle {
                        id: progressBarTrack
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        radius: 2
                        color: Qt.rgba(255, 255, 255, 0.08)
                        clip: true

                        // Full width fill when success
                        Rectangle {
                            id: progressSuccessBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: transferFeedback.isSuccess ? parent.width : 0
                            color: Services.Theme.success
                            radius: 2

                            Behavior on width {
                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                            }
                        }

                        // Indeterminate glowing sweep beam while sending
                        Rectangle {
                            id: progressSendingBeam
                            visible: root.isDropSending && !transferFeedback.isSuccess
                            width: 140
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Services.Theme.accent }
                                GradientStop { position: 1.0; color: "transparent" }
                            }

                            SequentialAnimation on x {
                                running: progressSendingBeam.visible
                                loops: Animation.Infinite
                                NumberAnimation { from: -140; to: progressBarTrack.width + 40; duration: 1000; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    // Subtitle: File name or transfer message
                    Text {
                        Layout.fillWidth: true
                        text: transferFeedback.isError
                            ? (Services.DeviceShare && Services.DeviceShare.transferMessage !== "" ? Services.DeviceShare.transferMessage : "Transfer failed")
                            : (transferFeedback.isSuccess
                                ? (root.dropFileName !== "" ? root.dropFileName : (Services.DeviceShare ? Services.DeviceShare.transferMessage : "Transfer completed"))
                                : (Services.DeviceShare ? Services.DeviceShare.transferMessage : "Transfer in progress"))
                        font.pixelSize: 10
                        color: Services.Theme.textSecondary
                        elide: Text.ElideRight
                    }
                }

                // Right Status Circle
                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    Layout.alignment: Qt.AlignVCenter
                    color: transferFeedback.isError
                        ? Qt.rgba(239 / 255, 68 / 255, 68 / 255, 0.16)
                        : (transferFeedback.isSuccess
                            ? Qt.rgba(34 / 255, 197 / 255, 94 / 255, 0.18)
                            : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.15))

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        anchors.centerIn: parent
                        text: transferFeedback.isError ? "󰅚" : (transferFeedback.isSuccess ? "󰄬" : "󰄶")
                        font.family: Services.Theme.fontSymbols
                        font.pixelSize: 15
                        color: transferFeedback.isError ? Services.Theme.danger : (transferFeedback.isSuccess ? Services.Theme.success : Services.Theme.accent)
                    }

                    SequentialAnimation on scale {
                        running: root.isDropSending && !transferFeedback.isSuccess
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.12; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

    }

    // ==================== Liquid Bridges (Air Membelah Diri / Metaball Meniscus) ====================
    LiquidSplitBridge {
        id: rightLiquidBridge
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - 32) / 2)
        x: island.x + island.width - 6
        width: Math.max(0, (rightSatDot.x + 6) - (island.x + island.width - 6))
        gap: rightSatDot.leftMarginValue
        isRight: true
        snapped: rightSatDot.bridgeSnapped || root.expanded || root.lockBlocked
        z: 3
    }

    LiquidSplitBridge {
        id: leftLiquidBridge
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - 32) / 2)
        x: leftSatDot.x + leftSatDot.width - 6
        width: Math.max(0, (island.x + 6) - (leftSatDot.x + leftSatDot.width - 6))
        gap: leftSatDot.rightMarginValue
        isRight: false
        snapped: leftSatDot.bridgeSnapped || root.expanded || root.lockBlocked
        z: 3
    }

    // ==================== Right Dynamic Satellite Dot ("Sebelum baru ke kanan") ====================
    Rectangle {
        id: rightSatDot
        readonly property var item: root.slotRightItem
        readonly property string activity: root.slotRightType
        readonly property bool isSatellite: !root.lockBlocked && (!root.mediaStopping || !root.mediaIconTransformed ? activity !== "" : false)
        anchors.left: island.right
        anchors.leftMargin: leftMarginValue
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - implicitHeight) / 2)
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: Services.Theme.bgPure
        border.color: Services.Theme.borderSubtle
        border.width: 1
        z: 1

        property real leftMarginValue: isSatellite ? 8 : -32
        property bool bridgeSnapped: !isSatellite
        property real contentOpacity: isSatellite ? 1.0 : 0.0
        property real contentScale: isSatellite ? 1.0 : 0.5

        opacity: isSatellite ? 1.0 : 0.0
        scale: isSatellite ? 1.0 : 0.0
        visible: isSatellite || opacity > 0 || scale > 0 || rightRetractAnim.running || rightDetachAnim.running

        transform: Scale {
            id: rightTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                rightRetractAnim.stop()
                rightDetachAnim.restart()
            } else {
                rightDetachAnim.stop()
                rightRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: rightDetachAnim

            ScriptAction {
                script: {
                    rightSatDot.visible = true
                    rightSatDot.opacity = 1.0
                    rightSatDot.scale = 1.0
                    rightSatDot.leftMarginValue = -32
                    rightSatDot.bridgeSnapped = false
                    rightSatDot.contentOpacity = 0.0
                    rightSatDot.contentScale = 0.5
                    rightTransform.xScale = 1.0
                    rightTransform.yScale = 1.0
                }
            }

            // Phase 1: Extrusion & Viscous Stretching (0ms -> 200ms)
            ParallelAnimation {
                NumberAnimation {
                    target: rightSatDot
                    property: "leftMarginValue"
                    from: -32
                    to: 7.5
                    duration: 200
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: rightTransform
                    property: "xScale"
                    from: 1.0
                    to: 1.40
                    duration: 200
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: rightTransform
                    property: "yScale"
                    from: 1.0
                    to: 0.72
                    duration: 200
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: root
                    property: "rightIslandBulge"
                    from: 0.0
                    to: 3.0
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }

            // Snap Point: Surface tension reaches critical limit (~200ms)
            ScriptAction {
                script: {
                    rightSatDot.bridgeSnapped = true
                }
            }

            // Phase 2: Damped Fluid Jelly Wobble & Content Blossom (200ms -> 560ms)
            ParallelAnimation {
                // Position settles to 8px
                SequentialAnimation {
                    NumberAnimation {
                        target: rightSatDot
                        property: "leftMarginValue"
                        from: 7.5
                        to: 9.2
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: rightSatDot
                        property: "leftMarginValue"
                        from: 9.2
                        to: 8.0
                        duration: 160
                        easing.type: Easing.InOutQuad
                    }
                }

                // Island recoil
                SequentialAnimation {
                    NumberAnimation {
                        target: root
                        property: "rightIslandBulge"
                        from: 3.0
                        to: -2.0
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: root
                        property: "rightIslandBulge"
                        from: -2.0
                        to: 0.0
                        duration: 160
                        easing.type: Easing.OutBack
                    }
                }

                // Harmonic damped fluid oscillation
                SequentialAnimation {
                    // Recoil squash
                    ParallelAnimation {
                        NumberAnimation { target: rightTransform; property: "xScale"; to: 0.78; duration: 80; easing.type: Easing.OutQuad }
                        NumberAnimation { target: rightTransform; property: "yScale"; to: 1.24; duration: 80; easing.type: Easing.OutQuad }
                    }
                    // Rebound
                    ParallelAnimation {
                        NumberAnimation { target: rightTransform; property: "xScale"; to: 1.14; duration: 85; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: rightTransform; property: "yScale"; to: 0.88; duration: 85; easing.type: Easing.InOutQuad }
                    }
                    // Counter oscillation
                    ParallelAnimation {
                        NumberAnimation { target: rightTransform; property: "xScale"; to: 0.95; duration: 75; easing.type: Easing.InOutSine }
                        NumberAnimation { target: rightTransform; property: "yScale"; to: 1.04; duration: 75; easing.type: Easing.InOutSine }
                    }
                    // Settle to circle
                    ParallelAnimation {
                        NumberAnimation { target: rightTransform; property: "xScale"; to: 1.0; duration: 80; easing.type: Easing.OutCubic }
                        NumberAnimation { target: rightTransform; property: "yScale"; to: 1.0; duration: 80; easing.type: Easing.OutCubic }
                    }
                }

                // Content bloom
                SequentialAnimation {
                    PauseAnimation { duration: 30 }
                    ParallelAnimation {
                        NumberAnimation {
                            target: rightSatDot
                            property: "contentOpacity"
                            from: 0.0
                            to: 1.0
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: rightSatDot
                            property: "contentScale"
                            from: 0.5
                            to: 1.0
                            duration: 260
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.15
                        }
                    }
                }
            }
        }

        SequentialAnimation {
            id: rightRetractAnim

            // Content dissolves first
            ParallelAnimation {
                NumberAnimation { target: rightSatDot; property: "contentOpacity"; to: 0.0; duration: 80; easing.type: Easing.InQuad }
                NumberAnimation { target: rightSatDot; property: "contentScale"; to: 0.6; duration: 80; easing.type: Easing.InQuad }
            }

            ScriptAction {
                script: {
                    rightSatDot.bridgeSnapped = false
                }
            }

            // Droplet pulled into island
            ParallelAnimation {
                NumberAnimation {
                    target: rightSatDot
                    property: "leftMarginValue"
                    to: -32
                    duration: 240
                    easing.type: Easing.InBack
                    easing.overshoot: 1.1
                }
                NumberAnimation {
                    target: rightTransform
                    property: "xScale"
                    to: 1.25
                    duration: 140
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: rightTransform
                    property: "yScale"
                    to: 0.80
                    duration: 140
                    easing.type: Easing.OutQuad
                }
            }

            // Fully absorbed
            ScriptAction {
                script: {
                    rightSatDot.opacity = 0.0
                    rightSatDot.scale = 0.0
                    rightTransform.xScale = 1.0
                    rightTransform.yScale = 1.0
                    rightSatDot.bridgeSnapped = true
                }
            }
        }

        // ── Content Wrapper (Synchronized fluid blooming) ──
        Item {
            id: rightContentWrapper
            anchors.fill: parent
            opacity: rightSatDot.contentOpacity
            scale: rightSatDot.contentScale

            // ── Content: Media Waveform ──
            Row {
                anchors.centerIn: parent
                spacing: 2.5
                visible: rightSatDot.activity === "media"

                Repeater {
                    model: 3
                    Rectangle {
                        id: rightWaveBar
                        required property int index
                        width: 2.5
                        height: 10
                        radius: 1.25
                        color: Services.Theme.success
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on height {
                            running: rightSatDot.activity === "media" && rightSatDot.visible
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: rightWaveBar.index === 0 ? 14 : (rightWaveBar.index === 1 ? 6 : 12)
                                duration: rightWaveBar.index === 0 ? 280 : (rightWaveBar.index === 1 ? 400 : 340)
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: rightWaveBar.index === 0 ? 4 : (rightWaveBar.index === 1 ? 14 : 4)
                                duration: rightWaveBar.index === 0 ? 320 : (rightWaveBar.index === 1 ? 300 : 380)
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }
            }

            // ── Content: Notification (App Icon + Badge) ──
            Item {
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: rightSatDot.activity === "notif"

                Image {
                    id: rightNotifImg
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: (rightSatDot.item && rightSatDot.item.notif) ? root.resolveNotifIcon(rightSatDot.item.notif) : ""
                    visible: status === Image.Ready && source.toString().length > 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(32, 32)
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰂚"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: Services.Theme.accent
                    visible: !rightNotifImg.visible
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Services.Theme.danger
                    anchors.top: parent.top
                    anchors.topMargin: -1
                    anchors.right: parent.right
                    anchors.rightMargin: -1
                }
            }

            // ── Content: Camera Privacy Indicator ──
            Item {
                anchors.centerIn: parent
                width: 16
                height: 16
                visible: rightSatDot.activity === "camera"

                Text {
                    anchors.centerIn: parent
                    text: "󰄀"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: Services.Theme.success
                }

                SequentialAnimation on opacity {
                    running: rightSatDot.activity === "camera" && rightSatDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                }
            }

            // ── Content: Screen Recording Indicator ──
            Text {
                anchors.centerIn: parent
                text: "●"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 12
                color: root.recordingColor
                visible: rightSatDot.activity === "recording"

                SequentialAnimation on opacity {
                    running: rightSatDot.activity === "recording" && rightSatDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                }
            }

            // ── Content: CapsLock Indicator ──
            Text {
                anchors.centerIn: parent
                text: "󰘶"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.alertYellow
                visible: rightSatDot.activity === "capslock"
            }

            // ── Content: System HUD ──
            Text {
                anchors.centerIn: parent
                text: (rightSatDot.item && rightSatDot.item.icon) ? rightSatDot.item.icon : (root.sysHudIcon || "󰋩")
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: (rightSatDot.item && rightSatDot.item.color) ? rightSatDot.item.color : root.sysHudColor
                visible: rightSatDot.activity === "syshud"
            }

            // ── Content: Transfer Progress ──
            Text {
                anchors.centerIn: parent
                text: "󰒍"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.accent
                visible: rightSatDot.activity === "transfer"

                SequentialAnimation on scale {
                    running: rightSatDot.activity === "transfer" && rightSatDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.95; duration: 600; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── Smart Interactive Click Handler ──
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            z: 10
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && rightSatDot.activity === "media") {
                    if (root.activePlayer) root.activePlayer.togglePlaying()
                } else if (rightSatDot.item) {
                    root.handleSatelliteClick(rightSatDot.item)
                }
            }
        }
    }

    // ==================== Left Dynamic Satellite Dot ("Sebelumnya lagi ke kiri gitu") ====================
    Rectangle {
        id: leftSatDot
        readonly property var item: root.slotLeftItem
        readonly property string activity: root.slotLeftType
        readonly property bool isSatellite: !root.lockBlocked && (!root.mediaStopping || !root.mediaIconTransformed ? activity !== "" : false)
        anchors.right: island.left
        anchors.rightMargin: rightMarginValue
        anchors.top: island.top
        anchors.topMargin: Math.max(0, (root.collapsedHeight - implicitHeight) / 2)
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: Services.Theme.bgPure
        border.color: Services.Theme.borderSubtle
        border.width: 1
        z: 1

        property real rightMarginValue: isSatellite ? 8 : -32
        property bool bridgeSnapped: !isSatellite
        property real contentOpacity: isSatellite ? 1.0 : 0.0
        property real contentScale: isSatellite ? 1.0 : 0.5

        opacity: isSatellite ? 1.0 : 0.0
        scale: isSatellite ? 1.0 : 0.0
        visible: isSatellite || opacity > 0 || scale > 0 || leftRetractAnim.running || leftDetachAnim.running

        transform: Scale {
            id: leftTransform
            origin.x: 16
            origin.y: 16
            xScale: 1.0
            yScale: 1.0
        }

        onIsSatelliteChanged: {
            if (isSatellite) {
                leftRetractAnim.stop()
                leftDetachAnim.restart()
            } else {
                leftDetachAnim.stop()
                leftRetractAnim.restart()
            }
        }

        SequentialAnimation {
            id: leftDetachAnim

            ScriptAction {
                script: {
                    leftSatDot.visible = true
                    leftSatDot.opacity = 1.0
                    leftSatDot.scale = 1.0
                    leftSatDot.rightMarginValue = -32
                    leftSatDot.bridgeSnapped = false
                    leftSatDot.contentOpacity = 0.0
                    leftSatDot.contentScale = 0.5
                    leftTransform.xScale = 1.0
                    leftTransform.yScale = 1.0
                }
            }

            // Phase 1: Extrusion & Viscous Stretching (0ms -> 200ms)
            ParallelAnimation {
                NumberAnimation {
                    target: leftSatDot
                    property: "rightMarginValue"
                    from: -32
                    to: 7.5
                    duration: 200
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: leftTransform
                    property: "xScale"
                    from: 1.0
                    to: 1.40
                    duration: 200
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: leftTransform
                    property: "yScale"
                    from: 1.0
                    to: 0.72
                    duration: 200
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: root
                    property: "leftIslandBulge"
                    from: 0.0
                    to: 3.0
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }

            // Snap Point: Surface tension reaches critical limit (~200ms)
            ScriptAction {
                script: {
                    leftSatDot.bridgeSnapped = true
                }
            }

            // Phase 2: Damped Fluid Jelly Wobble & Content Blossom (200ms -> 560ms)
            ParallelAnimation {
                // Position settles to 8px
                SequentialAnimation {
                    NumberAnimation {
                        target: leftSatDot
                        property: "rightMarginValue"
                        from: 7.5
                        to: 9.2
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: leftSatDot
                        property: "rightMarginValue"
                        from: 9.2
                        to: 8.0
                        duration: 160
                        easing.type: Easing.InOutQuad
                    }
                }

                // Island recoil
                SequentialAnimation {
                    NumberAnimation {
                        target: root
                        property: "leftIslandBulge"
                        from: 3.0
                        to: -2.0
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: root
                        property: "leftIslandBulge"
                        from: -2.0
                        to: 0.0
                        duration: 160
                        easing.type: Easing.OutBack
                    }
                }

                // Harmonic damped fluid oscillation
                SequentialAnimation {
                    // Recoil squash
                    ParallelAnimation {
                        NumberAnimation { target: leftTransform; property: "xScale"; to: 0.78; duration: 80; easing.type: Easing.OutQuad }
                        NumberAnimation { target: leftTransform; property: "yScale"; to: 1.24; duration: 80; easing.type: Easing.OutQuad }
                    }
                    // Rebound
                    ParallelAnimation {
                        NumberAnimation { target: leftTransform; property: "xScale"; to: 1.14; duration: 85; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: leftTransform; property: "yScale"; to: 0.88; duration: 85; easing.type: Easing.InOutQuad }
                    }
                    // Counter oscillation
                    ParallelAnimation {
                        NumberAnimation { target: leftTransform; property: "xScale"; to: 0.95; duration: 75; easing.type: Easing.InOutSine }
                        NumberAnimation { target: leftTransform; property: "yScale"; to: 1.04; duration: 75; easing.type: Easing.InOutSine }
                    }
                    // Settle to circle
                    ParallelAnimation {
                        NumberAnimation { target: leftTransform; property: "xScale"; to: 1.0; duration: 80; easing.type: Easing.OutCubic }
                        NumberAnimation { target: leftTransform; property: "yScale"; to: 1.0; duration: 80; easing.type: Easing.OutCubic }
                    }
                }

                // Content bloom
                SequentialAnimation {
                    PauseAnimation { duration: 30 }
                    ParallelAnimation {
                        NumberAnimation {
                            target: leftSatDot
                            property: "contentOpacity"
                            from: 0.0
                            to: 1.0
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: leftSatDot
                            property: "contentScale"
                            from: 0.5
                            to: 1.0
                            duration: 260
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.15
                        }
                    }
                }
            }
        }

        SequentialAnimation {
            id: leftRetractAnim

            // Content dissolves first
            ParallelAnimation {
                NumberAnimation { target: leftSatDot; property: "contentOpacity"; to: 0.0; duration: 80; easing.type: Easing.InQuad }
                NumberAnimation { target: leftSatDot; property: "contentScale"; to: 0.6; duration: 80; easing.type: Easing.InQuad }
            }

            ScriptAction {
                script: {
                    leftSatDot.bridgeSnapped = false
                }
            }

            // Droplet pulled into island
            ParallelAnimation {
                NumberAnimation {
                    target: leftSatDot
                    property: "rightMarginValue"
                    to: -32
                    duration: 240
                    easing.type: Easing.InBack
                    easing.overshoot: 1.1
                }
                NumberAnimation {
                    target: leftTransform
                    property: "xScale"
                    to: 1.25
                    duration: 140
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: leftTransform
                    property: "yScale"
                    to: 0.80
                    duration: 140
                    easing.type: Easing.OutQuad
                }
            }

            // Fully absorbed
            ScriptAction {
                script: {
                    leftSatDot.opacity = 0.0
                    leftSatDot.scale = 0.0
                    leftTransform.xScale = 1.0
                    leftTransform.yScale = 1.0
                    leftSatDot.bridgeSnapped = true
                }
            }
        }

        // ── Content Wrapper (Synchronized fluid blooming) ──
        Item {
            id: leftContentWrapper
            anchors.fill: parent
            opacity: leftSatDot.contentOpacity
            scale: leftSatDot.contentScale

            // ── Content: Media Waveform ──
            Row {
                anchors.centerIn: parent
                spacing: 2.5
                visible: leftSatDot.activity === "media"

                Repeater {
                    model: 3
                    Rectangle {
                        id: leftWaveBar
                        required property int index
                        width: 2.5
                        height: 10
                        radius: 1.25
                        color: Services.Theme.success
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on height {
                            running: leftSatDot.activity === "media" && leftSatDot.visible
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: leftWaveBar.index === 0 ? 14 : (leftWaveBar.index === 1 ? 6 : 12)
                                duration: leftWaveBar.index === 0 ? 280 : (leftWaveBar.index === 1 ? 400 : 340)
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: leftWaveBar.index === 0 ? 4 : (leftWaveBar.index === 1 ? 14 : 4)
                                duration: leftWaveBar.index === 0 ? 320 : (leftWaveBar.index === 1 ? 300 : 380)
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }
            }

            // ── Content: Notification (App Icon + Badge) ──
            Item {
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: leftSatDot.activity === "notif"

                Image {
                    id: leftNotifImg
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: (leftSatDot.item && leftSatDot.item.notif) ? root.resolveNotifIcon(leftSatDot.item.notif) : ""
                    visible: status === Image.Ready && source.toString().length > 0
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    sourceSize: Qt.size(32, 32)
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰂚"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: Services.Theme.accent
                    visible: !leftNotifImg.visible
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Services.Theme.danger
                    anchors.top: parent.top
                    anchors.topMargin: -1
                    anchors.right: parent.right
                    anchors.rightMargin: -1
                }
            }

            // ── Content: Camera Privacy Indicator ──
            Item {
                anchors.centerIn: parent
                width: 16
                height: 16
                visible: leftSatDot.activity === "camera"

                Text {
                    anchors.centerIn: parent
                    text: "󰄀"
                    font.family: Services.Theme.fontSymbols
                    font.pixelSize: 13
                    color: Services.Theme.success
                }

                SequentialAnimation on opacity {
                    running: leftSatDot.activity === "camera" && leftSatDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                }
            }

            // ── Content: Screen Recording Indicator ──
            Text {
                anchors.centerIn: parent
                text: "●"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 12
                color: root.recordingColor
                visible: leftSatDot.activity === "recording"

                SequentialAnimation on opacity {
                    running: leftSatDot.activity === "recording" && leftSatDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                }
            }

            // ── Content: CapsLock Indicator ──
            Text {
                anchors.centerIn: parent
                text: "󰘶"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.alertYellow
                visible: leftSatDot.activity === "capslock"
            }

            // ── Content: System HUD ──
            Text {
                anchors.centerIn: parent
                text: (leftSatDot.item && leftSatDot.item.icon) ? leftSatDot.item.icon : (root.sysHudIcon || "󰋩")
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: (leftSatDot.item && leftSatDot.item.color) ? leftSatDot.item.color : root.sysHudColor
                visible: leftSatDot.activity === "syshud"
            }

            // ── Content: Transfer Progress ──
            Text {
                anchors.centerIn: parent
                text: "󰒍"
                font.family: Services.Theme.fontSymbols
                font.pixelSize: 13
                color: Services.Theme.accent
                visible: leftSatDot.activity === "transfer"

                SequentialAnimation on scale {
                    running: leftSatDot.activity === "transfer" && leftSatDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.95; duration: 600; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── Smart Interactive Click Handler ──
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            z: 10
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton && leftSatDot.activity === "media") {
                    if (root.activePlayer) root.activePlayer.togglePlaying()
                } else if (leftSatDot.item) {
                    root.handleSatelliteClick(leftSatDot.item)
                }
            }
        }
    }


    // ── Backward Compatibility Aliases ──
    readonly property alias mediaSatelliteDot: rightSatDot
    readonly property alias cameraSatelliteDot: rightSatDot
    readonly property alias capsLockDot: leftSatDot
    readonly property alias satDot1: rightSatDot
    readonly property alias satDot2: leftSatDot

}
