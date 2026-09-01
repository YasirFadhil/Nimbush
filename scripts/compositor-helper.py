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
import re
import bisect
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
            ("layout", "general:layout", str, "dwindle"),
            ("scrolling_column_width", "scrolling:column_width", float, 0.89),
            ("scrolling_fullscreen_on_one_column", "scrolling:fullscreen_on_one_column", bool, False),
            ("touchpad_natural", "input:touchpad:natural_scroll", bool, True),
            ("touchpad_tap", "input:touchpad:tap-to-click", bool, True),
            ("touchpad_dwt", "input:touchpad:disable_while_typing", bool, True),
            ("sensitivity", "input:sensitivity", float, 0.0),
            ("resize_border", "general:resize_on_border", bool, False),
            ("disable_hyprland_logo", "misc:disable_hyprland_logo", bool, False),
            ("smart_gaps", "dwindle:no_gaps_when_only", bool, False),
            ("follow_mouse", "input:follow_mouse", int, 1),
            ("workspace_swipe", "gestures:workspace_swipe", bool, True),
            ("workspace_swipe_invert", "gestures:workspace_swipe_invert", bool, False),
            ("vfr", "misc:vfr", bool, True),
            ("allow_tearing", "general:allow_tearing", bool, False)
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
                                        "make": m.get("make", ""),
                                        "model": m.get("model", ""),
                                        "serial": m.get("serial", ""),
                                        "width": int(m.get("width", 1920)),
                                        "height": int(m.get("height", 1080)),
                                        "physicalWidth": int(m.get("physicalWidth", 0)),
                                        "physicalHeight": int(m.get("physicalHeight", 0)),
                                        "refreshRate": round(float(m.get("refreshRate", 60))),
                                        "exactRefreshRate": round(float(m.get("refreshRate", 60)), 2),
                                        "x": int(m.get("x", 0)),
                                        "y": int(m.get("y", 0)),
                                        "scale": float(m.get("scale", 1.0)),
                                        "transform": int(m.get("transform", 0)),
                                        "focused": bool(m.get("focused", False)),
                                        "vrr": bool(m.get("vrr", False)),
                                        "dpmsStatus": bool(m.get("dpmsStatus", True)),
                                        "disabled": bool(m.get("disabled", False)),
                                        "mirrorOf": m.get("mirrorOf", "none") or "none",
                                        "availableModes": m.get("availableModes", []),
                                        "sdrBrightness": float(m.get("sdrBrightness", 1.0)),
                                        "sdrSaturation": float(m.get("sdrSaturation", 1.0)),
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
    elif comp == "niri":
        clean_monitors = []
        workspaces_count = 1
        windows_count = 0
        ver = "Niri"
        try:
            ver_p = subprocess.run(["niri", "--version"], capture_output=True, text=True, timeout=0.8)
            if ver_p.returncode == 0:
                ver = ver_p.stdout.strip()
        except Exception:
            pass

        try:
            out_p = subprocess.run(["niri", "msg", "-j", "outputs"], capture_output=True, text=True, timeout=0.8)
            if out_p.returncode == 0:
                outs = json.loads(out_p.stdout)
                if isinstance(outs, dict):
                    for name, m in outs.items():
                        modes = m.get("modes", [])
                        cur_mode = m.get("current_mode", 0)
                        mode_info = modes[cur_mode] if (isinstance(cur_mode, int) and cur_mode < len(modes)) else (modes[0] if modes else {})
                        clean_monitors.append({
                            "id": name,
                            "name": name,
                            "description": (m.get("make", "") + " " + m.get("model", "")).strip() or name,
                            "make": m.get("make", ""),
                            "model": m.get("model", ""),
                            "serial": m.get("serial", ""),
                            "width": int(mode_info.get("width", 1920)),
                            "height": int(mode_info.get("height", 1080)),
                            "physicalWidth": 0,
                            "physicalHeight": 0,
                            "refreshRate": round(float(mode_info.get("refresh_rate", 60000)) / 1000.0),
                            "exactRefreshRate": round(float(mode_info.get("refresh_rate", 60000)) / 1000.0, 2),
                            "x": int(m.get("position", {}).get("x", 0)) if isinstance(m.get("position"), dict) else 0,
                            "y": int(m.get("position", {}).get("y", 0)) if isinstance(m.get("position"), dict) else 0,
                            "scale": float(m.get("scale", 1.0)),
                            "transform": 0,
                            "focused": True,
                            "vrr": bool(m.get("vrr", False)),
                            "dpmsStatus": not bool(m.get("is_off", False)),
                            "disabled": bool(m.get("is_off", False)),
                            "mirrorOf": "none",
                            "availableModes": [f"{mode.get('width')}x{mode.get('height')}@{round(mode.get('refresh_rate', 60000)/1000.0, 2)}Hz" for mode in modes if isinstance(mode, dict)],
                            "sdrBrightness": 1.0,
                            "sdrSaturation": 1.0,
                            "activeWorkspace": "1"
                        })
        except Exception:
            pass

        try:
            ws_p = subprocess.run(["niri", "msg", "-j", "workspaces"], capture_output=True, text=True, timeout=0.8)
            if ws_p.returncode == 0:
                ws_list = json.loads(ws_p.stdout)
                if isinstance(ws_list, list):
                    workspaces_count = max(1, len(ws_list))
        except Exception:
            pass

        try:
            win_p = subprocess.run(["niri", "msg", "-j", "windows"], capture_output=True, text=True, timeout=0.8)
            if win_p.returncode == 0:
                win_list = json.loads(win_p.stdout)
                if isinstance(win_list, list):
                    windows_count = len(win_list)
        except Exception:
            pass

        return {
            "activeCompositor": "niri",
            "activeDisplayName": "Niri",
            "configType": "kdl",
            "version": ver,
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
            "layout": "scrolling",
            "scrolling_column_width": 0.89,
            "scrolling_fullscreen_on_one_column": False,
            "touchpad_natural": True,
            "touchpad_tap": True,
            "touchpad_dwt": False,
            "sensitivity": 0.0,
            "resize_border": False,
            "disable_hyprland_logo": False,
            "monitorsCount": max(1, len(clean_monitors)),
            "monitors": clean_monitors,
            "workspacesCount": max(1, workspaces_count),
            "windowsCount": windows_count,
            "installedCompositors": installed_compositors,
            "discoveredConfigFiles": found_files
        }
    else:
        return {
            "activeCompositor": comp,
            "activeDisplayName": comp.capitalize(),
            "configType": "conf",
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
            "scrolling_column_width": 0.89,
            "scrolling_fullscreen_on_one_column": False,
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

LUA_MAP = {
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
    "scrolling_column_width": lambda v: f"hl.config({{ scrolling = {{ column_width = {float(v):.2f} }} }})",
    "scrolling_fullscreen_on_one_column": lambda v: f"hl.config({{ scrolling = {{ fullscreen_on_one_column = {str(v).lower()} }} }})",
    "column_width": lambda v: f"hl.config({{ scrolling = {{ column_width = {float(v):.2f} }} }})",
    "fullscreen_on_one_column": lambda v: f"hl.config({{ scrolling = {{ fullscreen_on_one_column = {str(v).lower()} }} }})",
    "touchpad_natural": lambda v: f"hl.config({{ input = {{ touchpad = {{ natural_scroll = {str(v).lower()} }} }} }})",
    "touchpad_tap": lambda v: f"hl.config({{ input = {{ touchpad = {{ tap_to_click = {str(v).lower()} }} }} }})",
    "touchpad_dwt": lambda v: f"hl.config({{ input = {{ touchpad = {{ disable_while_typing = {str(v).lower()} }} }} }})",
    "sensitivity": lambda v: f"hl.config({{ input = {{ sensitivity = {float(v):.2f} }} }})",
    "resize_border": lambda v: f"hl.config({{ general = {{ resize_on_border = {str(v).lower()} }} }})",
    "disable_hyprland_logo": lambda v: f"hl.config({{ misc = {{ disable_hyprland_logo = {str(v).lower()} }} }})",
    "border_color_preset": lambda v: f"hl.config({{ general = {{ col = {{ active_border = {v} }} }} }})"
}

KEYWORD_MAP = {
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
    "scrolling_column_width": lambda v: ("scrolling:column_width", str(v)),
    "scrolling_fullscreen_on_one_column": lambda v: ("scrolling:fullscreen_on_one_column", "1" if str(v).lower() in ("true", "1") else "0"),
    "column_width": lambda v: ("scrolling:column_width", str(v)),
    "fullscreen_on_one_column": lambda v: ("scrolling:fullscreen_on_one_column", "1" if str(v).lower() in ("true", "1") else "0"),
    "touchpad_natural": lambda v: ("input:touchpad:natural_scroll", "1" if str(v).lower() in ("true", "1") else "0"),
    "touchpad_tap": lambda v: ("input:touchpad:tap-to-click", "1" if str(v).lower() in ("true", "1") else "0"),
    "touchpad_dwt": lambda v: ("input:touchpad:disable_while_typing", "1" if str(v).lower() in ("true", "1") else "0"),
    "sensitivity": lambda v: ("input:sensitivity", str(v)),
    "resize_border": lambda v: ("general:resize_on_border", "1" if str(v).lower() in ("true", "1") else "0"),
    "disable_hyprland_logo": lambda v: ("misc:disable_hyprland_logo", "1" if str(v).lower() in ("true", "1") else "0"),
}

lua_map = LUA_MAP
keyword_map = KEYWORD_MAP

def set_option(opt_name, opt_val):
    # If Lua mapper exists, try eval first
    res = None
    if opt_name in LUA_MAP:
        lua_code = LUA_MAP[opt_name](opt_val)
        try:
            r = subprocess.run(["hyprctl", "eval", lua_code], capture_output=True, text=True, timeout=0.8)
            if r.returncode == 0 and "ok" in r.stdout.lower():
                res = {"ok": True, "method": "eval", "lua": lua_code}
        except Exception:
            pass

    # Fallback to keyword if eval not supported or returned error
    if res is None and opt_name in KEYWORD_MAP:
        k_key, k_val = KEYWORD_MAP[opt_name](opt_val)
        try:
            r = subprocess.run(["hyprctl", "keyword", k_key, str(k_val)], capture_output=True, text=True, timeout=0.8)
            if r.returncode == 0:
                res = {"ok": True, "method": "keyword", "key": k_key, "val": k_val}
            else:
                res = {"ok": False, "error": r.stderr.strip() or r.stdout.strip()}
        except Exception as e:
            res = {"ok": False, "error": str(e)}

    if res is None:
        res = {"ok": False, "error": f"Unknown option {opt_name}"}

    # Automatically persist option to config file
    try:
        save_general_options({opt_name: opt_val})
    except Exception:
        pass

    return res

def update_lua_option(content, opt_name, opt_val):
    val_str = str(opt_val).lower() if isinstance(opt_val, bool) or str(opt_val).lower() in ("true", "false") else str(opt_val)

    scalar_patterns = {
        "gaps_in": r'(gaps_in\s*=\s*)[0-9]+',
        "gaps_out": r'(gaps_out\s*=\s*)[0-9]+',
        "border_size": r'(border_size\s*=\s*)[0-9]+',
        "rounding": r'(rounding\s*=\s*)[0-9]+',
        "active_opacity": r'(active_opacity\s*=\s*)[0-9.]+',
        "inactive_opacity": r'(inactive_opacity\s*=\s*)[0-9.]+',
        "dim_strength": r'(dim_strength\s*=\s*)[0-9.]+',
        "sensitivity": r'(sensitivity\s*=\s*)[-0-9.]+',
        "follow_mouse": r'(follow_mouse\s*=\s*)[0-9]+',
        "dim_inactive": r'(dim_inactive\s*=\s*)(?:true|false)',
        "resize_border": r'(resize_on_border\s*=\s*)(?:true|false)',
        "allow_tearing": r'(allow_tearing\s*=\s*)(?:true|false)',
        "disable_hyprland_logo": r'(disable_hyprland_logo\s*=\s*)(?:true|false)',
        "vfr": r'(vfr\s*=\s*)(?:true|false)',
        "smart_gaps": r'(no_gaps_when_only\s*=\s*)(?:true|false|[0-9]+)',
    }

    if opt_name in scalar_patterns:
        pat = scalar_patterns[opt_name]
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "layout":
        pat = r'(layout\s*=\s*)"[^"]+"'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>"' + str(opt_val) + '"', content, count=1)

    if opt_name in ("scrolling_column_width", "column_width"):
        pat = r'(scrolling\s*=\s*\{[\s\S]*?column_width\s*=\s*)[0-9.]+'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + f"{float(opt_val):.2f}", content, count=1)
        pat2 = r'(hl\.scrolling\s*\(\s*\{[\s\S]*?column_width\s*=\s*)[0-9.]+'
        if re.search(pat2, content):
            return re.sub(pat2, r'\g<1>' + f"{float(opt_val):.2f}", content, count=1)
        pat_tbl = r'(scrolling\s*=\s*\{)'
        if re.search(pat_tbl, content):
            return re.sub(pat_tbl, r'\g<1>\n        column_width = ' + f"{float(opt_val):.2f},", content, count=1)

    if opt_name in ("scrolling_fullscreen_on_one_column", "fullscreen_on_one_column"):
        pat = r'(scrolling\s*=\s*\{[\s\S]*?fullscreen_on_one_column\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)
        pat2 = r'(hl\.scrolling\s*\(\s*\{[\s\S]*?fullscreen_on_one_column\s*=\s*)(?:true|false)'
        if re.search(pat2, content):
            return re.sub(pat2, r'\g<1>' + val_str, content, count=1)
        pat_tbl = r'(scrolling\s*=\s*\{)'
        if re.search(pat_tbl, content):
            return re.sub(pat_tbl, r'\g<1>\n        fullscreen_on_one_column = ' + val_str + ',', content, count=1)

    if opt_name == "anim":
        pat = r'(animations\s*=\s*\{[\s\S]*?enabled\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "blur":
        pat = r'(blur\s*=\s*\{[\s\S]*?enabled\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "blur_size":
        pat = r'(blur\s*=\s*\{[\s\S]*?size\s*=\s*)[0-9]+'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "blur_passes":
        pat = r'(blur\s*=\s*\{[\s\S]*?passes\s*=\s*)[0-9]+'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "shadow":
        pat = r'(shadow\s*=\s*\{[\s\S]*?enabled\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "shadow_range":
        pat = r'(shadow\s*=\s*\{[\s\S]*?range\s*=\s*)[0-9]+'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "shadow_power":
        pat = r'(shadow\s*=\s*\{[\s\S]*?render_power\s*=\s*)[0-9]+'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "touchpad_natural":
        pat = r'(touchpad\s*=\s*\{[\s\S]*?natural_scroll\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "touchpad_tap":
        pat = r'(touchpad\s*=\s*\{[\s\S]*?tap_to_click\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "touchpad_dwt":
        pat = r'(touchpad\s*=\s*\{[\s\S]*?disable_while_typing\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "workspace_swipe":
        pat = r'(workspace_swipe\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name == "workspace_swipe_invert":
        pat = r'(workspace_swipe_invert\s*=\s*)(?:true|false)'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    return content

def update_hyprconf_option(content, opt_name, opt_val):
    val_str = str(opt_val).lower() if isinstance(opt_val, bool) or str(opt_val).lower() in ("true", "false") else str(opt_val)

    scalar_patterns = {
        "layout": r'(?m)^(\s*layout\s*=\s*).*$',
        "gaps_in": r'(?m)^(\s*gaps_in\s*=\s*).*$',
        "gaps_out": r'(?m)^(\s*gaps_out\s*=\s*).*$',
        "border_size": r'(?m)^(\s*border_size\s*=\s*).*$',
        "rounding": r'(?m)^(\s*rounding\s*=\s*).*$',
        "active_opacity": r'(?m)^(\s*active_opacity\s*=\s*).*$',
        "inactive_opacity": r'(?m)^(\s*inactive_opacity\s*=\s*).*$',
        "dim_inactive": r'(?m)^(\s*dim_inactive\s*=\s*).*$',
        "dim_strength": r'(?m)^(\s*dim_strength\s*=\s*).*$',
        "resize_border": r'(?m)^(\s*resize_on_border\s*=\s*).*$',
        "allow_tearing": r'(?m)^(\s*allow_tearing\s*=\s*).*$',
        "follow_mouse": r'(?m)^(\s*follow_mouse\s*=\s*).*$',
        "sensitivity": r'(?m)^(\s*sensitivity\s*=\s*).*$',
        "workspace_swipe": r'(?m)^(\s*workspace_swipe\s*=\s*).*$',
        "workspace_swipe_invert": r'(?m)^(\s*workspace_swipe_invert\s*=\s*).*$',
        "disable_hyprland_logo": r'(?m)^(\s*disable_hyprland_logo\s*=\s*).*$',
        "vfr": r'(?m)^(\s*vfr\s*=\s*).*$',
        "smart_gaps": r'(?m)^(\s*no_gaps_when_only\s*=\s*).*$',
    }

    if opt_name in scalar_patterns:
        pat = scalar_patterns[opt_name]
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    if opt_name in ("scrolling_column_width", "column_width"):
        pat = r'(scrolling\s*\{[\s\S]*?column_width\s*=\s*)[0-9.]+'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + str(opt_val), content, count=1)
        pat_sec = r'(scrolling\s*\{)'
        if re.search(pat_sec, content):
            return re.sub(pat_sec, r'\g<1>\n    column_width = ' + str(opt_val), content, count=1)
        pat_scalar = r'(?m)^(\s*scrolling:column_width\s*=\s*).*$'
        if re.search(pat_scalar, content):
            return re.sub(pat_scalar, r'\g<1>' + str(opt_val), content, count=1)

    if opt_name in ("scrolling_fullscreen_on_one_column", "fullscreen_on_one_column"):
        pat = r'(scrolling\s*\{[\s\S]*?fullscreen_on_one_column\s*=\s*)(?:true|false|[0-1])'
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)
        pat_sec = r'(scrolling\s*\{)'
        if re.search(pat_sec, content):
            return re.sub(pat_sec, r'\g<1>\n    fullscreen_on_one_column = ' + val_str, content, count=1)
        pat_scalar = r'(?m)^(\s*scrolling:fullscreen_on_one_column\s*=\s*).*$'
        if re.search(pat_scalar, content):
            return re.sub(pat_scalar, r'\g<1>' + val_str, content, count=1)

    nested_patterns = {
        "anim": r'(animations\s*\{[\s\S]*?enabled\s*=\s*)(?:true|false|[0-1])',
        "blur": r'(blur\s*\{[\s\S]*?enabled\s*=\s*)(?:true|false|[0-1])',
        "blur_size": r'(blur\s*\{[\s\S]*?size\s*=\s*)[0-9]+',
        "blur_passes": r'(blur\s*\{[\s\S]*?passes\s*=\s*)[0-9]+',
        "shadow": r'(shadow\s*\{[\s\S]*?enabled\s*=\s*)(?:true|false|[0-1])',
        "shadow_range": r'(shadow\s*\{[\s\S]*?range\s*=\s*)[0-9]+',
        "shadow_power": r'(shadow\s*\{[\s\S]*?render_power\s*=\s*)[0-9]+',
        "touchpad_natural": r'(touchpad\s*\{[\s\S]*?natural_scroll\s*=\s*)(?:true|false|[0-1])',
        "touchpad_tap": r'(touchpad\s*\{[\s\S]*?tap-to-click\s*=\s*)(?:true|false|[0-1])',
        "touchpad_dwt": r'(touchpad\s*\{[\s\S]*?disable_while_typing\s*=\s*)(?:true|false|[0-1])',
    }

    if opt_name in nested_patterns:
        pat = nested_patterns[opt_name]
        if re.search(pat, content):
            return re.sub(pat, r'\g<1>' + val_str, content, count=1)

    return content

def save_general_options(changes):
    if not isinstance(changes, dict) or not changes:
        return {"ok": True, "saved": False}

    if is_lua_config():
        lua_path = os.path.join(HOME, ".config/hypr/hyprland.lua")
        if not os.path.exists(lua_path):
            return {"ok": False, "error": "hyprland.lua not found"}
        try:
            with open(lua_path, "r", encoding="utf-8") as f:
                content = f.read()

            modified = content
            for k, v in changes.items():
                modified = update_lua_option(modified, k, v)

            if modified != content:
                tmp_path = f"{lua_path}.tmp.{os.getpid()}"
                with open(tmp_path, "w", encoding="utf-8") as f:
                    f.write(modified)
                os.replace(tmp_path, lua_path)
                return {"ok": True, "file": lua_path}
            return {"ok": True, "no_change": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}
    else:
        conf_path = os.path.join(HOME, ".config/hypr/hyprland.conf")
        if os.path.exists(conf_path):
            try:
                with open(conf_path, "r", encoding="utf-8") as f:
                    content = f.read()
                modified = content
                for k, v in changes.items():
                    modified = update_hyprconf_option(modified, k, v)
                if modified != content:
                    tmp_path = f"{conf_path}.tmp.{os.getpid()}"
                    with open(tmp_path, "w", encoding="utf-8") as f:
                        f.write(modified)
                    os.replace(tmp_path, conf_path)
                    return {"ok": True, "file": conf_path}
                return {"ok": True, "no_change": True}
            except Exception as e:
                return {"ok": False, "error": str(e)}
        return {"ok": True, "saved": False}

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

# ── Keybindings Management ───────────────────────────────────────────────────

def get_primary_config():
    if is_lua_config():
        if os.path.exists(os.path.join(HOME, ".config/hypr/conf/keybinds.lua")):
            return os.path.join(HOME, ".config/hypr/conf/keybinds.lua"), "lua"
        return os.path.join(HOME, ".config/hypr/hyprland.lua"), "lua"
    if os.path.exists(os.path.join(HOME, ".config/hypr/conf/keybinds.conf")):
        return os.path.join(HOME, ".config/hypr/conf/keybinds.conf"), "hyprconf"
    if os.path.exists(os.path.join(HOME, ".config/hypr/hyprland.conf")):
        return os.path.join(HOME, ".config/hypr/hyprland.conf"), "hyprconf"
    if os.path.exists(os.path.join(HOME, ".config/niri/conf/keybinds.kdl")):
        return os.path.join(HOME, ".config/niri/conf/keybinds.kdl"), "niri"
    if os.path.exists(os.path.join(HOME, ".config/niri/config.kdl")):
        return os.path.join(HOME, ".config/niri/config.kdl"), "niri"
    return None, None

def get_keybind_files():
    comp = "hyprland"
    if is_niri():
        comp = "niri"

    files = []
    if comp == "hyprland":
        if is_lua_config():
            candidates = [
                os.path.join(HOME, ".config/hypr/conf/keybinds.lua"),
                os.path.join(HOME, ".config/hypr/conf/quickshell.lua"),
                os.path.join(HOME, ".config/hypr/hyprland.lua"),
            ]
            conf_dir = os.path.join(HOME, ".config/hypr/conf")
            if os.path.isdir(conf_dir):
                for fname in sorted(os.listdir(conf_dir)):
                    if fname.endswith(".lua"):
                        fpath = os.path.join(conf_dir, fname)
                        if fpath not in candidates:
                            candidates.append(fpath)
            for p in candidates:
                if os.path.isfile(p) and (p, "lua") not in files:
                    files.append((p, "lua"))
        else:
            candidates = [
                os.path.join(HOME, ".config/hypr/conf/keybinds.conf"),
                os.path.join(HOME, ".config/hypr/conf/quickshell.conf"),
                os.path.join(HOME, ".config/hypr/hyprland.conf"),
            ]
            conf_dir = os.path.join(HOME, ".config/hypr/conf")
            if os.path.isdir(conf_dir):
                for fname in sorted(os.listdir(conf_dir)):
                    if fname.endswith(".conf") and fname not in ["hypridle.conf", "hyprlock.conf", "hyprpaper.conf"]:
                        fpath = os.path.join(conf_dir, fname)
                        if fpath not in candidates:
                            candidates.append(fpath)
            for p in candidates:
                if os.path.isfile(p) and (p, "hyprconf") not in files:
                    files.append((p, "hyprconf"))
    elif comp == "niri":
        candidates = [
            os.path.join(HOME, ".config/niri/conf/keybinds.kdl"),
            os.path.join(HOME, ".config/niri/conf/quickshell.kdl"),
            os.path.join(HOME, ".config/niri/config.kdl"),
        ]
        conf_dir = os.path.join(HOME, ".config/niri/conf")
        if os.path.isdir(conf_dir):
            for fname in sorted(os.listdir(conf_dir)):
                if fname.endswith(".kdl"):
                    fpath = os.path.join(conf_dir, fname)
                    if fpath not in candidates:
                        candidates.append(fpath)
        for p in candidates:
            if os.path.isfile(p) and (p, "niri") not in files:
                files.append((p, "niri"))

    return files

def parse_lua_binds(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return []

    lines = text.splitlines()
    vars_dict = {}
    var_re = re.compile(r'^\s*local\s+([a-zA-Z0-9_]+)\s*=\s*["\']([^"\']+)["\']')
    for l in lines:
        m = var_re.match(l)
        if m:
            vars_dict[m.group(1)] = m.group(2)

    line_starts = [0]
    for pos, ch in enumerate(text):
        if ch == '\n':
            line_starts.append(pos + 1)

    def get_line(idx):
        return bisect.bisect_right(line_starts, idx)

    binds = []
    n = len(text)
    pattern = re.compile(r'(?:local\s+([a-zA-Z0-9_]+)\s*=\s*)?hl\.bind\s*\(')

    for match in pattern.finditer(text):
        start_char = match.start()
        start_line = get_line(start_char)
        line_str = lines[start_line - 1] if start_line <= len(lines) else ""
        line_before = line_str[:line_str.find("hl.bind")].strip()
        if line_before.startswith("--"):
            continue

        open_paren_idx = match.end() - 1
        depth = 1
        j = open_paren_idx + 1
        in_str = False
        str_char = ''
        inner = ""
        while j < n and depth > 0:
            c = text[j]
            if c in ('"', "'", '`') and not in_str:
                in_str = True
                str_char = c
                inner += c
            elif in_str and c == str_char and text[j-1] != '\\':
                in_str = False
                inner += c
            elif in_str:
                inner += c
            elif c == '(':
                depth += 1
                inner += c
            elif c == ')':
                depth -= 1
                if depth > 0:
                    inner += c
            else:
                inner += c
            j += 1

        end_line = get_line(j)
        raw_snippet = text[start_char:j]

        parts = []
        cur = ""
        depth_p = 0
        depth_b = 0
        in_s = False
        s_char = ''
        for c in inner:
            if c in ('"', "'") and not in_s:
                in_s = True
                s_char = c
                cur += c
            elif in_s and c == s_char:
                in_s = False
                cur += c
            elif in_s:
                cur += c
            elif c == '(':
                depth_p += 1
                cur += c
            elif c == ')':
                depth_p -= 1
                cur += c
            elif c == '{':
                depth_b += 1
                cur += c
            elif c == '}':
                depth_b -= 1
                cur += c
            elif c == ',' and depth_p == 0 and depth_b == 0:
                parts.append(cur.strip())
                cur = ""
            else:
                cur += c
        if cur.strip():
            parts.append(cur.strip())

        if len(parts) >= 2:
            raw_combo = parts[0]
            raw_action = parts[1]
            opts = parts[2] if len(parts) > 2 else ""

            # Check if this line is in a loop for workspaces (e.g. key or i)
            if 'key' in raw_combo and 'workspace' in raw_action:
                for ws in range(1, 11):
                    k_str = str(ws % 10)
                    combo = raw_combo
                    for vn, vv in vars_dict.items():
                        combo = re.sub(r'\b' + vn + r'\b', f'"{vv}"', combo)
                    combo = combo.replace('key', f'"{k_str}"')
                    combo_parts = [p.strip().strip('"\'') for p in combo.split("..")]
                    clean_combo = " + ".join([p.strip().strip('+ ') for p in combo_parts if p.strip()])

                    action = raw_action
                    for vn, vv in vars_dict.items():
                        action = re.sub(r'\b' + vn + r'\b', f'"{vv}"', action)
                    action = action.replace('workspace = i', f'workspace = {ws}')

                    if "hl.dsp.focus" in action:
                        clean_action = f"focus workspace {ws}"
                    elif "hl.dsp.window.move" in action:
                        clean_action = f"move window to workspace {ws}"
                    else:
                        clean_action = action

                    cat = "nav"
                    key_tokens = [k.strip() for k in clean_combo.split("+") if k.strip()]
                    binds.append({
                        "id": f"{os.path.basename(path)}:{start_line}:{ws}",
                        "file": path,
                        "fileName": os.path.basename(path),
                        "startLine": start_line,
                        "endLine": end_line,
                        "keys": clean_combo,
                        "keyTokens": key_tokens,
                        "action": clean_action,
                        "raw": raw_snippet.strip(),
                        "category": cat,
                        "opts": opts.strip()
                    })
                continue

            combo = raw_combo
            for vn, vv in vars_dict.items():
                combo = re.sub(r'\b' + vn + r'\b', f'"{vv}"', combo)
            combo_parts = [p.strip().strip('"\'') for p in combo.split("..")]
            clean_combo = " + ".join([p.strip().strip('+ ') for p in combo_parts if p.strip()])

            action = raw_action
            for vn, vv in vars_dict.items():
                action = re.sub(r'\b' + vn + r'\b', f'"{vv}"', action)

            clean_action = action
            if "hl.dsp.exec_cmd(" in action:
                m_act = re.search(r'hl\.dsp\.exec_cmd\(\s*["\']?(.*?)["\']?\s*\)', action, re.DOTALL)
                if m_act:
                    clean_action = m_act.group(1).strip('"\'').strip()
            elif "hl.dsp.window.close" in action:
                clean_action = "close window"
            elif "hl.dsp.window.float" in action:
                clean_action = "toggle floating"
            elif "hl.dsp.window.fullscreen" in action:
                clean_action = "toggle fullscreen"
            elif "hl.dsp.window.drag" in action:
                clean_action = "drag window (move)"
            elif "hl.dsp.window.resize" in action:
                clean_action = "resize window"
            elif "hl.dsp.layout" in action:
                m_l = re.search(r'hl\.dsp\.layout\(\s*["\']?(.*?)["\']?\s*\)', action)
                clean_action = f"layout {m_l.group(1)}" if m_l else "toggle layout"
            elif "hl.dsp.focus" in action:
                m_f = re.search(r'direction\s*=\s*["\'](.*?)["\']', action)
                m_ws = re.search(r'workspace\s*=\s*["\']?(.*?)["\']?\}', action)
                if m_f:
                    clean_action = f"focus window ({m_f.group(1)})"
                elif m_ws:
                    clean_action = f"focus workspace {m_ws.group(1)}"
                else:
                    clean_action = "focus"
            elif "hl.dsp.window.move" in action:
                m_ws = re.search(r'workspace\s*=\s*["\']?(.*?)["\']?\}', action)
                clean_action = f"move window to workspace {m_ws.group(1)}" if m_ws else "move window"

            cat = "other"
            ca_low = clean_action.lower()
            cb_low = clean_combo.lower()
            if "qs ipc call" in ca_low or "quickshell" in ca_low:
                cat = "quickshell"
            elif any(x in ca_low for x in ["kitty", "alacritty", "foot", "ghostty", "nautilus", "thunar", "dolphin", "browser", "firefox", "chrome", "code"]):
                cat = "apps"
            elif any(x in ca_low for x in ["close", "fullscreen", "floating", "focus", "workspace", "swapcol", "togglesplit", "drag", "resize"]):
                cat = "nav"
            elif "screenshot" in ca_low or "grim" in ca_low or "print" in cb_low:
                cat = "screenshot"
            elif any(x in ca_low for x in ["wpctl", "pactl", "volume", "brightnessctl", "playerctl", "mute", "audio"]):
                cat = "media"

            key_tokens = [k.strip() for k in clean_combo.split("+") if k.strip()]
            binds.append({
                "id": f"{os.path.basename(path)}:{start_line}",
                "file": path,
                "fileName": os.path.basename(path),
                "startLine": start_line,
                "endLine": end_line,
                "keys": clean_combo,
                "keyTokens": key_tokens,
                "action": clean_action,
                "raw": raw_snippet.strip(),
                "category": cat,
                "opts": opts.strip()
            })
    return binds

HYPR_DISPATCHERS = {
    "killactive", "closewindow", "togglefloating", "fullscreen", "fakefullscreen",
    "workspace", "movetoworkspace", "movetoworkspacesilent", "togglesplit", "swapsplit",
    "pseudo", "pin", "movefocus", "movewindow", "movecurrentworkspacetomonitor",
    "focusmonitor", "focuswindow", "splitratio", "toggleopaque", "dpms", "exit",
    "submap", "layoutmsg"
}

def format_hyprconf_bind(keys, action):
    parts = [p.strip() for p in keys.split("+") if p.strip()]
    if not parts:
        return ""
    if len(parts) > 1:
        raw_mods = parts[:-1]
        k = parts[-1]
        mod_tokens = []
        for m in raw_mods:
            mu = m.upper()
            if mu in ("SUPER", "CTRL", "ALT", "SHIFT"):
                mod_tokens.append(mu)
            elif m.startswith("$"):
                mod_tokens.append(m)
            elif mu == "MOD4":
                mod_tokens.append("SUPER")
            elif mu == "MOD1":
                mod_tokens.append("ALT")
            else:
                mod_tokens.append(m)
        mod = " ".join(mod_tokens)
    else:
        mod = ""
        k = parts[0]

    act = action.strip()
    act_low = act.lower()

    if act_low in ("close window", "killactive"):
        return f"bind = {mod}, {k}, killactive,\n"
    elif act_low in ("toggle floating", "togglefloating"):
        return f"bind = {mod}, {k}, togglefloating,\n"
    elif act_low in ("toggle fullscreen", "fullscreen"):
        return f"bind = {mod}, {k}, fullscreen, 0\n"
    elif act_low in ("togglesplit", "layout togglesplit", "toggle split"):
        return f"bind = {mod}, {k}, togglesplit,\n"
    elif act_low.startswith("focus workspace ") or (act_low.startswith("workspace ") and not act_low.startswith("workspace =")):
        ws_num = act.split()[-1]
        return f"bind = {mod}, {k}, workspace, {ws_num}\n"
    elif act_low.startswith("move window to workspace ") or act_low.startswith("movetoworkspace "):
        ws_num = act.split()[-1]
        return f"bind = {mod}, {k}, movetoworkspace, {ws_num}\n"
    elif act_low.startswith("move window (silent) to workspace ") or act_low.startswith("movetoworkspacesilent "):
        ws_num = act.split()[-1]
        return f"bind = {mod}, {k}, movetoworkspacesilent, {ws_num}\n"

    first_word = act.split()[0] if act.split() else ""
    if first_word.lower() in HYPR_DISPATCHERS:
        arg_part = act[len(first_word):].strip().lstrip(",").strip()
        if arg_part:
            return f"bind = {mod}, {k}, {first_word}, {arg_part}\n"
        return f"bind = {mod}, {k}, {first_word},\n"

    if act.startswith("exec, ") or act.startswith("exec "):
        cmd = act[5:].strip()
        return f"bind = {mod}, {k}, exec, {cmd}\n"

    return f"bind = {mod}, {k}, exec, {act}\n"

def format_lua_bind(keys, action):
    act = action.strip()
    act_low = act.lower()

    if act_low in ("close window", "killactive"):
        return f'hl.bind("{keys}", hl.dsp.window.close(), {{ repeating = true }})\n'
    elif act_low in ("toggle floating", "togglefloating"):
        return f'hl.bind("{keys}", hl.dsp.window.float())\n'
    elif act_low in ("toggle fullscreen", "fullscreen"):
        return f'hl.bind("{keys}", hl.dsp.window.fullscreen())\n'
    elif act_low in ("togglesplit", "layout togglesplit", "toggle split"):
        return f'hl.bind("{keys}", hl.dsp.layout("togglesplit"))\n'
    elif act_low.startswith("focus workspace ") or (act_low.startswith("workspace ") and not act_low.startswith("workspace =")):
        ws_num = act.split()[-1]
        return f'hl.bind("{keys}", hl.dsp.focus({{ workspace = {ws_num} }}))\n'
    elif act_low.startswith("move window to workspace ") or act_low.startswith("movetoworkspace "):
        ws_num = act.split()[-1]
        return f'hl.bind("{keys}", hl.dsp.window.move({{ workspace = {ws_num} }}))\n'
    elif act.startswith("hl.dsp."):
        return f'hl.bind("{keys}", {act})\n'
    else:
        escaped_action = act.replace('\\', '\\\\').replace('"', '\\"')
        return f'hl.bind("{keys}", hl.dsp.exec_cmd("{escaped_action}"))\n'

def format_niri_bind(keys, action):
    clean_combo = keys.replace(" ", "")
    act = action.strip()
    act_low = act.lower()

    if act_low in ("close window", "killactive", "close-window"):
        return f'    {clean_combo} {{ close-window; }}\n'
    elif act_low in ("toggle floating", "togglefloating", "toggle-window-floating"):
        return f'    {clean_combo} {{ toggle-window-floating; }}\n'
    elif act_low in ("toggle fullscreen", "fullscreen", "fullscreen-window"):
        return f'    {clean_combo} {{ fullscreen-window; }}\n'
    elif act_low.startswith("focus-workspace ") or act_low.startswith("focus workspace "):
        ws_num = act.split()[-1]
        return f'    {clean_combo} {{ focus-workspace {ws_num}; }}\n'
    elif act_low.startswith("move-window-to-workspace ") or act_low.startswith("move window to workspace "):
        ws_num = act.split()[-1]
        return f'    {clean_combo} {{ move-window-to-workspace {ws_num}; }}\n'
    elif act.startswith("niri:") or "(" in act or "-" in act or act.endswith(";"):
        clean_act = act.rstrip(";")
        return f'    {clean_combo} {{ {clean_act}; }}\n'
    else:
        parts = act.split()
        quoted_parts = " ".join(f'"{p}"' for p in parts)
        return f'    {clean_combo} {{ spawn {quoted_parts}; }}\n'

def parse_hyprconf_binds(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return []

    binds = []
    bind_re = re.compile(r'^\s*bind[a-zA-Z]*\s*=\s*([^,]*),\s*([^,]+),\s*([^,]+)(?:,\s*(.*))?')
    for idx, line in enumerate(lines):
        line_str = line.strip()
        if not line_str or line_str.startswith("#"):
            continue
        m = bind_re.match(line_str)
        if m:
            mod = m.group(1).strip()
            key = m.group(2).strip()
            disp = m.group(3).strip()
            arg = m.group(4).strip() if m.group(4) else ""

            combo = f"{mod} + {key}" if mod else key
            action = f"{disp} {arg}".strip() if arg else disp
            if disp == "exec":
                action = arg

            cat = "other"
            ca_low = action.lower()
            cb_low = combo.lower()
            if "qs ipc call" in ca_low or "quickshell" in ca_low:
                cat = "quickshell"
            elif any(x in ca_low for x in ["kitty", "alacritty", "foot", "ghostty", "nautilus", "thunar", "dolphin", "browser", "firefox"]):
                cat = "apps"
            elif any(x in ca_low for x in ["killactive", "fullscreen", "togglefloating", "workspace", "movetoworkspace", "splitratio", "movefocus", "movewindow"]):
                cat = "nav"
            elif "screenshot" in ca_low or "grim" in ca_low or "print" in cb_low:
                cat = "screenshot"
            elif any(x in ca_low for x in ["wpctl", "pactl", "volume", "brightnessctl", "playerctl"]):
                cat = "media"

            key_tokens = [k.strip() for k in combo.split("+") if k.strip()]
            binds.append({
                "id": f"{os.path.basename(path)}:{idx + 1}",
                "file": path,
                "fileName": os.path.basename(path),
                "startLine": idx + 1,
                "endLine": idx + 1,
                "keys": combo,
                "keyTokens": key_tokens,
                "action": action,
                "raw": line_str,
                "category": cat,
                "opts": ""
            })
    return binds

def parse_niri_binds(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception:
        return []

    binds = []
    niri_bind_re = re.compile(r'^\s*([A-Za-z0-9_\+\-]+)(?:\s+[^\{]+)?\s*\{\s*([^;\}]+);?\s*\}')
    in_binds_block = False
    for idx, line in enumerate(lines):
        line_str = line.strip()
        if not line_str or line_str.startswith("//"):
            continue
        if "binds {" in line_str:
            in_binds_block = True
            continue
        if in_binds_block and line_str == "}":
            in_binds_block = False
            continue
        if in_binds_block or niri_bind_re.match(line_str):
            m = niri_bind_re.match(line_str)
            if m:
                combo = m.group(1).replace("-", "+").replace("+", " + ")
                action = m.group(2).strip()
                if action.startswith('spawn "') and action.endswith('"'):
                    parts = re.findall(r'"([^"]*)"', action)
                    action = " ".join(parts) if parts else action

                cat = "other"
                ca_low = action.lower()
                cb_low = combo.lower()
                if "qs ipc call" in ca_low or "quickshell" in ca_low:
                    cat = "quickshell"
                elif any(x in ca_low for x in ["kitty", "alacritty", "foot", "ghostty", "nautilus", "thunar", "dolphin", "browser", "firefox"]):
                    cat = "apps"
                elif any(x in ca_low for x in ["close-window", "fullscreen", "focus-", "move-", "column", "workspace"]):
                    cat = "nav"
                elif "screenshot" in ca_low or "grim" in ca_low or "print" in cb_low:
                    cat = "screenshot"
                elif any(x in ca_low for x in ["wpctl", "pactl", "volume", "brightnessctl", "playerctl"]):
                    cat = "media"

                key_tokens = [k.strip() for k in combo.split("+") if k.strip()]
                binds.append({
                    "id": f"{os.path.basename(path)}:{idx + 1}",
                    "file": path,
                    "fileName": os.path.basename(path),
                    "startLine": idx + 1,
                    "endLine": idx + 1,
                    "keys": combo,
                    "keyTokens": key_tokens,
                    "action": action,
                    "raw": line_str,
                    "category": cat,
                    "opts": ""
                })
    return binds

def list_keybinds():
    files = get_keybind_files()
    if not files:
        primary_path, primary_type = get_primary_config()
        if primary_path and os.path.exists(primary_path):
            files = [(primary_path, primary_type)]

    all_binds = []
    seen = set()
    for fpath, ftype in files:
        file_binds = []
        if ftype == "lua":
            file_binds = parse_lua_binds(fpath)
        elif ftype == "hyprconf":
            file_binds = parse_hyprconf_binds(fpath)
        elif ftype == "niri":
            file_binds = parse_niri_binds(fpath)

        for b in file_binds:
            dedup_key = (b["keys"], b["action"])
            if dedup_key not in seen:
                seen.add(dedup_key)
                all_binds.append(b)

    primary_path, primary_type = get_primary_config()
    return {
        "ok": True,
        "binds": all_binds,
        "configPath": primary_path or (files[0][0] if files else ""),
        "configType": primary_type or (files[0][1] if files else "lua"),
        "total": len(all_binds)
    }

def add_keybind(keys, action, desc="", target_file=None):
    if target_file and os.path.exists(target_file):
        cfg_path = target_file
        cfg_type = "lua" if target_file.endswith(".lua") else ("niri" if target_file.endswith(".kdl") else "hyprconf")
    else:
        cfg_path, cfg_type = get_primary_config()

    if not cfg_path or not os.path.exists(cfg_path):
        return {"ok": False, "error": "No compositor config found"}

    keys = keys.strip()
    action = action.strip()
    if not keys or not action:
        return {"ok": False, "error": "Keys and action cannot be empty"}

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        return {"ok": False, "error": str(e)}

    if cfg_type == "lua":
        new_line = format_lua_bind(keys, action)
        insert_idx = len(lines)
        for i, l in enumerate(lines):
            if "WINDOW / LAYER RULES" in l or "WINDOW RULES" in l or "LAYER RULES" in l:
                insert_idx = max(0, i - 1)
                break
        lines.insert(insert_idx, new_line)

    elif cfg_type == "hyprconf":
        new_line = format_hyprconf_bind(keys, action)
        lines.append(new_line)

    elif cfg_type == "niri":
        new_line = format_niri_bind(keys, action)
        insert_idx = len(lines)
        for i, l in enumerate(lines):
            if "binds {" in l:
                insert_idx = i + 1
                break
        lines.insert(insert_idx, new_line)

    content = "".join(lines)
    res = _write_and_validate(cfg_path, content)
    if res.get("ok"):
        reload_compositor()
    return res

def update_keybind(line_num, keys, action, desc="", target_file=None):
    if target_file and os.path.exists(target_file):
        cfg_path = target_file
        cfg_type = "lua" if target_file.endswith(".lua") else ("niri" if target_file.endswith(".kdl") else "hyprconf")
    else:
        cfg_path, cfg_type = get_primary_config()

    if not cfg_path or not os.path.exists(cfg_path):
        return {"ok": False, "error": "No compositor config found"}

    try:
        line_idx = int(line_num) - 1
    except Exception:
        return {"ok": False, "error": "Invalid line number"}

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        return {"ok": False, "error": str(e)}

    if line_idx < 0 or line_idx >= len(lines):
        return {"ok": False, "error": f"Line {line_num} out of range"}

    keys = keys.strip()
    action = action.strip()

    if cfg_type == "lua":
        lines[line_idx] = format_lua_bind(keys, action)
    elif cfg_type == "hyprconf":
        lines[line_idx] = format_hyprconf_bind(keys, action)
    elif cfg_type == "niri":
        lines[line_idx] = format_niri_bind(keys, action)

    content = "".join(lines)
    res = _write_and_validate(cfg_path, content)
    if res.get("ok"):
        reload_compositor()
    return res

def delete_keybind(line_num, target_file=None):
    if target_file and os.path.exists(target_file):
        cfg_path = target_file
    else:
        cfg_path, cfg_type = get_primary_config()

    if not cfg_path or not os.path.exists(cfg_path):
        return {"ok": False, "error": "No compositor config found"}

    try:
        line_idx = int(line_num) - 1
    except Exception:
        return {"ok": False, "error": "Invalid line number"}

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        return {"ok": False, "error": str(e)}

    if line_idx < 0 or line_idx >= len(lines):
        return {"ok": False, "error": f"Line {line_num} out of range"}

    del lines[line_idx]

    content = "".join(lines)
    res = _write_and_validate(cfg_path, content)
    if res.get("ok"):
        reload_compositor()
    return res

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

def deduplicate_lines(lines):
    seen = set()
    result = []
    PROTECTED_TOKENS = {
        "end", "end)", "end);", "end,", "}", "})", "});", "},", ")", ");", "),", "]", "];",
        "then", "do", "else", "elseif"
    }
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if result and result[-1].strip():
                result.append(line)
            continue
        if stripped in PROTECTED_TOKENS or stripped.startswith("--") or stripped.startswith("//") or stripped.startswith("#"):
            result.append(line)
            continue
        if stripped in seen:
            continue
        seen.add(stripped)
        result.append(line)
    return result

def strip_header_banner(content: str) -> str:
    lines = content.splitlines()
    start_idx = 0
    while start_idx < len(lines):
        s = lines[start_idx].strip()
        if not s:
            start_idx += 1
            continue
        if (s.startswith("# ═══") or s.startswith("// ═══") or s.startswith("-- ═══") or
            s.startswith("# ───") or s.startswith("-- ───") or s.startswith("// ───") or
            s.startswith("----") or s.startswith("---") or
            s.startswith("#  Autostart") or s.startswith("--  Autostart") or s.startswith("//  Autostart") or
            s.startswith("#  Keybindings") or s.startswith("--  Keybindings") or s.startswith("//  Keybindings") or
            s.startswith("#  Window") or s.startswith("--  Window") or s.startswith("//  Window") or
            s.startswith("#  Quickshell") or s.startswith("--  Quickshell") or s.startswith("//  Quickshell") or
            s.startswith("#  KEYBINDINGS") or s.startswith("--  KEYBINDINGS") or "KEYBINDING" in s or
            s.startswith("#  AUTOSTART") or s.startswith("--  AUTOSTART") or "AUTOSTART" in s or
            s.startswith("#  WINDOW RULES") or s.startswith("--  WINDOW RULES") or "WINDOWS AND WORKSPACES" in s or
            s.startswith("#  RULES") or s.startswith("--  RULES")):
            start_idx += 1
            continue
        break
    return "\n".join(lines[start_idx:]).strip()

def modularize_hypr_lua():
    hypr_dir = os.path.join(HOME, ".config/hypr")
    conf_dir = os.path.join(hypr_dir, "conf")
    lua_path = os.path.join(hypr_dir, "hyprland.lua")
    os.makedirs(conf_dir, exist_ok=True)

    # 1. Quickshell Integration File (~/.config/hypr/conf/quickshell.lua)
    qs_lua_path = os.path.join(conf_dir, "quickshell.lua")
    qs_lua_content = """-- ══════════════════════════════════════════════════════════════════════════════
--  Quickshell Desktop Environment Integration (~/.config/hypr/conf/quickshell.lua)
-- ══════════════════════════════════════════════════════════════════════════════

local mainMod = "SUPER"

-- ── 1. Autostart Quickshell Desktop Environment ──────────────────────────────
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs")
end)

-- ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
hl.bind(mainMod .. " + SPACE",         hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + SHIFT + W",     hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))
hl.bind(mainMod .. " + SHIFT + E",     hl.dsp.exec_cmd("qs ipc call emoji toggle"))
hl.bind(mainMod .. " + V",             hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P",             hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + ALT + L",       hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))
hl.bind(mainMod .. " + D",             hl.dsp.exec_cmd("qs ipc call dashboard toggle"))
hl.bind(mainMod .. " + N",             hl.dsp.exec_cmd("qs ipc call notifCenter toggle"))
hl.bind(mainMod .. " + C",             hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))
hl.bind(mainMod .. " + B",             hl.dsp.exec_cmd("qs ipc call battery toggle"))

-- ── 3. Quickshell Layer Rules (Blur & Transparency) ───────────────────────────
hl.layer_rule({ match = { namespace = "quickshell:bar" },               blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:wallpaperselector" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:emojipicker" },       blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },       blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },               blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:traymenu" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:trayoverflow" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:settings" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:battery" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:volume" },            blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:welcome" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:powermenu" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },              blur = true, ignore_alpha = 0 })
"""
    with open(qs_lua_path, "w", encoding="utf-8") as f:
        f.write(qs_lua_content)

    autostart_path = os.path.join(conf_dir, "autostart.lua")
    keybinds_path = os.path.join(conf_dir, "keybinds.lua")
    rules_path = os.path.join(conf_dir, "rules.lua")

    if not os.path.exists(lua_path):
        with open(lua_path, "w", encoding="utf-8") as f:
            f.write("""-- ══════════════════════════════════════════════════════════════════════════════
--  Hyprland Lua Modular Configuration (~/.config/hypr/hyprland.lua)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Monitors ──────────────────────────────────────────────────────────────
hl.monitor({ name = "", modeline = "preferred,auto,1" })

-- ── 2. Environment Variables ─────────────────────────────────────────────────
hl.env({
    XCURSOR_SIZE        = 24,
    HYPRCURSOR_SIZE     = 24,
    XDG_CURRENT_DESKTOP = "Hyprland",
    XDG_SESSION_TYPE    = "wayland",
    XDG_SESSION_DESKTOP = "Hyprland",
    QT_QPA_PLATFORM     = "wayland;xcb",
    GDK_BACKEND         = "wayland,x11,*",
})

-- ── 3. Look and Feel ─────────────────────────────────────────────────────────
hl.general({
    gaps_in             = 5,
    gaps_out            = 10,
    border_size         = 2,
    "col.active_border"   = "rgba(89b4faee) rgba(cba6f7ee) 45deg",
    "col.inactive_border" = "rgba(313244aa)",
    resize_on_border    = true,
    allow_tearing       = false,
    layout              = "dwindle",
})

hl.decoration({
    rounding            = 10,
    active_opacity      = 1.0,
    inactive_opacity    = 0.95,
    shadow = {
        enabled = true,
        range   = 15,
        render_power = 3,
        color   = "rgba(181825ee)",
    },
    blur = {
        enabled = true,
        size    = 6,
        passes  = 3,
        new_optimizations = true,
        xray    = false,
    },
})

-- ── 4. Animations ────────────────────────────────────────────────────────────
hl.animation({ leaf = "windows",   enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "layers",    enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade",      enabled = true, speed = 3 })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })

-- ── 5. Layouts & Input ───────────────────────────────────────────────────────
hl.dwindle({
    pseudotile     = true,
    preserve_split = true,
})

hl.config({
    scrolling = {
        column_width             = 0.89,
        fullscreen_on_one_column = false,
    },
})

hl.input({
    kb_layout     = "us",
    follow_mouse  = 1,
    sensitivity   = 0,
    touchpad = {
        natural_scroll = true,
    },
})

-- ── 6. Load Modular Configuration Files ──────────────────────────────────────
local home = os.getenv("HOME") or ""
local confDir = home .. "/.config/hypr/conf"

local function load_conf(module_name)
    local module_path = confDir .. "/" .. module_name .. ".lua"
    local f = io.open(module_path, "r")
    if f then
        f:close()
        dofile(module_path)
    end
end

-- Load separated modules
load_conf("autostart")
load_conf("keybinds")
load_conf("rules")
load_conf("quickshell")
""")
        if not os.path.exists(autostart_path):
            with open(autostart_path, "w", encoding="utf-8") as f:
                f.write("""-- ══════════════════════════════════════════════════════════════════════════════
--  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.lua)
-- ══════════════════════════════════════════════════════════════════════════════

hl.on("hyprland.start", function ()
    hl.exec_cmd("systemctl enable --now --user hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
""")
        if not os.path.exists(keybinds_path):
            with open(keybinds_path, "w", encoding="utf-8") as f:
                f.write("""-- ══════════════════════════════════════════════════════════════════════════════
--  Keybindings & Shortcuts (~/.config/hypr/conf/keybinds.lua)
-- ══════════════════════════════════════════════════════════════════════════════

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "nautilus"
local menu = "wofi --show drun"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal), { repeating = true })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { repeating = true })
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind("print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh full"), { locked = true })
hl.bind("SHIFT + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh region"), { locked = true })
hl.bind(mainMod .. " + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh window"), { locked = true })
""")
        if not os.path.exists(rules_path):
            with open(rules_path, "w", encoding="utf-8") as f:
                f.write("""-- ══════════════════════════════════════════════════════════════════════════════
--  Window & Workspace Rules (~/.config/hypr/conf/rules.lua)
-- ══════════════════════════════════════════════════════════════════════════════

hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "pip-float",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float = true,
    pin   = true,
})

hl.window_rule({
    name  = "dialog-float",
    match = { class = "(pavucontrol|nm-connection-editor|blueman-manager|swappy)" },
    float = true,
})
""")
        return {"ok": True, "created_main": True, "conf_dir": conf_dir}

    backup_path = f"{lua_path}.bak.{int(time.time())}"
    shutil.copy2(lua_path, backup_path)

    with open(lua_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    autostart_lines = []
    keybind_lines = []
    rule_lines = []
    main_lines = []

    current_section = 'main'
    section_keywords = {
        'autostart': ['AUTOSTART', 'STARTUP', 'DAEMONS'],
        'keybinds': ['KEYBINDINGS', 'KEYBINDINGSS', 'KEYBINDS', 'BINDS', 'SHORTCUTS'],
        'rules': ['WINDOW / LAYER RULES', 'WINDOW RULES', 'LAYER RULES', 'WINDOWS AND WORKSPACES', 'WORKSPACE RULES', 'WINDOW & WORKSPACE RULES', 'RULES'],
        'programs': ['MY PROGRAMS', 'PROGRAMS', 'PROGRAMS / VARIABLES', 'VARIABLES', 'USER PROGRAMS', 'APPS'],
        'main': ['MONITORS', 'ENVIRONMENT VARIABLES', 'PERMISSIONS', 'LOOK AND FEEL', 'ANIMATIONS', 'WORKSPACE RULES', 'LAYOUTS', 'MISC', 'INPUT', 'GESTURES', 'DEVICES']
    }

    var_re = re.compile(r'^\s*local\s+([A-Za-z0-9_]+)\s*=\s*(?:([\"\'\`])(.*?)\2|([0-9]+|true|false))\s*(?:--.*)?$')
    var_defs = {}
    qs_vars = set()

    for line in lines:
        m = var_re.match(line)
        if m:
            vname = m.group(1).strip()
            raw_val = (m.group(3) if m.group(3) is not None else m.group(4)).strip()
            if 'qs ' in raw_val or 'qs"' in raw_val or "qs'" in raw_val or 'quickshell' in raw_val:
                qs_vars.add(vname)
            else:
                var_defs[vname] = line.strip()

    # Provide safe fallback definitions if not found
    if 'mainMod' not in var_defs:
        var_defs['mainMod'] = 'local mainMod = "SUPER"'
    if 'terminal' not in var_defs and 'myTerminal' not in var_defs and 'term' not in var_defs:
        var_defs['terminal'] = 'local terminal = "kitty"'
    if 'fileManager' not in var_defs and 'file_manager' not in var_defs and 'filemanager' not in var_defs:
        var_defs['fileManager'] = 'local fileManager = "nautilus"'
    if 'menu' not in var_defs and 'launcher' not in var_defs and 'appLauncher' not in var_defs:
        var_defs['menu'] = 'local menu = "wofi --show drun"'
    if 'browser' not in var_defs:
        var_defs['browser'] = 'local browser = "xdg-open https://"'
    if 'editor' not in var_defs:
        var_defs['editor'] = 'local editor = "nano"'

    # Build prioritized var definitions string
    priority_order = ['mainMod', 'terminal', 'myTerminal', 'term', 'fileManager', 'file_manager', 'filemanager', 'menu', 'launcher', 'browser', 'editor']
    vars_prefix_lines = []
    for k in priority_order:
        if k in var_defs and var_defs[k] not in vars_prefix_lines:
            vars_prefix_lines.append(var_defs[k])
    for k, v in var_defs.items():
        if v not in vars_prefix_lines:
            vars_prefix_lines.append(v)
    vars_prefix = "\n".join(vars_prefix_lines)

    in_loader_block = False
    current_section = 'main'
    active_target = 'main'
    paren_depth = 0
    brace_depth = 0
    in_for_loop = False

    for line in lines:
        stripped = line.strip()

        if "Load Modular Configuration Files" in stripped or "── Modular Configuration" in stripped:
            in_loader_block = True
            continue

        if in_loader_block:
            if (stripped.startswith("load_conf(") or 
                stripped in ["end", "end)", "end);", "end}"] or 
                "local home" in stripped or 
                "local confDir" in stripped or 
                "local function load_conf" in stripped or 
                "dofile(" in stripped or 
                "io.open(" in stripped or 
                "Load separated modules" in stripped or 
                not stripped):
                continue
            else:
                in_loader_block = False

        if any(marker in stripped for marker in [
            'Load Modular Configuration Files',
            'Quickshell Desktop Environment Integration',
            'Quickshell Integration',
            'load_conf',
            'confDir',
            'module_name',
            'module_path',
            'Load separated modules',
        ]):
            continue
        if ('dofile(' in stripped and ('quickshell' in stripped or 'conf/' in stripped or 'module_path' in stripped)):
            continue
        if 'local home = os.getenv("HOME")' in stripped or 'io.open(module_path' in stripped or 'local function load_conf' in stripped:
            continue

        if 'qs ipc call' in stripped or 'quickshell:' in stripped:
            continue

        # If not inside a multiline statement or loop, update section and statement target
        if paren_depth == 0 and brace_depth == 0 and not in_for_loop:
            for sec, kws in section_keywords.items():
                if any(re.search(rf'--\s*{re.escape(kw)}\b', stripped, re.IGNORECASE) for kw in kws):
                    current_section = sec
                    break

            if current_section == 'keybinds':
                active_target = 'keybinds'
            elif current_section == 'autostart':
                if stripped.startswith(('hl.env', 'hl.config', 'hl.general', 'hl.decoration', 'hl.animation', 'hl.curve', 'hl.monitor', 'hl.dwindle', 'hl.master', 'hl.input', 'hl.gesture', 'hl.device', 'local ')):
                    active_target = 'main'
                    current_section = 'main'
                else:
                    active_target = 'autostart'
            elif current_section == 'rules':
                if stripped.startswith(('hl.env', 'hl.config', 'hl.general', 'hl.decoration', 'hl.animation', 'hl.curve', 'hl.monitor', 'hl.dwindle', 'hl.master', 'hl.input', 'hl.gesture', 'hl.device')):
                    active_target = 'main'
                    current_section = 'main'
                else:
                    active_target = 'rules'
            else:
                if (stripped.startswith('hl.on(') or stripped.startswith('hl.on (')) and ('hyprland.start' in stripped or 'start' in stripped):
                    active_target = 'autostart'
                elif 'hl.bind(' in stripped or 'hl.bind (' in stripped:
                    active_target = 'keybinds'
                elif 'hl.window_rule(' in stripped or 'hl.layer_rule(' in stripped:
                    active_target = 'rules'
                else:
                    active_target = 'main'

        # Track bracket & string depths across multiline blocks
        in_str = False
        str_ch = ''
        for idx, ch in enumerate(stripped):
            if ch in ('"', "'") and not in_str:
                in_str = True
                str_ch = ch
            elif in_str and ch == str_ch and (idx == 0 or stripped[idx-1] != '\\'):
                in_str = False
            elif not in_str:
                if ch == '-' and idx + 1 < len(stripped) and stripped[idx+1] == '-':
                    break
                elif ch == '(':
                    paren_depth += 1
                elif ch == ')':
                    paren_depth = max(0, paren_depth - 1)
                elif ch == '{':
                    brace_depth += 1
                elif ch == '}':
                    brace_depth = max(0, brace_depth - 1)

        if stripped.startswith('for ') and ' do' in stripped:
            in_for_loop = True
        elif in_for_loop and stripped == 'end':
            in_for_loop = False

        if active_target == 'autostart':
            autostart_lines.append(line)
        elif active_target == 'keybinds':
            keybind_lines.append(line)
        elif active_target == 'rules':
            rule_lines.append(line)
        else:
            main_lines.append(line)

    # Write conf/autostart.lua
    existing_autostart = ""
    if os.path.exists(autostart_path):
        with open(autostart_path, "r", encoding="utf-8") as f:
            existing_autostart = f.read()

    autostart_vars = []
    for v in ["terminal", "myTerminal", "term", "fileManager", "browser"]:
        if v in var_defs and any(re.search(rf'\b{re.escape(v)}\b', l) for l in autostart_lines):
            autostart_vars.append(var_defs[v])

    if autostart_lines:
        raw_as = strip_header_banner("".join(autostart_lines)).strip()
        if autostart_vars and not any(f"local {v}" in raw_as for v in ["terminal", "myTerminal", "term"]):
            autostart_content = "\n".join(autostart_vars) + "\n\n" + raw_as
        else:
            autostart_content = raw_as
    elif existing_autostart.strip():
        autostart_content = strip_header_banner(existing_autostart).strip()
    else:
        autostart_content = """hl.on("hyprland.start", function ()
    hl.exec_cmd("systemctl enable --now --user hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)"""

    with open(autostart_path, "w", encoding="utf-8") as f:
        f.write(f"""-- ══════════════════════════════════════════════════════════════════════════════
--  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.lua)
-- ══════════════════════════════════════════════════════════════════════════════

{autostart_content}
""")

    # Write conf/keybinds.lua
    # Clean duplicate local literal variable declarations from keybind lines if already in vars_prefix
    clean_keybind_lines = []
    for line in keybind_lines:
        m = var_re.match(line)
        if m and m.group(1).strip() in var_defs:
            continue
        clean_keybind_lines.append(line)

    if clean_keybind_lines:
        keybind_body = strip_header_banner("".join(clean_keybind_lines)).strip()
        keybind_content = f"{vars_prefix}\n\n{keybind_body}"
    elif os.path.exists(keybinds_path):
        with open(keybinds_path, "r", encoding="utf-8") as f:
            existing_kb = strip_header_banner(f.read()).strip()
        if not any(f"local {k}" in existing_kb for k in ['terminal', 'fileManager']):
            keybind_content = f"{vars_prefix}\n\n{existing_kb}"
        else:
            keybind_content = existing_kb
    else:
        keybind_content = vars_prefix + """

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal), { repeating = true })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { repeating = true })
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind("print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh full"), { locked = true })
hl.bind("SHIFT + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh region"), { locked = true })
hl.bind(mainMod .. " + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh window"), { locked = true })"""

    with open(keybinds_path, "w", encoding="utf-8") as f:
        f.write(f"""-- ══════════════════════════════════════════════════════════════════════════════
--  Keybindings & Shortcuts (~/.config/hypr/conf/keybinds.lua)
-- ══════════════════════════════════════════════════════════════════════════════

{keybind_content}
""")

    # Write conf/rules.lua
    if rule_lines:
        rules_content = strip_header_banner("".join(rule_lines))
    elif os.path.exists(rules_path):
        with open(rules_path, "r", encoding="utf-8") as f:
            rules_content = strip_header_banner(f.read())
    else:
        rules_content = """hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "pip-float",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float = true,
    pin   = true,
})

hl.window_rule({
    name  = "dialog-float",
    match = { class = "(pavucontrol|nm-connection-editor|blueman-manager|swappy)" },
    float = true,
})"""

    with open(rules_path, "w", encoding="utf-8") as f:
        f.write(f"""-- ══════════════════════════════════════════════════════════════════════════════
--  Window & Workspace Rules (~/.config/hypr/conf/rules.lua)
-- ══════════════════════════════════════════════════════════════════════════════

{rules_content}
""")

    # Clean up main hyprland.lua
    while main_lines and (not main_lines[-1].strip() or main_lines[-1].strip() in ['end', 'end)', 'end);', 'end}']):
        main_lines.pop()

    cleaned_main = "".join(main_lines).strip()
    final_main = f"""{cleaned_main}

-- ── Load Modular Configuration Files ────────────────────────────────────────
local home = os.getenv("HOME") or ""
local confDir = home .. "/.config/hypr/conf"

local function load_conf(module_name)
    local module_path = confDir .. "/" .. module_name .. ".lua"
    local f = io.open(module_path, "r")
    if f then
        f:close()
        dofile(module_path)
    end
end

-- Load separated modules
load_conf("autostart")
load_conf("keybinds")
load_conf("rules")
load_conf("quickshell")
"""
    with open(lua_path, "w", encoding="utf-8") as f:
        f.write(final_main)

    return {
        "ok": True,
        "backup": backup_path,
        "conf_dir": conf_dir,
        "extracted_autostart": len(autostart_lines),
        "extracted_keybinds": len(keybind_lines),
        "extracted_rules": len(rule_lines)
    }

def modularize_hypr_conf():
    hypr_dir = os.path.join(HOME, ".config/hypr")
    conf_dir = os.path.join(hypr_dir, "conf")
    conf_path = os.path.join(hypr_dir, "hyprland.conf")
    os.makedirs(conf_dir, exist_ok=True)

    # 1. Quickshell conf (~/.config/hypr/conf/quickshell.conf)
    qs_conf_path = os.path.join(conf_dir, "quickshell.conf")
    qs_conf_content = """# ══════════════════════════════════════════════════════════════════════════════
#  Quickshell Desktop Environment Integration (~/.config/hypr/conf/quickshell.conf)
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Autostart Quickshell Desktop Environment ──────────────────────────────
exec-once = qs

# ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
bind = SUPER, SPACE,         exec, qs ipc call launcher toggle
bind = SUPER SHIFT, W,       exec, qs ipc call wallpaper toggle
bind = SUPER SHIFT, E,       exec, qs ipc call emoji toggle
bind = SUPER, V,             exec, qs ipc call clipboard toggle
bind = SUPER, P,             exec, qs ipc call powermenu toggle
bind = SUPER ALT, L,         exec, qs ipc call lockscreen toggle
bind = SUPER, D,             exec, qs ipc call dashboard toggle
bind = SUPER, N,             exec, qs ipc call notifCenter toggle
bind = SUPER, C,             exec, qs ipc call controlCenter toggle
bind = SUPER, B,             exec, qs ipc call battery toggle

# ── 3. Quickshell Layer Rules (Blur & Transparency) ───────────────────────────
layerrule = blur, quickshell:bar
layerrule = blur, quickshell:launcher
layerrule = ignorezero, quickshell:launcher
layerrule = blur, quickshell:wallpaperselector
layerrule = ignorezero, quickshell:wallpaperselector
layerrule = blur, quickshell:emojipicker
layerrule = ignorezero, quickshell:emojipicker
layerrule = blur, quickshell:clipboard
layerrule = ignorezero, quickshell:clipboard
layerrule = blur, quickshell:controlcenter
layerrule = ignorezero, quickshell:controlcenter
layerrule = blur, quickshell:notifcenter
layerrule = ignorezero, quickshell:notifcenter
layerrule = blur, quickshell:dashboard
layerrule = ignorezero, quickshell:dashboard
layerrule = blur, quickshell:calendar
layerrule = ignorezero, quickshell:calendar
layerrule = blur, quickshell:hud
layerrule = ignorezero, quickshell:hud
layerrule = blur, quickshell:traymenu
layerrule = ignorezero, quickshell:traymenu
layerrule = blur, quickshell:trayoverflow
layerrule = ignorezero, quickshell:trayoverflow
layerrule = blur, quickshell:settings
layerrule = ignorezero, quickshell:settings
layerrule = blur, quickshell:battery
layerrule = ignorezero, quickshell:battery
layerrule = blur, quickshell:volume
layerrule = ignorezero, quickshell:volume
layerrule = blur, quickshell:welcome
layerrule = ignorezero, quickshell:welcome
layerrule = blur, quickshell:powermenu
layerrule = ignorezero, quickshell:powermenu
layerrule = blur, quickshell:lockscreen
layerrule = blur, quickshell:osd
layerrule = ignorezero, quickshell:osd
layerrule = blur, quickshell:volumeosd
layerrule = ignorezero, quickshell:volumeosd
layerrule = blur, quickshell:brightnessosd
layerrule = ignorezero, quickshell:brightnessosd
layerrule = blur, ^quickshell:.*$
layerrule = ignorezero, ^quickshell:.*$
"""
    with open(qs_conf_path, "w", encoding="utf-8") as f:
        f.write(qs_conf_content)

    autostart_path = os.path.join(conf_dir, "autostart.conf")
    keybinds_path = os.path.join(conf_dir, "keybinds.conf")
    rules_path = os.path.join(conf_dir, "rules.conf")

    if not os.path.exists(conf_path):
        with open(conf_path, "w", encoding="utf-8") as f:
            f.write("""# ══════════════════════════════════════════════════════════════════════════════
#  Hyprland Classic Modular Configuration (~/.config/hypr/hyprland.conf)
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Monitors ──────────────────────────────────────────────────────────────
monitor=,preferred,auto,1

# ── 2. Environment Variables ─────────────────────────────────────────────────
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = QT_QPA_PLATFORM,wayland;xcb
env = GDK_BACKEND,wayland,x11,*

# ── 3. Look and Feel ─────────────────────────────────────────────────────────
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(313244aa)
    resize_on_border = true
    allow_tearing = false
    layout = dwindle
}

decoration {
    rounding = 10
    active_opacity = 1.0
    inactive_opacity = 0.95
    shadow {
        enabled = true
        range = 15
        render_power = 3
        color = rgba(181825ee)
    }
    blur {
        enabled = true
        size = 6
        passes = 3
        new_optimizations = true
        xray = false
    }
}

# ── 4. Animations ────────────────────────────────────────────────────────────
animations {
    enabled = true
    bezier = easeOutQuint,0.23,1,0.32,1
    animation = windows, 1, 4, easeOutQuint
    animation = layers, 1, 4, easeOutQuint
    animation = fade, 1, 3, default
    animation = workspaces, 1, 4, easeOutQuint, slide
}

# ── 5. Layouts & Input ───────────────────────────────────────────────────────
dwindle {
    pseudotile = true
    preserve_split = true
}

scrolling {
    column_width = 0.89
    fullscreen_on_one_column = false
}

input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    touchpad {
        natural_scroll = true
    }
}

# ── 6. Source Modular Configuration Files ────────────────────────────────────
source = ~/.config/hypr/conf/autostart.conf
source = ~/.config/hypr/conf/keybinds.conf
source = ~/.config/hypr/conf/rules.conf
source = ~/.config/hypr/conf/quickshell.conf
""")
        if not os.path.exists(autostart_path):
            with open(autostart_path, "w", encoding="utf-8") as f:
                f.write("""# ══════════════════════════════════════════════════════════════════════════════
#  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.conf)
# ══════════════════════════════════════════════════════════════════════════════

# Polkit Authentication Agent
exec-once = systemctl enable --now --user hyprpolkitagent

# Clipboard History Daemons
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
""")
        if not os.path.exists(keybinds_path):
            with open(keybinds_path, "w", encoding="utf-8") as f:
                f.write("""# ══════════════════════════════════════════════════════════════════════════════
#  Keybindings & Shortcuts (~/.config/hypr/conf/keybinds.conf)
# ══════════════════════════════════════════════════════════════════════════════

$mainMod = SUPER
$terminal = kitty
$fileManager = nautilus

bind = $mainMod, T, exec, $terminal
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, Q, killactive,
bind = $mainMod ALT, F, togglefloating,
bind = $mainMod SHIFT, F, fullscreen, 0
bind = $mainMod, J, togglesplit,

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

bind = , PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh full
bind = SHIFT, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh region
bind = $mainMod, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh window
""")
        if not os.path.exists(rules_path):
            with open(rules_path, "w", encoding="utf-8") as f:
                f.write("""# ══════════════════════════════════════════════════════════════════════════════
#  Window Rules (~/.config/hypr/conf/rules.conf)
# ══════════════════════════════════════════════════════════════════════════════

windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = float, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = pin, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = float, class:^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$
""")
        return {"ok": True, "created_main": True, "conf_dir": conf_dir}

    backup_path = f"{conf_path}.bak.{int(time.time())}"
    shutil.copy2(conf_path, backup_path)

    with open(conf_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    autostart_lines = []
    keybind_lines = []
    rule_lines = []
    main_lines = []

    for line in lines:
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            if "source = ~/.config/hypr/" in stripped or "quickshell" in stripped or "Modular Configuration Sources" in stripped:
                continue
            main_lines.append(line)
            continue

        if "qs ipc call" in stripped or "quickshell:" in stripped or stripped.startswith("source = ~/.config/hypr/"):
            continue

        if stripped.startswith("exec-once") or stripped.startswith("exec "):
            if re.match(r'^exec-once\s*=\s*qs\b', stripped):
                continue
            autostart_lines.append(line)
        elif stripped.startswith("bind") or stripped.startswith("bindm") or stripped.startswith("bindl") or stripped.startswith("binde"):
            keybind_lines.append(line)
        elif stripped.startswith("windowrule") or stripped.startswith("windowrulev2") or stripped.startswith("layerrule") or stripped.startswith("workspacerule"):
            rule_lines.append(line)
        else:
            main_lines.append(line)

    # 2. Write conf/autostart.conf (Deduplicated)
    existing_autostart = ""
    if os.path.exists(autostart_path):
        with open(autostart_path, "r", encoding="utf-8") as f:
            existing_autostart = f.read()

    if autostart_lines:
        combined_autostart = deduplicate_lines(autostart_lines)
        autostart_content = strip_header_banner("".join(combined_autostart))
    elif existing_autostart.strip():
        autostart_content = strip_header_banner(existing_autostart)
    else:
        autostart_content = """# Polkit Authentication Agent
exec-once = systemctl enable --now --user hyprpolkitagent

# Clipboard History Daemons
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store"""

    with open(autostart_path, "w", encoding="utf-8") as f:
        f.write(f"""# ══════════════════════════════════════════════════════════════════════════════
#  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.conf)
# ══════════════════════════════════════════════════════════════════════════════

{autostart_content}
""")

    # 3. Write conf/keybinds.conf (Deduplicated)
    if keybind_lines:
        combined_keybinds = deduplicate_lines(keybind_lines)
        keybind_content = strip_header_banner("".join(combined_keybinds))
    elif os.path.exists(keybinds_path):
        with open(keybinds_path, "r", encoding="utf-8") as f:
            keybind_content = strip_header_banner(f.read())
    else:
        keybind_content = """$mainMod = SUPER
$terminal = kitty
$fileManager = nautilus

bind = $mainMod, T, exec, $terminal
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, Q, killactive,
bind = $mainMod ALT, F, togglefloating,
bind = $mainMod SHIFT, F, fullscreen, 0
bind = $mainMod, J, togglesplit,

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

bind = , PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh full
bind = SHIFT, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh region
bind = $mainMod, PRINT, exec, ~/.config/quickshell/scripts/screenshot.sh window"""

    with open(keybinds_path, "w", encoding="utf-8") as f:
        f.write(f"""# ══════════════════════════════════════════════════════════════════════════════
#  Keybindings & Shortcuts (~/.config/hypr/conf/keybinds.conf)
# ══════════════════════════════════════════════════════════════════════════════

{keybind_content}
""")

    # 4. Write conf/rules.conf (Deduplicated)
    if rule_lines:
        combined_rules = deduplicate_lines(rule_lines)
        rules_content = strip_header_banner("".join(combined_rules))
    elif os.path.exists(rules_path):
        with open(rules_path, "r", encoding="utf-8") as f:
            rules_content = strip_header_banner(f.read())
    else:
        rules_content = """windowrulev2 = suppressevent maximize, class:.*
windowrulev2 = float, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = pin, title:^(Picture-in-Picture|Picture in picture)$
windowrulev2 = float, class:^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$"""

    with open(rules_path, "w", encoding="utf-8") as f:
        f.write(f"""# ══════════════════════════════════════════════════════════════════════════════
#  Window Rules (~/.config/hypr/conf/rules.conf)
# ══════════════════════════════════════════════════════════════════════════════

{rules_content}
""")

    # 5. Clean main hyprland.conf
    while main_lines and not main_lines[-1].strip():
        main_lines.pop()

    cleaned_main = "".join(main_lines).strip()
    final_main = f"""{cleaned_main}

# ── Modular Configuration Sources ────────────────────────────────────────────
source = ~/.config/hypr/conf/autostart.conf
source = ~/.config/hypr/conf/keybinds.conf
source = ~/.config/hypr/conf/rules.conf
source = ~/.config/hypr/conf/quickshell.conf
"""
    with open(conf_path, "w", encoding="utf-8") as f:
        f.write(final_main)

    return {
        "ok": True,
        "backup": backup_path,
        "conf_dir": conf_dir,
        "extracted_autostart": len(autostart_lines),
        "extracted_keybinds": len(keybind_lines),
        "extracted_rules": len(rule_lines)
    }

def modularize_niri_kdl():
    niri_dir = os.path.join(HOME, ".config/niri")
    conf_dir = os.path.join(niri_dir, "conf")
    niri_path = os.path.join(niri_dir, "config.kdl")
    os.makedirs(conf_dir, exist_ok=True)

    # 1. Quickshell kdl (~/.config/niri/conf/quickshell.kdl)
    qs_kdl_path = os.path.join(conf_dir, "quickshell.kdl")
    qs_kdl_content = """// ══════════════════════════════════════════════════════════════════════════════
//  Quickshell Desktop Environment Integration (~/.config/niri/conf/quickshell.kdl)
// ══════════════════════════════════════════════════════════════════════════════

// ── 1. Autostart Quickshell Desktop Environment ──────────────────────────────
spawn-at-startup "qs"

// ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
binds {
    Mod+Space       { spawn "qs" "ipc" "call" "launcher" "toggle"; }
    Mod+Shift+W     { spawn "qs" "ipc" "call" "wallpaper" "toggle"; }
    Mod+Shift+E     { spawn "qs" "ipc" "call" "emoji" "toggle"; }
    Mod+V           { spawn "qs" "ipc" "call" "clipboard" "toggle"; }
    Mod+P           { spawn "qs" "ipc" "call" "powermenu" "toggle"; }
    Mod+Alt+L       { spawn "qs" "ipc" "call" "lockscreen" "toggle"; }
    Mod+D           { spawn "qs" "ipc" "call" "dashboard" "toggle"; }
    Mod+N           { spawn "qs" "ipc" "call" "notifCenter" "toggle"; }
    Mod+C           { spawn "qs" "ipc" "call" "controlCenter" "toggle"; }
    Mod+B           { spawn "qs" "ipc" "call" "battery" "toggle"; }
}
"""
    with open(qs_kdl_path, "w", encoding="utf-8") as f:
        f.write(qs_kdl_content)

    autostart_path = os.path.join(conf_dir, "autostart.kdl")
    keybinds_path = os.path.join(conf_dir, "keybinds.kdl")
    rules_path = os.path.join(conf_dir, "rules.kdl")

    if not os.path.exists(niri_path):
        with open(niri_path, "w", encoding="utf-8") as f:
            f.write("""// ══════════════════════════════════════════════════════════════════════════════
//  Niri Modular Configuration (~/.config/niri/config.kdl)
// ══════════════════════════════════════════════════════════════════════════════

// ── 1. Output & Display ──────────────────────────────────────────────────────
output "eDP-1" {
    mode "1920x1080@60.0"
    scale 1.0
    transform "normal"
    position x=0 y=0
}

// ── 2. Layout & Window Behavior ──────────────────────────────────────────────
layout {
    gaps 8
    center-focused-column "never"

    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }

    default-column-width { proportion 0.5; }

    focus-ring {
        width 2
        active-color "#89b4fa"
        inactive-color "#313244"
    }

    border {
        off
    }
}

// ── 3. Input Settings ────────────────────────────────────────────────────────
input {
    keyboard {
        xkb {
            layout "us"
        }
    }
    touchpad {
        natural-scroll
        tap
    }
}

// ── 4. Include Modular Configurations ────────────────────────────────────────
include "conf/autostart.kdl"
include "conf/keybinds.kdl"
include "conf/rules.kdl"
include "conf/quickshell.kdl"
""")
        if not os.path.exists(autostart_path):
            with open(autostart_path, "w", encoding="utf-8") as f:
                f.write("""// ══════════════════════════════════════════════════════════════════════════════
//  Autostart Daemons & Services (~/.config/niri/conf/autostart.kdl)
// ══════════════════════════════════════════════════════════════════════════════

spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store"
""")
        if not os.path.exists(keybinds_path):
            with open(keybinds_path, "w", encoding="utf-8") as f:
                f.write("""// ══════════════════════════════════════════════════════════════════════════════
//  Keybindings & Shortcuts (~/.config/niri/conf/keybinds.kdl)
// ══════════════════════════════════════════════════════════════════════════════

binds {
    Mod+Return { spawn "kitty"; }
    Mod+E      { spawn "nautilus"; }
    Mod+Q      { close-window; }
    Mod+F      { fullscreen-window; }

    Mod+Left   { focus-column-left; }
    Mod+Right  { focus-column-right; }
    Mod+Up     { focus-window-up; }
    Mod+Down   { focus-window-down; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }

    Print       { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh full"; }
    Shift+Print { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh region"; }
    Mod+Print   { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh window"; }
}
""")
        if not os.path.exists(rules_path):
            with open(rules_path, "w", encoding="utf-8") as f:
                f.write("""// ══════════════════════════════════════════════════════════════════════════════
//  Window & Layout Rules (~/.config/niri/conf/rules.kdl)
// ══════════════════════════════════════════════════════════════════════════════

window-rule {
    match app-id=r#"^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$"#
    open-floating true
}

window-rule {
    match title=r#"^(Picture-in-Picture|Picture in picture)$"#
    open-floating true
}
""")
        return {"ok": True, "created_main": True, "conf_dir": conf_dir}

    backup_path = f"{niri_path}.bak.{int(time.time())}"
    shutil.copy2(niri_path, backup_path)

    with open(niri_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Extract spawn-at-startup
    spawn_matches = re.findall(r'spawn-at-startup\s+([^\n;]+);?', content)
    clean_spawns = []
    for sp in spawn_matches:
        if '"qs"' in sp or "'qs'" in sp:
            continue
        clean_spawns.append(f'spawn-at-startup {sp}')

    # Extract binds
    binds_match = re.search(r'binds\s*\{([\s\S]*?)\n\}', content)
    binds_body = binds_match.group(1) if binds_match else ""
    clean_binds_lines = []
    if binds_body:
        for bl in binds_body.splitlines():
            if "qs ipc call" in bl or '"qs" "ipc" "call"' in bl:
                continue
            clean_binds_lines.append(bl)

    # Extract window-rule
    rule_matches = re.findall(r'window-rule\s*\{([\s\S]*?)\n\}', content)

    # Write conf/autostart.kdl
    if clean_spawns:
        combined_spawns = deduplicate_lines(clean_spawns)
        autostart_content = strip_header_banner("\n".join(combined_spawns))
    elif os.path.exists(autostart_path):
        with open(autostart_path, "r", encoding="utf-8") as f:
            autostart_content = strip_header_banner(f.read())
    else:
        autostart_content = """spawn-at-startup "wl-paste" "--type" "text" "--watch" "cliphist" "store"
spawn-at-startup "wl-paste" "--type" "image" "--watch" "cliphist" "store\""""

    with open(autostart_path, "w", encoding="utf-8") as f:
        f.write(f"""// ══════════════════════════════════════════════════════════════════════════════
//  Autostart Daemons & Services (~/.config/niri/conf/autostart.kdl)
// ══════════════════════════════════════════════════════════════════════════════

{autostart_content}
""")

    # Write conf/keybinds.kdl
    if clean_binds_lines:
        keybinds_content = strip_header_banner("\n".join(clean_binds_lines))
        final_binds_block = f"binds {{\n{keybinds_content}\n}}"
    elif os.path.exists(keybinds_path):
        with open(keybinds_path, "r", encoding="utf-8") as f:
            raw_existing = strip_header_banner(f.read())
        if raw_existing.strip().startswith("binds {") and raw_existing.strip().endswith("}"):
            final_binds_block = raw_existing.strip()
        else:
            final_binds_block = f"binds {{\n{raw_existing}\n}}"
    else:
        keybinds_content = """    Mod+Return { spawn "kitty"; }
    Mod+E      { spawn "nautilus"; }
    Mod+Q      { close-window; }
    Mod+F      { fullscreen-window; }

    Mod+Left   { focus-column-left; }
    Mod+Right  { focus-column-right; }
    Mod+Up     { focus-window-up; }
    Mod+Down   { focus-window-down; }

    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }

    Print       { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh full"; }
    Shift+Print { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh region"; }
    Mod+Print   { spawn "sh" "-c" "~/.config/quickshell/scripts/screenshot.sh window"; }"""
        final_binds_block = f"binds {{\n{keybinds_content}\n}}"

    with open(keybinds_path, "w", encoding="utf-8") as f:
        f.write(f"""// ══════════════════════════════════════════════════════════════════════════════
//  Keybindings & Shortcuts (~/.config/niri/conf/keybinds.kdl)
// ══════════════════════════════════════════════════════════════════════════════

{final_binds_block}
""")

    # Write conf/rules.kdl
    if rule_matches:
        rules_content = strip_header_banner("\n\n".join([f"window-rule {{\n{rm.strip()}\n}}" for rm in rule_matches]))
    elif os.path.exists(rules_path):
        with open(rules_path, "r", encoding="utf-8") as f:
            rules_content = strip_header_banner(f.read())
    else:
        rules_content = """window-rule {
    match app-id=r#"^(pavucontrol|nm-connection-editor|blueman-manager|swappy)$"#
    open-floating true
}

window-rule {
    match title=r#"^(Picture-in-Picture|Picture in picture)$"#
    open-floating true
}"""

    with open(rules_path, "w", encoding="utf-8") as f:
        f.write(f"""// ══════════════════════════════════════════════════════════════════════════════
//  Window & Layout Rules (~/.config/niri/conf/rules.kdl)
// ══════════════════════════════════════════════════════════════════════════════

{rules_content}
""")

    # Clean main config.kdl
    cleaned = content
    cleaned = re.sub(r'//\s*──\s*Quickshell.*', '', cleaned)
    cleaned = re.sub(r'//\s*──\s*Modular Configurations.*', '', cleaned)
    cleaned = re.sub(r'include\s+["\'][^"\']*quickshell[^"\']*["\'];?', '', cleaned)
    cleaned = re.sub(r'include\s+["\']conf/[^"\']*["\'];?', '', cleaned)
    cleaned = re.sub(r'spawn-at-startup\s+[^\n;]+;?', '', cleaned)
    cleaned = re.sub(r'binds\s*\{[\s\S]*?\n\}', '', cleaned)
    cleaned = re.sub(r'window-rule\s*\{[\s\S]*?\n\}', '', cleaned)
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned).strip()

    final_kdl = f"""{cleaned}

// ── Modular Configurations ───────────────────────────────────────────────────
include "conf/autostart.kdl"
include "conf/keybinds.kdl"
include "conf/rules.kdl"
include "conf/quickshell.kdl"
"""
    with open(niri_path, "w", encoding="utf-8") as f:
        f.write(final_kdl)

    return {
        "ok": True,
        "backup": backup_path,
        "conf_dir": conf_dir
    }

def modularize_compositor(comp_type="auto"):
    results = {}
    hypr_lua_exists = os.path.exists(os.path.join(HOME, ".config/hypr/hyprland.lua"))
    hypr_conf_exists = os.path.exists(os.path.join(HOME, ".config/hypr/hyprland.conf"))
    niri_exists = os.path.exists(os.path.join(HOME, ".config/niri/config.kdl"))

    if comp_type == "hyprland":
        if hypr_lua_exists:
            results["hypr_lua"] = modularize_hypr_lua()
        else:
            results["hypr_conf"] = modularize_hypr_conf()
    elif comp_type == "hypr_lua":
        results["hypr_lua"] = modularize_hypr_lua()
    elif comp_type == "hypr_conf":
        results["hypr_conf"] = modularize_hypr_conf()
    elif comp_type == "niri":
        results["niri"] = modularize_niri_kdl()
    elif comp_type == "all":
        if hypr_lua_exists:
            results["hypr_lua"] = modularize_hypr_lua()
        if hypr_conf_exists or not hypr_lua_exists:
            results["hypr_conf"] = modularize_hypr_conf()
        results["niri"] = modularize_niri_kdl()
    else:  # auto
        applied = False
        if hypr_lua_exists:
            results["hypr_lua"] = modularize_hypr_lua()
            applied = True
        if hypr_conf_exists:
            results["hypr_conf"] = modularize_hypr_conf()
            applied = True
        if niri_exists:
            results["niri"] = modularize_niri_kdl()
            applied = True
        if not applied:
            # Check installed binaries
            if is_hyprland() or shutil.which("hyprctl"):
                results["hypr_conf"] = modularize_hypr_conf()
            elif is_niri() or shutil.which("niri"):
                results["niri"] = modularize_niri_kdl()
            else:
                results["hypr_conf"] = modularize_hypr_conf()

    return {"ok": True, "results": results}

def save_monitors_to_file(monitors_data, is_lua=True):
    hypr_dir = os.path.join(HOME, ".config/hypr")
    if not os.path.exists(hypr_dir):
        os.makedirs(hypr_dir, exist_ok=True)

    if is_lua:
        lua_path = os.path.join(hypr_dir, "hyprland.lua")
        if not os.path.exists(lua_path):
            return {"ok": False, "error": "hyprland.lua does not exist"}

        backup_path = f"{lua_path}.bak.{int(time.time())}"
        shutil.copy2(lua_path, backup_path)

        with open(lua_path, "r", encoding="utf-8") as f:
            content = f.read()

        blocks = [
            "-- ──────────────────────────────",
            "--  MONITORS",
            "-- ──────────────────────────────",
            "-- https://wiki.hypr.land/Configuring/Basics/Monitors/\n"
        ]

        for m in monitors_data:
            name = m.get("name")
            if not name:
                continue
            if m.get("disabled"):
                blocks.append(f"""hl.monitor({{
    output   = "{name}",
    mode     = "disabled",
}})\n""")
            elif m.get("mirrorOf") and m.get("mirrorOf") != "none" and m.get("mirrorOf") != name:
                mirror = m.get("mirrorOf")
                scale = float(m.get("scale", 1.0))
                mode = str(m.get("mode") or "preferred")
                blocks.append(f"""hl.monitor({{
    output   = "{name}",
    mode     = "{mode}",
    position = "{int(m.get('x', 0))}x{int(m.get('y', 0))}",
    scale    = {scale},
    mirror   = "{mirror}",
}})\n""")
            else:
                scale = float(m.get("scale", 1.0))
                mode = str(m.get("mode") or "preferred")
                transform = int(m.get("transform", 0))
                vrr_val = 1 if m.get("vrr") else 0
                x = int(m.get("x", 0))
                y = int(m.get("y", 0))
                blocks.append(f"""hl.monitor({{
    output    = "{name}",
    mode      = "{mode}",
    position  = "{x}x{y}",
    scale     = {scale},
    transform = {transform},
    vrr       = {vrr_val},
}})\n""")

        new_monitors_section = "\n".join(blocks).strip() + "\n\n"

        pattern = r'(--\s*─+\s*\n--\s*MONITORS\s*\n--\s*─+[\s\S]*?)(?=\n--\s*─+\s*\n--\s*|\Z)'
        if re.search(pattern, content):
            new_content = re.sub(pattern, new_monitors_section.strip(), content, count=1)
        else:
            mon_call_pattern = r'(hl\.monitor\(\{[\s\S]*?\}\)\s*)+'
            if re.search(mon_call_pattern, content):
                new_content = re.sub(mon_call_pattern, new_monitors_section, content, count=1)
            else:
                new_content = new_monitors_section + "\n" + content

        with open(lua_path, "w", encoding="utf-8") as f:
            f.write(new_content)

        return {"ok": True, "file": lua_path, "backup": backup_path}

    else:
        conf_path = os.path.join(hypr_dir, "hyprland.conf")
        if not os.path.exists(conf_path):
            return {"ok": False, "error": "hyprland.conf does not exist"}

        backup_path = f"{conf_path}.bak.{int(time.time())}"
        shutil.copy2(conf_path, backup_path)

        with open(conf_path, "r", encoding="utf-8") as f:
            content = f.read()

        lines = [
            "# ── Monitors ──────────────────────────────────────────────────────────────────"
        ]
        for m in monitors_data:
            name = m.get("name")
            if not name:
                continue
            if m.get("disabled"):
                lines.append(f"monitor = {name}, disable")
            elif m.get("mirrorOf") and m.get("mirrorOf") != "none" and m.get("mirrorOf") != name:
                scale = float(m.get("scale", 1.0))
                lines.append(f"monitor = {name}, preferred, auto, {scale}, mirror, {m.get('mirrorOf')}")
            else:
                scale = float(m.get("scale", 1.0))
                mode = str(m.get("mode") or "preferred")
                x = int(m.get("x", 0))
                y = int(m.get("y", 0))
                transform = int(m.get("transform", 0))
                lines.append(f"monitor = {name}, {mode}, {x}x{y}, {scale}, transform, {transform}")

        new_section = "\n".join(lines) + "\n"
        cleaned = re.sub(r'^\s*monitor\s*=.*$\n?', '', content, flags=re.MULTILINE)
        cleaned = re.sub(r'#\s*──+\s*Monitors[\s\S]*?(?=\n#\s*──|\Z)', '', cleaned)
        new_content = new_section + "\n" + cleaned.strip() + "\n"

        with open(conf_path, "w", encoding="utf-8") as f:
            f.write(new_content)

        return {"ok": True, "file": conf_path, "backup": backup_path}

def save_niri_monitors(monitors_data):
    niri_dir = os.path.join(HOME, ".config/niri")
    kdl_path = os.path.join(niri_dir, "config.kdl")
    if not os.path.exists(kdl_path):
        return {"ok": False, "error": "config.kdl does not exist"}

    backup_path = f"{kdl_path}.bak.{int(time.time())}"
    shutil.copy2(kdl_path, backup_path)

    with open(kdl_path, "r", encoding="utf-8") as f:
        content = f.read()

    blocks = []
    for m in monitors_data:
        name = m.get("name")
        if not name:
            continue
        scale = float(m.get("scale", 1.0))
        mode = str(m.get("mode") or "")
        x = int(m.get("x", 0))
        y = int(m.get("y", 0))
        mode_line = f'    mode "{mode}"\n' if mode and mode != "preferred" else ""
        off_line = "    off\n" if m.get("disabled") else ""
        vrr_line = "    variable-refresh-rate\n" if m.get("vrr") else ""
        blocks.append(f"""output "{name}" {{
{off_line}{mode_line}    scale {scale}
    position x={x} y={y}
{vrr_line}}}""")

    outputs_section = "\n\n".join(blocks)
    cleaned = re.sub(r'output\s+"[^"]+"\s*\{[\s\S]*?\n\}', '', content)
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned).strip()
    new_content = outputs_section + "\n\n" + cleaned + "\n"

    with open(kdl_path, "w", encoding="utf-8") as f:
        f.write(new_content)

    return {"ok": True, "file": kdl_path, "backup": backup_path}

def apply_monitors_layout(monitors_data, save_config=True):
    if not isinstance(monitors_data, list):
        return {"ok": False, "error": "monitors_data must be a list of monitor objects"}

    comp = "hyprland"
    if is_niri():
        comp = "niri"

    results = []
    if comp == "hyprland":
        is_lua = is_lua_config()
        if is_lua:
            lua_parts = []
            for m in monitors_data:
                name = m.get("name")
                if not name:
                    continue
                disabled = m.get("disabled", False)
                if disabled:
                    lua_parts.append(f'hl.monitor({{ output = "{name}", mode = "disabled" }})')
                    continue

                mirror = m.get("mirrorOf")
                scale = float(m.get("scale", 1.0))
                mode = str(m.get("mode") or "preferred")
                x = int(m.get("x", 0))
                y = int(m.get("y", 0))
                transform = int(m.get("transform", 0))
                vrr = 1 if m.get("vrr") else 0
                pos_str = f"{x}x{y}"

                if mirror and mirror != "none" and mirror != name:
                    lua_parts.append(f'hl.monitor({{ output = "{name}", mode = "{mode}", position = "{pos_str}", scale = {scale}, mirror = "{mirror}" }})')
                else:
                    lua_parts.append(f'hl.monitor({{ output = "{name}", mode = "{mode}", position = "{pos_str}", scale = {scale}, transform = {transform}, vrr = {vrr} }})')

            if lua_parts:
                eval_cmd = " ; ".join(lua_parts)
                r = subprocess.run(["hyprctl", "eval", eval_cmd], capture_output=True, text=True, timeout=2.0)
                results.append({"type": "hypr_eval", "returncode": r.returncode, "stdout": r.stdout.strip(), "stderr": r.stderr.strip()})
        else:
            for m in monitors_data:
                name = m.get("name")
                if not name:
                    continue
                disabled = m.get("disabled", False)
                if disabled:
                    subprocess.run(["hyprctl", "keyword", "monitor", f"{name},disable"], timeout=1.0)
                    continue

                mirror = m.get("mirrorOf")
                scale = float(m.get("scale", 1.0))
                mode = str(m.get("mode") or "preferred")
                x = int(m.get("x", 0))
                y = int(m.get("y", 0))
                transform = int(m.get("transform", 0))
                pos_str = f"{x}x{y}"

                if mirror and mirror != "none" and mirror != name:
                    cmd_str = f"{name},preferred,auto,{scale},mirror,{mirror}"
                else:
                    cmd_str = f"{name},{mode},{pos_str},{scale},transform,{transform}"

                subprocess.run(["hyprctl", "keyword", "monitor", cmd_str], timeout=1.0)
                if m.get("vrr") is not None:
                    subprocess.run(["hyprctl", "keyword", "misc:vrr", "1" if m.get("vrr") else "0"], timeout=1.0)

        if save_config:
            save_res = save_monitors_to_file(monitors_data, is_lua=is_lua)
            return {"ok": True, "live": results, "saved": save_res}

        return {"ok": True, "live": results}

    elif comp == "niri":
        if save_config:
            save_res = save_niri_monitors(monitors_data)
            return {"ok": True, "saved": save_res}
        return {"ok": True}

    return {"ok": False, "error": f"Unsupported compositor {comp}"}

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Missing command argument"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "query":
        data = query_all()
        print(json.dumps(data))
    elif cmd == "modularize":
        target = sys.argv[2] if len(sys.argv) > 2 else "auto"
        res = modularize_compositor(target)
        print(json.dumps(res))
    elif cmd == "monitors-apply":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--layout", required=True)
        parser.add_argument("--save", action="store_true", default=False)
        args = parser.parse_args(sys.argv[2:])
        try:
            if os.path.exists(args.layout):
                with open(args.layout, "r", encoding="utf-8") as lf:
                    layout_data = json.load(lf)
            else:
                layout_data = json.loads(args.layout)
            res = apply_monitors_layout(layout_data, save_config=args.save)
            print(json.dumps(res))
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)}))
    elif cmd == "binds-list":
        data = list_keybinds()
        print(json.dumps(data))
    elif cmd == "binds-add":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--keys", required=True)
        parser.add_argument("--action", required=True)
        parser.add_argument("--desc", default="")
        parser.add_argument("--file", default=None)
        args = parser.parse_args(sys.argv[2:])
        res = add_keybind(args.keys, args.action, args.desc, target_file=args.file)
        print(json.dumps(res))
    elif cmd == "binds-update":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--line", required=True)
        parser.add_argument("--keys", required=True)
        parser.add_argument("--action", required=True)
        parser.add_argument("--desc", default="")
        parser.add_argument("--file", default=None)
        args = parser.parse_args(sys.argv[2:])
        res = update_keybind(args.line, args.keys, args.action, args.desc, target_file=args.file)
        print(json.dumps(res))
    elif cmd == "binds-delete":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--line", required=True)
        parser.add_argument("--file", default=None)
        args = parser.parse_args(sys.argv[2:])
        res = delete_keybind(args.line, target_file=args.file)
        print(json.dumps(res))
    elif cmd in ("options-apply", "save-options"):
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--changes", required=True)
        args = parser.parse_args(sys.argv[2:])
        try:
            changes_data = json.loads(args.changes)
            res = save_general_options(changes_data)
            print(json.dumps(res))
        except Exception as e:
            print(json.dumps({"ok": False, "error": str(e)}))
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

