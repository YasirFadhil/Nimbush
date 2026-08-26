#!/usr/bin/env python3
import sys
import os
import signal
import subprocess
import json
import getpass

def get_cpu_info():
    model = "Processor"
    cores = os.cpu_count() or 1
    try:
        with open("/proc/cpuinfo", "r") as f:
            for line in f:
                if line.startswith("model name"):
                    model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass
    # Clean up model name
    model = model.replace("(R)", "").replace("(TM)", "").replace("CPU", "").strip()
    return {
        "model": model,
        "cores": cores
    }

NAME_MAP = {
    "antigravity-ide": "Antigravity IDE",
    "antigravity-i": "Antigravity IDE",
    "claude-desktop": "Claude Desktop",
    "quickshell": "Quickshell",
    "hyprland": "Hyprland",
    "hyprlan": "Hyprland",
    "kitty": "Kitty",
    "firefox": "Firefox",
    "chrome": "Chrome",
    "chromium": "Chromium",
    "brave": "Brave",
    "zen": "Zen Browser",
    "code": "VS Code",
    "wireplumber": "WirePlumber",
    "pipewire": "PipeWire",
    "pipewire-pulse": "PipeWire Pulse",
    "kdeconnectd": "KDE Connect",
    "dbus-broker": "DBus Broker",
    "warp-svc": "Cloudflare WARP",
    "systemd": "systemd",
    "language_server": "Language Server",
    "language_server_lin": "Language Server",
    "waybar": "Waybar",
    "swww": "SWWW Daemon",
    "swww-daemon": "SWWW Daemon",
    "dunst": "Dunst",
    "mako": "Mako",
    "rofi": "Rofi",
    "wofi": "Wofi",
    "bash": "Bash",
    "zsh": "Zsh",
    "fish": "Fish",
    "tmux": "Tmux",
    "spotify": "Spotify",
    "discord": "Discord",
    "slack": "Slack",
    "telegram-desktop": "Telegram",
    "obs": "OBS Studio",
    "foot": "Foot Terminal",
    "alacritty": "Alacritty",
    "wezterm": "WezTerm",
    "mpv": "MPV Player",
    "vlc": "VLC Media Player"
}

def get_process_name(pid, comm, args):
    raw_name = ""
    # Try reading /proc/pid/cmdline first for exact executable basename
    try:
        with open(f"/proc/{pid}/cmdline", "r", errors="ignore") as f:
            raw = f.read()
            if raw:
                parts = raw.split("\x00")
                exe = parts[0]
                if exe and ("/" in exe or len(exe) > 1):
                    b = os.path.basename(exe).lstrip(".").rstrip("-wrapped")
                    if b and b not in ("python", "python3", "sh", "bash", "zsh", "exe", "electron"):
                        raw_name = b
    except Exception:
        pass

    if not raw_name:
        try:
            with open(f"/proc/{pid}/comm", "r", errors="ignore") as f:
                c = f.read().strip()
                if c:
                    raw_name = c.lstrip(".").rstrip("-wrapped")
        except Exception:
            pass

    if not raw_name and comm:
        raw_name = comm.lstrip(".").rstrip("-wrapped")

    if not raw_name and args:
        first = args.split()[0]
        raw_name = os.path.basename(first).lstrip(".").rstrip("-wrapped")

    if not raw_name:
        raw_name = f"proc_{pid}"

    # Clean display name
    clean_lower = raw_name.lower()
    display = NAME_MAP.get(clean_lower, raw_name)

    if display == raw_name and len(display) > 2 and display.islower():
        display = display.capitalize()

    # Append subtype if electron/chrome/ide
    if any(k in clean_lower for k in ("antigravity", "claude", "chrome", "chromium", "electron", "code")):
        if "--type=renderer" in args:
            display += " (Renderer)"
        elif "--type=zygote" in args:
            display += " (Zygote)"
        elif "--type=utility" in args:
            display += " (Utility)"
        elif "--type=gpu-process" in args:
            display += " (GPU)"

    return display

def list_processes(sort_by="cpu", query=""):
    sort_flag = "-%cpu"
    if sort_by == "mem":
        sort_flag = "-%mem"
    elif sort_by == "name":
        sort_flag = "comm"

    my_pid = os.getpid()
    current_user = getpass.getuser()
    
    try:
        cmd = ["ps", "-eo", "pid,user,%cpu,%mem,rss,comm,args", f"--sort={sort_flag}"]
        output = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception as e:
        return []

    lines = output.strip().split("\n")
    procs = []
    q = query.lower().strip()

    for line in lines[1:]:
        parts = line.strip().split(None, 6)
        if len(parts) >= 7:
            pid_str, user, cpu_str, mem_str, rss_str_raw, comm, args = parts
        elif len(parts) == 6:
            pid_str, user, cpu_str, mem_str, rss_str_raw, comm = parts
            args = comm
        else:
            continue

        try:
            pid = int(pid_str)
        except ValueError:
            continue

        if pid == my_pid:
            continue

        name = get_process_name(pid, comm, args)

        if name in ("ps", "tasks-helper.py", "tasks-helper"):
            continue

        # Apply search query filter if provided
        if q:
            if q not in name.lower() and q not in str(pid) and q not in args.lower():
                continue

        try:
            cpu_val = float(cpu_str)
            mem_val = float(mem_str)
            rss_val = int(rss_str_raw)
        except ValueError:
            continue

        if rss_val < 1024:
            rss_formatted = f"{rss_val} KB"
        elif rss_val < 1048576:
            rss_formatted = f"{round(rss_val / 1024, 1)} MB"
        else:
            rss_formatted = f"{round(rss_val / 1048576, 2)} GB"

        # Determine icon type / category
        icon_category = "process"
        lower_name = name.lower()
        if any(b in lower_name for b in ["firefox", "chrome", "chromium", "brave", "zen", "opera", "vivaldi", "edge", "tor"]):
            icon_category = "browser"
        elif any(e in lower_name for e in ["code", "cursor", "antigravity", "idea", "sublime", "nvim", "vim", "emacs", "zed"]):
            icon_category = "editor"
        elif any(t in lower_name for t in ["kitty", "alacritty", "foot", "wezterm", "terminal", "bash", "zsh", "fish", "tmux"]):
            icon_category = "terminal"
        elif any(m in lower_name for m in ["spotify", "vlc", "mpv", "amberol", "rhythmbox", "discord", "telegram", "slack"]):
            icon_category = "media"
        elif any(s in lower_name for s in ["systemd", "dbus", "wireplumber", "pipewire", "hyprland", "waybar", "quickshell", "polkit", "warp"]):
            icon_category = "system"

        is_user_app = (icon_category in ("browser", "editor", "terminal", "media") or (user.startswith(current_user[:6]) and icon_category != "system"))

        procs.append({
            "pid": pid,
            "name": name,
            "user": user,
            "cpu": cpu_val,
            "mem": mem_val,
            "rss_mb": round(rss_val / 1024, 1),
            "rss_str": rss_formatted,
            "category": icon_category,
            "is_app": is_user_app,
            "cmd": args[:200]
        })

        if len(procs) >= 75:
            break

    return procs

def kill_process(pid_str, sig_num=15):
    try:
        pid = int(pid_str)
        os.kill(pid, sig_num)
        return {"success": True, "pid": pid, "signal": sig_num}
    except ProcessLookupError:
        return {"success": False, "error": "Process not found", "pid": pid_str}
    except PermissionError:
        return {"success": False, "error": "Permission denied", "pid": pid_str}
    except Exception as e:
        return {"success": False, "error": str(e), "pid": pid_str}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No action specified"}))
        return

    action = sys.argv[1]

    if action == "list":
        sort_by = sys.argv[2] if len(sys.argv) > 2 else "cpu"
        query = sys.argv[3] if len(sys.argv) > 3 else ""
        data = list_processes(sort_by, query)
        print(json.dumps(data))

    elif action == "kill":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "PID required"}))
            return
        pid = sys.argv[2]
        sig = int(sys.argv[3]) if len(sys.argv) > 3 else 15
        result = kill_process(pid, sig)
        print(json.dumps(result))

    elif action == "info":
        info = get_cpu_info()
        print(json.dumps(info))

    else:
        print(json.dumps({"error": f"Unknown action {action}"}))

if __name__ == "__main__":
    main()
