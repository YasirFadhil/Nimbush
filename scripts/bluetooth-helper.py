#!/usr/bin/env python3
"""
bluetooth-helper.py - Robust Bluetooth Management Helper for Quickshell
Handles device listing (categorizing saved vs unpaired devices), pairing, trusting,
connecting, disconnecting, and battery monitoring with zero dropped states.
"""

import sys
import subprocess
import json
import re

def get_devices():
    saved_devices = []
    unpaired_devices = []
    
    try:
        dev_proc = subprocess.run(
            ["bluetoothctl", "devices"],
            capture_output=True,
            text=True,
            timeout=4
        )
        dev_lines = dev_proc.stdout.strip().splitlines()
    except Exception:
        dev_lines = []
        
    for line in dev_lines:
        line = line.strip()
        if not line.startswith("Device "):
            continue
        parts = line.split(" ", 2)
        if len(parts) < 3:
            continue
        mac = parts[1]
        name = parts[2]
        
        info = {
            "mac": mac,
            "name": name,
            "connected": False,
            "paired": False,
            "trusted": False,
            "bonded": False,
            "battery": -1,
            "icon": ""
        }
        
        try:
            info_proc = subprocess.run(
                ["bluetoothctl", "info", mac],
                capture_output=True,
                text=True,
                timeout=3
            )
            for iline in info_proc.stdout.splitlines():
                s = iline.strip()
                if s.startswith("Connected: yes"):
                    info["connected"] = True
                elif s.startswith("Paired: yes"):
                    info["paired"] = True
                elif s.startswith("Trusted: yes"):
                    info["trusted"] = True
                elif s.startswith("Bonded: yes"):
                    info["bonded"] = True
                elif s.startswith("Name: "):
                    info["name"] = s[6:].strip()
                elif s.startswith("Alias: "):
                    info["name"] = s[7:].strip()
                elif s.startswith("Icon: "):
                    info["icon"] = s[6:].strip()
                elif "Battery Percentage:" in s:
                    m = re.search(r"Battery Percentage:\s*(?:0x[0-9a-fA-F]+\s*\()?(\d+)\)?%?", s)
                    if m:
                        try:
                            info["battery"] = int(m.group(1))
                        except ValueError:
                            pass
        except Exception:
            pass
            
        # Any device that is Trusted, Paired, Bonded, or Connected is a Saved / Paired Device
        if info["trusted"] or info["paired"] or info["bonded"] or info["connected"]:
            saved_devices.append(info)
        else:
            unpaired_devices.append(info)
            
    # Sort: Connected devices first, then alphabetically by name
    saved_devices.sort(key=lambda d: (not d["connected"], d["name"].lower()))
    
    return {"devices": saved_devices, "unpaired": unpaired_devices}


def pair_device(mac):
    if not mac:
        return {"success": False, "error": "No MAC specified"}
        
    # Ensure bluetooth is powered on & pairable
    subprocess.run(["bluetoothctl", "power", "on"], capture_output=True, timeout=3)
    subprocess.run(["bluetoothctl", "pairable", "on"], capture_output=True, timeout=3)
    
    # Automated interactive session with NoInputNoOutput agent for PINless auto-approval
    session_input = f"agent NoInputNoOutput\ndefault-agent\ntrust {mac}\npair {mac}\ntrust {mac}\nconnect {mac}\nquit\n"
    try:
        subprocess.run(
            ["bluetoothctl", "--timeout", "25"],
            input=session_input,
            text=True,
            capture_output=True,
            timeout=28
        )
    except Exception:
        pass
        
    # Extra safety: trust the device
    subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, timeout=3)
    
    # Check if device is saved or connected
    try:
        check = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True, timeout=3).stdout
        is_ok = ("Trusted: yes" in check) or ("Paired: yes" in check) or ("Connected: yes" in check)
        return {"success": is_ok}
    except Exception as e:
        return {"success": False, "error": str(e)}


def connect_device(mac):
    if not mac:
        return {"success": False, "error": "No MAC specified"}
    # Ensure trusted so connection is accepted smoothly
    subprocess.run(["bluetoothctl", "trust", mac], capture_output=True, timeout=3)
    res = subprocess.run(["bluetoothctl", "connect", mac], capture_output=True, text=True, timeout=12)
    return {"success": res.returncode == 0, "output": res.stdout + res.stderr}


def disconnect_device(mac):
    if not mac:
        return {"success": False, "error": "No MAC specified"}
    res = subprocess.run(["bluetoothctl", "disconnect", mac], capture_output=True, text=True, timeout=8)
    return {"success": res.returncode == 0, "output": res.stdout + res.stderr}


def remove_device(mac):
    if not mac:
        return {"success": False, "error": "No MAC specified"}
    res = subprocess.run(["bluetoothctl", "remove", mac], capture_output=True, text=True, timeout=8)
    return {"success": res.returncode == 0, "output": res.stdout + res.stderr}


def main():
    if len(sys.argv) < 2:
        cmd = "list"
    else:
        cmd = sys.argv[1].lower()
        
    if cmd == "list":
        data = get_devices()
        print(json.dumps(data))
    elif cmd == "pair" and len(sys.argv) >= 3:
        res = pair_device(sys.argv[2])
        print(json.dumps(res))
    elif cmd == "connect" and len(sys.argv) >= 3:
        res = connect_device(sys.argv[2])
        print(json.dumps(res))
    elif cmd == "disconnect" and len(sys.argv) >= 3:
        res = disconnect_device(sys.argv[2])
        print(json.dumps(res))
    elif cmd == "remove" and len(sys.argv) >= 3:
        res = remove_device(sys.argv[2])
        print(json.dumps(res))
    else:
        print(json.dumps({"error": f"Unknown command: {cmd}"}))

if __name__ == "__main__":
    main()
