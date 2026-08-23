pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

import "." as Services

Singleton {
    id: root
    property string profile: "balanced" // performance | balanced | power-saver
    property var supportedProfiles: ["power-saver", "balanced", "performance"]
    readonly property string currentProfile: profile
    readonly property bool saverEnabled: profile === "power-saver"

    function refresh() {
        if (!getProc.running) getProc.running = true
        if (!listProfilesProc.running) listProfilesProc.running = true
    }

    function setProfile(name) {
        if (!name) return
        root.profile = name
        setProc.command = ["powerprofilesctl", "set", name]
        setProc.running = true
    }

    function toggleSaver() {
        setProfile(root.saverEnabled ? "balanced" : "power-saver")
    }

    // Periodic check (20s interval)
    Timer {
        interval: 20000
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
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim()
                if (p.length > 0) root.profile = p
            }
        }
    }

    Process {
        id: listProfilesProc
        command: [
            "python3", "-c",
            "import subprocess, json\n" +
            "try:\n" +
            "    out = subprocess.check_output(['powerprofilesctl', 'list']).decode()\n" +
            "    profs = []\n" +
            "    for l in out.splitlines():\n" +
            "        l = l.strip()\n" +
            "        if l.startswith('*'):\n" +
            "            p = l.lstrip('* ').rstrip(':')\n" +
            "            if p and p not in profs: profs.append(p)\n" +
            "        elif l.endswith(':') and ' ' not in l:\n" +
            "            p = l.rstrip(':')\n" +
            "            if p and p not in profs: profs.append(p)\n" +
            "    print(json.dumps(profs))\n" +
            "except Exception:\n" +
            "    print('[\"power-saver\", \"balanced\"]')"
        ]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        root.supportedProfiles = parsed
                    }
                } catch(e) {}
            }
        }
    }

    Process { id: setProc; onExited: root.refresh() }
}
