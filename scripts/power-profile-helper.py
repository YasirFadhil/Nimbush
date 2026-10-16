#!/usr/bin/env python3
"""
power-profile-helper.py - Power Profile & Manager helper for Quickshell
Supports TLP as primary power management daemon (with native profile switching & intel_pstate tuning),
with fallback to power-profiles-daemon (powerprofilesctl).
"""

import sys
import os
import json
import shutil
import subprocess

PSTATE_MAX_PERF = "/sys/devices/system/cpu/intel_pstate/max_perf_pct"


def get_sudo_nopasswd_binaries():
    """Dynamically discover binaries permitted with NOPASSWD in sudoers."""
    bins = {"tlp": [], "tee": []}
    try:
        res = subprocess.run(
            ["sudo", "-n", "-l"], capture_output=True, text=True, timeout=2
        )
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                for word in line.replace(",", " ").split():
                    if word.endswith("/tlp") and os.path.exists(word) and word not in bins["tlp"]:
                        bins["tlp"].append(word)
                    elif word.endswith("/tee") and os.path.exists(word) and word not in bins["tee"]:
                        bins["tee"].append(word)
    except Exception:
        pass
    return bins


def set_pstate_max_perf(pct):
    if not os.path.exists(PSTATE_MAX_PERF):
        return False

    # 1. Direct write fallback jika punya izin tulis langsung
    try:
        with open(PSTATE_MAX_PERF, "w") as f:
            f.write(str(pct) + "\n")
        return True
    except Exception:
        pass

    # 2. Coba via sudo -n tee (NOPASSWD discovery & system paths)
    tee_candidates = list(get_sudo_nopasswd_binaries().get("tee", []))
    for p in ["/run/current-system/sw/bin/tee", shutil.which("tee") or ""]:
        if p and os.path.exists(p) and p not in tee_candidates:
            tee_candidates.append(p)
        if p and os.path.islink(p):
            rp = os.path.realpath(p)
            if rp not in tee_candidates:
                tee_candidates.append(rp)
    for p in ["/usr/bin/tee", "/bin/tee"]:
        if os.path.exists(p) and p not in tee_candidates:
            tee_candidates.append(p)
    if "tee" not in tee_candidates:
        tee_candidates.append("tee")

    for tee_bin in tee_candidates:
        try:
            res = subprocess.run(
                ["sudo", "-n", tee_bin, PSTATE_MAX_PERF],
                input=f"{pct}\n".encode(),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=2,
            )
            if res.returncode == 0:
                return True
        except Exception:
            pass

    return False


def detect_backend():
    # 1. Prioritize TLP as the active power management backend
    if (
        os.path.exists("/run/tlp/last_pwr")
        or os.path.exists("/run/tlp/run.conf")
        or shutil.which("tlp")
        or shutil.which("tlp-stat")
    ):
        return "tlp"

    # 2. Fallback to power-profiles-daemon if active and available
    pp_cmd = shutil.which("powerprofilesctl")
    if pp_cmd:
        try:
            res = subprocess.run(
                [pp_cmd, "get"], capture_output=True, text=True, timeout=1.5
            )
            if res.returncode == 0 and res.stdout.strip():
                return "ppd"
        except Exception:
            pass

    return "none"


def get_tlp_profile():
    pp_map = {"0": "performance", "1": "balanced", "2": "power-saver"}
    ps_map = {"0": "AC", "1": "BAT", "128": "Unknown"}

    prof = None
    is_manual = False
    pwr_src = ""

    # 1. Cek manual mode TLP
    if os.path.exists("/run/tlp/manual_mode"):
        try:
            with open("/run/tlp/manual_mode") as f:
                code = f.read().strip()
                if code in pp_map:
                    prof = pp_map[code]
                    is_manual = True
        except Exception:
            pass

    # 2. Cek runtime state TLP last_pwr (profile & power source)
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

    # 3. Fallback tlp-stat -s (tidak butuh root privilege)
    if not prof or not pwr_src:
        tlp_stat = shutil.which("tlp-stat")
        if tlp_stat:
            try:
                res = subprocess.run(
                    [tlp_stat, "-s"], capture_output=True, text=True, timeout=1.5
                )
                if res.returncode == 0:
                    for line in res.stdout.splitlines():
                        if "TLP profile" in line:
                            val = line.split("=")[-1].strip().lower()
                            if not prof:
                                if "performance" in val or "prf" in val:
                                    prof = "performance"
                                elif "power-saver" in val or "battery" in val or "sav" in val:
                                    prof = "power-saver"
                                elif "balanced" in val or "bal" in val:
                                    prof = "balanced"
                        elif "Power source" in line and not pwr_src:
                            src_val = line.split("=")[-1].strip()
                            pwr_src = "BAT" if "bat" in src_val.lower() else ("AC" if "ac" in src_val.lower() else src_val)
            except Exception:
                pass

    # 4. Fallback cek dari pstate max_perf_pct jika belum terdeteksi
    if not prof and os.path.exists(PSTATE_MAX_PERF):
        try:
            with open(PSTATE_MAX_PERF, "r") as f:
                val = int(f.read().strip())
                if val <= 50:
                    prof = "power-saver"
                elif val >= 90:
                    prof = "performance"
                else:
                    prof = "balanced"
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
        "success": True,
    }

    if backend == "tlp":
        res["backendName"] = "TLP"
        prof, is_manual, pwr_src = get_tlp_profile()
        res["profile"] = prof
        res["isManual"] = is_manual
        res["powerSource"] = pwr_src
        res["supported"] = ["power-saver", "balanced", "performance"]

    elif backend == "ppd":
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
                    if p and p not in profs:
                        profs.append(p)
                elif l.endswith(":") and " " not in l:
                    p = l.rstrip(":")
                    if p and p not in profs:
                        profs.append(p)
            if profs:
                res["supported"] = profs
        except Exception:
            pass

    return res


def run_tlp_command(args):
    # Kumpulkan semua kandidat tlp executable:
    # Prioritaskan binary yang terdaftar di sudoers NOPASSWD, lalu system binaries
    candidate_paths = list(get_sudo_nopasswd_binaries().get("tlp", []))
    for p in ["/run/current-system/sw/bin/tlp", shutil.which("tlp") or ""]:
        if p and os.path.exists(p) and p not in candidate_paths:
            candidate_paths.append(p)
        if p and os.path.islink(p):
            rp = os.path.realpath(p)
            if rp not in candidate_paths:
                candidate_paths.append(rp)
    for p in ["/usr/bin/tlp", "/usr/local/bin/tlp", "/bin/tlp"]:
        if os.path.exists(p) and p not in candidate_paths:
            candidate_paths.append(p)
    if "tlp" not in candidate_paths:
        candidate_paths.append("tlp")

    # 1. Coba via sudo -n
    for tp in candidate_paths:
        try:
            res = subprocess.run(
                ["sudo", "-n", tp] + args, capture_output=True, text=True, timeout=3
            )
            if res.returncode == 0:
                return True, res.stdout.strip()
        except Exception:
            pass

    # 2. Coba via pkexec jika sudo -n belum berhasil
    pkexec_path = shutil.which("pkexec")
    if pkexec_path:
        env = dict(os.environ)
        std_shell = (
            "/run/current-system/sw/bin/bash"
            if os.path.exists("/run/current-system/sw/bin/bash")
            else (shutil.which("bash") or "/bin/sh")
        )
        env["SHELL"] = std_shell
        for tp in candidate_paths:
            if tp == "tlp":
                continue
            try:
                res = subprocess.run(
                    [pkexec_path, "--disable-internal-agent", tp] + args,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if res.returncode == 0:
                    return True, res.stdout.strip()
            except Exception:
                pass

    # 3. Direct execution fallback
    for tp in candidate_paths:
        try:
            res = subprocess.run([tp] + args, capture_output=True, text=True, timeout=3)
            if res.returncode == 0:
                return True, res.stdout.strip()
            err_msg = (res.stderr or res.stdout).strip()
            if err_msg:
                return False, err_msg
        except Exception as e:
            return False, str(e)

    return False, "Failed to execute tlp command (requires root / sudoers / polkit permission)"


def set_profile(name):
    backend = detect_backend()
    if backend == "tlp":
        # Atur batas performa CPU Intel sesuai profile jika intel_pstate tersedia
        if name == "power-saver":
            set_pstate_max_perf(45)
            # Modern TLP 1.8+ supports 'power-saver', fallback to 'bat'
            ok, out = run_tlp_command(["power-saver"])
            if not ok:
                ok, out = run_tlp_command(["bat"])
            return ok, out
        elif name == "performance":
            set_pstate_max_perf(100)
            # Modern TLP 1.8+ supports 'performance', fallback to 'ac'
            ok, out = run_tlp_command(["performance"])
            if not ok:
                ok, out = run_tlp_command(["ac"])
            return ok, out
        elif name == "balanced":
            set_pstate_max_perf(70)
            # Modern TLP 1.8+ supports 'balanced', fallback to 'start'
            ok, out = run_tlp_command(["balanced"])
            if not ok:
                ok, out = run_tlp_command(["start"])
            return ok, out
        elif name in ("auto", "start"):
            return run_tlp_command(["start"])
        return False, f"Unknown profile: {name}"

    elif backend == "ppd":
        pp_cmd = shutil.which("powerprofilesctl") or "powerprofilesctl"
        res = subprocess.run([pp_cmd, "set", name], capture_output=True, text=True)
        return res.returncode == 0, res.stderr or res.stdout

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
        status["profile"] = target
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
        print(
            json.dumps({"success": False, "error": f"Unknown command: {sys.argv[1]}"})
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
