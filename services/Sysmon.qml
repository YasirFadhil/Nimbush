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

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true
            ramProc.running = true
            tempProc.running = true
            diskProc.running = true
            uptimeProc.running = true
        }
    }

    // CPU usage via two /proc/stat samples 1s apart
    Process {
        id: cpuProc
        command: ["sh", "-c",
            "read _ u n s i io irq sirq _ < /proc/stat; " +
            "t1=$((u+n+s+i+io+irq+sirq)); i1=$i; sleep 1; " +
            "read _ u n s i io irq sirq _ < /proc/stat; " +
            "t2=$((u+n+s+i+io+irq+sirq)); i2=$i; " +
            "dt=$((t2-t1)); di=$((i2-i1)); " +
            "[ $dt -gt 0 ] && echo $(( (100*(dt-di))/dt )) || echo 0"
        ]
        stdout: SplitParser {
            onRead: data => {
                const v = parseFloat(data)
                if (!isNaN(v)) root.cpuUsage = v
            }
        }
    }

    // RAM usage via free
    Process {
        id: ramProc
        command: ["sh", "-c", "pct=$(free | awk '/Mem:/{printf \"%.0f\", ($2-$7)/$2*100}'); set -- $(free -h | awk '/Mem:/{print $3, $2}'); echo \"$pct|$1|$2\""]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("|")
                if (parts.length >= 3) {
                    const v = parseFloat(parts[0])
                    if (!isNaN(v)) root.ramUsage = v
                    root.ramUsedStr = parts[1]
                    root.ramTotalStr = parts[2]
                }
            }
        }
    }

    // CPU temp
    Process {
        id: tempProc
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do type=$(cat \"$z/type\" 2>/dev/null); if [ \"$type\" = \"x86_pkg_temp\" ] || [ \"$type\" = \"TCPU\" ] || [ \"$type\" = \"cpu_thermal\" ] || [ \"$type\" = \"coretemp\" ]; then cat \"$z/temp\" 2>/dev/null; exit 0; fi; done; cat " + root.thermalZone + " 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: data => {
                const v = parseFloat(data)
                if (!isNaN(v) && v > 0) root.cpuTemp = v / 1000
            }
        }
    }

    // Disk usage
    Process {
        id: diskProc
        command: ["sh", "-c", "df -h / | awk 'NR==2{gsub(\"%\",\"\",$5); print $5\"|\"$3\"|\"$2}'"]
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split("|")
                if (parts.length >= 3) {
                    const v = parseFloat(parts[0])
                    if (!isNaN(v)) root.diskUsage = v
                    root.diskUsedStr = parts[1]
                    root.diskTotalStr = parts[2]
                }
            }
        }
    }

    // Uptime
    Process {
        id: uptimeProc
        command: ["sh", "-c", "awk '{s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); if(d>0) print d\"d \"h\"h \"m\"m\"; else if(h>0) print h\"h \"m\"m\"; else print m\"m\"}' /proc/uptime"]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim().length > 0) root.uptimeStr = data.trim()
            }
        }
    }
}
