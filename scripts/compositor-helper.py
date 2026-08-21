#!/usr/bin/env python3
"""
Compositor Helper for Quickshell
Fast, parallel, non-blocking queries and safe configuration changes for Hyprland and other compositors.
"""

import sys
import os
import json
import subprocess
import time
import shutil
import base64
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")

def is_hyprland():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    return bool(sig) or "hyprland" in desktop

def is_niri():
    sock = os.environ.get("NIRI_SOCKET", "")
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    return bool(sock) or "niri" in desktop

def is_lua_config():
    return os.path.exists(os.path.join(HOME, ".config/hypr/hyprland.lua"))

def run_proc(args, timeout=0.8):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        if r.returncode == 0:
            try:
                return json.loads(r.stdout)
            except Exception:
                return r.stdout.strip()
    except Exception:
        pass
    return None

def query_all():
    comp = "hyprland"
    if is_niri():
        comp = "niri"

    candidate_files = [
        os.path.join(HOME, ".config/hypr/hyprland.lua"),
        os.path.join(HOME, ".config/hypr/hyprland.conf"),
        os.path.join(HOME, ".config/hypr/hypridle.conf"),
        os.path.join(HOME, ".config/hypr/hyprlock.conf"),
        os.path.join(HOME, ".config/hypr/hyprpaper.conf"),
        os.path.join(HOME, ".config/niri/config.kdl"),
        os.path.join(HOME, ".config/sway/config"),
        os.path.join(HOME, ".config/river/init"),
        os.path.join(HOME, ".config/wayfire.ini"),
        os.path.join(HOME, ".config/MangoHud/MangoHud.conf")
    ]
    found_files = []
    for p in candidate_files:
        if os.path.exists(p):
            try:
                sz = os.path.getsize(p)
            except Exception:
                sz = 0
            found_files.append({
                "path": p,
                "name": os.path.basename(p),
                "dir": os.path.basename(os.path.dirname(p)),
                "size": sz
            })

    known_compositors = [
        {"id": "hyprland", "name": "Hyprland", "bin": "hyprctl", "primary": os.path.join(HOME, ".config/hypr/hyprland.lua") if os.path.exists(os.path.join(HOME, ".config/hypr/hyprland.lua")) else os.path.join(HOME, ".config/hypr/hyprland.conf")},
        {"id": "niri", "name": "Niri", "bin": "niri", "primary": os.path.join(HOME, ".config/niri/config.kdl")},
        {"id": "sway", "name": "Sway", "bin": "sway", "primary": os.path.join(HOME, ".config/sway/config")},
        {"id": "river", "name": "River", "bin": "river", "primary": os.path.join(HOME, ".config/river/init")},
        {"id": "wayfire", "name": "Wayfire", "bin": "wayfire", "primary": os.path.join(HOME, ".config/wayfire.ini")}
    ]
    installed_compositors = []
    for c in known_compositors:
        is_inst = shutil.which(c["bin"]) is not None or os.path.exists(c["primary"])
        installed_compositors.append({
            "id": c["id"],
            "name": c["name"],
            "isInstalled": is_inst,
            "primary": c["primary"]
        })

    if comp == "hyprland":
        options_keys = [
            ("blur", "decoration:blur:enabled", bool, True),
            ("blur_size", "decoration:blur:size", int, 4),
            ("blur_passes", "decoration:blur:passes", int, 2),
            ("anim", "animations:enabled", bool, True),
            ("shadow", "decoration:shadow:enabled", bool, True),
            ("shadow_range", "decoration:shadow:range", int, 4),
            ("shadow_power", "decoration:shadow:render_power", int, 3),
            ("rounding", "decoration:rounding", int, 10),
            ("border_size", "general:border_size", int, 0),
            ("gaps_in", "general:gaps_in", "gap", 5),
            ("gaps_out", "general:gaps_out", "gap", 10),
            ("active_opacity", "decoration:active_opacity", float, 0.90),
            ("inactive_opacity", "decoration:inactive_opacity", float, 0.95),
            ("dim_inactive", "decoration:dim_inactive", bool, False),
            ("dim_strength", "decoration:dim_strength", float, 0.50),
            ("layout", "general:layout", str, "scrolling"),
            ("touchpad_natural", "input:touchpad:natural_scroll", bool, True),
            ("touchpad_tap", "input:touchpad:tap-to-click", bool, True),
            ("touchpad_dwt", "input:touchpad:disable_while_typing", bool, True),
            ("sensitivity", "input:sensitivity", float, 0.0),
            ("resize_border", "general:resize_on_border", bool, False),
            ("disable_hyprland_logo", "misc:disable_hyprland_logo", bool, False)
        ]

        batch_list = ["j/monitors", "j/workspaces", "j/clients"] + [f"j/getoption {opt[1]}" for opt in options_keys]

        try:
            ver_p = subprocess.run(["hyprctl", "version"], capture_output=True, text=True, timeout=0.8)
            ver = ver_p.stdout.split("\n")[0] if ver_p.returncode == 0 else "Hyprland"
        except Exception:
            ver = "Hyprland"

        raw_opts = {k: dflt for k, _, _, dflt in options_keys}
        clean_monitors = []
        workspaces_count = 1
        windows_count = 0

        try:
            r = subprocess.run(["hyprctl", "--batch", " ; ".join(batch_list)], capture_output=True, text=True, timeout=1.0)
            if r.returncode == 0:
                import re
                raw_items = [x.strip() for x in re.split(r"\n{2,}", r.stdout.strip()) if x.strip()]
                if len(raw_items) >= 3:
                    try:
                        m_list = json.loads(raw_items[0])
                        if isinstance(m_list, list):
                            for m in m_list:
                                if isinstance(m, dict):
                                    clean_monitors.append({
                                        "id": m.get("id", 0),
                                        "name": m.get("name", "Display"),
                                        "description": m.get("description", ""),
                                        "width": m.get("width", 1920),
                                        "height": m.get("height", 1080),
                                        "refreshRate": round(float(m.get("refreshRate", 60))),
                                        "scale": float(m.get("scale", 1.0)),
                                        "focused": bool(m.get("focused", False)),
                                        "vrr": bool(m.get("vrr", False)),
                                        "activeWorkspace": m.get("activeWorkspace", {}).get("name", "1") if isinstance(m.get("activeWorkspace"), dict) else "1"
                                    })
                    except Exception:
                        pass

                    try:
                        ws_list = json.loads(raw_items[1])
                        if isinstance(ws_list, list):
                            workspaces_count = max(1, len(ws_list))
                    except Exception:
                        pass

                    try:
                        c_list = json.loads(raw_items[2])
                        if isinstance(c_list, list):
                            windows_count = len(c_list)
                    except Exception:
                        pass

                    for i, (k, _, typ, dflt) in enumerate(options_keys):
                        item_idx = 3 + i
                        if item_idx < len(raw_items):
                            try:
                                v_dict = json.loads(raw_items[item_idx])
                                if typ == bool:
                                    raw_opts[k] = v_dict.get("bool", dflt)
                                elif typ == int:
                                    raw_opts[k] = v_dict.get("int", dflt)
                                elif typ == float:
                                    raw_opts[k] = round(float(v_dict.get("float", dflt)), 2)
                                elif typ == "gap":
                                    s_val = str(v_dict.get("css") or v_dict.get("str") or dflt).strip().split()
                                    raw_opts[k] = int(s_val[0]) if s_val else dflt
                                elif typ == str:
                                    raw_opts[k] = v_dict.get("str") or v_dict.get("data") or dflt
                            except Exception:
                                raw_opts[k] = dflt
        except Exception:
            pass

        res = {
            "activeCompositor": "hyprland",
            "activeDisplayName": "Hyprland",
            "configType": "lua" if is_lua_config() else "conf",
            "version": ver,
            "monitorsCount": max(1, len(clean_monitors)),
            "monitors": clean_monitors,
            "workspacesCount": max(1, workspaces_count),
            "windowsCount": windows_count,
            "installedCompositors": installed_compositors,
            "discoveredConfigFiles": found_files
        }
        res.update(raw_opts)
        return res
    else:
        return {
            "activeCompositor": comp,
            "activeDisplayName": comp.capitalize(),
            "configType": "kdl" if comp == "niri" else "conf",
            "version": comp.capitalize(),
            "blur": True,
            "blur_size": 4,
            "blur_passes": 2,
            "anim": True,
            "shadow": True,
            "shadow_range": 4,
            "shadow_power": 3,
            "rounding": 10,
            "border_size": 1,
            "gaps_in": 5,
            "gaps_out": 10,
            "active_opacity": 1.0,
            "inactive_opacity": 1.0,
            "dim_inactive": False,
            "dim_strength": 0.5,
            "layout": "default",
            "touchpad_natural": True,
            "touchpad_tap": True,
            "touchpad_dwt": False,
            "sensitivity": 0.0,
            "resize_border": False,
            "disable_hyprland_logo": False,
            "monitorsCount": 1,
            "monitors": [],
            "workspacesCount": 1,
            "windowsCount": 0,
            "installedCompositors": installed_compositors,
            "discoveredConfigFiles": found_files
        }

def set_option(opt_name, opt_val):
    lua_map = {
        "blur": lambda v: f"hl.config({{ decoration = {{ blur = {{ enabled = {str(v).lower()} }} }} }})",
        "blur_size": lambda v: f"hl.config({{ decoration = {{ blur = {{ size = {int(v)} }} }} }})",
        "blur_passes": lambda v: f"hl.config({{ decoration = {{ blur = {{ passes = {int(v)} }} }} }})",
        "anim": lambda v: f"hl.config({{ animations = {{ enabled = {str(v).lower()} }} }})",
        "shadow": lambda v: f"hl.config({{ decoration = {{ shadow = {{ enabled = {str(v).lower()} }} }} }})",
        "shadow_range": lambda v: f"hl.config({{ decoration = {{ shadow = {{ range = {int(v)} }} }} }})",
        "shadow_power": lambda v: f"hl.config({{ decoration = {{ shadow = {{ render_power = {int(v)} }} }} }})",
        "rounding": lambda v: f"hl.config({{ decoration = {{ rounding = {int(v)} }} }})",
        "border_size": lambda v: f"hl.config({{ general = {{ border_size = {int(v)} }} }})",
        "gaps_in": lambda v: f"hl.config({{ general = {{ gaps_in = {int(v)} }} }})",
        "gaps_out": lambda v: f"hl.config({{ general = {{ gaps_out = {int(v)} }} }})",
        "active_opacity": lambda v: f"hl.config({{ decoration = {{ active_opacity = {float(v):.2f} }} }})",
        "inactive_opacity": lambda v: f"hl.config({{ decoration = {{ inactive_opacity = {float(v):.2f} }} }})",
        "dim_inactive": lambda v: f"hl.config({{ decoration = {{ dim_inactive = {str(v).lower()} }} }})",
        "dim_strength": lambda v: f"hl.config({{ decoration = {{ dim_strength = {float(v):.2f} }} }})",
        "layout": lambda v: f"hl.config({{ general = {{ layout = \"{str(v)}\" }} }})",
        "touchpad_natural": lambda v: f"hl.config({{ input = {{ touchpad = {{ natural_scroll = {str(v).lower()} }} }} }})",
        "touchpad_tap": lambda v: f"hl.config({{ input = {{ touchpad = {{ tap_to_click = {str(v).lower()} }} }} }})",
        "touchpad_dwt": lambda v: f"hl.config({{ input = {{ touchpad = {{ disable_while_typing = {str(v).lower()} }} }} }})",
        "sensitivity": lambda v: f"hl.config({{ input = {{ sensitivity = {float(v):.2f} }} }})",
        "resize_border": lambda v: f"hl.config({{ general = {{ resize_on_border = {str(v).lower()} }} }})",
        "disable_hyprland_logo": lambda v: f"hl.config({{ misc = {{ disable_hyprland_logo = {str(v).lower()} }} }})",
        "border_color_preset": lambda v: f"hl.config({{ general = {{ col = {{ active_border = {v} }} }} }})"
    }

    keyword_map = {
        "blur": lambda v: ("decoration:blur:enabled", "1" if str(v).lower() in ("true", "1") else "0"),
        "blur_size": lambda v: ("decoration:blur:size", str(v)),
        "blur_passes": lambda v: ("decoration:blur:passes", str(v)),
        "anim": lambda v: ("animations:enabled", "1" if str(v).lower() in ("true", "1") else "0"),
        "shadow": lambda v: ("decoration:shadow:enabled", "1" if str(v).lower() in ("true", "1") else "0"),
        "shadow_range": lambda v: ("decoration:shadow:range", str(v)),
        "shadow_power": lambda v: ("decoration:shadow:render_power", str(v)),
        "rounding": lambda v: ("decoration:rounding", str(v)),
        "border_size": lambda v: ("general:border_size", str(v)),
        "gaps_in": lambda v: ("general:gaps_in", str(v)),
        "gaps_out": lambda v: ("general:gaps_out", str(v)),
        "active_opacity": lambda v: ("decoration:active_opacity", str(v)),
        "inactive_opacity": lambda v: ("decoration:inactive_opacity", str(v)),
        "dim_inactive": lambda v: ("decoration:dim_inactive", "1" if str(v).lower() in ("true", "1") else "0"),
        "dim_strength": lambda v: ("decoration:dim_strength", str(v)),
        "layout": lambda v: ("general:layout", str(v)),
        "touchpad_natural": lambda v: ("input:touchpad:natural_scroll", "1" if str(v).lower() in ("true", "1") else "0"),
        "touchpad_tap": lambda v: ("input:touchpad:tap-to-click", "1" if str(v).lower() in ("true", "1") else "0"),
        "touchpad_dwt": lambda v: ("input:touchpad:disable_while_typing", "1" if str(v).lower() in ("true", "1") else "0"),
        "sensitivity": lambda v: ("input:sensitivity", str(v)),
        "resize_border": lambda v: ("general:resize_on_border", "1" if str(v).lower() in ("true", "1") else "0"),
        "disable_hyprland_logo": lambda v: ("misc:disable_hyprland_logo", "1" if str(v).lower() in ("true", "1") else "0"),
    }

    # If Lua mapper exists, try eval first
    if opt_name in lua_map:
        lua_code = lua_map[opt_name](opt_val)
        try:
            r = subprocess.run(["hyprctl", "eval", lua_code], capture_output=True, text=True, timeout=0.8)
            if r.returncode == 0 and "ok" in r.stdout.lower():
                return {"ok": True, "method": "eval", "lua": lua_code}
        except Exception:
            pass

    # Fallback to keyword if eval not supported or returned error
    if opt_name in keyword_map:
        k_key, k_val = keyword_map[opt_name](opt_val)
        try:
            r = subprocess.run(["hyprctl", "keyword", k_key, str(k_val)], capture_output=True, text=True, timeout=0.8)
            if r.returncode == 0:
                return {"ok": True, "method": "keyword", "key": k_key, "val": k_val}
            else:
                return {"ok": False, "error": r.stderr.strip() or r.stdout.strip()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    return {"ok": False, "error": f"Unknown option {opt_name}"}

def _write_and_validate(target_path, content):
    if not target_path:
        return {"ok": False, "error": "No target path provided"}

    # Syntax check if lua file
    if target_path.endswith(".lua"):
        tmp_check = f"/tmp/hypr_check_{os.getpid()}.lua"
        try:
            with open(tmp_check, "w", encoding="utf-8") as f:
                f.write(content)
            luac_res = subprocess.run(["luac", "-p", tmp_check], capture_output=True, text=True)
            if luac_res.returncode != 0:
                err = luac_res.stderr.strip() or luac_res.stdout.strip()
                if os.path.exists(tmp_check):
                    os.remove(tmp_check)
                return {"ok": False, "syntax_error": True, "error": f"Lua syntax error: {err}"}
            if os.path.exists(tmp_check):
                os.remove(tmp_check)
        except Exception as e:
            pass

    try:
        if os.path.exists(target_path):
            backup_path = f"{target_path}.bak.{int(time.time())}"
            shutil.copy2(target_path, backup_path)
        else:
            backup_path = None

        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        tmp_target = f"{target_path}.tmp.{os.getpid()}"
        with open(tmp_target, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_target, target_path)
        return {"ok": True, "backup": backup_path}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def save_config(target_path):
    content = sys.stdin.read()
    return _write_and_validate(target_path, content)

def save_config_b64(target_path, b64_str):
    try:
        content = base64.b64decode(b64_str.encode("ascii")).decode("utf-8")
        return _write_and_validate(target_path, content)
    except Exception as e:
        return {"ok": False, "error": f"Base64 decode error: {str(e)}"}

def reload_compositor():
    comp = "hyprland"
    if is_niri():
        comp = "niri"

    if comp == "hyprland":
        try:
            r = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True, timeout=1.5)
            return {"ok": r.returncode == 0, "output": r.stdout.strip()}
        except Exception as e:
            return {"ok": False, "error": str(e)}
    elif comp == "niri":
        try:
            r = subprocess.run(["niri", "msg", "action", "reload-config"], capture_output=True, text=True, timeout=1.5)
            return {"ok": r.returncode == 0, "output": r.stdout.strip()}
        except Exception as e:
            return {"ok": False, "error": str(e)}
    return {"ok": False, "error": "Unsupported compositor"}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Missing command argument"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "query":
        data = query_all()
        print(json.dumps(data))
    elif cmd == "set":
        if len(sys.argv) < 4:
            print(json.dumps({"ok": False, "error": "Usage: set <option> <value>"}))
            sys.exit(1)
        opt_name = sys.argv[2]
        opt_val = sys.argv[3]
        res = set_option(opt_name, opt_val)
        print(json.dumps(res))
    elif cmd == "save":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Usage: save <target_path>"}))
            sys.exit(1)
        target = sys.argv[2]
        res = save_config(target)
        print(json.dumps(res))
    elif cmd == "save-b64":
        if len(sys.argv) < 4:
            print(json.dumps({"ok": False, "error": "Usage: save-b64 <target_path> <b64_str>"}))
            sys.exit(1)
        target = sys.argv[2]
        b64_str = sys.argv[3]
        res = save_config_b64(target, b64_str)
        print(json.dumps(res))
    elif cmd == "reload":
        res = reload_compositor()
        print(json.dumps(res))
    else:
        print(json.dumps({"ok": False, "error": f"Unknown command {cmd}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
