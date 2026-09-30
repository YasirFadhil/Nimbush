pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "." as Services

Singleton {
    id: root

    property bool ready: false

    // Sysfs fallback properties when UPower daemon is not running
    property real sysfsPercentage: 0.0
    property string sysfsState: ""
    property bool sysfsPresent: false

    readonly property bool upowerActive: UPower.displayDevice && UPower.displayDevice.isPresent && !isNaN(UPower.displayDevice.percentage) && UPower.displayDevice.percentage >= 0

    property bool charging: isChargeInhibited ? false : (upowerActive 
        ? isChargingState(UPower.displayDevice.state) 
        : (sysfsState === "charging" || sysfsState === "full"))

    property real percentage: upowerActive 
        ? UPower.displayDevice.percentage 
        : sysfsPercentage

    readonly property bool hasBattery: (UPower.displayDevice && UPower.displayDevice.isPresent) || sysfsPresent || (sysfsPercentage > 0)

    readonly property string stateString: {
        if (isChargeInhibited) return "Charge Limit Active (Idle)"
        if (upowerActive) {
            const st = UPower.displayDevice.state
            if (st === UPowerDeviceState.Charging) return "Charging"
            if (st === UPowerDeviceState.FullyCharged) return "Fully Charged"
            if (st === UPowerDeviceState.Discharging) return "Discharging"
            if (st === UPowerDeviceState.Empty) return "Empty"
        }
        if (sysfsState === "charging") return "Charging"
        if (sysfsState === "full") return "Fully Charged"
        if (sysfsState === "discharging") return "Discharging"
        if (sysfsState === "not charging") return "Not Charging"
        if (sysfsState === "empty") return "Empty"
        return "AC Power / Unknown"
    }

    readonly property bool isWarning: !charging && ready && hasBattery && !isNaN(percentage) && (percentage * 100 <= (Services.Config ? Services.Config.batteryLowThreshold : 20))
    readonly property bool isLow: !charging && ready && hasBattery && !isNaN(percentage) && (percentage * 100 <= 10)

    // Detailed Hardware Battery Metrics
    property string timeRemaining: ""
    property string timeType: "" // "until full" | "remaining" | ""
    property string energyRate: ""
    property string voltage: ""
    property string health: ""
    property string energyCurrent: ""
    property string energyFull: ""
    property string energyDesign: ""
    property string chargeCycles: ""
    property string vendor: ""
    property string model: ""
    property string technology: ""

    // Charge Limit & Health Protection
    property bool chargeLimitSupported: true
    property string chargeMode: "auto" // "auto" | "inhibit-charge"
    readonly property bool isChargeInhibited: chargeMode === "inhibit-charge"

    property bool warn20Sent: false
    property bool warn10Sent: false
    property bool warn5Sent: false
    property bool autoSaverTriggered: false

    signal chargingStateChanged(bool charging, real percentage)
    signal batteryWarning(int level, string title, string message)

    Process {
        id: detailProc
        command: [
            "python3", "-c",
            "import json, subprocess, glob, os\n" +
            "res = {}\n" +
            "try:\n" +
            "    dev = subprocess.check_output(['sh', '-c', 'upower -e 2>/dev/null | grep battery | head -n 1'], stderr=subprocess.DEVNULL, timeout=2.0).decode().strip()\n" +
            "    if dev:\n" +
            "        out = subprocess.check_output(['upower', '-i', dev], stderr=subprocess.DEVNULL, timeout=2.0).decode()\n" +
            "        d = {}\n" +
            "        for l in out.splitlines():\n" +
            "            if ':' in l:\n" +
            "                k, v = l.split(':', 1)\n" +
            "                d[k.strip()] = v.strip()\n" +
            "        pct_val = d.get('percentage', '')\n" +
            "        raw_pct = float(pct_val.replace('%', '').strip()) / 100.0 if pct_val else 0.0\n" +
            "        res = {\n" +
            "            'state': d.get('state', ''),\n" +
            "            'percentage': pct_val,\n" +
            "            'rawPercentage': raw_pct,\n" +
            "            'timeToFull': d.get('time to full', ''),\n" +
            "            'timeToEmpty': d.get('time to empty', ''),\n" +
            "            'energyRate': d.get('energy-rate', ''),\n" +
            "            'voltage': d.get('voltage', ''),\n" +
            "            'capacity': d.get('capacity', ''),\n" +
            "            'energy': d.get('energy', ''),\n" +
            "            'energyFull': d.get('energy-full', ''),\n" +
            "            'energyFullDesign': d.get('energy-full-design', ''),\n" +
            "            'chargeCycles': d.get('charge-cycles', ''),\n" +
            "            'vendor': d.get('vendor', ''),\n" +
            "            'model': d.get('model', ''),\n" +
            "            'technology': d.get('technology', ''),\n" +
            "            'present': d.get('present', 'yes') == 'yes'\n" +
            "        }\n" +
            "except Exception:\n" +
            "    pass\n" +
            "if not res or not res.get('percentage'):\n" +
            "    bats = glob.glob('/sys/class/power_supply/BAT*')\n" +
            "    if bats:\n" +
            "        b = bats[0]\n" +
            "        def read_f(fname):\n" +
            "            try:\n" +
            "                with open(os.path.join(b, fname)) as f:\n" +
            "                    return f.read().strip()\n" +
            "            except Exception:\n" +
            "                return ''\n" +
            "        status = read_f('status')\n" +
            "        cap = read_f('capacity')\n" +
            "        v_now = read_f('voltage_now')\n" +
            "        c_now = read_f('current_now')\n" +
            "        p_now = read_f('power_now')\n" +
            "        c_full = read_f('charge_full') or read_f('energy_full')\n" +
            "        c_full_design = read_f('charge_full_design') or read_f('energy_full_design')\n" +
            "        cycles = read_f('cycle_count')\n" +
            "        mfr = read_f('manufacturer')\n" +
            "        model = read_f('model_name')\n" +
            "        tech = read_f('technology')\n" +
            "        present = read_f('present') != '0'\n" +
            "        v_val = float(v_now) / 1e6 if v_now.isdigit() else 0.0\n" +
            "        p_val = 0.0\n" +
            "        if p_now.isdigit():\n" +
            "            p_val = float(p_now) / 1e6\n" +
            "        elif c_now.isdigit() and v_val > 0:\n" +
            "            p_val = (float(c_now) / 1e6) * v_val\n" +
            "        health_str = ''\n" +
            "        if c_full.isdigit() and c_full_design.isdigit() and float(c_full_design) > 0:\n" +
            "            health_str = f'{round(float(c_full) / float(c_full_design) * 100, 1)}%'\n" +
            "        res = {\n" +
            "            'state': status.lower() if status else 'unknown',\n" +
            "            'percentage': f'{cap}%' if cap else '',\n" +
            "            'rawPercentage': float(cap) / 100.0 if cap.isdigit() else 0.0,\n" +
            "            'timeToFull': '',\n" +
            "            'timeToEmpty': '',\n" +
            "            'energyRate': f'{p_val:.1f} W' if p_val > 0 else '',\n" +
            "            'voltage': f'{v_val:.2f} V' if v_val > 0 else '',\n" +
            "            'capacity': health_str,\n" +
            "            'energy': '',\n" +
            "            'energyFull': '',\n" +
            "            'energyFullDesign': '',\n" +
            "            'chargeCycles': cycles,\n" +
            "            'vendor': mfr,\n" +
            "            'model': model,\n" +
            "            'technology': tech,\n" +
            "            'present': present\n" +
            "        }\n" +
            "print(json.dumps(res))"
        ]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (parsed.rawPercentage !== undefined && !isNaN(parsed.rawPercentage) && parsed.rawPercentage >= 0) {
                        root.sysfsPercentage = parsed.rawPercentage
                    } else if (parsed.percentage) {
                        const p = parseFloat(parsed.percentage)
                        if (!isNaN(p) && p >= 0) root.sysfsPercentage = p / 100.0
                    }
                    if (parsed.state) root.sysfsState = parsed.state.toLowerCase()
                    if (parsed.present !== undefined) root.sysfsPresent = !!parsed.present

                    if (parsed.percentage) {
                        if (root.isChargeInhibited) {
                            root.timeRemaining = ""
                            root.timeType = ""
                        } else if (parsed.timeToFull) {
                            root.timeRemaining = parsed.timeToFull
                            root.timeType = "until full"
                        } else if (parsed.timeToEmpty) {
                            root.timeRemaining = parsed.timeToEmpty
                            root.timeType = "remaining"
                        } else {
                            root.timeRemaining = ""
                            root.timeType = ""
                        }
                        root.energyRate = parsed.energyRate || ""
                        root.voltage = parsed.voltage || ""
                        root.health = parsed.capacity || ""
                        root.energyCurrent = parsed.energy || ""
                        root.energyFull = parsed.energyFull || ""
                        root.energyDesign = parsed.energyFullDesign || ""
                        root.chargeCycles = parsed.chargeCycles || ""
                        root.vendor = parsed.vendor || ""
                        root.model = parsed.model || ""
                        root.technology = parsed.technology || ""
                    }
                } catch(e) {}
            }
        }
    }

    Process {
        id: chargeStatusProc
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (parsed.supported !== undefined) root.chargeLimitSupported = parsed.supported
                    if (parsed.mode) root.chargeMode = parsed.mode
                } catch(e) {}
            }
        }
    }

    Process {
        id: chargeSetProc
        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data.trim())
                    if (parsed.mode) root.chargeMode = parsed.mode
                } catch(e) {}
            }
        }
    }

    readonly property string chargeHelperScript: (Quickshell.env("HOME") || ("/home/" + (Quickshell.env("USER") || "user"))) + "/.config/quickshell/scripts/battery-charge-helper.py"

    function refreshChargeStatus() {
        if (!chargeStatusProc.running) {
            chargeStatusProc.command = ["python3", chargeHelperScript, "get"]
            chargeStatusProc.running = true
        }
    }

    function updateChargeLimit() {
        if (!chargeLimitSupported) return
        if (!Services.Config) return
        const enabled = Services.Config.batteryChargeLimitEnabled
        const limit = Services.Config.batteryChargeLimitValue || 80
        const pct = Math.round(percentage * 100)

        if (!enabled) {
            if (chargeMode !== "auto" && !chargeSetProc.running) {
                chargeMode = "auto"
                chargeSetProc.command = ["python3", chargeHelperScript, "set", "auto"]
                chargeSetProc.running = true
            }
            return
        }

        if (pct >= limit) {
            if (chargeMode !== "inhibit-charge" && !chargeSetProc.running) {
                chargeMode = "inhibit-charge"
                chargeSetProc.command = ["python3", chargeHelperScript, "set", "inhibit-charge"]
                chargeSetProc.running = true
            }
        } else if (pct <= (limit - 5)) {
            if (chargeMode !== "auto" && !chargeSetProc.running) {
                chargeMode = "auto"
                chargeSetProc.command = ["python3", chargeHelperScript, "set", "auto"]
                chargeSetProc.running = true
            }
        }
    }

    function refreshDetails() {
        if (!detailProc.running) detailProc.running = true
        refreshChargeStatus()
        updateChargeLimit()
    }

    function isChargingState(state) {
        return state === UPowerDeviceState.Charging || state === UPowerDeviceState.FullyCharged
    }

    function sendNotification(title, message, urgencyStr, icon) {
        let u = 1
        if (urgencyStr === "critical") u = 2
        else if (urgencyStr === "low") u = 0

        Notifications.addSystemNotification({
            appName: "System Warning",
            appIcon: icon || "battery-caution",
            summary: title,
            body: message,
            urgency: u,
            isBattery: true
        })
    }

    function checkBatteryWarnings() {
        if (Services.Config && !Services.Config.batteryShowWarnings) return
        if (!ready || !hasBattery || isNaN(percentage) || percentage <= 0) return
        if (charging) return

        const pct = Math.round(percentage * 100)
        if (pct <= 0 || pct > 100) return

        if (pct > 20) {
            warn20Sent = false
            warn10Sent = false
            warn5Sent = false
        } else if (pct > 10) {
            warn10Sent = false
            warn5Sent = false
        } else if (pct > 5) {
            warn5Sent = false
        }

        if (pct > 15) {
            autoSaverTriggered = false
        }

        // Auto Power Saver at <= 15% (always active directly when discharging)
        if (pct <= 15 && !autoSaverTriggered) {
            autoSaverTriggered = true
            if (Services.PowerProfile && Services.PowerProfile.profile !== "power-saver") {
                Services.PowerProfile.setProfile("power-saver")
                sendNotification("Auto Power Saver", "Battery reached " + pct + "%. Switched to Power Saver mode to preserve battery.", "normal", "battery-low")
            }
        }

        if (pct <= 5 && pct > 0 && !warn5Sent) {
            warn5Sent = true
            warn10Sent = true
            warn20Sent = true
            sendNotification("Battery Critical (5%)", "Battery remaining: " + pct + "%! Device will shut down soon.", "critical", "battery-empty")
            root.batteryWarning(5, "Battery Critical (" + pct + "%)", "Battery remaining: " + pct + "%! Device will shut down soon.")
        } else if (pct <= 10 && pct > 5 && !warn10Sent) {
            warn10Sent = true
            warn20Sent = true
            sendNotification("Battery Low (10%)", "Battery remaining: " + pct + "%! Please connect your charger.", "critical", "battery-caution")
            root.batteryWarning(10, "Battery Low (" + pct + "%)", "Battery remaining: " + pct + "%! Please connect your charger.")
        } else if (pct <= (Services.Config ? Services.Config.batteryLowThreshold : 20) && pct > 10 && !warn20Sent) {
            warn20Sent = true
            sendNotification("Battery Warning (" + pct + "%)", "Battery remaining: " + pct + "%. Consider connecting charger.", "critical", "battery-low")
            root.batteryWarning(20, "Battery Warning (" + pct + "%)", "Battery remaining: " + pct + "%. Consider connecting charger.")
        }
    }

    onPercentageChanged: {
        checkBatteryWarnings()
        refreshDetails()
    }

    onChargingChanged: {
        if (!root.ready) return
        root.chargingStateChanged(root.charging, root.percentage)
        refreshDetails()
        if (charging) {
            warn20Sent = false
            warn10Sent = false
            warn5Sent = false
            autoSaverTriggered = false
        } else {
            checkBatteryWarnings()
        }
    }

    Component.onCompleted: {
        root.refreshDetails()
    }

    Timer {
        id: detailPeriodicTimer
        interval: root.upowerActive ? 15000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshDetails()
    }

    Timer {
        id: readyTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            root.ready = true
            root.refreshDetails()
            if (root.hasBattery && !isNaN(root.percentage) && root.percentage > 0) {
                const initialPct = Math.round(root.percentage * 100)
                if (initialPct <= 20) root.warn20Sent = true
                if (initialPct <= 10) root.warn10Sent = true
                if (initialPct <= 5)  root.warn5Sent = true
            }
        }
    }
}


