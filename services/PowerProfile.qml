pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

import "." as Services

Singleton {
    id: root
    property string profile: "balanced" // performance | balanced | power-saver
    property var supportedProfiles: ["power-saver", "balanced", "performance"]
    property string backend: "none"
    property string backendName: "None"
    property bool isManual: false
    property string powerSource: ""
    readonly property string currentProfile: profile
    readonly property bool saverEnabled: profile === "power-saver"

    // ChromeOS-style display dimming when entering power-saver
    property real preSaverBrightness: -1.0
    property string previousProfile: profile

    onProfileChanged: {
        if (profile === "power-saver") {
            if (previousProfile !== "power-saver") {
                if (Services.Brightness && Services.Brightness.percent > 0) {
                    preSaverBrightness = Services.Brightness.percent
                    const target = Math.max(0.20, Math.round(preSaverBrightness * 0.75 * 100) / 100)
                    if (target < preSaverBrightness) {
                        Services.Brightness.setPercent(target)
                    }
                }
            }
        } else {
            if (previousProfile === "power-saver") {
                if (preSaverBrightness > 0 && Services.Brightness) {
                    Services.Brightness.setPercent(preSaverBrightness)
                    preSaverBrightness = -1.0
                }
            }
        }
        previousProfile = profile
    }

    Component.onCompleted: {
        root.previousProfile = root.profile
    }

    readonly property string helperScript: (Quickshell.env("HOME") || ("/home/" + (Quickshell.env("USER") || "user"))) + "/.config/quickshell/scripts/power-profile-helper.py"

    function refresh() {
        if (!getProc.running) getProc.running = true
    }

    function setProfile(name) {
        if (!name) return
        root.profile = name
        setProc.command = ["python3", helperScript, "set", name]
        setProc.running = true
    }

    function toggleSaver() {
        setProfile(root.saverEnabled ? "balanced" : "power-saver")
    }

    // Periodic check (15s interval)
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Connections {
        target: Services.Power
        function onChargingChanged() {
            root.refresh()
        }
    }

    Process {
        id: getProc
        command: ["python3", helperScript, "get"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (parsed.profile) root.profile = parsed.profile
                    if (Array.isArray(parsed.supported) && parsed.supported.length > 0) {
                        root.supportedProfiles = parsed.supported
                    }
                    if (parsed.backend) root.backend = parsed.backend
                    if (parsed.backendName) root.backendName = parsed.backendName
                    if (parsed.isManual !== undefined) root.isManual = parsed.isManual
                    if (parsed.powerSource !== undefined) root.powerSource = parsed.powerSource
                } catch(e) {}
            }
        }
    }

    Process {
        id: setProc
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (parsed.profile) root.profile = parsed.profile
                    if (parsed.backend) root.backend = parsed.backend
                    if (parsed.backendName) root.backendName = parsed.backendName
                    if (parsed.success === false && parsed.error) {
                        Services.Notifications.addSystemNotification({
                            appName: "Power Manager",
                            appIcon: "battery-caution",
                            summary: "Failed to Change Power Profile",
                            body: parsed.error + "\nPlease configure NOPASSWD sudoers / polkit rule for tlp.",
                            urgency: 1
                        })
                    }
                } catch(e) {}
            }
        }
        onExited: root.refresh()
    }
}
