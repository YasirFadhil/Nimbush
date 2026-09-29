#!/usr/bin/env python3
"""
power-profile-helper.py - Power Profile & Manager helper for Quickshell
Supports both power-profiles-daemon (powerprofilesctl) and TLP.
"""

import sys
import os
import json
import shutil
import subprocess

def detect_backend():
    # 1. Check if powerprofilesctl exists and daemon is actively responding
    pp_cmd = shutil.which("powerprofilesctl")
    if pp_cmd:
        try:
            res = subprocess.run([pp_cmd, "get"], capture_output=True, text=True, timeout=1.5)
            if res.returncode == 0 and res.stdout.strip():
                return "ppd"
        except Exception:
            pass

    # 2. Check if TLP is installed or active
    if os.path.exists("/run/tlp/last_pwr") or os.path.exists("/run/tlp/run.conf") or shutil.which("tlp") or shutil.which("tlp-stat"):
        return "tlp"

    return "none"

def get_tlp_profile():
    pp_map = {"0": "performance", "1": "balanced", "2": "power-saver"}
    ps_map = {"0": "AC", "1": "BAT", "128": "Unknown"}

    prof = None
    is_manual = False
    pwr_src = ""

    # Check manual override
    if os.path.exists("/run/tlp/manual_mode"):
        try:
            with open("/run/tlp/manual_mode") as f:
                code = f.read().strip()
                if code in pp_map:
                    prof = pp_map[code]
                    is_manual = True
        except Exception:
            pass

    # Check last applied profile from /run/tlp/last_pwr
    if os.path.exists("/run/tlp/last_pwr"):
        try:
            with open("/run/tlp/last_pwr") as f:
                parts = f.read().strip().split()
                if parts:
                    if not prof and parts[0] in pp_map:
                        prof = pp_map[parts[0]]
                    if len(parts) > 1 and parts[1] in ps_map:
                        pwr_src = ps_map[parts[1]]
        except Exception:
            pass

    # Fallback to tlp-stat -s if needed
    if not prof:
        tlp_stat = shutil.which("tlp-stat")
        if tlp_stat:
            try:
                out = subprocess.check_output([tlp_stat, "-s"], timeout=2.0).decode()
                for line in out.splitlines():
                    if "TLP profile" in line:
                        v = line.split("=", 1)[1].strip().lower()
                        if "manual" in v:
                            is_manual = True
                        if "power-saver" in v:
                            prof = "power-saver"
                        elif "performance" in v:
                            prof = "performance"
                        elif "balanced" in v:
                            prof = "balanced"
                    elif "Power source" in line:
                        pwr_src = line.split("=", 1)[1].strip()
            except Exception:
                pass

    return prof or "balanced", is_manual, pwr_src

def get_status():
    backend = detect_backend()
    res = {
        "backend": backend,
        "backendName": "None",
        "profile": "balanced",
        "supported": ["power-saver", "balanced", "performance"],
        "isManual": False,
        "powerSource": "",
        "success": True
    }

    if backend == "ppd":
        res["backendName"] = "Power Profiles Daemon"
        pp_cmd = shutil.which("powerprofilesctl")
        try:
            out = subprocess.check_output([pp_cmd, "get"], timeout=1.5).decode().strip()
            if out:
                res["profile"] = out
        except Exception:
            pass

        try:
            out = subprocess.check_output([pp_cmd, "list"], timeout=1.5).decode()
            profs = []
            for l in out.splitlines():
                l = l.strip()
                if l.startswith("*"):
                    p = l.lstrip("* ").rstrip(":")
                    if p and p not in profs: profs.append(p)
                elif l.endswith(":") and " " not in l:
                    p = l.rstrip(":")
                    if p and p not in profs: profs.append(p)
            if profs:
                res["supported"] = profs
        except Exception:
            pass

    elif backend == "tlp":
        res["backendName"] = "TLP"
        prof, is_manual, pwr_src = get_tlp_profile()
        res["profile"] = prof
        res["isManual"] = is_manual
        res["powerSource"] = pwr_src
        res["supported"] = ["power-saver", "balanced", "performance"]

    return res

def run_tlp_command(args):
    candidate_paths = [
        "/run/current-system/sw/bin/tlp",
        shutil.which("tlp") or ""
    ]
    tlp_paths = list(dict.fromkeys([p for p in candidate_paths if p and os.path.exists(p)]))
    if not tlp_paths:
        return False, "tlp executable not found"

    # 1. Try sudo -n for each candidate path (works if sudoers has NOPASSWD)
    for tp in tlp_paths:
        try:
            res = subprocess.run(["sudo", "-n", tp] + args, capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                return True, res.stdout
        except Exception:
            pass

    # 2. Try pkexec (ensure SHELL is a valid standard shell present in /etc/shells, avoiding nushell issue)
    pkexec_path = shutil.which("pkexec")
    if pkexec_path:
        env = dict(os.environ)
        # /etc/shells on NixOS contains /run/current-system/sw/bin/bash or /bin/sh
        std_shell = "/run/current-system/sw/bin/bash" if os.path.exists("/run/current-system/sw/bin/bash") else (shutil.which("bash") or "/bin/sh")
        env["SHELL"] = std_shell
        for tp in tlp_paths:
            try:
                res = subprocess.run([pkexec_path, "--disable-internal-agent", tp] + args, env=env, capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    return True, res.stdout
            except Exception:
                pass

    # 3. Direct execution fallback
    for tp in tlp_paths:
        try:
            res = subprocess.run([tp] + args, capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                return True, res.stdout
            return False, (res.stderr or res.stdout).strip()
        except Exception as e:
            return False, str(e)

    return False, "Failed to execute tlp command"


def set_profile(name):
    backend = detect_backend()
    if backend == "ppd":
        pp_cmd = shutil.which("powerprofilesctl") or "powerprofilesctl"
        res = subprocess.run([pp_cmd, "set", name], capture_output=True, text=True)
        return res.returncode == 0, res.stderr or res.stdout
    elif backend == "tlp":
        if name in ("auto", "start"):
            return run_tlp_command(["start"])
        # name is power-saver, balanced, or performance
        return run_tlp_command([name])
    return False, "No active power profile backend detected"

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "get":
        print(json.dumps(get_status()))
    elif sys.argv[1] == "set":
        if len(sys.argv) < 3:
            print(json.dumps({"success": False, "error": "Missing profile argument"}))
            sys.exit(1)
        target = sys.argv[2]
        ok, msg = set_profile(target)
        status = get_status()
        status["success"] = ok
        if not ok:
            status["error"] = str(msg).strip()
        print(json.dumps(status))
    elif sys.argv[1] == "auto":
        ok, msg = set_profile("auto")
        status = get_status()
        status["success"] = ok
        if not ok:
            status["error"] = str(msg).strip()
        print(json.dumps(status))
    else:
        print(json.dumps({"success": False, "error": f"Unknown command: {sys.argv[1]}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
