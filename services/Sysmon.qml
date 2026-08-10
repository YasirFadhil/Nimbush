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

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true
            ramProc.running = true
            tempProc.running = true
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
        command: ["sh", "-c", "free | awk '/Mem:/{printf \"%.0f\", ($2-$7)/$2*100}'"]
        stdout: SplitParser {
            onRead: data => {
                const v = parseFloat(data)
                if (!isNaN(v)) root.ramUsage = v
            }
        }
    }

    // CPU temp
    Process {
        id: tempProc
        command: ["sh", "-c", "cat " + root.thermalZone + " 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: data => {
                const v = parseFloat(data)
                if (!isNaN(v)) root.cpuTemp = v / 1000
            }
        }
    }
}
