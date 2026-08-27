#!/usr/bin/env bash

# High precision system resource reader with persistent delta

STAT_FILE="/tmp/quickshell_stat.tmp"

# 1. CPU Delta measurement (across poll intervals)
read _ u n s i io irq sirq st _ < /proc/stat
total=$((u + n + s + i + io + irq + sirq + st))
idle=$((i + io))

cpu_pct=0
if [ -f "$STAT_FILE" ]; then
    read prev_total prev_idle < "$STAT_FILE"
    dt=$((total - prev_total))
    di=$((idle - prev_idle))
    if [ "$dt" -gt 0 ] && [ "$di" -ge 0 ] && [ "$dt" -ge "$di" ]; then
        cpu_pct=$(( (100 * (dt - di)) / dt ))
    fi
fi
echo "$total $idle" > "$STAT_FILE"

# 2. RAM (MemTotal, MemAvailable)
while read k v _; do
    case "$k" in
        MemTotal:) mt=$v ;;
        MemAvailable:) ma=$v ;;
    esac
    [ -n "$mt" ] && [ -n "$ma" ] && break
done < /proc/meminfo
mu=$((mt - ma))
ram_pct=$(( (mu * 100) / mt ))
used_g=$(awk -v u=$mu 'BEGIN {printf "%.1fG", u/1048576}')
tot_g=$(awk -v t=$mt 'BEGIN {printf "%.1fG", t/1048576}')

# 3. Temp (x86_pkg_temp / TCPU / coretemp / thermal_zone)
temp=0
for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/type" 2>/dev/null)
    if [ "$t" = "x86_pkg_temp" ] || [ "$t" = "TCPU" ] || [ "$t" = "cpu_thermal" ] || [ "$t" = "coretemp" ]; then
        temp=$(cat "$z/temp" 2>/dev/null)
        break
    fi
done
[ "$temp" = "0" ] && temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)

# 4. Disk Usage (root /)
disk_info=$(df -h / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5"|"$3"|"$2}')
IFS='|' read -r disk_pct disk_used disk_tot <<< "$disk_info"

# 5. Uptime
read up _ < /proc/uptime
s=${up%.*}
d=$((s / 86400))
h=$(((s % 86400) / 3600))
m=$(((s % 3600) / 60))
if [ "$d" -gt 0 ]; then
    uptime_str="${d}d ${h}h ${m}m"
elif [ "$h" -gt 0 ]; then
    uptime_str="${h}h ${m}m"
else
    uptime_str="${m}m"
fi

echo "$cpu_pct|$ram_pct|$used_g|$tot_g|$temp|$disk_pct|$disk_used|$disk_tot|$uptime_str"
