#!/usr/bin/env python3
"""
atspi_menu.py - Multi-Backend Global Menu Bridge for Nimbush Global Menu
Supports AT-SPI (MenuBar + deep Hamburger/Toolbar), D-Bus (com.canonical.dbusmenu),
and GTK GMenu/GAction (org.gtk.Menus / org.gtk.Actions).
"""

import sys
import os
import re
import json
import subprocess
import threading
import xml.etree.ElementTree as ET


def enable_accessibility():
    try:
        subprocess.run(
            ["busctl", "--user", "set-property", "org.a11y.Bus", "/org/a11y/bus",
             "org.a11y.Status", "IsEnabled", "b", "true"],
            capture_output=True,
            timeout=2.0
        )
    except Exception:
        pass


enable_accessibility()

try:
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi, Gio, GLib
    Atspi.init()
except Exception as e:
    sys.stderr.write(f"[atspi_menu] Failed to initialize AT-SPI: {e}\n")
    sys.stderr.flush()
    if "--daemon" in sys.argv or not sys.stdin.isatty():
        print(json.dumps({"type": "error", "msg": f"Failed to initialize AT-SPI: {e}"}), flush=True)
    sys.exit(1)


# ── Label & Shortcut Helpers ──────────────────────────────────────────────────

def clean_label(text):
    if not text:
        return ""
    s = str(text).strip()
    # Unescape && -> placeholder, strip single & mnemonic, restore &
    s = s.replace("&&", "\x00")
    s = re.sub(r"&([A-Za-z0-9])", r"\1", s)
    s = s.replace("\x00", "&")
    # Strip trailing ellipsis? Keep it if present, just collapse whitespace
    s = re.sub(r"\s+", " ", s).strip()
    return s


def normalize_shortcut(raw):
    if not raw:
        return ""
    s = str(raw).strip()
    if not s:
        return ""
    # AT-SPI sometimes returns ";Ctrl+S" or "<Control>s" or "Primary+s"
    if ";" in s:
        parts = [p.strip() for p in s.split(";") if p.strip()]
        s = parts[-1] if parts else ""
    s = (s.replace("<Primary>", "Ctrl+")
          .replace("<Control>", "Ctrl+")
          .replace("<Ctrl>", "Ctrl+")
          .replace("<Shift>", "Shift+")
          .replace("<Alt>", "Alt+")
          .replace("<Super>", "Super+")
          .replace("<Meta>", "Meta+")
          .replace("Primary+", "Ctrl+")
          .replace("Control+", "Ctrl+"))
    # Uppercase trailing single key
    if "+" in s:
        head, tail = s.rsplit("+", 1)
        if len(tail) == 1:
            tail = tail.upper()
        s = f"{head}+{tail}"
    return s


# ── Process & Hyprland Helpers ────────────────────────────────────────────────

def get_active_hyprland_window():
    try:
        res = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=1.5)
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)
            pid = data.get("pid")
            if pid and pid > 0:
                return {
                    "pid": int(pid),
                    "app_class": str(data.get("class") or ""),
                    "title": str(data.get("title") or ""),
                }
    except Exception as e:
        sys.stderr.write(f"[atspi_menu] Error getting active window: {e}\n")
    return None


def get_pid_family(pid):
    """Return ordered list of related PIDs: [pid, ancestors..., children...]."""
    if not pid or pid <= 0:
        return []
    family = [int(pid)]
    seen = {int(pid)}

    # Walk up ancestors (max 4, stop before PID 1 / systemd)
    curr = int(pid)
    for _ in range(4):
        try:
            with open(f"/proc/{curr}/stat", "r") as f:
                stat = f.read()
            rparen = stat.rfind(")")
            if rparen == -1:
                break
            fields = stat[rparen + 2:].split()
            ppid = int(fields[1])
            if ppid <= 1 or ppid in seen:
                break
            # Stop if parent is a shell/compositor/systemd
            with open(f"/proc/{ppid}/comm", "r") as cf:
                comm = cf.read().strip().lower()
            if comm in ("systemd", "hyprland", "niri", "sway", "bash", "zsh", "fish", "sh"):
                break
            family.append(ppid)
            seen.add(ppid)
            curr = ppid
        except Exception:
            break

    # Walk down direct children (2 levels)
    queue = [int(pid)]
    for _ in range(2):
        next_q = []
        for p in queue:
            try:
                task_dir = f"/proc/{p}/task"
                for tid in os.listdir(task_dir):
                    cpath = f"{task_dir}/{tid}/children"
                    if os.path.exists(cpath):
                        with open(cpath, "r") as f:
                            for tok in f.read().split():
                                cpid = int(tok)
                                if cpid not in seen:
                                    seen.add(cpid)
                                    family.append(cpid)
                                    next_q.append(cpid)
            except Exception:
                continue
        queue = next_q
    return family


# ── AT-SPI Helpers ────────────────────────────────────────────────────────────

def find_app_node(pid, app_class="", title=""):
    try:
        desktop_count = Atspi.get_desktop_count()
    except Exception:
        return None

    family = get_pid_family(pid)
    family_set = set(family)
    apps = []

    for d in range(desktop_count):
        try:
            desktop = Atspi.get_desktop(d)
            if not desktop:
                continue
            for i in range(desktop.get_child_count()):
                try:
                    child = desktop.get_child_at_index(i)
                    if child:
                        apps.append(child)
                except Exception:
                    continue
        except Exception:
            continue

    # 1. Exact PID match
    for child in apps:
        try:
            if child.get_process_id() == pid:
                return child
        except Exception:
            continue

    # 2. Family PID match
    for target_pid in family:
        for child in apps:
            try:
                if child.get_process_id() == target_pid:
                    return child
            except Exception:
                continue

    # 3. Class / Name heuristic match (for single-instance / wrapper apps)
    cls_low = (app_class or "").strip().lower()
    if cls_low:
        cls_leaf = cls_low.split(".")[-1]
        for child in apps:
            try:
                cname = (child.get_name() or "").strip().lower()
                if not cname:
                    continue
                if cname == cls_low or cname == cls_leaf or cls_leaf in cname or cname in cls_low:
                    return child
            except Exception:
                continue

    return None


def get_node_shortcut(node):
    try:
        kb = node.get_key_binding(0)
        if kb:
            return normalize_shortcut(kb)
    except Exception:
        pass
    return ""


def is_node_enabled(node):
    try:
        ss = node.get_state_set()
        if ss:
            return ss.contains(Atspi.StateType.SENSITIVE) or ss.contains(Atspi.StateType.ENABLED)
    except Exception:
        pass
    return True


def is_node_checked(node):
    try:
        ss = node.get_state_set()
        if ss:
            return ss.contains(Atspi.StateType.CHECKED)
    except Exception:
        pass
    return False


def is_node_showing(node):
    try:
        ss = node.get_state_set()
        if ss:
            return ss.contains(Atspi.StateType.SHOWING) and ss.contains(Atspi.StateType.VISIBLE)
    except Exception:
        pass
    return False


def pick_best_frame(app_node, title=""):
    """Pick the active or title-matching top-level window/frame inside app_node."""
    if not app_node:
        return None
    try:
        cc = app_node.get_child_count()
    except Exception:
        return None

    frames = []
    for i in range(cc):
        try:
            ch = app_node.get_child_at_index(i)
            if ch:
                frames.append((i, ch))
        except Exception:
            continue

    if not frames:
        return app_node

    title_low = (title or "").strip().lower()
    if title_low:
        for idx, fr in frames:
            try:
                fn = (fr.get_name() or "").strip().lower()
                if fn and (fn == title_low or title_low in fn or fn in title_low):
                    return fr
            except Exception:
                continue

    for idx, fr in frames:
        try:
            ss = fr.get_state_set()
            if ss and ss.contains(Atspi.StateType.ACTIVE):
                return fr
        except Exception:
            continue

    return frames[0][1]


def find_all_menubars(node, depth=0, max_depth=18, results=None):
    if results is None:
        results = []
    if depth > max_depth or not node:
        return results
    try:
        role = node.get_role_name()
        if role in ("menu bar", "menubar") or node.get_role() == Atspi.Role.MENU_BAR:
            results.append(node)
            return results
    except Exception:
        return results

    try:
        count = node.get_child_count()
    except Exception:
        return results

    for i in range(min(count, 60)):
        try:
            child = node.get_child_at_index(i)
            if child:
                find_all_menubars(child, depth + 1, max_depth, results)
        except Exception:
            continue
    return results


def unwrap_transparent_children(node):
    """Unwrap popup menu / panel / filler / scroll pane containers."""
    try:
        count = node.get_child_count()
    except Exception:
        return []

    if count == 0:
        return []

    # Check if any child is a popup menu / menu container (even if there is also a label child)
    for idx in range(min(count, 20)):
        try:
            sub = node.get_child_at_index(idx)
            if sub and sub.get_role_name() in ("popup menu", "scroll pane", "viewport"):
                sub_count = sub.get_child_count()
                if sub_count > 0:
                    out = []
                    for sc in range(min(sub_count, 100)):
                        try:
                            sc_node = sub.get_child_at_index(sc)
                            if sc_node:
                                out.append((sc, sc_node))
                        except Exception:
                            continue
                    return out
        except Exception:
            continue

    if count == 1:
        try:
            sub = node.get_child_at_index(0)
            if sub and sub.get_role_name() in ("panel", "filler"):
                sub_count = sub.get_child_count()
                if sub_count > 0:
                    out = []
                    for sc in range(min(sub_count, 100)):
                        try:
                            sc_node = sub.get_child_at_index(sc)
                            if sc_node:
                                out.append((sc, sc_node))
                        except Exception:
                            continue
                    return out
        except Exception:
            pass

    out = []
    for idx in range(min(count, 100)):
        try:
            ch = node.get_child_at_index(idx)
            if ch:
                out.append((idx, ch))
        except Exception:
            continue
    return out


def build_atspi_menu_tree(node, current_path, depth=0, max_depth=6):
    if depth > max_depth or not node:
        return None
    try:
        raw_name = node.get_name() or ""
        role = node.get_role_name() or ""
    except Exception:
        return None

    name = clean_label(raw_name)
    is_sep = ("separator" in role) or (name == "-" and role == "menu item")
    if not is_sep and not name and role not in ("menu", "menu item", "check menu item", "radio menu item"):
        return None

    enabled = is_node_enabled(node)
    checked = is_node_checked(node)
    shortcut = get_node_shortcut(node)

    children = []
    for item_idx, child_node in unwrap_transparent_children(node):
        child_path = current_path + [item_idx]
        item_data = build_atspi_menu_tree(child_node, child_path, depth + 1, max_depth)
        if item_data:
            children.append(item_data)

    return {
        "label": name,
        "role": role,
        "path": current_path,
        "action": {"backend": "atspi_menubar", "path": current_path},
        "enabled": enabled,
        "checked": checked,
        "separator": is_sep,
        "shortcut": shortcut,
        "children": children,
    }


def get_atspi_menubar_menu(app_node, title=""):
    # Search best frame first, then entire app
    frame = pick_best_frame(app_node, title)
    menubars = find_all_menubars(frame, max_depth=18) if frame else []
    if not menubars:
        menubars = find_all_menubars(app_node, max_depth=18)
    if not menubars:
        return []

    # Prefer a menubar that has children and is showing
    best_mb = None
    best_score = -1
    for mb in menubars:
        try:
            cc = mb.get_child_count()
            if cc == 0:
                continue
            score = cc + (100 if is_node_showing(mb) else 0)
            if score > best_score:
                best_score = score
                best_mb = mb
        except Exception:
            continue

    if not best_mb:
        return []

    items = []
    try:
        top_count = best_mb.get_child_count()
    except Exception:
        return []

    for i in range(top_count):
        try:
            top_node = best_mb.get_child_at_index(i)
            if not top_node:
                continue
            item = build_atspi_menu_tree(top_node, [i], depth=0)
            if item and (item["label"] or item["children"]):
                items.append(item)
        except Exception:
            continue
    return items


# ── AT-SPI Hamburger / Toolbar Discovery ──────────────────────────────────────

MENU_BUTTON_KEYWORDS = (
    "main menu", "application menu", "open application menu", "open menu",
    "customize and control", "view options", "current folder menu",
    "more options", "more actions", "menu", "settings", "options"
)


def get_atspi_node_by_tree_path(root_node, tree_path):
    curr = root_node
    for idx in tree_path:
        try:
            if idx < 0 or idx >= curr.get_child_count():
                return None
            curr = curr.get_child_at_index(idx)
            if not curr:
                return None
        except Exception:
            return None
    return curr


def get_atspi_toolbar_and_hamburger_menu(app_node, title=""):
    """
    For apps that hide their menubar inside a hamburger menu / headerbar / toolbar
    (e.g. GTK4/libadwaita, modern Qt/KDE, Electron):
    1. Extract any populated popup/menu inside menu buttons / hamburger buttons.
    2. Extract clickable toolbar & headerbar buttons with their exact AT-SPI tree paths.
    """
    frame = pick_best_frame(app_node, title) or app_node
    if not frame:
        return []

    # Compute path from app_node to frame
    frame_prefix = []
    if frame != app_node:
        try:
            for i in range(app_node.get_child_count()):
                if app_node.get_child_at_index(i) == frame:
                    frame_prefix = [i]
                    break
        except Exception:
            pass

    menu_buttons = []
    toolbar_buttons = []
    seen_labels = set()

    def walk(node, path, depth, in_toolbar):
        if depth > 26 or not node:
            return
        try:
            role = node.get_role_name() or ""
            raw_name = node.get_name() or ""
            name = clean_label(raw_name)
            cc = node.get_child_count()
            n_act = node.get_n_actions()
        except Exception:
            return

        is_tb = in_toolbar or (role in ("tool bar", "toolbar", "header bar"))
        name_low = name.lower()

        # Check if this node is a menu/hamburger button or has a popup menu child
        is_menu_btn = (
            role in ("menu button", "menu")
            or (role in ("push button", "toggle button", "button") and any(k in name_low for k in MENU_BUTTON_KEYWORDS))
        )

        if is_menu_btn and name:
            # Check if it already has populated menu items inside a popup/menu/panel child
            sub_items = []
            for ci in range(min(cc, 20)):
                try:
                    ch = node.get_child_at_index(ci)
                    if ch and ch.get_role_name() in ("popup menu", "menu"):
                        for gi, gch in unwrap_transparent_children(ch):
                            built = build_atspi_menu_tree(gch, path + [ci, gi], depth=0)
                            if built and (built["label"] or built["separator"]):
                                # Rewrite backend to atspi_node since path is from app_node
                                built["action"] = {"backend": "atspi_node", "path": path + [ci, gi]}
                                sub_items.append(built)
                except Exception:
                    continue

            if sub_items:
                menu_buttons.append({
                    "label": name,
                    "role": role,
                    "path": path,
                    "action": {"backend": "atspi_node", "path": path},
                    "enabled": is_node_enabled(node),
                    "checked": False,
                    "separator": False,
                    "shortcut": get_node_shortcut(node),
                    "children": sub_items,
                })
                return

            if n_act > 0 and name_low not in seen_labels:
                seen_labels.add(name_low)
                toolbar_buttons.append({
                    "label": name,
                    "role": role,
                    "path": path,
                    "action": {"backend": "atspi_node", "path": path},
                    "enabled": is_node_enabled(node),
                    "checked": is_node_checked(node),
                    "separator": False,
                    "shortcut": get_node_shortcut(node),
                    "children": [],
                })
                return

        elif (is_tb or depth <= 22) and role in ("push button", "toggle button", "check box", "radio button") and n_act > 0 and name:
            # Skip generic window titlebar controls
            if name_low not in ("minimize", "maximize", "restore", "close", "unmaximize") and name_low not in seen_labels:
                seen_labels.add(name_low)
                toolbar_buttons.append({
                    "label": name,
                    "role": role,
                    "path": path,
                    "action": {"backend": "atspi_node", "path": path},
                    "enabled": is_node_enabled(node),
                    "checked": is_node_checked(node),
                    "separator": False,
                    "shortcut": get_node_shortcut(node),
                    "children": [],
                })

        for i in range(min(cc, 45)):
            try:
                ch = node.get_child_at_index(i)
                if ch:
                    walk(ch, path + [i], depth + 1, is_tb)
            except Exception:
                continue

    walk(frame, frame_prefix, 0, False)

    result = []
    for mb in menu_buttons:
        result.append(mb)
    if toolbar_buttons:
        result.append({
            "label": "Toolbar",
            "role": "menu",
            "path": [],
            "enabled": True,
            "checked": False,
            "separator": False,
            "shortcut": "",
            "children": toolbar_buttons[:30],
        })
    return result


# ── D-Bus Helpers (com.canonical.dbusmenu & org.gtk.Menus / org.gtk.Actions) ──

_SESSION_BUS = None


def get_session_bus():
    global _SESSION_BUS
    if _SESSION_BUS is None:
        try:
            _SESSION_BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        except Exception:
            return None
    return _SESSION_BUS


def dbus_call_sync(bus_name, obj_path, iface, method, params=None, reply_type=None, timeout_ms=400):
    bus = get_session_bus()
    if not bus:
        return None
    try:
        return bus.call_sync(
            bus_name, obj_path, iface, method,
            params, reply_type,
            Gio.DBusCallFlags.NONE, timeout_ms, None
        )
    except Exception:
        return None


def find_dbus_names_for_pid(pid, app_class=""):
    """Find unique D-Bus connection name(s) and matching well-known names for pid."""
    bus = get_session_bus()
    if not bus:
        return []

    family = set(get_pid_family(pid))
    res = dbus_call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames", None, GLib.VariantType("(as)"), 500)
    if not res:
        return []

    all_names = res.unpack()[0]
    well_known = [n for n in all_names if not n.startswith(":")]
    matches = []

    # Check well-known names first (fast, fewer calls)
    cls_low = (app_class or "").strip().lower()
    cls_leaf = cls_low.split(".")[-1] if cls_low else ""

    for name in well_known:
        # Filter obviously unrelated system services to keep it super fast
        nl = name.lower()
        if any(skip in nl for skip in ("org.freedesktop.systemd", "org.freedesktop.dbus", "org.a11y", "org.gtk.vfs", "org.freedesktop.portal")):
            continue
        pid_res = dbus_call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "GetConnectionUnixProcessID",
            GLib.Variant("(s)", (name,)), GLib.VariantType("(u)"), 150
        )
        if pid_res:
            npid = pid_res.unpack()[0]
            if npid in family:
                matches.append(name)
                continue
        if cls_leaf and (cls_low == nl or cls_leaf in nl):
            matches.append(name)

    # Also check unique names (:1.xxx) matching exact PID if no well-known names matched
    if not matches:
        unique_names = [n for n in all_names if n.startswith(":")]
        for name in unique_names:
            pid_res = dbus_call_sync(
                "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "GetConnectionUnixProcessID",
                GLib.Variant("(s)", (name,)), GLib.VariantType("(u)"), 80
            )
            if pid_res and pid_res.unpack()[0] in family:
                matches.append(name)

    return matches


def introspect_dbus_paths(bus_name, root_path="/", max_depth=4):
    """Collect object paths and their interfaces under bus_name."""
    found = {}
    queue = [(root_path, 0)]
    visited = set()

    while queue:
        path, depth = queue.pop(0)
        if path in visited or depth > max_depth:
            continue
        visited.add(path)

        timeout_ms = 80 if path == "/" else 150
        res = dbus_call_sync(bus_name, path, "org.freedesktop.DBus.Introspectable", "Introspect", None, GLib.VariantType("(s)"), timeout_ms)
        if not res:
            if path == "/":
                return found
            continue
        xml_str = res.unpack()[0]
        try:
            root = ET.fromstring(xml_str)
        except Exception:
            continue

        ifaces = [el.attrib.get("name", "") for el in root.findall("interface")]
        if ifaces:
            found[path] = set(ifaces)

        for node_el in root.findall("node"):
            child_name = node_el.attrib.get("name", "")
            if not child_name:
                continue
            child_path = f"/{child_name}" if path == "/" else f"{path}/{child_name}"
            queue.append((child_path, depth + 1))

    return found


def build_dbusmenu_tree(bus_name, obj_path, layout_node):
    """Convert com.canonical.dbusmenu GetLayout tuple (id, props, children) to Nimbush menu item."""
    item_id, props, raw_children = layout_node
    visible = props.get("visible", True)
    if not visible:
        return None

    item_type = props.get("type", "")
    raw_label = props.get("label", "")
    label = clean_label(raw_label)
    is_sep = (item_type == "separator") or (label == "-")
    enabled = bool(props.get("enabled", True))
    toggle_type = props.get("toggle-type", "")
    toggle_state = props.get("toggle-state", 0)
    checked = bool(toggle_type in ("checkmark", "radio") and toggle_state == 1)

    shortcut = ""
    raw_sc = props.get("shortcut")
    if isinstance(raw_sc, list) and raw_sc:
        first_combo = raw_sc[0]
        if isinstance(first_combo, list):
            shortcut = normalize_shortcut("+".join(str(x) for x in first_combo))

    children = []
    for ch in raw_children:
        # Each ch is a Variant wrapping (ia{sv}av)
        unpacked = ch.unpack() if hasattr(ch, "unpack") else ch
        built = build_dbusmenu_tree(bus_name, obj_path, unpacked)
        if built:
            children.append(built)

    return {
        "label": label,
        "role": "separator" if is_sep else "menu item",
        "path": [int(item_id)],
        "action": {"backend": "dbusmenu", "bus": bus_name, "path": obj_path, "id": int(item_id)},
        "enabled": enabled,
        "checked": checked,
        "separator": is_sep,
        "shortcut": shortcut,
        "children": children,
    }


def get_dbusmenu_items(bus_name, obj_path):
    res = dbus_call_sync(
        bus_name, obj_path, "com.canonical.dbusmenu", "GetLayout",
        GLib.Variant("(iias)", (0, -1, ["label", "enabled", "visible", "shortcut", "type", "toggle-type", "toggle-state", "children-display"])),
        None, 600
    )
    if not res:
        return []
    _, root_layout = res.unpack()
    built = build_dbusmenu_tree(bus_name, obj_path, root_layout)
    if not built:
        return []
    return built.get("children", [])


def humanize_action_name(name):
    s = str(name or "").replace("_", "-").strip()
    if "." in s:
        s = s.split(".", 1)[1]
    words = [w for w in s.split("-") if w]
    return " ".join(w.capitalize() for w in words)


def categorize_gtk_action(action_name):
    n = action_name.lower()
    if any(k in n for k in ("new", "open", "save", "close", "quit", "kill", "clone", "print", "export", "import")):
        return "File"
    if any(k in n for k in ("undo", "redo", "cut", "copy", "paste", "select", "find", "search", "delete", "rename", "pref", "setting")):
        return "Edit"
    if any(k in n for k in ("view", "zoom", "sidebar", "fullscreen", "sort", "layout", "show", "toggle", "theme", "dark", "grid", "list")):
        return "View"
    if any(k in n for k in ("tab", "window", "go-", "back", "forward", "home", "up", "restore", "location", "focus")):
        return "Window"
    if any(k in n for k in ("help", "about", "shortcut", "doc", "manual")):
        return "Help"
    return "Actions"


GTK_ACTION_SKIP = {"kill", "search-settings"}
GTK_ACTION_LABELS = {
    "shortcuts": "Keyboard Shortcuts",
    "close-current-view": "Close Tab",
    "show-file-transfers": "File Transfers",
    "current-location-menu": "Location Options",
}
GTK_ACTION_SHORTCUTS = {
    "new-window": "Ctrl+N",
    "new-tab": "Ctrl+T",
    "close-current-view": "Ctrl+W",
    "restore-tab": "Ctrl+Shift+T",
    "undo": "Ctrl+Z",
    "redo": "Ctrl+Shift+Z",
    "preferences": "Ctrl+,",
    "shortcuts": "Ctrl+?",
    "help": "F1",
    "quit": "Ctrl+Q",
    "toggle-sidebar": "F9",
}


def get_gtk_actions_menu(bus_name, paths_map):
    """Build structured macOS-style menus from org.gtk.Actions interfaces."""
    buckets = {"File": [], "Edit": [], "View": [], "Window": [], "Actions": [], "Help": []}
    seen = set()

    # Sort so window paths come first, then app path
    sorted_paths = sorted(paths_map.keys(), key=lambda p: (0 if "/window/" in p else 1, p))

    for obj_path in sorted_paths:
        if "org.gtk.Actions" not in paths_map[obj_path]:
            continue
        res = dbus_call_sync(bus_name, obj_path, "org.gtk.Actions", "DescribeAll", None, GLib.VariantType("(a{s(bgav)})"), 400)
        if not res:
            continue
        actions_dict = res.unpack()[0]
        for act_name, (enabled, param_type, state_list) in actions_dict.items():
            # Skip internal parameterized navigation actions that require args (unless boolean/empty)
            if param_type and param_type not in ("", "b"):
                continue
            key = act_name.lower()
            if key in seen or key in GTK_ACTION_SKIP:
                continue
            seen.add(key)

            checked = False
            if state_list and isinstance(state_list[0], bool):
                checked = bool(state_list[0])

            cat = categorize_gtk_action(act_name)
            buckets[cat].append({
                "label": GTK_ACTION_LABELS.get(key, humanize_action_name(act_name)),
                "role": "check menu item" if state_list else "menu item",
                "path": [act_name],
                "action": {
                    "backend": "gtk_action",
                    "bus": bus_name,
                    "path": obj_path,
                    "name": act_name,
                    "param_type": param_type,
                },
                "enabled": bool(enabled),
                "checked": checked,
                "separator": False,
                "shortcut": GTK_ACTION_SHORTCUTS.get(key, ""),
                "children": [],
            })

    menu = []
    for cat in ("File", "Edit", "View", "Window", "Actions", "Help"):
        items = buckets[cat]
        if items:
            items.sort(key=lambda x: x["label"])
            menu.append({
                "label": cat,
                "role": "menu",
                "path": [],
                "enabled": True,
                "checked": False,
                "separator": False,
                "shortcut": "",
                "children": items,
            })
    return menu


def get_dbus_app_menu(pid, app_class=""):
    bus_names = find_dbus_names_for_pid(pid, app_class)
    if not bus_names:
        return None, ""

    for bname in bus_names:
        paths_map = introspect_dbus_paths(bname, "/", max_depth=5)
        if not paths_map:
            continue

        # 1. com.canonical.dbusmenu (ignore system tray NotificationItem / StatusNotifierItem menus)
        for p, ifaces in paths_map.items():
            p_low = p.lower()
            if "notificationitem" in p_low or "statusnotifieritem" in p_low:
                continue
            if "com.canonical.dbusmenu" in ifaces:
                items = get_dbusmenu_items(bname, p)
                if items and any(it.get("children") for it in items):
                    return items, "dbusmenu"

        # 2. org.gtk.Actions (GTK3/GTK4/libadwaita)
        if any("org.gtk.Actions" in ifaces for ifaces in paths_map.values()):
            items = get_gtk_actions_menu(bname, paths_map)
            if items:
                return items, "gtk_actions"

    return None, ""


# ── Unified Menu Fetch & Trigger ──────────────────────────────────────────────

def get_application_menu(pid, app_class="", title=""):
    app_node = find_app_node(pid, app_class, title)

    # 1. AT-SPI Native MenuBar (deep search)
    if app_node:
        items = get_atspi_menubar_menu(app_node, title)
        if items:
            return items, "atspi_menubar"

    # 2. D-Bus Menu (com.canonical.dbusmenu / org.gtk.Actions)
    dbus_items, dbus_src = get_dbus_app_menu(pid, app_class)
    if dbus_items:
        return dbus_items, dbus_src

    # 3. AT-SPI Hamburger / Toolbar Discovery (only when D-Bus didn't yield a menu)
    tb_items = get_atspi_toolbar_and_hamburger_menu(app_node, title) if app_node else []
    if tb_items:
        return tb_items, "atspi_toolbar"

    return [], ""


def resolve_menubar_path(menubar, path):
    if not menubar or not path:
        return None
    current = menubar
    for idx in path:
        try:
            children = unwrap_transparent_children(current)
            matched = None
            for c_idx, c_node in children:
                if c_idx == idx:
                    matched = c_node
                    break
            if not matched:
                return None
            current = matched
        except Exception:
            return None
    return current


def trigger_action(pid, action=None, path=None, app_class="", title=""):
    if not action and path:
        action = {"backend": "atspi_menubar", "path": path}
    if not action:
        return False

    backend = action.get("backend", "atspi_menubar")

    if backend == "dbusmenu":
        bname = action.get("bus")
        obj_path = action.get("path")
        item_id = action.get("id")
        if bname and obj_path and item_id is not None:
            def _call():
                dbus_call_sync(
                    bname, obj_path, "com.canonical.dbusmenu", "Event",
                    GLib.Variant("(isvu)", (int(item_id), "clicked", GLib.Variant("s", ""), 0)),
                    None, 1000
                )
            threading.Thread(target=_call, daemon=True).start()
            return True
        return False

    if backend == "gtk_action":
        bname = action.get("bus")
        obj_path = action.get("path")
        act_name = action.get("name")
        if bname and obj_path and act_name:
            def _call():
                dbus_call_sync(
                    bname, obj_path, "org.gtk.Actions", "Activate",
                    GLib.Variant("(sava{sv})", (act_name, [], {})),
                    None, 1000
                )
            threading.Thread(target=_call, daemon=True).start()
            return True
        return False

    if backend in ("atspi_menubar", "atspi_node"):
        app_node = find_app_node(pid, app_class, title)
        if not app_node:
            return False

        target = None
        if backend == "atspi_menubar":
            frame = pick_best_frame(app_node, title)
            menubars = find_all_menubars(frame, max_depth=18) if frame else []
            if not menubars:
                menubars = find_all_menubars(app_node, max_depth=18)
            for mb in menubars:
                target = resolve_menubar_path(mb, action.get("path", []))
                if target:
                    break
        else:
            target = get_atspi_node_by_tree_path(app_node, action.get("path", []))

        if not target:
            return False

        def _invoke():
            try:
                target.do_action(0)
            except Exception:
                pass
        threading.Thread(target=_invoke, daemon=True).start()
        return True

    return False


# ── CLI & Daemon ──────────────────────────────────────────────────────────────

def run_standalone_dump(pid, app_class="", title=""):
    print(f"=== Global Menu Dump for PID {pid} ({app_class or 'unknown'}) ===")
    items, src = get_application_menu(pid, app_class, title)
    print(f"[+] Source: {src or 'none'} | Top-level items: {len(items)}")
    print(json.dumps(items, indent=2))


def run_daemon():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception as e:
            print(json.dumps({"type": "error", "msg": f"Invalid JSON: {e}"}), flush=True)
            continue

        cmd = req.get("cmd")
        if cmd == "ping":
            print(json.dumps({"type": "pong"}), flush=True)

        elif cmd == "menu":
            pid = req.get("pid")
            app_class = req.get("app_class", "")
            title = req.get("title", "")
            if not pid:
                print(json.dumps({"type": "error", "msg": "Missing pid"}), flush=True)
                continue
            items, src = get_application_menu(pid, app_class, title)
            print(json.dumps({
                "type": "menu",
                "pid": pid,
                "source": src,
                "available": len(items) > 0,
                "items": items
            }), flush=True)

        elif cmd == "active":
            win = get_active_hyprland_window()
            if not win:
                print(json.dumps({"type": "menu", "pid": 0, "source": "", "available": False, "items": []}), flush=True)
                continue
            items, src = get_application_menu(win["pid"], win["app_class"], win["title"])
            print(json.dumps({
                "type": "menu",
                "pid": win["pid"],
                "source": src,
                "available": len(items) > 0,
                "items": items
            }), flush=True)

        elif cmd == "trigger":
            pid = req.get("pid")
            action = req.get("action")
            path = req.get("path")
            app_class = req.get("app_class", "")
            title = req.get("title", "")
            if not pid or (not action and path is None):
                print(json.dumps({"type": "error", "msg": "Missing pid or action/path"}), flush=True)
                continue
            ok = trigger_action(pid, action=action, path=path, app_class=app_class, title=title)
            print(json.dumps({
                "type": "trigger",
                "pid": pid,
                "success": ok
            }), flush=True)

        else:
            print(json.dumps({"type": "error", "msg": f"Unknown command: {cmd}"}), flush=True)


def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "active":
            win = get_active_hyprland_window()
            if not win:
                print("No active Hyprland window found.")
                sys.exit(1)
            run_standalone_dump(win["pid"], win["app_class"], win["title"])
            return
        elif arg == "--daemon":
            run_daemon()
            return
        else:
            try:
                pid = int(arg)
                run_standalone_dump(pid)
                return
            except ValueError:
                pass

    print("Usage:")
    print("  python atspi_menu.py <pid>    - Dump menu for PID")
    print("  python atspi_menu.py active   - Dump menu for active Hyprland window")
    print("  python atspi_menu.py --daemon - Run JSON-lines daemon mode")


if __name__ == "__main__":
    main()
