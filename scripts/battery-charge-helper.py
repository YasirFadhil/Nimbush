#!/usr/bin/env python3
"""
battery-charge-helper.py - Battery Charge Limit & Inhibit Helper for Quickshell
Works with Linux kernel power_supply charge_behaviour interface (Chromebooks, ACPI, generic).
"""

import sys
import os
import glob
import json
import subprocess

BAT_DIR = "/sys/class/power_supply/BAT0"
BEHAVIOUR_FILE = os.path.join(BAT_DIR, "charge_behaviour")
CAPACITY_FILE = os.path.join(BAT_DIR, "capacity")
STATUS_FILE = os.path.join(BAT_DIR, "status")

def is_supported():
    return os.path.exists(BEHAVIOUR_FILE)

def is_ac_online():
    for p in glob.glob('/sys/class/power_supply/*'):
        if 'BAT' not in os.path.basename(p):
            online_f = os.path.join(p, 'online')
            if os.path.exists(online_f):
                try:
                    with open(online_f) as f:
                        if f.read().strip() == '1':
                            return True
                except Exception:
                    pass
    return False

def get_sysfs_status():
    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE) as f:
                return f.read().strip()
        except Exception:
            pass
    return "Unknown"

def get_current_mode():
    if not is_supported():
        return "unsupported"
    try:
        with open(BEHAVIOUR_FILE, "r") as f:
            content = f.read().strip()
            # Content format: "[auto] inhibit-charge force-discharge" or "auto [inhibit-charge] force-discharge"
            for item in content.split():
                if item.startswith("[") and item.endswith("]"):
                    return item[1:-1]
            return "auto"
    except Exception:
        return "unknown"

def get_capacity():
    if os.path.exists(CAPACITY_FILE):
        try:
            with open(CAPACITY_FILE, "r") as f:
                val = f.read().strip()
                if val.isdigit():
                    return int(val)
        except Exception:
            pass
    return 0

def set_mode(mode):
    if not is_supported():
        return False, "charge_behaviour not supported on this hardware"
    if mode not in ("auto", "inhibit-charge", "force-discharge"):
        return False, f"Invalid mode: {mode}"

    # 1. Try direct write (works if udev/tmpfiles sets 0666)
    try:
        with open(BEHAVIOUR_FILE, "w") as f:
            f.write(mode + "\n")
        return True, "Direct write succeeded"
    except PermissionError:
        pass
    except OSError as e:
        # ChromeOS EC may reject inhibit-charge when AC is disconnected (EIO / Errno 5).
        if not is_ac_online():
            return True, "On battery (charging already stopped naturally)"
        return False, str(e)
    except Exception as e:
        return False, str(e)

    # 2. Try sudo -n tee (works if sudoers has NOPASSWD for tee or script)
    try:
        proc = subprocess.run(
            ["sudo", "-n", "tee", BEHAVIOUR_FILE],
            input=(mode + "\n").encode(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=3
        )
        if proc.returncode == 0:
            return True, "sudo write succeeded"
        err_msg = proc.stderr.decode().strip()
    except Exception as e:
        err_msg = str(e)

    # 3. Try pkexec tee with standard bash shell
    try:
        env = dict(os.environ)
        env["SHELL"] = "/run/current-system/sw/bin/bash" if os.path.exists("/run/current-system/sw/bin/bash") else "/bin/sh"
        proc = subprocess.run(
            ["pkexec", "--disable-internal-agent", "tee", BEHAVIOUR_FILE],
            input=(mode + "\n").encode(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env=env,
            timeout=4
        )
        if proc.returncode == 0:
            return True, "pkexec write succeeded"
    except Exception:
        pass

    return False, f"Permission denied: {err_msg if 'err_msg' in locals() and err_msg else 'need write permission on charge_behaviour'}"

def get_status():
    supported = is_supported()
    mode = get_current_mode()
    cap = get_capacity()
    ac_online = is_ac_online()
    raw_status = get_sysfs_status()
    return {
        "supported": supported,
        "mode": mode,
        "isInhibited": mode == "inhibit-charge",
        "capacity": cap,
        "acOnline": ac_online,
        "batteryStatus": raw_status,
        "success": True
    }

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "get"
    if cmd == "get":
        print(json.dumps(get_status()))
    elif cmd == "set":
        if len(sys.argv) < 3:
            print(json.dumps({"success": False, "error": "Missing target mode (auto | inhibit-charge)"}))
            sys.exit(1)
        target = sys.argv[2]
        ok, msg = set_mode(target)
        status = get_status()
        status["success"] = ok
        if not ok:
            status["error"] = msg
        print(json.dumps(status))
    else:
        print(json.dumps({"success": False, "error": f"Unknown command: {cmd}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
