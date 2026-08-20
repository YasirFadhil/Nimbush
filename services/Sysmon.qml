pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Polls system stats every few seconds for use in the bar.
// NOTE: cpuTemp reads /sys/class/thermal/thermal_zone0/temp — on some
// hosts (Gentho, nixosss) the right coretemp zone may be a different
// index. Check `cat /sys/class/thermal/thermal_zone*/type` and adjust
// THERMAL_ZONE below if the reading looks wrong.
Singleton {
    id: root

    readonly property string thermalZone: "/sys/class/thermal/thermal_zone0/temp"

    property real cpuUsage: 0   // 0-100
    property real ramUsage: 0   // 0-100
    property real cpuTemp: 0    // celsius
    property real diskUsage: 0  // 0-100
    property string ramUsedStr: ""
    property string ramTotalStr: ""
    property string diskUsedStr: ""
    property string diskTotalStr: ""
    property string uptimeStr: ""

    // Fast loop: CPU usage, RAM, and Temperature (3s interval, single shell read)
    Timer {
        id: fastTimer
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!fastProc.running) fastProc.running = true
        }
    }

    // Slow loop: Disk usage and Uptime (30s interval)
    Timer {
        id: slowTimer
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!slowProc.running) slowProc.running = true
        }
    }

    property real _prevTotal: 0
    property real _prevIdle: 0

    // Single unified process for CPU, RAM (/proc/meminfo), and CPU Temp
    Process {
        id: fastProc
        command: ["sh", "-c",
            "read _ u n s i io irq sirq _ < /proc/stat; " +
            "total=$((u+n+s+i+io+irq+sirq)); " +
            "while read k v _; do case \"$k\" in MemTotal:) mt=$v ;; MemAvailable:) ma=$v ;; esac; [ -n \"$mt\" ] && [ -n \"$ma\" ] && break; done < /proc/meminfo; " +
            "mu=$((mt - ma)); ram_pct=$(( (mu * 100) / mt )); " +
            "used_g=$(awk -v u=$mu 'BEGIN {printf \"%.1fG\", u/1048576}'); " +
            "tot_g=$(awk -v t=$mt 'BEGIN {printf \"%.1fG\", t/1048576}'); " +
            "temp=0; " +
            "for z in /sys/class/thermal/thermal_zone*; do t=$(cat \"$z/type\" 2>/dev/null); if [ \"$t\" = \"x86_pkg_temp\" ] || [ \"$t\" = \"TCPU\" ] || [ \"$t\" = \"cpu_thermal\" ] || [ \"$t\" = \"coretemp\" ]; then temp=$(cat \"$z/temp\" 2>/dev/null); break; fi; done; " +
            "[ \"$temp\" = \"0\" ] && temp=$(cat " + root.thermalZone + " 2>/dev/null || echo 0); " +
            "echo \"$total|$i|$ram_pct|$used_g|$tot_g|$temp\""]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("|")
                if (parts.length >= 6) {
                    // CPU
                    const total = parseFloat(parts[0])
                    const idle = parseFloat(parts[1])
                    if (root._prevTotal > 0) {
                        const totalDiff = total - root._prevTotal
                        const idleDiff = idle - root._prevIdle
                        if (totalDiff > 0) {
                            root.cpuUsage = Math.round(((totalDiff - idleDiff) / totalDiff) * 100)
                        }
                    }
                    root._prevTotal = total
                    root._prevIdle = idle

                    // RAM
                    const ramPct = parseFloat(parts[2])
                    if (!isNaN(ramPct)) root.ramUsage = ramPct
                    root.ramUsedStr = parts[3] || ""
                    root.ramTotalStr = parts[4] || ""

                    // Temp
                    const tempRaw = parseFloat(parts[5])
                    if (!isNaN(tempRaw) && tempRaw > 0) {
                        root.cpuTemp = tempRaw > 1000 ? (tempRaw / 1000) : tempRaw
                    }
                }
            }
        }
    }

    // Single unified process for Disk and Uptime
    Process {
        id: slowProc
        command: ["sh", "-c",
            "df -h / | awk 'NR==2{gsub(\"%\",\"\",$5); print $5\"|\"$3\"|\"$2}'; " +
            "read up _ < /proc/uptime; s=${up%.*}; " +
            "d=$((s/86400)); h=$(((s%86400)/3600)); m=$(((s%3600)/60)); " +
            "if [ $d -gt 0 ]; then echo \"$d\"d \"$h\"h \"$m\"m; elif [ $h -gt 0 ]; then echo \"$h\"h \"$m\"m; else echo \"$m\"m; fi"]
        stdout: SplitParser {
            onRead: data => {
                const lines = data.trim().split("\n")
                if (lines.length >= 1 && lines[0].includes("|")) {
                    const parts = lines[0].split("|")
                    if (parts.length >= 3) {
                        const v = parseFloat(parts[0])
                        if (!isNaN(v)) root.diskUsage = v
                        root.diskUsedStr = parts[1]
                        root.diskTotalStr = parts[2]
                    }
                }
                if (lines.length >= 2 && lines[1].trim().length > 0) {
                    root.uptimeStr = lines[1].trim()
                }
            }
        }
    }
}
