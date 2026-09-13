import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import "../../services" as Services
import "../bar/components" as BarComponents
import "../notifications" as NotifModule

Scope {
    id: root

    property bool isLocked: sessionLock.locked
    property bool lockVisible: sessionLock.locked
    property string passwordInput: ""
    property string pendingPassword: ""
    property bool showPassword: false
    property bool isError: false
    property string errorMessage: ""
    property bool isAuthenticating: false

    property string timeStr: "00:00"
    property string hourStr: "00"
    property string minStr: "00"
    property string dateStr: ""
    property string greetingStr: "Welcome"
    property string username: "user"
    property string hostname: "host"
    property bool capsLockOn: false
    property bool isRevealed: false
    property bool lockscreenCcOpen: false
    property bool lockscreenPwrOpen: false
    property bool userRevealedInput: false

    property bool isFaceVerified: false
    property bool isFaceContracted: false
    property bool isFaceTimeoutContracted: false
    property bool deviceLockedPeekActive: false
    property bool hasPeekedLocked: false
    property int faceIdRetryCount: 0
    readonly property int maxFaceIdRetries: 1

    readonly property bool isFaceActive: Boolean(
        Services.FaceId &&
        Services.FaceId.isEnabled &&
        Services.FaceId.isEnrolled &&
        (
            Services.FaceId.status === "starting" ||
            Services.FaceId.status === "camera_ready" ||
            Services.FaceId.status === "scanning" ||
            Services.FaceId.status === "detected" ||
            (Services.FaceId.status === "success" && !root.isFaceContracted) ||
            (Services.FaceId.status === "timeout" && !root.isFaceTimeoutContracted)
        ) &&
        root.isLocked
    )

    readonly property bool isDeviceLockedPeek: root.deviceLockedPeekActive && !root.isFaceActive

    readonly property string lockLayout: Services.Config ? (Services.Config.lockscreenLayout || "default") : "default"
    readonly property bool isCompact: lockLayout === "compact"
    readonly property bool isMinimal: lockLayout === "minimal"
    readonly property bool isDefault: !isCompact && !isMinimal

    function numberToWords(num) {
        const ones = ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN"];
        const tens = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY"];
        if (num < 20) return ones[num] || "";
        const t = Math.floor(num / 10);
        const o = num % 10;
        return tens[t] + (o > 0 ? (" " + ones[o]) : "");
    }

    readonly property string hourWords: numberToWords(Number(root.hourStr))
    readonly property string minWords: (Number(root.minStr) === 0) ? "O'CLOCK" : ((Number(root.minStr) < 10 ? "OH " : "") + numberToWords(Number(root.minStr)))

    readonly property var player: Services.Mpris.activePlayer
    readonly property bool hasPlayer: player !== null && (player?.trackTitle ?? "").length > 0
    readonly property bool isPlaying: player?.isPlaying ?? false
    readonly property int notifCount: Services.Notifications.historyList ? Services.Notifications.historyList.count : 0

    // Smart Adaptive state detections
    readonly property bool hasActiveNotifs: !root.isMinimal && root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
    readonly property bool hasActiveMedia: root.isDefault && root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
    readonly property bool isCrowded: hasActiveNotifs && hasActiveMedia
    readonly property bool isBusy: hasActiveNotifs || hasActiveMedia

    function fmtTime(sec) {
        const s = Math.max(0, Math.floor(sec ?? 0))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    Timer {
        id: lockMprisTimer
        interval: 500
        running: root.isLocked && root.isPlaying
        repeat: true
        onTriggered: root.player?.positionChanged?.()
    }

    Timer {
        id: revealTimer
        interval: 50
        onTriggered: root.isRevealed = true
    }

    onIsRevealedChanged: {
        if (root.isRevealed) {
            root.deviceLockedPeekActive = false
            deviceLockedPeekStartTimer.restart()
        } else {
            deviceLockedPeekStartTimer.stop()
            deviceLockedPeekDurationTimer.stop()
            root.deviceLockedPeekActive = false
        }
    }

    Timer {
        id: unlockTimer
        interval: 220
        onTriggered: {
            root.isLocked = false
            Services.OverlayManager.isLocked = false
            sessionLock.locked = false
        }
    }

    Timer {
        id: deviceLockedPeekStartTimer
        interval: 400
        repeat: false
        onTriggered: root.triggerDeviceLockedPeek()
    }

    Timer {
        id: deviceLockedPeekDurationTimer
        interval: 1800
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Device Locked peek duration elapsed -> contracting peek, waiting delay before Face ID")
            root.deviceLockedPeekActive = false
            root.hasPeekedLocked = true
            if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !root.isFaceVerified && !Services.FaceId.isScanning) {
                faceIdScanTimer.restart()
            }
        }
    }

    Timer {
        id: faceIdScanTimer
        interval: 2500
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Face ID delay timer triggered. isLocked:", root.isLocked, "FaceId:", Services.FaceId, "isEnabled:", Services.FaceId?.isEnabled)
            if (root.isLocked && Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !root.isFaceVerified && !Services.FaceId.isScanning) {
                root.triggerFaceIdScan()
            }
        }
    }

    Timer {
        id: faceIdContractTimer
        interval: 1000
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Face ID contract timer triggered -> contracting island")
            root.isFaceContracted = true
        }
    }

    Timer {
        id: faceIdTimeoutShrinkTimer
        interval: 1400
        repeat: false
        onTriggered: {
            root.isFaceTimeoutContracted = true
            if (Services.FaceId) Services.FaceId.stopScan()
            if (root.isLocked && !root.isFaceVerified && root.faceIdRetryCount < root.maxFaceIdRetries) {
                console.log("[Lockscreen] Face ID failed, scheduling retry in 3s. Current retryCount:", root.faceIdRetryCount)
                faceIdRetryTimer.restart()
            } else {
                console.log("[Lockscreen] Face ID failed, max retries reached (" + root.faceIdRetryCount + "). No more auto retries.")
            }
        }
    }

    Timer {
        id: faceIdRetryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.isLocked && !root.isFaceVerified && !root.isFaceActive && root.faceIdRetryCount < root.maxFaceIdRetries) {
                root.faceIdRetryCount++
                console.log("[Lockscreen] Executing Face ID auto-retry #" + root.faceIdRetryCount)
                root.triggerFaceIdScan()
            }
        }
    }

    Timer {
        id: faceIdUnlockDelayTimer
        interval: 850
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Face ID auto-unlock triggered")
            root.unlockSuccess()
        }
    }

    function triggerDeviceLockedPeek() {
        console.log("[Lockscreen] triggerDeviceLockedPeek called. isLocked:", root.isLocked, "isFaceVerified:", root.isFaceVerified, "isFaceActive:", root.isFaceActive)
        if (!root.isLocked || root.isFaceVerified || root.isFaceActive) return
        deviceLockedPeekStartTimer.stop()
        root.deviceLockedPeekActive = true
        deviceLockedPeekDurationTimer.restart()
    }

    function triggerFaceIdScan() {
        console.log("[Lockscreen] triggerFaceIdScan called. isLocked:", root.isLocked, "isEnabled:", Services.FaceId?.isEnabled, "isEnrolled:", Services.FaceId?.isEnrolled)
        if (!root.isLocked || !Services.FaceId || !Services.FaceId.isEnabled || !Services.FaceId.isEnrolled) return
        if (Services.FaceId.isScanning) return
        if (root.isFaceVerified) return

        deviceLockedPeekStartTimer.stop()
        deviceLockedPeekDurationTimer.stop()
        faceIdScanTimer.stop()
        faceIdRetryTimer.stop()
        root.deviceLockedPeekActive = false
        root.hasPeekedLocked = true

        faceIdContractTimer.stop()
        faceIdTimeoutShrinkTimer.stop()
        root.isFaceContracted = false
        root.isFaceTimeoutContracted = false
        Services.FaceId.startScan()
    }

    function stopFaceIdScan() {
        console.log("[Lockscreen] stopFaceIdScan called")
        faceIdScanTimer.stop()
        faceIdRetryTimer.stop()
        faceIdContractTimer.stop()
        faceIdTimeoutShrinkTimer.stop()
        faceIdUnlockDelayTimer.stop()
        root.isFaceContracted = false
        root.isFaceTimeoutContracted = false
        if (Services.FaceId) Services.FaceId.stopScan()
    }

    Connections {
        target: Services.FaceId
        function onAuthenticated(user, confidence) {
            console.log("[Lockscreen] Face ID authenticated for:", user, "autoUnlock:", Services.FaceId.autoUnlock)
            if (!root.isLocked) return

            root.isError = false
            root.errorMessage = ""
            root.isAuthenticating = false
            root.hasPeekedLocked = true
            root.isFaceVerified = true
            root.faceIdRetryCount = 0

            if (Services.FaceId.autoUnlock) {
                faceIdUnlockDelayTimer.restart()
            } else {
                faceIdContractTimer.restart()
            }
        }

        function onStatusChanged() {
            if (Services.FaceId && Services.FaceId.status === "timeout") {
                faceIdTimeoutShrinkTimer.restart()
            }
        }

        function onScanFailed(reason) {
            console.log("[Lockscreen] Face ID scan failed:", reason)
            faceIdTimeoutShrinkTimer.restart()
        }
    }

    function open() {
        if (isLocked) return
        if (Services.FaceId) Services.FaceId.resetStatus()
        faceIdUnlockDelayTimer.stop()
        faceIdContractTimer.stop()
        faceIdTimeoutShrinkTimer.stop()
        faceIdRetryTimer.stop()
        deviceLockedPeekStartTimer.stop()
        deviceLockedPeekDurationTimer.stop()
        faceIdScanTimer.stop()
        root.faceIdRetryCount = 0
        root.deviceLockedPeekActive = false
        root.isFaceContracted = false
        root.isFaceTimeoutContracted = false
        root.isFaceVerified = false
        root.hasPeekedLocked = false
        isLocked = true
        passwordInput = ""
        pendingPassword = ""
        isError = false
        errorMessage = ""
        showPassword = false
        capsLockOn = false
        isAuthenticating = false
        isRevealed = false
        userRevealedInput = false
        updateTime()
        sessionLock.locked = true
        revealTimer.start()
        deviceLockedPeekStartTimer.restart()
    }

    function close() {
        if (isLocked) {
            triggerShake("Password required!")
            return
        }
        root.isLocked = false
        Services.OverlayManager.isLocked = false
        sessionLock.locked = false
    }

    function lock() { open() }
    function show() { open() }
    function hide() {
        if (!isLocked) {
            root.isLocked = false
            Services.OverlayManager.isLocked = false
            sessionLock.locked = false
        }
    }
    function toggle() {
        if (isLocked) close()
        else open()
    }

    function updateTime() {
        const now = new Date()
        const is24 = Services.Config ? Services.Config.lockscreen24h : false
        let h = now.getHours()
        if (h < 12) greetingStr = "Good Morning"
        else if (h < 18) greetingStr = "Good Afternoon"
        else greetingStr = "Good Evening"

        if (!is24) {
            h = h % 12
            if (h === 0) h = 12
        }
        hourStr = String(h).padStart(2, "0")
        minStr = String(now.getMinutes()).padStart(2, "0")
        timeStr = hourStr + ":" + minStr
        dateStr = Qt.formatDateTime(now, "dddd, MMMM d")
    }

    function authenticate() {
        if (isAuthenticating) return
        const pw = passwordInput.trim()
        if (pw.length === 0) {
            if ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified) {
                root.unlockSuccess()
                return
            }
            triggerShake("Enter password")
            return
        }
        isAuthenticating = true
        pendingPassword = passwordInput
        if (pam.active && pam.responseRequired) {
            pam.respond(pendingPassword)
            pendingPassword = ""
        } else {
            if (pam.active) pam.abort()
            pam.start()
        }
    }

    function triggerShake(msg) {
        isError = true
        errorMessage = msg || "Incorrect password!"
        isAuthenticating = false
        pendingPassword = ""
        passwordInput = ""
        showPassword = false
        if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
        if (pam.active) pam.abort()
        if (typeof shakeAnim !== "undefined" && shakeAnim) shakeAnim.restart()
    }

    function unlockSuccess() {
        isError = false
        errorMessage = ""
        passwordInput = ""
        pendingPassword = ""
        showPassword = false
        if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
        isAuthenticating = false
        isRevealed = false
        capsLockOn = false
        lockscreenCcOpen = false
        lockscreenPwrOpen = false
        faceIdUnlockDelayTimer.stop()
        faceIdContractTimer.stop()
        faceIdTimeoutShrinkTimer.stop()
        faceIdRetryTimer.stop()
        root.faceIdRetryCount = 0
        root.isFaceContracted = false
        root.isFaceTimeoutContracted = false
        root.isFaceVerified = false
        root.hasPeekedLocked = false
        if (Services.FaceId) Services.FaceId.stopScan()
        unlockTimer.start()
    }

    Component.onCompleted: {
        Services.OverlayManager.register(root)
        updateTime()
        userInfoProc.running = true
    }

    Timer {
        id: clockTimer
        interval: 1000
        running: root.isLocked
        repeat: true
        triggeredOnStart: true
        onTriggered: root.updateTime()
    }

    // System info process
    Process {
        id: userInfoProc
        command: ["sh", "-c", "echo $USER && uname -n"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n")
                if (lines.length > 0 && lines[0]) root.username = lines[0]
                if (lines.length > 1 && lines[1]) root.hostname = lines[1]
            }
        }
    }

    // Power Action Processes
    Process { id: suspendProc; command: ["systemctl", "suspend"] }
    Process { id: rebootProc; command: ["systemctl", "reboot"] }
    Process { id: shutdownProc; command: ["systemctl", "poweroff"] }

    PamContext {
        id: pam
        config: "login"

        onResponseRequiredChanged: {
            if (responseRequired && root.pendingPassword !== "") {
                pam.respond(root.pendingPassword)
                root.pendingPassword = ""
            }
        }

        onCompleted: (result) => {
            if (result === PamResult.Success) {
                root.unlockSuccess()
            } else {
                root.triggerShake("Incorrect password")
            }
        }

        onError: (err) => {
            root.triggerShake(err || "Authentication error")
        }
    }

    // ── Session Lock Integration (Wayland ext-session-lock-v1) ──────────────
    WlSessionLock {
        id: sessionLock

        onLockedChanged: {
            root.isLocked = sessionLock.locked
            Services.OverlayManager.isLocked = sessionLock.locked
            if (!sessionLock.locked) {
                if (Services.FaceId) Services.FaceId.stopScan()
                faceIdUnlockDelayTimer.stop()
                faceIdContractTimer.stop()
                faceIdTimeoutShrinkTimer.stop()
                faceIdRetryTimer.stop()
                deviceLockedPeekStartTimer.stop()
                deviceLockedPeekDurationTimer.stop()
                faceIdScanTimer.stop()
                root.faceIdRetryCount = 0
                root.deviceLockedPeekActive = false
                root.isFaceContracted = false
                root.isFaceTimeoutContracted = false
                root.isFaceVerified = false
                root.hasPeekedLocked = false
                root.passwordInput = ""
                root.pendingPassword = ""
                root.isAuthenticating = false
                root.isRevealed = false
                root.capsLockOn = false
                if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
                if (pam.active) pam.abort()
            } else {
                if (Services.FaceId) Services.FaceId.resetStatus()
                faceIdUnlockDelayTimer.stop()
                faceIdContractTimer.stop()
                faceIdTimeoutShrinkTimer.stop()
                faceIdRetryTimer.stop()
                root.faceIdRetryCount = 0
                root.isFaceContracted = false
                root.isFaceTimeoutContracted = false
                root.isFaceVerified = false
                root.hasPeekedLocked = false
                root.deviceLockedPeekActive = false
                deviceLockedPeekStartTimer.restart()
            }
        }

        WlSessionLockSurface {
            id: surface

            // Fullscreen solid root container inside lock surface
            Rectangle {
                anchors.fill: parent
                color: Services.Theme.bgDeep
                focus: true

                Component.onCompleted: pwTextInput.forceActiveFocus()

                // Keyboard Handler - Strictly prevents ESC from unlocking
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        root.passwordInput = ""
                        root.userRevealedInput = false
                        if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
                        root.triggerShake("Password required")
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (typeof pwTextInput !== "undefined" && pwTextInput) root.passwordInput = pwTextInput.text
                        if (root.passwordInput.length === 0) {
                            if ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified) {
                                root.unlockSuccess()
                                event.accepted = true
                                return
                            }
                            if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !Services.FaceId.isScanning) {
                                root.triggerFaceIdScan()
                                event.accepted = true
                                return
                            }
                            if (Services.FaceId && Services.FaceId.isScanning) {
                                event.accepted = true
                                return
                            }
                        }
                        root.authenticate()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Space && (!pwTextInput || pwTextInput.text.length === 0)) {
                        if ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified) {
                            root.unlockSuccess()
                            event.accepted = true
                            return
                        }
                        if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !Services.FaceId.isScanning) {
                            root.triggerFaceIdScan()
                            event.accepted = true
                            return
                        }
                        if (Services.FaceId && Services.FaceId.isScanning) {
                            event.accepted = true
                            return
                        }
                    } else if (event.key === Qt.Key_CapsLock) {
                        root.capsLockOn = !root.capsLockOn
                        event.accepted = true
                    } else {
                        // Intelligent CapsLock auto-detection heuristic based on typed character casing vs Shift key
                        if (event.text && event.text.length === 1) {
                            const c = event.text
                            const isShift = !!(event.modifiers & Qt.ShiftModifier)
                            if (c >= 'A' && c <= 'Z') {
                                root.capsLockOn = !isShift
                            } else if (c >= 'a' && c <= 'z') {
                                root.capsLockOn = isShift
                            }
                        }
                        if (event.text.length > 0) {
                            root.userRevealedInput = true
                        }
                        if (typeof pwTextInput !== "undefined" && pwTextInput && !pwTextInput.activeFocus && event.text.length > 0) {
                            pwTextInput.forceActiveFocus()
                        }
                    }
                }

                // Fullscreen Wallpaper Layer (Gets image from Services.Wallpaper or custom lockscreen image, with smooth Zoom and MultiEffect blur)
                Item {
                    anchors.fill: parent

                    Image {
                        id: bgImage
                        anchors.fill: parent
                        source: {
                            if (Services.Config && Services.Config.lockscreenWallpaperMode === "custom" && Services.Config.lockscreenCustomWallpaper.length > 0) {
                                return "file://" + Services.Config.lockscreenCustomWallpaper
                            }
                            return Services.Wallpaper.currentWallpaper.length > 0 ? ("file://" + Services.Wallpaper.currentWallpaper) : ("file://" + Services.Wallpaper.darkWallbler)
                        }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: false
                        smooth: true
                        cache: true
                        scale: (Services.Config && !Services.Config.lockscreenWallpaperZoom) ? 1.0 : (root.isRevealed ? 1.16 : 1.0)
                        transformOrigin: Item.Center
                        visible: !(Services.Config && Services.Config.lockscreenBlur && (Services.Config.lockscreenBlurRadius > 0))
                        Behavior on scale { NumberAnimation { duration: 350; easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic } }
                    }

                    MultiEffect {
                        anchors.fill: bgImage
                        source: bgImage
                        scale: bgImage.scale
                        transformOrigin: Item.Center
                        blurEnabled: (Services.Config && Services.Config.lockscreenBlur) || false
                        blur: (Services.Config ? Services.Config.lockscreenBlurRadius : 0.40)
                        blurMax: 64
                        visible: (Services.Config && Services.Config.lockscreenBlur && (Services.Config.lockscreenBlurRadius > 0)) || false
                        Behavior on blur { NumberAnimation { duration: 250 } }
                    }

                    // Smooth Dark Dim / Vignette Overlay
                    Rectangle {
                        anchors.fill: parent
                        color: Services.Theme.bgDeep
                        opacity: {
                            if (!root.isRevealed) return 0.0
                            var baseDim = Services.Config ? Services.Config.lockscreenDim : 0.45
                            if (root.isCompact) return Math.min(0.85, baseDim + 0.15)
                            if (root.isMinimal) return Math.max(0.18, baseDim - 0.12)
                            return baseDim
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 900
                                easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic
                            }
                        }
                    }
                }

                // ── Top Header Bar (Center: DynamicIsland, Right: Quick Status & ControlCenter) ──
                Item {
                    id: topBarHeader
                    anchors.top: parent.top
                    anchors.topMargin: root.isRevealed ? 0 : -20
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 48
                    z: 100
                    visible: !root.isCompact
                    opacity: (root.isRevealed && !root.isCompact) ? 1.0 : 0.0
                    scale: root.isRevealed ? 1.0 : 0.96
                    Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                    // Center: Dynamic Island (Apple Face ID & Status Capsule)
                    Rectangle {
                        id: lockIsland
                        visible: root.isDefault
                        anchors.top: parent.top
                        anchors.topMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Services.Theme.bgDeep

                        readonly property bool isVerified: root.isFaceVerified
                        readonly property bool isFaceActive: root.isFaceActive
                        readonly property bool isDeviceLockedPeek: root.isDeviceLockedPeek

                        readonly property bool isFaceSuccess: Boolean(
                            root.isFaceActive &&
                            Services.FaceId &&
                            Services.FaceId.status === "success"
                        )

                        border.color: {
                            if (root.isFaceActive && Services.FaceId && Services.FaceId.status === "detected") return "#38bdf8"
                            if (root.isDeviceLockedPeek) return Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35)
                            return Services.Theme.borderSubtle
                        }
                        border.width: ((root.isFaceActive && Services.FaceId && Services.FaceId.status === "detected") || root.isDeviceLockedPeek) ? 1.5 : 1

                        width: root.isFaceActive ? 160 : (root.isDeviceLockedPeek ? 218 : 140)
                        height: root.isFaceActive ? 96 : (root.isDeviceLockedPeek ? 44 : 32)
                        radius: root.isFaceActive ? 24 : (height / 2)

                        Behavior on width  { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }
                        Behavior on height { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }
                        Behavior on radius {
                            enabled: root.isFaceActive || (lockIsland.height > 50)
                            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                        }
                        Behavior on border.color { ColorAnimation { duration: 250 } }

                        MouseArea {
                            anchors.fill: parent
                            z: 10
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.isFaceVerified || (Services.FaceId && Services.FaceId.status === "success")) {
                                    root.unlockSuccess()
                                    return
                                }
                                if (root.isFaceActive || (Services.FaceId && Services.FaceId.isScanning)) {
                                    root.stopFaceIdScan()
                                    return
                                }
                                if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled) {
                                    root.faceIdRetryCount = 0
                                    root.triggerFaceIdScan()
                                    return
                                }
                                root.triggerDeviceLockedPeek()
                            }
                        }

                        // ==================== Mode 1: Collapsed Idle Desktop Dot or Verified Pill ====================
                        Item {
                            id: statusIconContainer
                            anchors.fill: parent
                            z: 2
                            visible: (!root.isFaceActive && !root.isDeviceLockedPeek) || opacity > 0.01
                            opacity: (!root.isFaceActive && !root.isDeviceLockedPeek) ? 1 : 0
                            scale: (!root.isFaceActive && !root.isDeviceLockedPeek) ? 1.0 : 0.4
                            transformOrigin: Item.Center

                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }
                            Behavior on scale   { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                            Item {
                                id: statusIndicatorWrapper
                                width: 20
                                height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                x: (root.hasPeekedLocked || root.isFaceVerified) ? 14 : (parent.width - width) / 2

                                Behavior on x {
                                    NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
                                }

                                Text {
                                    id: statusIndicatorIcon
                                    anchors.centerIn: parent
                                    text: {
                                        if (root.isFaceVerified) return "󰌿"
                                        if (root.hasPeekedLocked) return "󰌾"
                                        return "●"
                                    }
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: (root.isFaceVerified || root.hasPeekedLocked) ? 14 : 13
                                    color: {
                                        if (root.isFaceVerified) return "#30d158"
                                        if (root.hasPeekedLocked) return Services.Theme.textPrimary
                                        return Services.Theme.textDisabled
                                    }
                                    scale: iconScale
                                    property real iconScale: 1.0

                                    Behavior on color { ColorAnimation { duration: 220 } }

                                    onTextChanged: {
                                        iconMorphAnim.restart()
                                    }

                                    SequentialAnimation {
                                        id: iconMorphAnim
                                        NumberAnimation { target: statusIndicatorIcon; property: "iconScale"; to: 0.6; duration: 90; easing.type: Easing.InQuad }
                                        NumberAnimation { target: statusIndicatorIcon; property: "iconScale"; to: 1.25; duration: 180; easing.type: Easing.OutBack }
                                        NumberAnimation { target: statusIndicatorIcon; property: "iconScale"; to: 1.0; duration: 120; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }
                        }

                        // ==================== Mode 2: Revamped "Device Locked" Dynamic Island Peek ====================
                        Item {
                            id: deviceLockedPeekContainer
                            anchors.fill: parent
                            visible: root.isDeviceLockedPeek || opacity > 0.01
                            opacity: root.isDeviceLockedPeek ? 1 : 0
                            scale: root.isDeviceLockedPeek ? 1.0 : 0.75
                            transformOrigin: Item.Center
                            z: 3

                            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
                            Behavior on scale   { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 14
                                spacing: 10

                                // Left: Sleek Circular Lock Icon Badge with subtle accent glow
                                Rectangle {
                                    id: lockBadge
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 14
                                    color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16)
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.28)
                                    border.width: 1

                                    Text {
                                        id: lockBadgeIcon
                                        anchors.centerIn: parent
                                        text: "󰌾"
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 14
                                        color: Services.Theme.accent

                                        scale: root.isDeviceLockedPeek ? 1.0 : 0.6
                                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                                    }
                                }

                                // Center: Typography Hierarchy
                                Column {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: "Device Locked"
                                        color: Services.Theme.textPrimary
                                        font.family: Services.Theme.fontDisplay
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: "Authentication required"
                                        color: Services.Theme.textSecondary
                                        font.family: Services.Theme.fontDisplay
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        opacity: 0.85
                                    }
                                }
                            }
                        }

                        // ==================== Mode 3: Apple Face ID Dynamic Island ====================
                        Item {
                            id: faceIdExpandedContainer
                            anchors.fill: parent
                            visible: root.isFaceActive || opacity > 0.01
                            opacity: root.isFaceActive ? 1 : 0
                            scale: root.isFaceActive ? 1.0 : 0.5
                            transformOrigin: Item.Center
                            z: 4

                            Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutQuad } }
                            Behavior on scale   { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }

                            function triggerVerifiedTransition() {
                                scanningPulseAnim.stop()
                                faceIconWrapper.pulseScale = 1.0
                                verifiedPopAnim.restart()
                                haloBurstAnim.restart()
                                appleFaceCanvas.requestPaint()
                            }

                            Connections {
                                target: Services.FaceId
                                function onStatusChanged() {
                                    if (Services.FaceId && Services.FaceId.status === "success") {
                                        faceIdExpandedContainer.triggerVerifiedTransition()
                                    } else if (Services.FaceId && Services.FaceId.isScanning) {
                                        verifiedPopAnim.stop()
                                        haloBurstAnim.stop()
                                        faceIconWrapper.popScale = 1.0
                                        if (!scanningPulseAnim.running) {
                                            scanningPulseAnim.restart()
                                        }
                                    } else {
                                        scanningPulseAnim.stop()
                                        verifiedPopAnim.stop()
                                        haloBurstAnim.stop()
                                        faceIconWrapper.pulseScale = 1.0
                                        faceIconWrapper.popScale = 1.0
                                    }
                                }
                                function onAuthenticated(user, confidence) {
                                    faceIdExpandedContainer.triggerVerifiedTransition()
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                width: parent.width - 20

                                // Authentic Apple Face ID Vector Glyph (34x34) with Spring Pop & Halo
                                Item {
                                    id: faceIconWrapper
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 34
                                    height: 34
                                    implicitWidth: 34
                                    implicitHeight: 34
                                    transformOrigin: Item.Center

                                    property real pulseScale: 1.0
                                    property real popScale: 1.0

                                    scale: pulseScale * popScale

                                    // Gentle breathing pulse during scanning
                                    SequentialAnimation {
                                        id: scanningPulseAnim
                                        running: Services.FaceId && Services.FaceId.isScanning && (Services.FaceId.status !== "success")
                                        loops: Animation.Infinite
                                        NumberAnimation { target: faceIconWrapper; property: "pulseScale"; from: 1.0; to: 1.07; duration: 520; easing.type: Easing.InOutSine }
                                        NumberAnimation { target: faceIconWrapper; property: "pulseScale"; from: 1.07; to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                                    }

                                    // Spring bounce on verification
                                    SequentialAnimation {
                                        id: verifiedPopAnim
                                        NumberAnimation { target: faceIconWrapper; property: "popScale"; to: 0.88; duration: 80; easing.type: Easing.InQuad }
                                        NumberAnimation { target: faceIconWrapper; property: "popScale"; to: 1.20; duration: 200; easing.type: Easing.OutBack }
                                        NumberAnimation { target: faceIconWrapper; property: "popScale"; to: 1.0; duration: 220; easing.type: Easing.InOutQuad }
                                    }

                                    // Emerald glowing halo flash behind icon on verification
                                    Rectangle {
                                        id: verifiedHalo
                                        anchors.centerIn: parent
                                        width: 34
                                        height: 34
                                        radius: 17
                                        color: "#30d158"
                                        opacity: 0.0
                                        scale: 0.5
                                        z: -1

                                        ParallelAnimation {
                                            id: haloBurstAnim
                                            NumberAnimation { target: verifiedHalo; property: "scale"; from: 0.6; to: 1.6; duration: 420; easing.type: Easing.OutCubic }
                                            SequentialAnimation {
                                                NumberAnimation { target: verifiedHalo; property: "opacity"; from: 0.0; to: 0.40; duration: 100; easing.type: Easing.OutQuad }
                                                NumberAnimation { target: verifiedHalo; property: "opacity"; from: 0.40; to: 0.0; duration: 320; easing.type: Easing.OutQuad }
                                            }
                                        }
                                    }

                                    Canvas {
                                        id: appleFaceCanvas
                                        anchors.fill: parent
                                        renderTarget: Canvas.FramebufferObject

                                        readonly property bool isSuccess: Boolean(Services.FaceId && Services.FaceId.status === "success")
                                        readonly property bool isDetected: Boolean(Services.FaceId && Services.FaceId.status === "detected")
                                        readonly property bool isTimeout: Boolean(Services.FaceId && Services.FaceId.status === "timeout")

                                        property color strokeColor: isSuccess ? "#30d158" : (isDetected ? "#38bdf8" : (isTimeout ? "#ef4444" : Services.Theme.accent))
                                        property real smileAmount: isSuccess ? 1.40 : 1.0
                                        property real cornerRadius: 4.0

                                        Behavior on strokeColor {
                                            ColorAnimation { duration: 280; easing.type: Easing.OutQuad }
                                        }
                                        Behavior on smileAmount {
                                            NumberAnimation { duration: 360; easing.type: Easing.OutBack }
                                        }

                                        onStrokeColorChanged: requestPaint()
                                        onSmileAmountChanged: requestPaint()
                                        onVisibleChanged: { if (visible) requestPaint() }
                                        Component.onCompleted: requestPaint()

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.strokeStyle = strokeColor
                                            ctx.lineWidth = 1.9
                                            ctx.lineCap = "round"
                                            ctx.lineJoin = "round"

                                            var w = width
                                            var h = height
                                            var r = cornerRadius

                                            // Top-Left Bracket
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.10, h * 0.32)
                                            ctx.lineTo(w * 0.10, h * 0.18 + r)
                                            ctx.arcTo(w * 0.10, h * 0.10, w * 0.18 + r, h * 0.10, r)
                                            ctx.lineTo(w * 0.34, h * 0.10)
                                            ctx.stroke()

                                            // Top-Right Bracket
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.66, h * 0.10)
                                            ctx.lineTo(w * 0.82 - r, h * 0.10)
                                            ctx.arcTo(w * 0.90, h * 0.10, w * 0.90, h * 0.18 + r, r)
                                            ctx.lineTo(w * 0.90, h * 0.32)
                                            ctx.stroke()

                                            // Bottom-Left Bracket
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.10, h * 0.68)
                                            ctx.lineTo(w * 0.10, h * 0.82 - r)
                                            ctx.arcTo(w * 0.10, h * 0.90, w * 0.18 + r, h * 0.90, r)
                                            ctx.lineTo(w * 0.34, h * 0.90)
                                            ctx.stroke()

                                            // Bottom-Right Bracket
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.66, h * 0.90)
                                            ctx.lineTo(w * 0.82 - r, h * 0.90)
                                            ctx.arcTo(w * 0.90, h * 0.90, w * 0.90, h * 0.82 - r, r)
                                            ctx.lineTo(w * 0.90, h * 0.68)
                                            ctx.stroke()

                                            // Left Eye
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.35, h * 0.36)
                                            ctx.lineTo(w * 0.35, h * 0.46)
                                            ctx.stroke()

                                            // Right Eye
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.65, h * 0.36)
                                            ctx.lineTo(w * 0.65, h * 0.46)
                                            ctx.stroke()

                                            // Nose
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.50, h * 0.42)
                                            ctx.lineTo(w * 0.50, h * 0.54)
                                            ctx.lineTo(w * 0.58, h * 0.54)
                                            ctx.stroke()

                                            // Smile
                                            ctx.beginPath()
                                            ctx.moveTo(w * 0.33, h * 0.69)
                                            ctx.quadraticCurveTo(w * 0.50, h * (0.69 + 0.11 * smileAmount), w * 0.67, h * 0.69)
                                            ctx.stroke()
                                        }
                                    }
                                }

                                // Status text stacked vertically beneath Face ID icon
                                Column {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 2

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "Face ID"
                                        font.family: Services.Theme.fontDisplay
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: Services.Theme.textPrimary
                                    }

                                    Item {
                                        id: statusSubtitleBox
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 130
                                        height: 15
                                        clip: true

                                        readonly property bool isVerified: Boolean(Services.FaceId && Services.FaceId.status === "success")

                                        Text {
                                            id: statusScanText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: statusSubtitleBox.isVerified ? -16 : 0
                                            opacity: statusSubtitleBox.isVerified ? 0.0 : 1.0

                                            text: {
                                                if (Services.FaceId && Services.FaceId.status === "detected") return "Verifying Face..."
                                                if (Services.FaceId && Services.FaceId.status === "scanning") return "Looking for Face..."
                                                if (Services.FaceId && (Services.FaceId.status === "starting" || Services.FaceId.status === "camera_ready")) return "Starting..."
                                                if (Services.FaceId && Services.FaceId.status === "timeout") return "Try Again"
                                                return "Ready"
                                            }
                                            font.family: Services.Theme.fontDisplay
                                            font.pixelSize: 10
                                            font.weight: Font.Normal
                                            horizontalAlignment: Text.AlignHCenter
                                            color: {
                                                if (Services.FaceId && Services.FaceId.status === "detected") return "#38bdf8"
                                                if (Services.FaceId && Services.FaceId.status === "timeout") return Services.Theme.danger
                                                return Services.Theme.textSecondary
                                            }

                                            Behavior on y {
                                                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                                            }
                                            Behavior on opacity {
                                                NumberAnimation { duration: 240; easing.type: Easing.OutQuad }
                                            }
                                        }

                                        Text {
                                            id: statusSuccessText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: statusSubtitleBox.isVerified ? 0 : 16
                                            opacity: statusSubtitleBox.isVerified ? 1.0 : 0.0

                                            text: "Verified"
                                            font.family: Services.Theme.fontDisplay
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            horizontalAlignment: Text.AlignHCenter
                                            color: "#30d158"

                                            Behavior on y {
                                                NumberAnimation { duration: 320; easing.type: Easing.OutBack }
                                            }
                                            Behavior on opacity {
                                                NumberAnimation { duration: 280; easing.type: Easing.OutQuad }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Mode A: Default Pill Box (Default Layout)
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        implicitWidth: combinedCcRow.implicitWidth + 22
                        radius: 15
                        color: ccMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surfaceVariant
                        border.color: root.lockscreenCcOpen ? Services.Theme.accent : Services.Theme.border
                        border.width: 1
                        visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowStatusPill : true)
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        RowLayout {
                            id: combinedCcRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Wi-Fi Status Icon (if enabled)
                            Text {
                                visible: Services.Wifi && Services.Wifi.enabled
                                text: Services.Icons.wifiIcon(Services.Wifi.signalStrength, Services.Wifi.connected, Services.Wifi.enabled)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: (Services.Wifi && Services.Wifi.connected) ? Services.Theme.accent : Services.Theme.textDisabled
                            }

                            // Bluetooth Status Icon (if enabled)
                            Text {
                                visible: Services.Bluetooth && Services.Bluetooth.enabled
                                text: (Services.Bluetooth && Services.Bluetooth.hasConnectedDevice)
                                      ? Services.Icons.btDeviceIcon(Services.Bluetooth.connectedDeviceIcon, Services.Bluetooth.connectedDeviceName)
                                      : Services.Icons.bluetooth
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: (Services.Bluetooth && Services.Bluetooth.hasConnectedDevice) ? Services.Theme.accent : Services.Theme.textDisabled
                            }

                            // Battery Icon & Percentage
                            RowLayout {
                                spacing: 4

                                Text {
                                    text: Services.Icons.powerIcon(Services.Power.charging, Math.round((Services.Power.percentage || 0) * 100))
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary))
                                }

                                Text {
                                    text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.bold: true
                                    color: Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary)
                                }
                            }

                            // Vertical Separator
                            Rectangle {
                                width: 1
                                height: 12
                                color: Services.Theme.border
                            }

                            // Control Center Toggle Icon
                            Text {
                                text: Services.Icons.sliders
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: 12
                                color: root.lockscreenCcOpen ? Services.Theme.accent : Services.Theme.textPrimary
                            }
                        }

                        MouseArea {
                            id: ccMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.lockscreenCcOpen = !root.lockscreenCcOpen
                            }
                        }
                    }

                    // Mode B: Minimal Discrete Status Icons (Minimal Layout - Clean, subtle monochrome)
                    RowLayout {
                        visible: root.isMinimal && (Services.Config ? Services.Config.lockscreenShowStatusPill : true)
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        opacity: 0.75

                        // Wi-Fi
                        Text {
                            visible: Services.Wifi && Services.Wifi.enabled
                            text: Services.Icons.wifi
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: Services.Theme.fontSizeSm
                            color: (Services.Wifi && Services.Wifi.connected) ? Services.Theme.accent : Services.Theme.textDisabled
                        }

                        // Battery
                        RowLayout {
                            spacing: 4
                            Text {
                                text: Services.Icons.powerIcon(Services.Power.charging, Math.round((Services.Power.percentage || 0) * 100))
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Power.charging ? Services.Theme.success : (Services.Power.isLow ? Services.Theme.danger : (Services.Power.isWarning ? Services.Theme.warning : Services.Theme.textPrimary))
                            }
                            Text {
                                text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.textSecondary
                            }
                        }

                        // Subtle CC Button
                        Text {
                            text: Services.Icons.sliders
                            font.family: Services.Theme.fontSymbols
                            font.pixelSize: 11
                            color: root.lockscreenCcOpen ? Services.Theme.accent : Services.Theme.textSecondary
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.lockscreenCcOpen = !root.lockscreenCcOpen
                            }
                        }
                    }
                }

                // Main Content Backdrop MouseArea
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.lockscreenCcOpen
                    onClicked: {
                        root.userRevealedInput = true
                        pwTextInput.forceActiveFocus()
                    }

                    Item {
                        id: mainContainer
                        anchors.fill: parent
                        anchors.horizontalCenterOffset: 0

                        // Shake Animation on Auth Error or ESC press
                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: 0; to: -14; duration: 40; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: -14; to: 14; duration: 40; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: 14; to: -8; duration: 35; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: -8; to: 8; duration: 35; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: mainContainer; property: "anchors.horizontalCenterOffset"; from: 8; to: 0; duration: 30; easing.type: Easing.InOutQuad }
                        }

                        // ── 1. Top Clock & Date (Default & Minimal Layouts) ───────────────────
                        ColumnLayout {
                            id: topClockColumn
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: root.isMinimal
                                ? Math.max(90, Math.round(parent.height * 0.22))
                                : Math.max(102, Math.round(parent.height * 0.125))

                            spacing: 4
                            visible: !root.isCompact
                            opacity: (root.isRevealed && !root.isCompact) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on anchors.topMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                            readonly property string clockStyle: root.isMinimal ? "minimal" : (Services.Config ? Services.Config.lockscreenClockStyle : "hero")

                            // Date Line (for hero, modern, minimal)
                            Text {
                                visible: topClockColumn.clockStyle !== "compact" && topClockColumn.clockStyle !== "vertical" && topClockColumn.clockStyle !== "typographic" && topClockColumn.clockStyle !== "radial" && topClockColumn.clockStyle !== "cyber"
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? root.dateStr.toUpperCase() : root.dateStr
                                color: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? Services.Theme.accent : Services.Theme.textPrimary
                                font.pixelSize: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? Services.Theme.fontSizeSm : 18
                                font.weight: Font.DemiBold
                                font.letterSpacing: (topClockColumn.clockStyle === "minimal" || root.isMinimal) ? 2.5 : 0.4
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 1: Hero Clock (Single horizontal huge display)
                            Text {
                                visible: topClockColumn.clockStyle === "hero"
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: root.timeStr
                                color: Services.Theme.white
                                font.pixelSize: 94
                                font.weight: Font.Bold
                                font.letterSpacing: -1.0
                                font.family: Services.Theme.fontDisplay
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 2: Modern Stacked Clock (Bold Hour on top, Clean Minute below)
                            ColumnLayout {
                                visible: topClockColumn.clockStyle === "modern"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: -20

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.hourStr
                                    color: Services.Theme.accent
                                    font.pixelSize: 80
                                    font.weight: Font.Black
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.minStr
                                    color: Services.Theme.white
                                    font.pixelSize: 80
                                    font.weight: Font.Black
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Style 3: Compact Island Pill Clock
                            Rectangle {
                                visible: topClockColumn.clockStyle === "compact"
                                Layout.alignment: Qt.AlignHCenter
                                height: 48
                                implicitWidth: compactRow.implicitWidth + 32
                                radius: 24
                                color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.75)
                                border.color: Services.Theme.borderHighlight
                                border.width: 1

                                RowLayout {
                                    id: compactRow
                                    anchors.centerIn: parent
                                    spacing: 14

                                    Text {
                                        text: root.timeStr
                                        color: Services.Theme.accent
                                        font.pixelSize: Services.Theme.fontSize2xl
                                        font.bold: true
                                        font.family: Services.Theme.fontDisplay
                                    }
                                    Rectangle { width: 1.5; height: 18; color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.4); radius: 1 }
                                    Text {
                                        text: root.dateStr
                                        color: Services.Theme.textPrimary
                                        font.pixelSize: Services.Theme.fontSizeMd
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            // Style 4: Minimalist Clock (Clean ultra-light display)
                            Text {
                                visible: topClockColumn.clockStyle === "minimal"
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: root.timeStr
                                color: Services.Theme.white
                                font.pixelSize: 96
                                font.weight: Font.ExtraLight
                                font.letterSpacing: 4
                                font.family: Services.Theme.fontDisplay
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // Style 5: Vertical Aesthetic Clock
                            RowLayout {
                                visible: topClockColumn.clockStyle === "vertical"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 20

                                ColumnLayout {
                                    spacing: -16
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.hourStr
                                        color: Services.Theme.accent
                                        font.pixelSize: 68
                                        font.weight: Font.Black
                                        font.family: Services.Theme.fontDisplay
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.minStr
                                        color: Services.Theme.white
                                        font.pixelSize: 68
                                        font.weight: Font.Black
                                        font.family: Services.Theme.fontDisplay
                                        style: Text.Outline
                                        styleColor: Services.Theme.overlayDim
                                    }
                                }

                                Rectangle {
                                    width: 2.5
                                    height: 86
                                    color: Services.Theme.accent
                                    radius: 1.5
                                }

                                ColumnLayout {
                                    spacing: 4
                                    Text {
                                        text: Qt.formatDateTime(new Date(), "dddd")
                                        color: Services.Theme.accent
                                        font.pixelSize: Services.Theme.fontSizeXl
                                        font.bold: true
                                    }
                                    Text {
                                        text: Qt.formatDateTime(new Date(), "MMMM d, yyyy")
                                        color: Services.Theme.textPrimary
                                        font.pixelSize: Services.Theme.fontSizeSm
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        text: root.greetingStr
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: Services.Theme.fontSizeXs
                                    }
                                }
                            }

                            // Style 6: Typographic Editorial Words Clock
                            ColumnLayout {
                                visible: topClockColumn.clockStyle === "typographic" || topClockColumn.clockStyle === "words"
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.hourWords
                                    color: Services.Theme.accent
                                    font.pixelSize: 46
                                    font.weight: Font.Black
                                    font.letterSpacing: 3
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.minWords
                                    color: Services.Theme.white
                                    font.pixelSize: 46
                                    font.weight: Font.Black
                                    font.letterSpacing: 3
                                    font.family: Services.Theme.fontDisplay
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 4
                                    width: 140; height: 2; radius: 1; color: Services.Theme.accent
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.dateStr.toUpperCase()
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.5
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Style 7: Radial Ring Gauge Clock
                            Rectangle {
                                visible: topClockColumn.clockStyle === "radial"
                                Layout.alignment: Qt.AlignHCenter
                                width: 154; height: 154; radius: 77
                                color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.65)
                                border.color: Services.Theme.accent
                                border.width: 2.5

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    radius: 70
                                    color: "transparent"
                                    border.color: Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3)
                                    border.width: 1.5
                                }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.timeStr
                                        color: Services.Theme.white
                                        font.pixelSize: 36
                                        font.weight: Font.Bold
                                        font.family: Services.Theme.fontDisplay
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Qt.formatDateTime(new Date(), "ddd, MMM d")
                                        color: Services.Theme.accent
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.5
                                    }
                                }
                            }

                            // Style 8: Cyberpunk / Terminal Monospace HUD
                            Rectangle {
                                visible: topClockColumn.clockStyle === "cyber"
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: cyberCol.implicitWidth + 40
                                implicitHeight: cyberCol.implicitHeight + 24
                                radius: 8
                                color: Qt.rgba(0, 0, 0, 0.75)
                                border.color: Services.Theme.accent
                                border.width: 1.5

                                ColumnLayout {
                                    id: cyberCol
                                    anchors.centerIn: parent
                                    spacing: 4

                                    RowLayout {
                                        spacing: 14
                                        Text {
                                            text: "┌[ SYS: LOCKED ]"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.accent
                                            font.bold: true
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "[ " + (Services.OsInfo.username || root.username) + "@" + (Services.OsInfo.hostname || root.hostname) + " ]┐"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.textSecondary
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.timeStr + ":" + String(new Date().getSeconds()).padStart(2, "0")
                                        font.family: Services.Theme.fontMono
                                        font.pixelSize: 44
                                        font.bold: true
                                        color: Services.Theme.white
                                    }

                                    RowLayout {
                                        spacing: 14
                                        Text {
                                            text: "└[ DATE: " + Qt.formatDateTime(new Date(), "yyyy.MM.dd") + " ]"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.textSecondary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "[ BAT: " + Math.round((Services.Power.percentage || 0.9) * 100) + "% ]┘"
                                            font.family: Services.Theme.fontMono
                                            font.pixelSize: 11
                                            color: Services.Theme.accent
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            // Ambient Greeting / Weather Subtitle (for styles other than vertical/radial/cyber)
                            RowLayout {
                                visible: (topClockColumn.clockStyle !== "vertical" && topClockColumn.clockStyle !== "radial" && topClockColumn.clockStyle !== "cyber") && (Services.Config ? Services.Config.lockscreenShowWeather : true)
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6
                                opacity: 0.85

                                Text {
                                    text: Services.Icons.sun || Services.Icons.sparkle
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 12
                                    color: Services.Theme.accent
                                }
                                Text {
                                    text: root.greetingStr + ", " + (Services.OsInfo.username || root.username)
                                    color: Services.Theme.textSecondary
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.weight: Font.Medium
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }
                        }

                        // ── 2. Bottom Profile Picture & Password Input System ────────────────────────
                        Item {
                            id: centerAuthCard
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: !root.isCompact ? parent.bottom : undefined
                            anchors.bottomMargin: !root.isCompact ? (root.isMinimal ? 24 : Math.max(36, Math.round(parent.height * 0.055))) : 0
                            anchors.verticalCenter: root.isCompact ? parent.verticalCenter : undefined
                            anchors.verticalCenterOffset: root.isCompact ? ((root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)) ? -15 : 0) : 0

                            width: root.isCompact ? Math.min(mainContainer.width - 40, 390) : 300
                            height: 195

                            readonly property string avatarShape: Services.Config ? Services.Config.lockscreenAvatarShape : "circle"
                            readonly property bool showAvatarRing: Services.Config ? Services.Config.lockscreenAvatarRing : true
                            readonly property string inputStyle: root.isMinimal ? "underline" : (Services.Config ? Services.Config.lockscreenInputStyle : "pill")
                            readonly property bool showPasswordBox: root.userRevealedInput || (root.passwordInput.length > 0) || root.isError || root.isAuthenticating || root.isCompact

                            readonly property int avatarRadius: {
                                if (avatarShape === "circle") return 24
                                if (avatarShape === "squircle") return 14
                                return 10
                            }
                            readonly property int ringRadius: {
                                if (avatarShape === "circle") return 27
                                if (avatarShape === "squircle") return 17
                                return 13
                            }

                            opacity: root.isRevealed ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                            // ── 1. Top Alerts & Banners (Fixed at Y: 0) ──────────────────────────
                            // Caps Lock Warning Banner
                            RowLayout {
                                visible: root.capsLockOn && !root.isError
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                spacing: 5

                                Text {
                                    text: Services.Icons.keyboard
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.warning
                                }

                                Text {
                                    text: "Caps Lock is on"
                                    color: Services.Theme.warning
                                    font.pixelSize: Services.Theme.fontSizeXs
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // PAM Authentication Error Banner
                            RowLayout {
                                visible: root.isError && root.errorMessage.length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                spacing: 5

                                Text {
                                    text: Services.Icons.error
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.danger
                                }

                                Text {
                                    text: root.errorMessage
                                    color: Services.Theme.danger
                                    font.pixelSize: Services.Theme.fontSizeSm
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }
                            }

                            // Modern PIN Dots Indicator Bar
                            RowLayout {
                                visible: !root.isCompact && centerAuthCard.inputStyle === "dots"
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 2
                                spacing: 10

                                Repeater {
                                    model: 6
                                    Rectangle {
                                        required property int index
                                        width: 14; height: 14; radius: 7
                                        color: (pwTextInput.text.length > index)
                                            ? (root.isError ? Services.Theme.danger : Services.Theme.accent)
                                            : Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.7)
                                        border.color: (pwTextInput.text.length > index)
                                            ? (root.isError ? Services.Theme.danger : Services.Theme.accent)
                                            : Services.Theme.border
                                        border.width: 1.5
                                        scale: (pwTextInput.text.length > index) ? 1.15 : 1.0

                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    }
                                }
                            }

                            // ── 2. Password Input Box (Fixed at Y: 20 - Fades/Scales smoothly without pushing anything) ──
                            Rectangle {
                                id: inputContainer
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 20
                                width: root.isCompact ? (parent.width - 40) : ((centerAuthCard.inputStyle === "underline") ? 240 : 250)
                                height: (centerAuthCard.inputStyle === "box") ? 42 : 38
                                radius: {
                                    if (centerAuthCard.inputStyle === "pill" || root.isCompact) return 19
                                    if (centerAuthCard.inputStyle === "box") return 8
                                    return 0
                                }
                                color: {
                                    if (!root.isCompact && (centerAuthCard.inputStyle === "underline" || centerAuthCard.inputStyle === "dots")) return "transparent"
                                    if (!root.isCompact && centerAuthCard.inputStyle === "box") return Services.Theme.bgElevated
                                    return pwTextInput.activeFocus 
                                        ? Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.85) 
                                        : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.65)
                                }
                                border.color: (!root.isCompact && (centerAuthCard.inputStyle === "underline" || centerAuthCard.inputStyle === "dots"))
                                    ? "transparent"
                                    : (root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border))
                                border.width: (!root.isCompact && (centerAuthCard.inputStyle === "underline" || centerAuthCard.inputStyle === "dots")) ? 0 : 1.5

                                visible: opacity > 0.01
                                opacity: centerAuthCard.showPasswordBox ? 1.0 : 0.0
                                scale: centerAuthCard.showPasswordBox ? 1.0 : 0.94
                                transformOrigin: Item.Bottom

                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                // Underline bar for "underline" style
                                Rectangle {
                                    visible: !root.isCompact && centerAuthCard.inputStyle === "underline"
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: pwTextInput.activeFocus ? 2 : 1
                                    color: root.isError ? Services.Theme.danger : (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border)
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on height { NumberAnimation { duration: 120 } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: (!root.isCompact && centerAuthCard.inputStyle === "underline") ? 6 : 12
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    // Leading Lock / State Icon
                                    Item {
                                        id: lockIconBox
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        Layout.alignment: Qt.AlignVCenter

                                        Text {
                                            id: lockStateIcon
                                            anchors.centerIn: parent
                                            text: {
                                                if (Services.FaceId && Services.FaceId.status === "success") return "󰌿"
                                                if (Services.FaceId && Services.FaceId.isScanning) return "󰘑"
                                                if (root.isAuthenticating) return Services.Icons.spinner
                                                if (root.isError) return Services.Icons.error
                                                return Services.Icons.lock
                                            }
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            color: {
                                                if (Services.FaceId && Services.FaceId.status === "success") return Services.Theme.success
                                                if (Services.FaceId && Services.FaceId.isScanning) return Services.Theme.accent
                                                if (root.isError) return Services.Theme.danger
                                                return (pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.textSecondary)
                                            }

                                            RotationAnimation on rotation {
                                                id: lockSpinAnim
                                                running: root.isAuthenticating
                                                loops: Animation.Infinite
                                                from: 0; to: 360; duration: 850
                                                onRunningChanged: {
                                                    if (!running) {
                                                        lockStateIcon.rotation = 0
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: {
                                                if ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified) {
                                                    root.unlockSuccess()
                                                    return
                                                }
                                                if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !Services.FaceId.isScanning) {
                                                    root.triggerFaceIdScan()
                                                }
                                                root.userRevealedInput = true
                                                pwTextInput.forceActiveFocus()
                                            }
                                        }
                                    }

                                    // Actual Password Input Container
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        TextInput {
                                            id: pwTextInput
                                            anchors.fill: parent
                                            echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                            passwordCharacter: "•"
                                            color: Services.Theme.textPrimary
                                            font.pixelSize: Services.Theme.fontSizeMd
                                            font.family: Services.Theme.fontMono
                                            verticalAlignment: TextInput.AlignVCenter
                                            clip: true
                                            focus: false
                                            cursorVisible: activeFocus
                                            enabled: !root.isAuthenticating

                                            onAccepted: {
                                                root.passwordInput = text
                                                if (text.length === 0 && ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified)) {
                                                    root.unlockSuccess()
                                                    return
                                                }
                                                root.authenticate()
                                            }

                                            onTextChanged: {
                                                root.passwordInput = text
                                                if (root.isError) {
                                                    root.isError = false
                                                    root.errorMessage = ""
                                                }
                                                if (text.length > 0) {
                                                    faceIdRetryTimer.stop()
                                                    if (root.deviceLockedPeekActive) {
                                                        deviceLockedPeekDurationTimer.stop()
                                                        root.deviceLockedPeekActive = false
                                                    }
                                                }
                                            }
                                        }

                                        // Placeholder prompt
                                        Text {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: {
                                                if (root.isAuthenticating) return "Authenticating..."
                                                if ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified) {
                                                    if (Services.FaceId && !Services.FaceId.autoUnlock) return "Press Enter to unlock"
                                                    return "Face ID Verified"
                                                }
                                                return "Enter Password"
                                            }
                                            color: ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified)
                                                ? Services.Theme.success
                                                : Qt.rgba(Services.Theme.textSecondary.r, Services.Theme.textSecondary.g, Services.Theme.textSecondary.b, 0.4)
                                            font.pixelSize: Services.Theme.fontSizeSm
                                            font.family: Services.Theme.fontPrimary
                                            visible: pwTextInput.text.length === 0 && !root.isAuthenticating
                                        }
                                    }
                                }
                            }

                            // ── 3. User Avatar (Fixed at Y: 72 - 100% IMMUTABLE POSITION) ────────
                            Item {
                                id: avatarBoxContainer
                                visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowAvatar : false)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 72
                                width: 56
                                height: 56

                                // Outer Glow / Focus Ring
                                Canvas {
                                    id: outerGlowRing
                                    anchors.centerIn: parent
                                    width: 54
                                    height: 54
                                    visible: centerAuthCard.showAvatarRing
                                    scale: pwTextInput.activeFocus ? 1.0 : 0.98

                                    property real r: centerAuthCard.ringRadius
                                    property real bw: pwTextInput.activeFocus ? 2 : 1.5
                                    property color bc: {
                                        if (Services.FaceId && Services.FaceId.status === "success") return Services.Theme.success
                                        if (Services.FaceId && Services.FaceId.isScanning) return Services.Theme.accent
                                        return root.isError
                                            ? Services.Theme.danger
                                            : (pwTextInput.activeFocus
                                                ? Services.Theme.accent
                                                : Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.3))
                                    }

                                    onRChanged: requestPaint()
                                    onBwChanged: requestPaint()
                                    onBcChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        ctx.clearRect(0, 0, width, height)
                                        if (width <= 0 || height <= 0 || bw <= 0) return
                                        ctx.strokeStyle = bc
                                        ctx.lineWidth = bw
                                        var half = bw / 2
                                        var rad = Math.max(0, Math.min(r - half, (width - bw) / 2, (height - bw) / 2))
                                        if (rad <= 0) return
                                        ctx.beginPath()
                                        ctx.moveTo(half + rad, half)
                                        ctx.lineTo(width - half - rad, half)
                                        ctx.arcTo(width - half, half, width - half, half + rad, rad)
                                        ctx.lineTo(width - half, height - half - rad)
                                        ctx.arcTo(width - half, height - half, width - half - rad, height - half, rad)
                                        ctx.lineTo(half + rad, height - half)
                                        ctx.arcTo(half, height - half, half, height - half - rad, rad)
                                        ctx.lineTo(half, half + rad)
                                        ctx.arcTo(half, half, half + rad, half, rad)
                                        ctx.closePath()
                                        ctx.stroke()
                                    }

                                    Behavior on bc { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    SequentialAnimation on opacity {
                                        running: pwTextInput.activeFocus || root.isAuthenticating || (Services.FaceId && Services.FaceId.isScanning)
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 0.5; duration: 1000; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.5; to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
                                    }
                                }

                                // Main Avatar Container
                                Services.AvatarFrame {
                                    id: avatarBox
                                    anchors.centerIn: parent
                                    width: 48
                                    height: 48
                                    source: Services.OsInfo.avatarPath.length > 0 ? Services.OsInfo.avatarPath : ("file://" + (Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")) + "/.face")
                                    shapeRadius: centerAuthCard.avatarRadius
                                    backgroundColor: Services.Theme.surfaceVariant
                                    borderColor: pwTextInput.activeFocus ? Services.Theme.accent : Services.Theme.border
                                    borderWidth: 1.5
                                    fallbackText: {
                                        const u = (Services.OsInfo.username || root.username) || "U"
                                        return u.charAt(0).toUpperCase()
                                    }
                                    fallbackFontFamily: Services.Theme.fontDisplay
                                    fallbackFontSize: 20
                                    fallbackColor: Services.Theme.accent
                                    Behavior on borderColor { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            // ── 4. Username Tag (Fixed at Y: 136 - 100% IMMUTABLE POSITION) ──────
                            Text {
                                id: usernameText
                                visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowGreeting : false)
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 136
                                horizontalAlignment: Text.AlignHCenter
                                text: Services.OsInfo.username.length > 0 ? Services.OsInfo.username : root.username
                                color: Services.Theme.textPrimary
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                font.letterSpacing: 0.3
                                style: Text.Outline
                                styleColor: Services.Theme.overlayDim
                            }

                            // ── 5. Idle Prompt (Fixed at Y: 160 - Fades smoothly without shifting layout) ──
                            Item {
                                id: authPrompt
                                visible: opacity > 0.01
                                opacity: (!centerAuthCard.showPasswordBox && !root.isCompact) ? 0.85 : 0.0
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 160
                                width: promptLabel.implicitWidth + 20
                                height: 20
                                Behavior on opacity { NumberAnimation { duration: 200 } }

                                Text {
                                    id: promptLabel
                                    anchors.centerIn: parent
                                    text: {
                                        if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled) {
                                            if (Services.FaceId.status === "success" || root.isFaceVerified) {
                                                if (!Services.FaceId.autoUnlock) return "Press Enter to unlock"
                                                return "Face ID Verified"
                                            }
                                            if (Services.FaceId.status === "detected") return "Verifying Face..."
                                            if (Services.FaceId.status === "scanning") return "Looking for Face..."
                                            if (Services.FaceId.status === "timeout") return "Face not matched (Click to retry)"
                                            return "Face ID or Enter Password"
                                        }
                                        return "Touch ID or Enter Password"
                                    }
                                    color: (Services.FaceId && (Services.FaceId.status === "success" || root.isFaceVerified)) ? Services.Theme.success : Services.Theme.textSecondary
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    style: Text.Outline
                                    styleColor: Services.Theme.overlayDim
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if ((Services.FaceId && Services.FaceId.status === "success") || root.isFaceVerified) {
                                            root.unlockSuccess()
                                            return
                                        }
                                        if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !Services.FaceId.isScanning) {
                                            root.triggerFaceIdScan()
                                        }
                                        root.userRevealedInput = true
                                        pwTextInput.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        // ── Minimalist Notification Pill Indicator (Minimal Layout Only) ──
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: centerAuthCard.bottom
                            anchors.topMargin: 18
                            height: 24
                            implicitWidth: minNotifRow.implicitWidth + 16
                            radius: 12
                            color: Qt.rgba(Services.Theme.surfaceVariant.r, Services.Theme.surfaceVariant.g, Services.Theme.surfaceVariant.b, 0.6)
                            border.color: Services.Theme.border
                            border.width: 1
                            visible: root.isMinimal && root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: (root.isMinimal && root.notifCount > 0 && root.isRevealed) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 250 } }

                            RowLayout {
                                id: minNotifRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: Services.Icons.bell
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 10
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: root.notifCount + (root.notifCount === 1 ? " Notification" : " Notifications")
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: Services.Theme.textPrimary
                                }
                            }
                        }

                        // ── Floating Overlapping Notification Cards Overlay (Default & Compact Layouts) ──
                        Item {
                            id: notifStackContainer
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: topClockColumn.bottom
                            anchors.topMargin: 36
                            width: Math.min(mainContainer.width - 50, 320)
                            height: 90
                            z: 100
                            visible: !root.isMinimal && root.notifCount > 0 && root.isRevealed && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: (!root.isMinimal && root.notifCount > 0 && root.isRevealed) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            Repeater {
                                model: Services.Notifications.historyList

                                delegate: NotifModule.PopupCard {
                                    required property var modelData
                                    required property int index

                                    visible: index < 2
                                    notif: modelData

                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: notifStackContainer.width

                                    // Overlap Effect (Solid color, older card peeks UPWARDS)
                                    z: 20 - index
                                    y: -index * 8
                                    scale: index === 0 ? 1.0 : 0.96
                                    opacity: 1.0

                                    Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }
                        }

                        // ── 3. Bottom-Left Corner: Sleek Frosted Glass Music Tile (Not a Pill, Marquee Title, Play/Stop/Next) ───────────────
                        Rectangle {
                            id: cornerMediaCard
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 24
                            width: 250
                            height: 56
                            radius: 12
                            color: Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.82)
                            border.color: Services.Theme.borderHighlight
                            border.width: 1
                            clip: true
                            visible: root.isDefault && root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
                            opacity: (root.isDefault && root.isRevealed && root.hasPlayer) ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                // Album Art Thumbnail (38x38, radius 8)
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 8
                                    color: Services.Theme.surfaceVariant
                                    border.color: Services.Theme.border
                                    border.width: 1
                                    clip: true

                                    Image {
                                        id: cornerArtImg
                                        anchors.fill: parent
                                        source: root.player?.trackArtUrl ?? ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        visible: status === Image.Ready
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.musicNote
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 16
                                        color: Services.Theme.accent
                                        visible: cornerArtImg.status !== Image.Ready
                                    }
                                }

                                // Title (Marquee if long) & Artist
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 1

                                    Item {
                                        id: marqueeBox
                                        Layout.fillWidth: true
                                        height: 16
                                        clip: true

                                        Text {
                                            id: marqueeTitle
                                            text: root.player?.trackTitle || "No Media"
                                            color: Services.Theme.textPrimary
                                            font.pixelSize: 11
                                            font.weight: Font.Bold

                                            property real overflow: Math.max(0, implicitWidth - marqueeBox.width)

                                            SequentialAnimation on x {
                                                running: marqueeTitle.overflow > 0 && root.isPlaying
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: 1600 }
                                                NumberAnimation {
                                                    from: 0
                                                    to: -marqueeTitle.overflow
                                                    duration: Math.max(2000, marqueeTitle.overflow * 35)
                                                    easing.type: Easing.Linear
                                                }
                                                PauseAnimation { duration: 1600 }
                                                NumberAnimation {
                                                    from: -marqueeTitle.overflow
                                                    to: 0
                                                    duration: 500
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: root.player?.trackArtist || (root.player?.trackAlbum || "Unknown Artist")
                                        color: Services.Theme.textSecondary
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Controls (Prev, Play/Pause, Next)
                                RowLayout {
                                    spacing: 2
                                    Layout.alignment: Qt.AlignVCenter

                                    // Prev
                                    Rectangle {
                                        width: 24; height: 24; radius: 6
                                        color: prevCornerMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaPrev
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Theme.textPrimary
                                        }
                                        MouseArea {
                                            id: prevCornerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.player?.previous()
                                        }
                                    }

                                    // Play / Pause / Stop
                                    Rectangle {
                                        width: 26; height: 26; radius: 6
                                        color: playCornerMouse.containsMouse ? Services.Theme.white : Services.Theme.accent
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaPlayPause(root.isPlaying)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            color: Services.Theme.bgDeep
                                        }
                                        MouseArea {
                                            id: playCornerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.player?.togglePlaying()
                                        }
                                    }

                                    // Next
                                    Rectangle {
                                        width: 24; height: 24; radius: 6
                                        color: nextCornerMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaNext
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 10
                                            color: Services.Theme.textPrimary
                                        }
                                        MouseArea {
                                            id: nextCornerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.player?.next()
                                        }
                                    }
                                }
                            }
                        }

                        // Mode C: Minimalist Single-Line Media Player (Minimal Layout)
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 24
                            height: 28
                            implicitWidth: minMediaRow.implicitWidth + 16
                            visible: root.isMinimal && root.hasPlayer && (Services.Config ? Services.Config.lockscreenShowMedia : true)
                            opacity: (root.isMinimal && root.isRevealed && root.hasPlayer) ? 0.85 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            RowLayout {
                                id: minMediaRow
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: Services.Icons.musicNote
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.accent
                                }

                                Text {
                                    text: (root.player?.trackTitle || "") + (root.player?.trackArtist ? " — " + root.player.trackArtist : "")
                                    color: Services.Theme.textPrimary
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 240
                                }

                                Text {
                                    text: Services.Icons.mediaPlayPause(root.isPlaying)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: 11
                                    color: Services.Theme.accent

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.player?.togglePlaying()
                                    }
                                }
                            }
                        }

                        // ── 4. Bottom Right: Power Button & Floating Power Menu Panel (Default & Minimal Layouts) ──
                        Item {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 24
                            anchors.bottomMargin: root.isRevealed ? 24 : 0
                            width: root.isMinimal ? 32 : 38
                            height: root.isMinimal ? 32 : 38
                            visible: !root.isCompact && (Services.Config ? Services.Config.lockscreenShowQuickPower : true)
                            opacity: (root.isRevealed && !root.isCompact) ? 1.0 : 0.0
                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                            // Floating Power Menu Panel (Opens right above the button)
                            Rectangle {
                                id: pwrMenuPopup
                                anchors.bottom: pwrBtnRound.top
                                anchors.right: parent.right
                                anchors.bottomMargin: 12
                                width: 220
                                implicitHeight: pwrMenuCol.implicitHeight + 20
                                radius: Services.Theme.radiusLg
                                color: Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.95)
                                border.color: Services.Theme.borderHighlight
                                border.width: 1
                                clip: true

                                visible: root.lockscreenPwrOpen
                                opacity: root.lockscreenPwrOpen ? 1.0 : 0.0
                                scale: root.lockscreenPwrOpen ? 1.0 : 0.85
                                transformOrigin: Item.BottomRight
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {}
                                }

                                ColumnLayout {
                                    id: pwrMenuCol
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    // Header
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "Power Options"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Services.Theme.textPrimary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            width: 20; height: 20; radius: 10
                                            color: pwrCloseMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: Services.Icons.close
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 9
                                                color: Services.Theme.textSecondary
                                            }
                                            MouseArea {
                                                id: pwrCloseMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.lockscreenPwrOpen = false
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Services.Theme.border
                                    }

                                    // Sleep Option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: Services.Theme.radiusSm
                                        color: sleepMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.pmSleep
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: sleepMouse.containsMouse ? Services.Theme.accent : Services.Theme.accentDim
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { text: "Sleep"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary }
                                                Text { text: "Suspend session"; font.pixelSize: 8; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        MouseArea {
                                            id: sleepMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lockscreenPwrOpen = false
                                                suspendProc.running = true
                                            }
                                        }
                                    }

                                    // Reboot Option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: Services.Theme.radiusSm
                                        color: rebootMouse.containsMouse ? Qt.rgba(Services.Theme.warning.r, Services.Theme.warning.g, Services.Theme.warning.b, 0.15) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.pmReboot
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: Services.Theme.warning
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { text: "Reboot"; font.pixelSize: 11; font.bold: true; color: Services.Theme.textPrimary }
                                                Text { text: "Restart system"; font.pixelSize: 8; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        MouseArea {
                                            id: rebootMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lockscreenPwrOpen = false
                                                rebootProc.running = true
                                            }
                                        }
                                    }

                                    // Shutdown Option
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 36
                                        radius: Services.Theme.radiusSm
                                        color: shutdownMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 10

                                            Text {
                                                text: Services.Icons.pmShutdown
                                                font.family: Services.Theme.fontSymbols
                                                font.pixelSize: 14
                                                color: Services.Theme.danger
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text { text: "Power Off"; font.pixelSize: 11; font.bold: true; color: Services.Theme.danger }
                                                Text { text: "Turn off PC"; font.pixelSize: 8; color: Services.Theme.textDisabled }
                                            }
                                        }

                                        MouseArea {
                                            id: shutdownMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.lockscreenPwrOpen = false
                                                shutdownProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Single Circular Power Button
                            Rectangle {
                                id: pwrBtnRound
                                anchors.fill: parent
                                radius: root.isMinimal ? 16 : 19
                                color: root.isMinimal
                                    ? (pwrBtnMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.2) : "transparent")
                                    : ((root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) 
                                        ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.25)
                                        : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.75))
                                border.color: root.isMinimal
                                    ? (pwrBtnMouse.containsMouse ? Services.Theme.danger : "transparent")
                                    : ((root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) ? Services.Theme.danger : Services.Theme.border)
                                border.width: root.isMinimal ? (pwrBtnMouse.containsMouse ? 1 : 0) : 1
                                opacity: root.isMinimal ? (pwrBtnMouse.containsMouse || root.lockscreenPwrOpen ? 1.0 : 0.6) : 1.0
                                scale: pwrBtnMouse.pressed ? 0.92 : 1.0
                                Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Services.Icons.power
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: root.isMinimal ? 13 : 15
                                    color: (root.lockscreenPwrOpen || pwrBtnMouse.containsMouse) ? Services.Theme.danger : Services.Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: pwrBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.lockscreenPwrOpen = !root.lockscreenPwrOpen
                                        if (root.lockscreenPwrOpen) root.lockscreenCcOpen = false
                                    }
                                }
                            }
                        }

                    }
                }

                // ── Control Center Overlay Panel on Lockscreen ──
                Item {
                    id: ccLockscreenOverlay
                    anchors.fill: parent
                    z: 9999
                    visible: root.lockscreenCcOpen
                    opacity: root.lockscreenCcOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.lockscreenCcOpen = false
                    }

                    LockscreenControlCenter {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 54
                        anchors.rightMargin: 20
                        onRequestClose: root.lockscreenCcOpen = false
                    }
                }
            }
        }
    }
}
