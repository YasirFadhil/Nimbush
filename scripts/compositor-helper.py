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
            ("layout", "general:layout", str, "scrolling"),
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

# ── Keybindings Management ───────────────────────────────────────────────────

def get_primary_config():
    if is_lua_config():
        return os.path.join(HOME, ".config/hypr/hyprland.lua"), "lua"
    if os.path.exists(os.path.join(HOME, ".config/hypr/hyprland.conf")):
        return os.path.join(HOME, ".config/hypr/hyprland.conf"), "hyprconf"
    if os.path.exists(os.path.join(HOME, ".config/niri/config.kdl")):
        return os.path.join(HOME, ".config/niri/config.kdl"), "niri"
    return None, None

def list_keybinds():
    cfg_path, cfg_type = get_primary_config()
    if not cfg_path or not os.path.exists(cfg_path):
        return {"ok": False, "error": "No compositor config found", "binds": []}

    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            full_text = f.read()
    except Exception as e:
        return {"ok": False, "error": str(e), "binds": []}

    lines = full_text.splitlines()
    binds = []

    if cfg_type == "lua":
        vars_dict = {}
        var_re = re.compile(r'^\s*local\s+([a-zA-Z0-9_]+)\s*=\s*["\']([^"\']+)["\']')
        for l in lines:
            m = var_re.match(l)
            if m:
                vars_dict[m.group(1)] = m.group(2)

        n = len(full_text)
        line_starts = [0]
        for pos, ch in enumerate(full_text):
            if ch == '\n':
                line_starts.append(pos + 1)

        import bisect
        def get_line_num(char_idx):
            return bisect.bisect_right(line_starts, char_idx)

        pattern = re.compile(r'(?:local\s+([a-zA-Z0-9_]+)\s*=\s*)?hl\.bind\s*\(')

        for match in pattern.finditer(full_text):
            start_char = match.start()
            start_line = get_line_num(start_char)

            line_str = lines[start_line - 1] if start_line <= len(lines) else ""
            line_before_match = line_str[:line_str.find("hl.bind")].strip()
            if line_before_match.startswith("--"):
                continue

            open_paren_idx = match.end() - 1
            depth = 1
            j = open_paren_idx + 1
            in_str = False
            str_char = ''
            inner = ""
            while j < n and depth > 0:
                c = full_text[j]
                if c in ('"', "'", '`') and not in_str:
                    in_str = True
                    str_char = c
                    inner += c
                elif in_str and c == str_char and full_text[j-1] != '\\':
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

            end_line = get_line_num(j)
            raw_snippet = full_text[start_char:j]

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

                combo = raw_combo
                for vname, vval in vars_dict.items():
                    combo = re.sub(r'\b' + vname + r'\b', f'"{vval}"', combo)
                combo_parts = [p.strip().strip('"\'') for p in combo.split("..")]
                clean_combo = " + ".join([p.strip().strip('+ ') for p in combo_parts if p.strip()])
                clean_combo = clean_combo.replace(" + + ", " + ").replace("  ", " ")

                action = raw_action
                for vname, vval in vars_dict.items():
                    action = re.sub(r'\b' + vname + r'\b', f'"{vval}"', action)

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
                elif any(x in ca_low for x in ["kitty", "alacritty", "foot", "nautilus", "thunar", "dolphin", "browser", "firefox", "chrome", "code"]):
                    cat = "apps"
                elif any(x in ca_low for x in ["close", "fullscreen", "floating", "focus", "workspace", "swapcol", "togglesplit", "drag", "resize"]):
                    cat = "nav"
                elif "screenshot" in ca_low or "grim" in ca_low or "print" in cb_low:
                    cat = "screenshot"
                elif any(x in ca_low for x in ["wpctl", "pactl", "volume", "brightnessctl", "playerctl", "mute", "audio"]):
                    cat = "media"

                key_tokens = [k.strip() for k in clean_combo.split("+") if k.strip()]

                binds.append({
                    "id": start_line,
                    "startLine": start_line,
                    "endLine": end_line,
                    "keys": clean_combo,
                    "keyTokens": key_tokens,
                    "action": clean_action,
                    "raw": raw_snippet.strip(),
                    "category": cat,
                    "opts": opts.strip()
                })

    elif cfg_type == "hyprconf":
        bind_re = re.compile(r'^\s*bind[lrme]?\s*=\s*([^,]+),\s*([^,]+),\s*([^,]+)(?:,\s*(.*))?')
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
                elif any(x in ca_low for x in ["kitty", "alacritty", "foot", "nautilus", "thunar", "dolphin", "browser", "firefox"]):
                    cat = "apps"
                elif any(x in ca_low for x in ["killactive", "fullscreen", "togglefloating", "workspace", "movetoworkspace", "splitratio"]):
                    cat = "nav"
                elif "screenshot" in ca_low or "grim" in ca_low or "print" in cb_low:
                    cat = "screenshot"
                elif any(x in ca_low for x in ["wpctl", "pactl", "volume", "brightnessctl", "playerctl"]):
                    cat = "media"

                key_tokens = [k.strip() for k in combo.split("+") if k.strip()]
                binds.append({
                    "id": idx + 1,
                    "startLine": idx + 1,
                    "endLine": idx + 1,
                    "keys": combo,
                    "keyTokens": key_tokens,
                    "action": action,
                    "raw": line_str,
                    "category": cat,
                    "opts": ""
                })

    return {
        "ok": True,
        "binds": binds,
        "configPath": cfg_path,
        "configType": cfg_type,
        "total": len(binds)
    }

def add_keybind(keys, action, desc=""):
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
        # Format hl.bind("COMBO", hl.dsp.exec_cmd("CMD"))
        # Check if action is known dispatcher or exec
        if action.startswith("hl.dsp."):
            new_line = f'hl.bind("{keys}", {action})\n'
        else:
            escaped_action = action.replace('\\', '\\\\').replace('"', '\\"')
            new_line = f'hl.bind("{keys}", hl.dsp.exec_cmd("{escaped_action}"))\n'

        # Find insertion position: right before "WINDOW / LAYER RULES" or end of file
        insert_idx = len(lines)
        for i, l in enumerate(lines):
            if "WINDOW / LAYER RULES" in l or "WINDOW RULES" in l or "LAYER RULES" in l:
                insert_idx = max(0, i - 1)
                break

        lines.insert(insert_idx, new_line)

    elif cfg_type == "hyprconf":
        # Parse keys into mod and key
        parts = [p.strip() for p in keys.split("+") if p.strip()]
        if len(parts) > 1:
            mod = " ".join(parts[:-1])
            k = parts[-1]
        else:
            mod = ""
            k = parts[0]

        new_line = f"bind = {mod}, {k}, exec, {action}\n"
        lines.append(new_line)

    content = "".join(lines)
    res = _write_and_validate(cfg_path, content)
    if res.get("ok"):
        reload_compositor()
    return res

def update_keybind(line_num, keys, action, desc=""):
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
        if action.startswith("hl.dsp."):
            lines[line_idx] = f'hl.bind("{keys}", {action})\n'
        else:
            escaped_action = action.replace('\\', '\\\\').replace('"', '\\"')
            lines[line_idx] = f'hl.bind("{keys}", hl.dsp.exec_cmd("{escaped_action}"))\n'
    elif cfg_type == "hyprconf":
        parts = [p.strip() for p in keys.split("+") if p.strip()]
        if len(parts) > 1:
            mod = " ".join(parts[:-1])
            k = parts[-1]
        else:
            mod = ""
            k = parts[0]
        lines[line_idx] = f"bind = {mod}, {k}, exec, {action}\n"

    content = "".join(lines)
    res = _write_and_validate(cfg_path, content)
    if res.get("ok"):
        reload_compositor()
    return res

def delete_keybind(line_num):
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

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "Missing command argument"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "query":
        data = query_all()
        print(json.dumps(data))
    elif cmd == "binds-list":
        data = list_keybinds()
        print(json.dumps(data))
    elif cmd == "binds-add":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--keys", required=True)
        parser.add_argument("--action", required=True)
        parser.add_argument("--desc", default="")
        args = parser.parse_args(sys.argv[2:])
        res = add_keybind(args.keys, args.action, args.desc)
        print(json.dumps(res))
    elif cmd == "binds-update":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--line", required=True)
        parser.add_argument("--keys", required=True)
        parser.add_argument("--action", required=True)
        parser.add_argument("--desc", default="")
        args = parser.parse_args(sys.argv[2:])
        res = update_keybind(args.line, args.keys, args.action, args.desc)
        print(json.dumps(res))
    elif cmd == "binds-delete":
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--line", required=True)
        args = parser.parse_args(sys.argv[2:])
        res = delete_keybind(args.line)
        print(json.dumps(res))
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
