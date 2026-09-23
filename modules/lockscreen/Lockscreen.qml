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
    property bool faceIdCancelledByUser: false
    property bool faceIconActive: false
    property bool faceTextActive: false
    property real unlockSuctionProgress: 0.0
    property bool isUnlockingWithGenie: false
    property real lockTopBarState: 0.0

    Binding {
        target: Services.OverlayManager
        property: "isUnlockingWithGenie"
        value: root.isUnlockingWithGenie
    }
    Binding {
        target: Services.OverlayManager
        property: "unlockSuctionProgress"
        value: root.unlockSuctionProgress
    }
    Binding {
        target: Services.OverlayManager
        property: "lockVerified"
        when: root.isLocked
        value: root.isFaceVerified || root.isUnlockingWithGenie
    }

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

    Timer {
        id: sessionLockCommitTimer
        interval: 290
        repeat: false
        onTriggered: {
            if (Services.OverlayManager) {
                Services.OverlayManager.isLockAbsorbing = false
                Services.OverlayManager.isLocked = true
            }
            root.isLocked = true
            sessionLock.locked = true
            revealTimer.restart()
            deviceLockedPeekStartTimer.restart()
        }
    }

    onIsRevealedChanged: {
        if (root.isRevealed) {
            root.deviceLockedPeekActive = false
            deviceLockedPeekStartTimer.restart()
            lockTopBarEjectAnim.restart()
        } else {
            deviceLockedPeekStartTimer.stop()
            deviceLockedPeekDurationTimer.stop()
            root.deviceLockedPeekActive = false
            root.lockTopBarState = 0.0
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
        id: lockCleanupTimer
        interval: 160
        repeat: false
        onTriggered: {
            root.isFaceVerified = false
            root.isFaceContracted = false
            root.isFaceTimeoutContracted = false
            root.faceIdRetryCount = 0
            root.faceIdCancelledByUser = false
            root.deviceLockedPeekActive = false
            root.hasPeekedLocked = false
            root.faceIconActive = false
            root.faceTextActive = false
            root.isUnlockingWithGenie = false
            root.unlockSuctionProgress = 0.0
            root.lockTopBarState = 0.0
            if (Services.FaceId) Services.FaceId.resetStatus()
            if (Services.OverlayManager) {
                Services.OverlayManager.lockVerified = false
                Services.OverlayManager.isUnlockingWithGenie = false
                Services.OverlayManager.unlockSuctionProgress = 0.0
                Services.OverlayManager.isLockAbsorbing = false
            }
            if (pam.active) pam.abort()
        }
    }

    NumberAnimation {
        id: lockTopBarEjectAnim
        target: root
        property: "lockTopBarState"
        from: 0.0
        to: 1.0
        duration: 340
        easing.type: Easing.OutBack
        easing.overshoot: 1.25
    }

    SequentialAnimation {
        id: lockTopBarAbsorbAnim
        running: false
        NumberAnimation {
            target: root
            property: "lockTopBarState"
            from: 1.0
            to: 0.0
            duration: 200
            easing.type: Easing.InBack
            easing.overshoot: 1.15
        }
        ScriptAction {
            script: {
                if (Services.Config && Services.Config.lockscreenGenieUnlock && root.isDefault) {
                    unlockGenieAnim.restart()
                } else {
                    root.isRevealed = false
                    unlockTimer.start()
                }
            }
        }
    }

    SequentialAnimation {
        id: unlockGenieAnim
        running: false
        PropertyAction { target: root; property: "isUnlockingWithGenie"; value: true }
        NumberAnimation {
            target: root
            property: "unlockSuctionProgress"
            from: 0.0
            to: 1.0
            duration: 520
            easing.type: Easing.InOutQuad
        }
        ScriptAction {
            script: {
                root.isLocked = false
                Services.OverlayManager.isLocked = false
                sessionLock.locked = false
            }
        }
    }


    Timer {
        id: deviceLockedPeekStartTimer
        interval: 520
        repeat: false
        onTriggered: root.triggerDeviceLockedPeek()
    }

    Timer {
        id: deviceLockedPeekDurationTimer
        interval: 1300
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Device Locked peek duration elapsed -> contracting peek, settling into lock capsule")
            root.deviceLockedPeekActive = false
            root.hasPeekedLocked = true
            if (Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !root.isFaceVerified && !Services.FaceId.isScanning) {
                faceIdScanTimer.restart()
            }
        }
    }

    Timer {
        id: faceIdScanTimer
        interval: 520
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Face ID delay timer triggered. isLocked:", root.isLocked, "FaceId:", Services.FaceId, "isEnabled:", Services.FaceId?.isEnabled)
            if (root.isLocked && Services.FaceId && Services.FaceId.isEnabled && Services.FaceId.isEnrolled && !root.isFaceVerified && !Services.FaceId.isScanning) {
                root.triggerFaceIdScan()
            }
        }
    }

    Timer {
        id: textOpenDelayTimer
        interval: 190
        repeat: false
        onTriggered: root.faceTextActive = true
    }

    Timer {
        id: iconCloseDelayTimer
        interval: 160
        repeat: false
        onTriggered: root.faceIconActive = false
    }

    onIsFaceActiveChanged: {
        if (root.isFaceActive) {
            iconCloseDelayTimer.stop()
            root.faceIconActive = true
            textOpenDelayTimer.restart()
        } else {
            textOpenDelayTimer.stop()
            root.faceTextActive = false
            iconCloseDelayTimer.restart()
        }
    }

    Timer {
        id: faceIdContractTimer
        interval: 850
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Face ID contract timer triggered -> contracting island")
            root.isFaceContracted = true
        }
    }

    Timer {
        id: faceIdAutoUnlockContractTimer
        interval: 650
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Auto-unlock: contracting face canvas before unlocking desktop")
            root.isFaceContracted = true
            faceIdUnlockDelayTimer.restart()
        }
    }

    Timer {
        id: faceIdTimeoutShrinkTimer
        interval: 1400
        repeat: false
        onTriggered: {
            root.isFaceTimeoutContracted = true
            if (Services.FaceId) Services.FaceId.stopScan()
            if (!root.faceIdCancelledByUser && root.isLocked && !root.isFaceVerified && root.faceIdRetryCount < root.maxFaceIdRetries) {
                console.log("[Lockscreen] Face ID failed, scheduling retry in 3s. Current retryCount:", root.faceIdRetryCount)
                faceIdRetryTimer.restart()
            } else {
                console.log("[Lockscreen] Face ID cancelled or max retries reached. No more auto retries.")
            }
        }
    }

    Timer {
        id: faceIdRetryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.faceIdCancelledByUser && root.isLocked && !root.isFaceVerified && !root.isFaceActive && root.faceIdRetryCount < root.maxFaceIdRetries) {
                root.faceIdRetryCount++
                console.log("[Lockscreen] Executing Face ID auto-retry #" + root.faceIdRetryCount)
                root.triggerFaceIdScan()
            }
        }
    }

    Timer {
        id: faceIdUnlockDelayTimer
        interval: 600
        repeat: false
        onTriggered: {
            console.log("[Lockscreen] Face ID auto-unlock triggered (canvas closed)")
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

        root.faceIdCancelledByUser = false
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
        console.log("[Lockscreen] stopFaceIdScan called (user cancelled)")
        root.faceIdCancelledByUser = true
        root.faceIdRetryCount = root.maxFaceIdRetries
        faceIdScanTimer.stop()
        faceIdRetryTimer.stop()
        faceIdContractTimer.stop()
        faceIdAutoUnlockContractTimer.stop()
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
                faceIdAutoUnlockContractTimer.restart()
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
            if (!root.faceIdCancelledByUser) {
                faceIdTimeoutShrinkTimer.restart()
            }
        }
    }

    function open() {
        if (isLocked && sessionLock.locked && root.isRevealed) return
        if (Services.FaceId) Services.FaceId.resetStatus()
        faceIdUnlockDelayTimer.stop()
        faceIdAutoUnlockContractTimer.stop()
        faceIdContractTimer.stop()
        faceIdTimeoutShrinkTimer.stop()
        faceIdRetryTimer.stop()
        deviceLockedPeekStartTimer.stop()
        deviceLockedPeekDurationTimer.stop()
        faceIdScanTimer.stop()
        root.faceIdRetryCount = 0
        root.faceIdCancelledByUser = false
        root.deviceLockedPeekActive = false
        root.isFaceContracted = false
        root.isFaceTimeoutContracted = false
        root.isFaceVerified = false
        root.hasPeekedLocked = false
        textOpenDelayTimer.stop()
        iconCloseDelayTimer.stop()
        root.faceIconActive = false
        root.faceTextActive = false
        unlockGenieAnim.stop()
        lockTopBarAbsorbAnim.stop()
        root.unlockSuctionProgress = 0.0
        root.isUnlockingWithGenie = false
        root.lockTopBarState = 0.0
        if (Services.OverlayManager) {
            Services.OverlayManager.isUnlockingWithGenie = false
            Services.OverlayManager.unlockSuctionProgress = 0.0
            Services.OverlayManager.lockVerified = false
            Services.OverlayManager.isLockAbsorbing = true
        }
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
        const needsMediaStop = Boolean(Services.Mpris && Services.Mpris.activePlayer && Services.Mpris.activePlayer.isPlaying)
        const needsNotifShrink = Boolean((Services.OverlayManager && Services.OverlayManager.desktopIslandIsWide) ||
                                        (Services.Notifications && Services.Notifications.popupList && Services.Notifications.popupList.count > 0))
        sessionLockCommitTimer.interval = needsMediaStop ? 700 : (needsNotifShrink ? 500 : 280)
        sessionLockCommitTimer.restart()
    }

    function close() {
        sessionLockCommitTimer.stop()
        if (isLocked) {
            triggerShake("Password required!")
            return
        }
        root.isLocked = false
        root.lockTopBarState = 0.0
        if (Services.OverlayManager) {
            Services.OverlayManager.isLockAbsorbing = false
            Services.OverlayManager.isLocked = false
        }
        sessionLock.locked = false
    }

    function lock() { open() }
    function show() { open() }
    function hide() {
        if (!isLocked) {
            root.isLocked = false
            root.lockTopBarState = 0.0
            if (Services.OverlayManager) {
                Services.OverlayManager.isLockAbsorbing = false
                Services.OverlayManager.isLocked = false
            }
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
        pendingPassword = pw
        if (Services.FaceId) Services.FaceId.stopScan()
        pam.start(root.username)
    }

    function triggerShake(msg) {
        errorMessage = msg || "Authentication error"
        isError = true
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
        capsLockOn = false
        lockscreenCcOpen = false
        lockscreenPwrOpen = false
        faceIdUnlockDelayTimer.stop()
        faceIdAutoUnlockContractTimer.stop()
        faceIdContractTimer.stop()
        faceIdTimeoutShrinkTimer.stop()
        faceIdRetryTimer.stop()
        root.faceIdRetryCount = 0
        root.faceIdCancelledByUser = false
        if (Services.FaceId) Services.FaceId.stopScan()
        if (Services.OverlayManager) Services.OverlayManager.lockVerified = true
        lockTopBarAbsorbAnim.restart()
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
                faceIdAutoUnlockContractTimer.stop()
                faceIdContractTimer.stop()
                faceIdTimeoutShrinkTimer.stop()
                faceIdRetryTimer.stop()
                deviceLockedPeekStartTimer.stop()
                deviceLockedPeekDurationTimer.stop()
                faceIdScanTimer.stop()
                root.faceIdRetryCount = 0
                root.faceIdCancelledByUser = false
                root.deviceLockedPeekActive = false
                root.isFaceContracted = false
                root.isFaceTimeoutContracted = false
                root.hasPeekedLocked = false
                textOpenDelayTimer.stop()
                iconCloseDelayTimer.stop()
                root.faceIconActive = false
                root.faceTextActive = false
                lockCleanupTimer.restart()
                root.passwordInput = ""
                root.pendingPassword = ""
                root.isAuthenticating = false
                root.isRevealed = false
                root.capsLockOn = false
                if (typeof pwTextInput !== "undefined" && pwTextInput) pwTextInput.text = ""
                if (pam.active) pam.abort()
            } else {
                sessionLockCommitTimer.stop()
                if (Services.OverlayManager) {
                    Services.OverlayManager.isLockAbsorbing = false
                    Services.OverlayManager.isLocked = true
                }
                if (Services.FaceId) Services.FaceId.resetStatus()
                unlockGenieAnim.stop()
                lockTopBarAbsorbAnim.stop()
                root.unlockSuctionProgress = 0.0
                root.isUnlockingWithGenie = false
                root.lockTopBarState = 0.0
                faceIdUnlockDelayTimer.stop()
                faceIdAutoUnlockContractTimer.stop()
                faceIdContractTimer.stop()
                faceIdTimeoutShrinkTimer.stop()
                faceIdRetryTimer.stop()
                textOpenDelayTimer.stop()
                iconCloseDelayTimer.stop()
                root.faceIconActive = false
                root.faceTextActive = false
                root.faceIdRetryCount = 0
                root.faceIdCancelledByUser = false
                root.isFaceContracted = false
                root.isFaceTimeoutContracted = false
                root.isFaceVerified = false
                root.hasPeekedLocked = false
                root.deviceLockedPeekActive = false
                root.isRevealed = false
                revealTimer.restart()
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
                        if (root.lockscreenCcOpen || root.lockscreenPwrOpen) {
                            root.lockscreenCcOpen = false
                            root.lockscreenPwrOpen = false
                            event.accepted = true
                            return
                        }
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
                        scale: {
                            if (Services.Config && !Services.Config.lockscreenWallpaperZoom) return 1.0
                            if (!root.isLocked) return 1.0
                            if (root.isUnlockingWithGenie) return 1.16 - 0.16 * root.unlockSuctionProgress
                            return root.isRevealed ? 1.12 : 1.0
                        }
                        transformOrigin: Item.Center
                        visible: !(Services.Config && Services.Config.lockscreenBlur && (Services.Config.lockscreenBlurRadius > 0))
                        Behavior on scale {
                            enabled: !root.isUnlockingWithGenie
                            NumberAnimation { duration: 350; easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic }
                        }
                    }

                    MultiEffect {
                        anchors.fill: bgImage
                        source: bgImage
                        scale: bgImage.scale
                        transformOrigin: Item.Center
                        blurEnabled: (Services.Config && Services.Config.lockscreenBlur) || false
                        blur: {
                            if (!root.isLocked || (!root.isRevealed && !root.isUnlockingWithGenie)) return 0.0
                            var baseBlur = Services.Config ? Services.Config.lockscreenBlurRadius : 0.40
                            if (root.isUnlockingWithGenie) return baseBlur * (1.0 - root.unlockSuctionProgress)
                            return root.isRevealed ? baseBlur : 0.0
                        }
                        blurMax: 64
                        visible: (Services.Config && Services.Config.lockscreenBlur && (Services.Config.lockscreenBlurRadius > 0)) || false
                        Behavior on blur {
                            enabled: !root.isUnlockingWithGenie
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    // Smooth Dark Dim / Vignette Overlay
                    Rectangle {
                        anchors.fill: parent
                        color: Services.Theme.bgDeep
                        opacity: {
                            if (!root.isLocked) return 0.0
                            if (!root.isRevealed && !root.isUnlockingWithGenie) return 0.0
                            var baseDim = Services.Config ? Services.Config.lockscreenDim : 0.45
                            if (root.isCompact) baseDim = Math.min(0.85, baseDim + 0.15)
                            else if (root.isMinimal) baseDim = Math.max(0.18, baseDim - 0.12)
                            if (root.isUnlockingWithGenie) return baseDim * (1.0 - root.unlockSuctionProgress)
                            return root.isRevealed ? baseDim : 0.0
                        }
                        Behavior on opacity {
                            enabled: !root.isUnlockingWithGenie
                            NumberAnimation {
                                duration: 380
                                easing.type: root.isRevealed ? Easing.OutCubic : Easing.InCubic
                            }
                        }
                    }
                }

                // ── Top Header Bar (Center: DynamicIsland, Right: Quick Status & ControlCenter) ──
                Item {
                    id: topBarHeader
                    anchors.top: parent.top
                    anchors.topMargin: 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 48
                    z: 10000
                    visible: !root.isCompact
                    opacity: root.isCompact ? 0.0 : 1.0
                    scale: 1.0

                    // Center: Dynamic Island (Apple Face ID & Status Capsule)
                    Rectangle {
                        id: lockIsland
                        visible: root.isDefault
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Services.Theme.bgPure

                        readonly property bool isVerified: root.isFaceVerified
                        readonly property bool isFaceActive: root.isFaceActive
                        readonly property bool isDeviceLockedPeek: root.isDeviceLockedPeek

                        readonly property bool isFaceSuccess: Boolean(
                            root.isFaceActive &&
                            Services.FaceId &&
                            Services.FaceId.status === "success"
                        )

                        readonly property bool isIslandExpanded: (root.faceIconActive || root.isFaceActive)

                        scale: {
                            if (root.isUnlockingWithGenie) return 1.0 + 0.14 * Math.sin(root.unlockSuctionProgress * Math.PI)
                            return 1.0
                        }

                        border.color: {
                            if (root.isFaceVerified || root.isUnlockingWithGenie) return "#30d158"
                            if (lockIsland.isIslandExpanded && Services.FaceId && Services.FaceId.status === "detected") return "#38bdf8"
                            if (root.isDeviceLockedPeek) return Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.35)
                            return Services.Theme.borderSubtle
                        }
                        border.width: (root.isFaceVerified || root.isUnlockingWithGenie) ? 2.0 : (((lockIsland.isIslandExpanded && Services.FaceId && Services.FaceId.status === "detected") || root.isDeviceLockedPeek) ? 1.5 : 1)

                        width: lockIsland.isIslandExpanded ? 160 : (root.isDeviceLockedPeek ? 218 : 140)
                        height: lockIsland.isIslandExpanded ? 96 : (root.isDeviceLockedPeek ? 44 : 32)
                        radius: height / 2

                        Behavior on width  { enabled: !root.isUnlockingWithGenie; NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 } }
                        Behavior on height { enabled: !root.isUnlockingWithGenie; NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 } }
                        Behavior on radius {
                            enabled: lockIsland.isIslandExpanded || (lockIsland.height > 50)
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                        Behavior on border.color { ColorAnimation { duration: 250 } }
                        Behavior on border.width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        MouseArea {
                            anchors.fill: parent
                            z: 20
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

                        // ==================== SINGLE MASTER MORPHING ICON ====================
                        Item {
                            id: masterMorphIcon
                            z: 10

                            readonly property bool isFace: root.faceIconActive
                            readonly property bool isPeek: root.isDeviceLockedPeek && !isFace

                            // Exact coordinates:
                            // Dot: Center x=60, y=6, w=20
                            // Peek: Left x=10, y=8, w=28
                            // Collapsed Lock: Left x=14, y=6, w=20 (Lock icon stays on the left)
                            // Face ID: Center x=63, y=16, w=34 (Upper center)
                            // Unlocked: Left x=14, y=6, w=20
                            x: {
                                if (masterMorphIcon.isFace) return 63
                                if (masterMorphIcon.isPeek) return 10
                                if (root.hasPeekedLocked || root.isFaceVerified) return 14
                                if (root.isUnlockingWithGenie) return 60
                                return 60
                            }
                            y: {
                                if (masterMorphIcon.isFace) return 16
                                if (masterMorphIcon.isPeek) return 8
                                return 6
                            }
                            width: {
                                if (masterMorphIcon.isFace) return 34
                                if (masterMorphIcon.isPeek) return 28
                                return 20
                            }
                            height: width

                            Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 } }
                            Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 } }
                            Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.10 } }

                            // Continuous morph progress (synchronized with capsule expansion)
                            property real faceProgress: isFace ? 1.0 : 0.0
                            Behavior on faceProgress {
                                NumberAnimation {
                                    duration: 340
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.10
                                }
                            }

                            property real peekProgress: isPeek ? 1.0 : 0.0
                            Behavior on peekProgress {
                                NumberAnimation {
                                    duration: 320
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.10
                                }
                            }

                            // Parabolic in-flight factor: 0.0 at rest, 1.0 at peak velocity (mid-flight)
                            readonly property real faceTransitFactor: 4.0 * faceProgress * (1.0 - faceProgress)
                            readonly property real peekTransitFactor: 4.0 * peekProgress * (1.0 - peekProgress)
                            readonly property real transitFactor: Math.max(faceTransitFactor, peekTransitFactor)

                            // Subtle liquid squash & stretch aligned exactly with flight path
                            transform: Scale {
                                origin.x: masterMorphIcon.width / 2
                                origin.y: masterMorphIcon.height / 2
                                xScale: 1.0 + 0.14 * masterMorphIcon.transitFactor
                                yScale: 1.0 - 0.08 * masterMorphIcon.transitFactor
                            }

                            // 1. Circular Badge Ring (Blooms during Peek)
                            Rectangle {
                                id: peekBadgeRing
                                anchors.fill: parent
                                radius: width / 2
                                color: masterMorphIcon.isPeek 
                                    ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.16) 
                                    : "transparent"
                                border.color: masterMorphIcon.isPeek 
                                    ? Qt.rgba(Services.Theme.accent.r, Services.Theme.accent.g, Services.Theme.accent.b, 0.28) 
                                    : "transparent"
                                border.width: 1
                                opacity: masterMorphIcon.isPeek ? 1.0 : 0.0
                                scale: 0.60 + 0.40 * masterMorphIcon.peekProgress
                                Behavior on color { ColorAnimation { duration: 220 } }
                                Behavior on border.color { ColorAnimation { duration: 220 } }
                                Behavior on opacity { NumberAnimation { duration: 220 } }
                            }

                            // 2. Glyph Layer (Dot ● -> Lock 󰌾 -> Unlock 󰌿)
                            Item {
                                id: glyphLayer
                                anchors.fill: parent
                                // Smoothly dissolves in the first half of flight as the icon glides to center
                                opacity: Math.max(0.0, 1.0 - masterMorphIcon.faceProgress * 2.2)
                                scale: 1.0 + masterMorphIcon.faceProgress * 0.15

                                Text {
                                    id: morphTextGlyph
                                    anchors.centerIn: parent
                                    text: {
                                        if (root.isFaceVerified || root.isUnlockingWithGenie) return "󰌿"
                                        if (root.hasPeekedLocked || masterMorphIcon.isPeek) return "󰌾"
                                        return "●"
                                    }
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: masterMorphIcon.isPeek ? 14 : ((text === "●") ? 13 : 14)
                                    scale: {
                                        if (root.isUnlockingWithGenie) return 1.0 + 0.35 * Math.sin(root.unlockSuctionProgress * Math.PI)
                                        return 1.0
                                    }
                                    color: {
                                        if (root.isFaceVerified || root.isUnlockingWithGenie) return "#30d158"
                                        if (masterMorphIcon.isPeek) return Services.Theme.accent
                                        if (root.hasPeekedLocked) return Services.Theme.textPrimary
                                        return Services.Theme.textDisabled
                                    }

                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on font.pixelSize { NumberAnimation { duration: 200 } }
                                }
                            }

                            // 3. Apple Face ID Vector Canvas Layer
                            Item {
                                id: faceCanvasLayer
                                anchors.fill: parent
                                // Emerges from within the liquid droplet as it crosses the halfway mark
                                opacity: Math.min(1.0, Math.max(0.0, (masterMorphIcon.faceProgress - 0.20) / 0.60))
                                scale: 0.65 + 0.35 * Math.min(1.0, masterMorphIcon.faceProgress / 0.95)

                                // Authentic subtle breathing pulse only runs once arrived and actively scanning
                                SequentialAnimation {
                                    running: masterMorphIcon.isFace && (masterMorphIcon.faceProgress >= 0.95) && Services.FaceId && Services.FaceId.isScanning && (Services.FaceId.status !== "success")
                                    loops: Animation.Infinite
                                    NumberAnimation { target: appleFaceCanvas; property: "scale"; from: 1.0; to: 1.04; duration: 600; easing.type: Easing.InOutSine }
                                    NumberAnimation { target: appleFaceCanvas; property: "scale"; from: 1.04; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
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

                                    Behavior on strokeColor { ColorAnimation { duration: 250 } }
                                    Behavior on smileAmount { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

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
                                        var r = 4.0

                                        // Apple Face ID Brackets
                                        ctx.beginPath(); ctx.moveTo(w * 0.10, h * 0.32); ctx.lineTo(w * 0.10, h * 0.18 + r); ctx.arcTo(w * 0.10, h * 0.10, w * 0.18 + r, h * 0.10, r); ctx.lineTo(w * 0.34, h * 0.10); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(w * 0.66, h * 0.10); ctx.lineTo(w * 0.82 - r, h * 0.10); ctx.arcTo(w * 0.90, h * 0.10, w * 0.90, h * 0.18 + r, r); ctx.lineTo(w * 0.90, h * 0.32); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(w * 0.10, h * 0.68); ctx.lineTo(w * 0.10, h * 0.82 - r); ctx.arcTo(w * 0.10, h * 0.90, w * 0.18 + r, h * 0.90, r); ctx.lineTo(w * 0.34, h * 0.90); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(w * 0.66, h * 0.90); ctx.lineTo(w * 0.82 - r, h * 0.90); ctx.arcTo(w * 0.90, h * 0.90, w * 0.90, h * 0.82 - r, r); ctx.lineTo(w * 0.90, h * 0.68); ctx.stroke()

                                        // Apple Face ID Features
                                        ctx.beginPath(); ctx.moveTo(w * 0.35, h * 0.36); ctx.lineTo(w * 0.35, h * 0.46); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(w * 0.65, h * 0.36); ctx.lineTo(w * 0.65, h * 0.46); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(w * 0.50, h * 0.42); ctx.lineTo(w * 0.50, h * 0.54); ctx.lineTo(w * 0.58, h * 0.54); ctx.stroke()
                                        ctx.beginPath(); ctx.moveTo(w * 0.33, h * 0.69); ctx.quadraticCurveTo(w * 0.50, h * (0.69 + 0.11 * smileAmount), w * 0.67, h * 0.69); ctx.stroke()
                                    }
                                }
                            }
                        }

                        // ==================== OVERLAY LABELS CONTAINER ====================
                        Item {
                            id: contentLabelsOverlay
                            anchors.fill: parent
                            z: 5

                            // 1. Device Locked Peek Details (Horizontal Slide + Unfurl from behind badge)
                            Item {
                                id: peekTextGroup
                                anchors.left: parent.left
                                anchors.leftMargin: 34 + 14 * masterMorphIcon.peekProgress
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150
                                height: 30
                                transformOrigin: Item.Left
                                opacity: Math.min(1.0, Math.max(0.0, (masterMorphIcon.peekProgress - 0.15) / 0.70))
                                scale: 0.85 + 0.15 * masterMorphIcon.peekProgress

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        text: "Device Locked"
                                        color: Services.Theme.textPrimary
                                        font.family: Services.Theme.fontDisplay
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: "Authentication required"
                                        color: Services.Theme.textSecondary
                                        font.family: Services.Theme.fontDisplay
                                        font.pixelSize: 10
                                        opacity: 0.85
                                    }
                                }
                            }

                            // 2. Face ID Status Details (Emerge out of the face icon, collapse back into it)
                            Item {
                                id: faceTextGroup
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 140
                                height: 34
                                transformOrigin: Item.Top

                                // Choreography: Text emerges from face icon (y=30 -> 55) and collapses back into it
                                property real textProgress: root.faceTextActive ? 1.0 : 0.0
                                Behavior on textProgress {
                                    NumberAnimation {
                                        duration: root.faceTextActive ? 220 : 150
                                        easing.type: root.faceTextActive ? Easing.OutBack : Easing.InQuad
                                        easing.overshoot: root.faceTextActive ? 1.15 : 1.0
                                    }
                                }

                                y: 30 + 25 * textProgress
                                opacity: Math.min(1.0, textProgress * 1.5)
                                scale: 0.20 + 0.80 * textProgress
                                visible: opacity > 0.01

                                readonly property bool isSuccess: Boolean(Services.FaceId && Services.FaceId.status === "success")
                                onIsSuccessChanged: {
                                    if (isSuccess) titlePopAnim.restart()
                                }

                                Column {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    spacing: 2

                                    Text {
                                        id: faceIdTitle
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "Face ID"
                                        font.family: Services.Theme.fontDisplay
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: faceTextGroup.isSuccess ? "#30d158" : Services.Theme.textPrimary

                                        Behavior on color { ColorAnimation { duration: 250 } }

                                        property real titleScale: 1.0
                                        scale: titleScale

                                        SequentialAnimation {
                                            id: titlePopAnim
                                            NumberAnimation { target: faceIdTitle; property: "titleScale"; to: 1.14; duration: 130; easing.type: Easing.OutQuad }
                                            NumberAnimation { target: faceIdTitle; property: "titleScale"; to: 1.0; duration: 160; easing.type: Easing.OutBack }
                                        }
                                    }

                                    Item {
                                        id: statusSubTextWrapper
                                        width: 130
                                        height: 14
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        readonly property string statusText: {
                                            if (Services.FaceId && Services.FaceId.status === "success") return "Verified"
                                            if (Services.FaceId && Services.FaceId.status === "detected") return "Verifying Face..."
                                            if (Services.FaceId && Services.FaceId.status === "scanning") return "Looking for Face..."
                                            if (Services.FaceId && Services.FaceId.status === "timeout") return "Try Again"
                                            return "Starting..."
                                        }

                                        onStatusTextChanged: statusCrossAnim.restart()

                                        Text {
                                            id: statusSubText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: statusSubTextWrapper.statusText
                                            font.family: Services.Theme.fontDisplay
                                            font.pixelSize: 10
                                            color: (Services.FaceId && Services.FaceId.status === "success") ? "#30d158" : Services.Theme.textSecondary

                                            property real textOffsetY: 0.0
                                            property real textFade: 1.0

                                            y: textOffsetY
                                            opacity: textFade

                                            Behavior on color { ColorAnimation { duration: 250 } }
                                        }

                                        SequentialAnimation {
                                            id: statusCrossAnim
                                            ParallelAnimation {
                                                NumberAnimation { target: statusSubText; property: "textFade"; to: 0.0; duration: 80; easing.type: Easing.InQuad }
                                                NumberAnimation { target: statusSubText; property: "textOffsetY"; to: -4; duration: 80; easing.type: Easing.InQuad }
                                            }
                                            PropertyAction { target: statusSubText; property: "textOffsetY"; value: 4 }
                                            ParallelAnimation {
                                                NumberAnimation { target: statusSubText; property: "textFade"; to: 1.0; duration: 130; easing.type: Easing.OutQuad }
                                                NumberAnimation { target: statusSubText; property: "textOffsetY"; to: 0.0; duration: 130; easing.type: Easing.OutBack }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Mode A: Combined Status & Control Center Pill (Desktop-Styled)
                    Rectangle {
                        id: combinedControlPill
                        anchors.right: parent.right
                        anchors.rightMargin: 18
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        height: 28
                        implicitWidth: combinedContentRow.implicitWidth + 24
                        width: implicitWidth
                        radius: 14
                        color: pillMouse.containsMouse ? Services.Theme.bgHover : Services.Theme.surface
                        border.color: root.lockscreenCcOpen ? Services.Theme.accent : (pillMouse.containsMouse ? Services.Theme.borderHighlight : Services.Theme.border)
                        border.width: 1
                        visible: root.isDefault && (Services.Config ? Services.Config.lockscreenShowStatusPill : true)

                        readonly property real targetDx: (topBarHeader.width / 2) - (topBarHeader.width - 18 - (combinedControlPill.width / 2))

                        transform: [
                            Translate {
                                x: combinedControlPill.targetDx * (1.0 - root.lockTopBarState)
                            },
                            Scale {
                                origin.x: combinedControlPill.width / 2
                                origin.y: combinedControlPill.height / 2
                                xScale: 0.15 + 0.85 * root.lockTopBarState
                                yScale: 0.15 + 0.85 * root.lockTopBarState
                            }
                        ]
                        opacity: root.isRevealed ? Math.min(1.0, Math.max(0.0, root.lockTopBarState * 1.35)) : 0.0

                        Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        RowLayout {
                            id: combinedContentRow
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

                            // Bluetooth Status Icon (if enabled and connected)
                            Text {
                                visible: Services.Bluetooth && Services.Bluetooth.enabled && Services.Bluetooth.hasConnectedDevice
                                text: Services.Icons.btDeviceIcon(Services.Bluetooth.connectedDeviceIcon, Services.Bluetooth.connectedDeviceName)
                                font.family: Services.Theme.fontSymbols
                                font.pixelSize: Services.Theme.fontSizeSm
                                color: Services.Theme.accent
                            }

                            // Battery Icon & Percentage
                            RowLayout {
                                spacing: 4
                                visible: Services.Config ? Services.Config.showBatteryTray : true

                                Text {
                                    id: batIconText
                                    text: Services.Icons.powerIcon(Services.Power.charging, (Services.Power.percentage || 0) * 100)
                                    font.family: Services.Theme.fontSymbols
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : ((pillMouse.containsMouse || root.lockscreenCcOpen) ? Services.Theme.accent : Services.Theme.textPrimary)))
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

                                    SequentialAnimation {
                                        running: Services.Power.isLow
                                        loops: Animation.Infinite
                                        NumberAnimation { target: batIconText; property: "opacity"; to: 0.2; duration: 500; easing.type: Easing.InOutQuad }
                                        NumberAnimation { target: batIconText; property: "opacity"; to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                                    }
                                }

                                Text {
                                    text: Math.round((Services.Power.percentage || 0) * 100) + "%"
                                    font.family: Services.Theme.fontMono
                                    font.pixelSize: Services.Theme.fontSizeMd
                                    font.bold: true
                                    color: Services.Power.isLow ? "#ff4444" : (Services.Power.isWarning ? "#e06c75" : (Services.PowerProfile.saverEnabled ? "#ff9800" : ((pillMouse.containsMouse || root.lockscreenCcOpen) ? Services.Theme.accent : Services.Theme.textSecondary)))
                                    Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                }
                            }

                            // Vertical Separator
                            Rectangle {
                                width: 1
                                height: 12
                                color: Services.Theme.border
                                opacity: 0.8
                            }

                            // Control Center Toggle Glyph (Morphs & Spins 180° into Close Icon)
                            Item {
                                width: 14
                                height: 14
                                Layout.alignment: Qt.AlignVCenter

                                Item {
                                    anchors.centerIn: parent
                                    width: 14
                                    height: 14
                                    rotation: root.lockscreenCcOpen ? 180 : 0
                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: 320
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 1.3
                                        }
                                    }

                                    // Sliders icon (Morphs out)
                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.controlcenter
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        color: (pillMouse.containsMouse || root.lockscreenCcOpen) ? Services.Theme.accent : Services.Theme.textPrimary
                                        opacity: root.lockscreenCcOpen ? 0.0 : 1.0
                                        scale: root.lockscreenCcOpen ? 0.4 : 1.0
                                        rotation: root.lockscreenCcOpen ? -90 : 0
                                        Behavior on opacity { NumberAnimation { duration: 180 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }

                                    // Close icon (Morphs in)
                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.close
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: (pillMouse.containsMouse || root.lockscreenCcOpen) ? Services.Theme.accent : Services.Theme.textPrimary
                                        opacity: root.lockscreenCcOpen ? 1.0 : 0.0
                                        scale: root.lockscreenCcOpen ? 1.0 : 0.4
                                        rotation: root.lockscreenCcOpen ? 0 : 90
                                        Behavior on opacity { NumberAnimation { duration: 180 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            z: 10
                            onClicked: root.lockscreenCcOpen = !root.lockscreenCcOpen
                        }
                    }

                    // Mode B: Minimal Discrete Status Icons (Minimal Layout - Clean, subtle monochrome)
                    RowLayout {
                        id: minimalControlRow
                        visible: root.isMinimal && (Services.Config ? Services.Config.lockscreenShowStatusPill : true)
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        readonly property real targetDx: (topBarHeader.width / 2) - (topBarHeader.width - 24 - ((minimalControlRow.implicitWidth > 0 ? minimalControlRow.implicitWidth : minimalControlRow.width) / 2))

                        transform: [
                            Translate {
                                x: minimalControlRow.targetDx * (1.0 - root.lockTopBarState)
                            },
                            Scale {
                                origin.x: (minimalControlRow.implicitWidth > 0 ? minimalControlRow.implicitWidth : minimalControlRow.width) / 2
                                origin.y: minimalControlRow.height / 2
                                xScale: 0.15 + 0.85 * root.lockTopBarState
                                yScale: 0.15 + 0.85 * root.lockTopBarState
                            }
                        ]
                        opacity: root.isRevealed ? Math.min(0.75, Math.max(0.0, root.lockTopBarState * 1.0)) : 0.0

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

                        opacity: root.isUnlockingWithGenie ? Math.max(0.0, 1.0 - Math.pow(root.unlockSuctionProgress, 1.5)) : 1.0

                        transform: Scale {
                            origin.x: mainContainer.width / 2
                            origin.y: 22
                            xScale: root.isUnlockingWithGenie ? Math.max(0.001, Math.pow(1.0 - root.unlockSuctionProgress, 1.3)) : 1.0
                            yScale: root.isUnlockingWithGenie ? Math.max(0.001, 1.0 - root.unlockSuctionProgress) : 1.0
                        }

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
                                : (root.isRevealed ? Math.max(102, Math.round(parent.height * 0.125)) : (Math.max(102, Math.round(parent.height * 0.125)) - 22))

                            spacing: 4
                            visible: !root.isCompact
                            opacity: {
                                if (root.isCompact) return 0.0
                                if (root.isUnlockingWithGenie) {
                                    let pTop = Math.min(1.0, root.unlockSuctionProgress / 0.45)
                                    return Math.max(0.0, 1.0 - Math.pow(pTop, 1.5))
                                }
                                return root.isRevealed ? 1.0 : 0.0
                            }
                            transform: Scale {
                                origin.x: topClockColumn.width / 2
                                origin.y: topClockColumn.height / 2
                                yScale: root.isUnlockingWithGenie ? (1.0 + 0.18 * Math.sin(Math.min(1.0, root.unlockSuctionProgress / 0.45) * Math.PI)) : 1.0
                            }
                            Behavior on opacity {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.topMargin {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
                            }

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
                            anchors.bottomMargin: !root.isCompact
                                ? ((root.isMinimal ? 24 : Math.max(36, Math.round(parent.height * 0.055))) + (root.isRevealed ? 0 : -20))
                                : 0
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

                            opacity: {
                                if (root.isUnlockingWithGenie) {
                                    let pCard = Math.min(1.0, root.unlockSuctionProgress / 0.75)
                                    return Math.max(0.0, 1.0 - Math.pow(pCard, 1.8))
                                }
                                return root.isRevealed ? 1.0 : 0.0
                            }
                            transform: Scale {
                                origin.x: centerAuthCard.width / 2
                                origin.y: centerAuthCard.height / 2
                                yScale: root.isUnlockingWithGenie ? (1.0 + 0.22 * Math.sin(Math.min(1.0, root.unlockSuctionProgress / 0.75) * Math.PI)) : 1.0
                            }
                            Behavior on opacity {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                            }
                            Behavior on anchors.bottomMargin {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
                            }

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
                                scale: centerAuthCard.showPasswordBox ? 1.0 : 0.88
                                transformOrigin: Item.Center

                                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
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
                                            scale: lockIconMorphScale
                                            property real lockIconMorphScale: 1.0

                                            Behavior on color { ColorAnimation { duration: 250 } }

                                            onTextChanged: {
                                                if (!root.isAuthenticating) {
                                                    lockMorphAnim.restart()
                                                }
                                            }

                                            SequentialAnimation {
                                                id: lockMorphAnim
                                                NumberAnimation { target: lockStateIcon; property: "lockIconMorphScale"; to: 0.45; duration: 80; easing.type: Easing.InQuad }
                                                NumberAnimation { target: lockStateIcon; property: "lockIconMorphScale"; to: 1.25; duration: 170; easing.type: Easing.OutBack }
                                                NumberAnimation { target: lockStateIcon; property: "lockIconMorphScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
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
                                scale: (!centerAuthCard.showPasswordBox && !root.isCompact) ? 1.0 : 0.82
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 160
                                width: promptLabel.implicitWidth + 20
                                height: 20
                                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }

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

                                    scale: promptMorphScale
                                    property real promptMorphScale: 1.0
                                    onTextChanged: promptMorphAnim.restart()

                                    SequentialAnimation {
                                        id: promptMorphAnim
                                        NumberAnimation { target: promptLabel; property: "promptMorphScale"; to: 0.65; duration: 80; easing.type: Easing.InQuad }
                                        NumberAnimation { target: promptLabel; property: "promptMorphScale"; to: 1.15; duration: 160; easing.type: Easing.OutBack }
                                        NumberAnimation { target: promptLabel; property: "promptMorphScale"; to: 1.0; duration: 100; easing.type: Easing.OutQuad }
                                    }
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
                            visible: root.isMinimal && root.notifCount > 0 && (root.isRevealed || root.isUnlockingWithGenie) && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: {
                                if (!root.isMinimal || root.notifCount <= 0) return 0.0
                                if (root.isUnlockingWithGenie) {
                                    let pPill = Math.min(1.0, root.unlockSuctionProgress / 0.75)
                                    return Math.max(0.0, 1.0 - Math.pow(pPill, 1.8))
                                }
                                return root.isRevealed ? 1.0 : 0.0
                            }
                            transform: Scale {
                                origin.x: (minNotifRow.implicitWidth + 16) / 2
                                origin.y: 0
                                yScale: root.isUnlockingWithGenie ? (1.0 + 0.20 * Math.sin(Math.min(1.0, root.unlockSuctionProgress / 0.75) * Math.PI)) : 1.0
                            }
                            Behavior on opacity {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 250 }
                            }

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
                            visible: !root.isMinimal && root.notifCount > 0 && (root.isRevealed || root.isUnlockingWithGenie) && (Services.Config ? Services.Config.lockscreenShowNotifs : true)
                            opacity: {
                                if (root.isMinimal || root.notifCount <= 0) return 0.0
                                if (root.isUnlockingWithGenie) {
                                    let pNotif = Math.min(1.0, root.unlockSuctionProgress / 0.60)
                                    return Math.max(0.0, 1.0 - Math.pow(pNotif, 1.8))
                                }
                                return root.isRevealed ? 1.0 : 0.0
                            }
                            transform: Scale {
                                origin.x: notifStackContainer.width / 2
                                origin.y: notifStackContainer.height / 2
                                yScale: root.isUnlockingWithGenie ? (1.0 + 0.20 * Math.sin(Math.min(1.0, root.unlockSuctionProgress / 0.60) * Math.PI)) : 1.0
                            }
                            Behavior on opacity {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 300 }
                            }
                            Behavior on anchors.topMargin {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }

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
                            visible: root.isDefault && root.hasPlayer && (root.isRevealed || root.isUnlockingWithGenie) && (Services.Config ? Services.Config.lockscreenShowMedia : true)
                            opacity: {
                                if (!root.isDefault || !root.hasPlayer) return 0.0
                                if (root.isUnlockingWithGenie) {
                                    let pMedia = Math.min(1.0, root.unlockSuctionProgress / 0.90)
                                    return Math.max(0.0, 1.0 - Math.pow(pMedia, 1.8))
                                }
                                return root.isRevealed ? 1.0 : 0.0
                            }
                            transform: Scale {
                                origin.x: cornerMediaCard.width / 2
                                origin.y: cornerMediaCard.height / 2
                                yScale: root.isUnlockingWithGenie ? (1.0 + 0.20 * Math.sin(Math.min(1.0, root.unlockSuctionProgress / 0.90) * Math.PI)) : 1.0
                            }
                            Behavior on opacity {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }

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
                                        scale: prevCornerMouse.pressed ? 0.88 : (prevCornerMouse.containsMouse ? 1.12 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 180 } }

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

                                    // Play / Pause / Stop (Natural Optical Glass Lens)
                                    Rectangle {
                                        id: playCornerGlass
                                        width: 26; height: 26; radius: 13
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop {
                                                position: 0.0
                                                color: playCornerMouse.pressed
                                                    ? Qt.rgba(255, 255, 255, 0.20)
                                                    : (playCornerMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.14) : Qt.rgba(255, 255, 255, 0.08))
                                            }
                                            GradientStop {
                                                position: 0.55
                                                color: playCornerMouse.pressed
                                                    ? Qt.rgba(255, 255, 255, 0.09)
                                                    : (playCornerMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.05) : Qt.rgba(255, 255, 255, 0.02))
                                            }
                                            GradientStop {
                                                position: 1.0
                                                color: playCornerMouse.pressed
                                                    ? Qt.rgba(0, 0, 0, 0.06)
                                                    : (playCornerMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.04) : Qt.rgba(0, 0, 0, 0.08))
                                            }
                                        }
                                        border.width: 1
                                        border.color: playCornerMouse.pressed
                                            ? Qt.rgba(255, 255, 255, 0.28)
                                            : (playCornerMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.18) : Qt.rgba(255, 255, 255, 0.09))
                                        scale: playCornerMouse.pressed ? 0.90 : (playCornerMouse.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        Behavior on border.color { ColorAnimation { duration: 200 } }

                                        // Soft physical contact shadow
                                        Rectangle {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: 1.5
                                            width: parent.width - 2
                                            height: parent.height - 2
                                            radius: parent.radius
                                            color: Qt.rgba(0, 0, 0, 0.30)
                                            z: -1
                                        }

                                        Text {
                                            id: playIconText
                                            anchors.centerIn: parent
                                            text: Services.Icons.mediaPlayPause(root.isPlaying)
                                            font.family: Services.Theme.fontSymbols
                                            font.pixelSize: 11
                                            color: Services.Theme.textPrimary
                                            opacity: playCornerMouse.containsMouse ? 1.0 : 0.92
                                            scale: playMorphScale
                                            property real playMorphScale: 1.0

                                            onTextChanged: playMorphAnim.restart()
                                            SequentialAnimation {
                                                id: playMorphAnim
                                                NumberAnimation { target: playIconText; property: "playMorphScale"; to: 0.65; duration: 80; easing.type: Easing.InQuad }
                                                NumberAnimation { target: playIconText; property: "playMorphScale"; to: 1.18; duration: 160; easing.type: Easing.OutBack }
                                                NumberAnimation { target: playIconText; property: "playMorphScale"; to: 1.0; duration: 90; easing.type: Easing.OutQuad }
                                            }
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
                                        scale: nextCornerMouse.pressed ? 0.88 : (nextCornerMouse.containsMouse ? 1.12 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                        Behavior on color { ColorAnimation { duration: 180 } }

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

                                Item {
                                    width: 14
                                    height: 14
                                    Layout.alignment: Qt.AlignVCenter
                                    rotation: root.isPlaying ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.25 } }

                                    Text {
                                        id: minPlayIconText
                                        anchors.centerIn: parent
                                        text: Services.Icons.mediaPlayPause(root.isPlaying)
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: 11
                                        color: Services.Theme.accent
                                        scale: minPlayMorphScale
                                        property real minPlayMorphScale: 1.0

                                        onTextChanged: minPlayMorphAnim.restart()
                                        SequentialAnimation {
                                            id: minPlayMorphAnim
                                            NumberAnimation { target: minPlayIconText; property: "minPlayMorphScale"; to: 0.5; duration: 80; easing.type: Easing.InQuad }
                                            NumberAnimation { target: minPlayIconText; property: "minPlayMorphScale"; to: 1.25; duration: 160; easing.type: Easing.OutBack }
                                            NumberAnimation { target: minPlayIconText; property: "minPlayMorphScale"; to: 1.0; duration: 90; easing.type: Easing.OutQuad }
                                        }
                                    }

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

                        // Power Menu Backdrop Dismiss (Clicking outside closes it)
                        MouseArea {
                            anchors.fill: parent
                            z: 998
                            enabled: root.lockscreenPwrOpen
                            visible: root.lockscreenPwrOpen
                            onClicked: root.lockscreenPwrOpen = false
                        }

                        // ── 4. Bottom Right: Vertical Morphing Power Capsule (Expands Upwards, Icon-Only) ──
                        Rectangle {
                            id: pwrPillCapsule
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 24
                            anchors.bottomMargin: root.isRevealed ? 24 : 0
                            z: 999

                            width: root.isMinimal ? 34 : 40
                            radius: width / 2
                            clip: true

                            // Expands vertically upwards when open, circle when closed
                            height: root.lockscreenPwrOpen ? (root.isMinimal ? 142 : 160) : width

                            visible: !root.isCompact && (root.isRevealed || root.isUnlockingWithGenie) && (Services.Config ? Services.Config.lockscreenShowQuickPower : true)
                            opacity: {
                                if (root.isCompact) return 0.0
                                if (root.isUnlockingWithGenie) {
                                    let pPwr = Math.min(1.0, root.unlockSuctionProgress / 0.90)
                                    return Math.max(0.0, 1.0 - Math.pow(pPwr, 1.8))
                                }
                                return root.isRevealed ? 1.0 : 0.0
                            }

                            color: root.lockscreenPwrOpen
                                ? Qt.rgba(Services.Theme.surface.r, Services.Theme.surface.g, Services.Theme.surface.b, 0.96)
                                : (pwrBottomMouse.containsMouse 
                                    ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.22)
                                    : Qt.rgba(Services.Theme.bgDeep.r, Services.Theme.bgDeep.g, Services.Theme.bgDeep.b, 0.82))

                            border.color: root.lockscreenPwrOpen
                                ? Services.Theme.borderHighlight
                                : (pwrBottomMouse.containsMouse ? Services.Theme.danger : Services.Theme.border)
                            border.width: 1

                            transform: Scale {
                                origin.x: pwrPillCapsule.width / 2
                                origin.y: pwrPillCapsule.height / 2
                                yScale: root.isUnlockingWithGenie ? (1.0 + 0.20 * Math.sin(Math.min(1.0, root.unlockSuctionProgress / 0.90) * Math.PI)) : 1.0
                            }

                            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                            Behavior on anchors.bottomMargin {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                            }
                            Behavior on opacity {
                                enabled: !root.isUnlockingWithGenie
                                NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                            }
                            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            // ── Action Icons Column (Emerges upwards from bottom button) ──
                            Column {
                                id: pwrActionsCol
                                anchors.top: parent.top
                                anchors.topMargin: root.isMinimal ? 5 : 7
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: root.isMinimal ? 4 : 5
                                visible: opacity > 0.01
                                opacity: root.lockscreenPwrOpen ? 1.0 : 0.0
                                scale: root.lockscreenPwrOpen ? 1.0 : 0.5
                                transformOrigin: Item.Bottom

                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                // 1. Sleep Action Button
                                Rectangle {
                                    width: root.isMinimal ? 26 : 30
                                    height: width
                                    radius: width / 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: sleepActionMouse.containsMouse ? Services.Theme.bgHover : "transparent"
                                    border.color: sleepActionMouse.containsMouse ? Services.Theme.borderHighlight : "transparent"
                                    border.width: 1
                                    scale: sleepActionMouse.pressed ? 0.88 : (sleepActionMouse.containsMouse ? 1.12 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.pmSleep
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: root.isMinimal ? 12 : 14
                                        color: sleepActionMouse.containsMouse ? Services.Theme.accent : Services.Theme.textPrimary
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }

                                    MouseArea {
                                        id: sleepActionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.lockscreenPwrOpen = false
                                            suspendProc.running = true
                                        }
                                    }
                                }

                                // Separator 1
                                Rectangle {
                                    width: 14
                                    height: 1
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: Services.Theme.border
                                    opacity: 0.5
                                }

                                // 2. Reboot Action Button
                                Rectangle {
                                    width: root.isMinimal ? 26 : 30
                                    height: width
                                    radius: width / 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: rebootActionMouse.containsMouse ? Qt.rgba(Services.Theme.warning.r, Services.Theme.warning.g, Services.Theme.warning.b, 0.2) : "transparent"
                                    border.color: rebootActionMouse.containsMouse ? Services.Theme.warning : "transparent"
                                    border.width: 1
                                    scale: rebootActionMouse.pressed ? 0.88 : (rebootActionMouse.containsMouse ? 1.12 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.pmReboot
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: root.isMinimal ? 12 : 14
                                        color: rebootActionMouse.containsMouse ? Services.Theme.warning : Services.Theme.textPrimary
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }

                                    MouseArea {
                                        id: rebootActionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.lockscreenPwrOpen = false
                                            rebootProc.running = true
                                        }
                                    }
                                }

                                // Separator 2
                                Rectangle {
                                    width: 14
                                    height: 1
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: Services.Theme.border
                                    opacity: 0.5
                                }

                                // 3. Power Off Action Button
                                Rectangle {
                                    width: root.isMinimal ? 26 : 30
                                    height: width
                                    radius: width / 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: shutdownActionMouse.containsMouse ? Qt.rgba(Services.Theme.danger.r, Services.Theme.danger.g, Services.Theme.danger.b, 0.25) : "transparent"
                                    border.color: shutdownActionMouse.containsMouse ? Services.Theme.danger : "transparent"
                                    border.width: 1
                                    scale: shutdownActionMouse.pressed ? 0.88 : (shutdownActionMouse.containsMouse ? 1.12 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 180 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.pmShutdown
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: root.isMinimal ? 12 : 14
                                        color: Services.Theme.danger
                                    }

                                    MouseArea {
                                        id: shutdownActionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.lockscreenPwrOpen = false
                                            shutdownProc.running = true
                                        }
                                    }
                                }

                                // Separator 3 (Divider between actions and bottom toggle)
                                Rectangle {
                                    width: 18
                                    height: 1
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    color: Services.Theme.border
                                    opacity: 0.6
                                }
                            }

                            // ── Base Morphing & Rotating Power Button (At bottom of capsule) ──
                            Item {
                                id: pwrBottomBtn
                                width: parent.width
                                height: parent.width
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter

                                // Rotating icon container
                                Item {
                                    id: pwrRotateWrapper
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height
                                    rotation: root.lockscreenPwrOpen ? 180 : 0
                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: 350
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 1.3
                                        }
                                    }

                                    // State A: Power Icon
                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.power
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: root.isMinimal ? 14 : 16
                                        color: pwrBottomMouse.containsMouse ? Services.Theme.danger : Services.Theme.textSecondary
                                        opacity: root.lockscreenPwrOpen ? 0.0 : 1.0
                                        scale: root.lockscreenPwrOpen ? 0.4 : 1.0
                                        rotation: root.lockscreenPwrOpen ? -90 : 0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        Behavior on rotation { NumberAnimation { duration: 280 } }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }

                                    // State B: Close Icon (✕)
                                    Text {
                                        anchors.centerIn: parent
                                        text: Services.Icons.close
                                        font.family: Services.Theme.fontSymbols
                                        font.pixelSize: root.isMinimal ? 11 : 13
                                        color: pwrBottomMouse.containsMouse ? Services.Theme.textPrimary : Services.Theme.textSecondary
                                        opacity: root.lockscreenPwrOpen ? 1.0 : 0.0
                                        scale: root.lockscreenPwrOpen ? 1.0 : 0.4
                                        rotation: root.lockscreenPwrOpen ? 0 : 90
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                        Behavior on rotation { NumberAnimation { duration: 280 } }
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                }

                                MouseArea {
                                    id: pwrBottomMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.lockscreenPwrOpen = !root.lockscreenPwrOpen
                                        if (root.lockscreenPwrOpen && root.lockscreenCcOpen) root.lockscreenCcOpen = false
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
                    visible: root.lockscreenCcOpen || ccCard.opacity > 0.01

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.lockscreenCcOpen = false
                    }

                    LockscreenControlCenter {
                        id: ccCard
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 42
                        anchors.rightMargin: 18
                        opacity: root.lockscreenCcOpen ? 1.0 : 0.0
                        scale: root.lockscreenCcOpen ? 1.0 : 0.96
                        transform: Translate {
                            y: root.lockscreenCcOpen ? 0 : -20
                            Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                        }
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
                        onRequestClose: root.lockscreenCcOpen = false
                    }
                }
            }
        }
    }
}
