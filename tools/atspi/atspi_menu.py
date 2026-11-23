#!/usr/bin/env python3
"""
atspi_menu.py - AT-SPI Menu Bridge for Nimbush Global Menu
Supports standalone CLI inspection and JSON-lines daemon mode for Quickshell.
"""

import sys
import os
import json
import time
import subprocess
import threading

# Ensure AT-SPI accessibility is enabled on user bus
def enable_accessibility():
    try:
        subprocess.run(
            ["busctl", "--user", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", "IsEnabled", "b", "true"],
            capture_output=True,
            timeout=2.0
        )
    except Exception:
        pass

enable_accessibility()

try:
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi, GLib
    Atspi.init()
except Exception as e:
    sys.stderr.write(f"[atspi_menu] Failed to initialize AT-SPI: {e}\n")
    sys.stderr.flush()
    if "--daemon" in sys.argv or not sys.stdin.isatty():
        # In daemon mode, write error JSON
        print(json.dumps({"type": "error", "msg": f"Failed to initialize AT-SPI: {e}"}), flush=True)
    sys.exit(1)


def get_active_hyprland_pid():
    try:
        res = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=1.5)
        if res.returncode == 0 and res.stdout.strip():
            data = json.loads(res.stdout)
            pid = data.get("pid")
            if pid and pid > 0:
                return pid
    except Exception as e:
        sys.stderr.write(f"[atspi_menu] Error getting active window from hyprctl: {e}\n")
    return None


def find_app_node_by_pid(pid):
    try:
        desktop_count = Atspi.get_desktop_count()
    except Exception:
        return None

    for d in range(desktop_count):
        try:
            desktop = Atspi.get_desktop(d)
            if not desktop:
                continue
            child_count = desktop.get_child_count()
            for i in range(child_count):
                try:
                    child = desktop.get_child_at_index(i)
                    if not child:
                        continue
                    if child.get_process_id() == pid:
                        return child
                except Exception:
                    continue
        except Exception:
            continue
    return None


def find_menubar(node, depth=0, max_depth=6):
    if depth > max_depth or not node:
        return None
    try:
        role = node.get_role_name()
        if role in ("menu bar", "menubar") or node.get_role() == Atspi.Role.MENU_BAR:
            return node
    except Exception:
        return None

    try:
        count = node.get_child_count()
    except Exception:
        return None

    for i in range(count):
        try:
            child = node.get_child_at_index(i)
            found = find_menubar(child, depth + 1, max_depth)
            if found:
                return found
        except Exception:
            continue
    return None


def get_node_shortcut(node):
    try:
        # Check accessible keybinding
        kb = node.get_key_binding(0)
        if kb:
            return str(kb).strip()
    except Exception:
        pass
    return ""


def is_node_enabled(node):
    try:
        state_set = node.get_state_set()
        if state_set:
            # Check SENSITIVE and ENABLED
            sensitive = state_set.contains(Atspi.StateType.SENSITIVE)
            enabled = state_set.contains(Atspi.StateType.ENABLED)
            return sensitive or enabled
    except Exception:
        pass
    return True


def is_node_checked(node):
    try:
        state_set = node.get_state_set()
        if state_set:
            return state_set.contains(Atspi.StateType.CHECKED)
    except Exception:
        pass
    return False


def build_menu_tree(node, current_path=None, depth=0, max_depth=5):
    if current_path is None:
        current_path = []
    if depth > max_depth or not node:
        return None

    try:
        name = node.get_name() or ""
        role = node.get_role_name() or ""
    except Exception:
        return None

    is_sep = ("separator" in role) or (name == "-" and role == "menu item")
    enabled = is_node_enabled(node)
    checked = is_node_checked(node)
    shortcut = get_node_shortcut(node)

    # Submenu containers (e.g. "popup menu" child under "File")
    # If this node is a popup menu container, pass its children up
    try:
        raw_children_count = node.get_child_count()
    except Exception:
        raw_children_count = 0

    children = []
    
    # If it's a menu or menu item that has a single "popup menu" child, unpack that popup menu
    actual_child_nodes = []
    if raw_children_count == 1:
        try:
            sub = node.get_child_at_index(0)
            if sub and sub.get_role_name() == "popup menu":
                sub_count = sub.get_child_count()
                for sc in range(sub_count):
                    try:
                        sc_node = sub.get_child_at_index(sc)
                        if sc_node:
                            actual_child_nodes.append((sc, sc_node, True))
                    except Exception:
                        continue
            else:
                actual_child_nodes.append((0, sub, False))
        except Exception:
            pass
    elif raw_children_count > 0:
        for idx in range(raw_children_count):
            try:
                ch = node.get_child_at_index(idx)
                if ch:
                    actual_child_nodes.append((idx, ch, False))
            except Exception:
                continue

    for item_idx, child_node, is_popup_child in actual_child_nodes:
        # The child's path in our addressing scheme
        child_path = current_path + [item_idx]
        item_data = build_menu_tree(child_node, child_path, depth + 1, max_depth)
        if item_data:
            children.append(item_data)

    item = {
        "label": name,
        "role": role,
        "path": current_path,
        "enabled": enabled,
        "checked": checked,
        "separator": is_sep,
        "shortcut": shortcut,
        "children": children
    }
    return item


def get_application_menu(pid):
    app = find_app_node_by_pid(pid)
    if not app:
        return []

    menubar = find_menubar(app)
    if not menubar:
        return []

    try:
        top_count = menubar.get_child_count()
    except Exception:
        return []

    items = []
    for i in range(top_count):
        try:
            top_node = menubar.get_child_at_index(i)
            if not top_node:
                continue
            item = build_menu_tree(top_node, current_path=[i], depth=0)
            if item:
                items.append(item)
        except Exception:
            continue
    return items


def resolve_node_at_path(menubar, path):
    """
    Traverse from menubar along the path indices to find target Accessible node.
    Accounts for transparent 'popup menu' nodes inserted by Qt/GTK.
    """
    if not menubar or not path:
        return None

    current = menubar
    for idx in path:
        try:
            # If current has a single popup menu child, drill into it first
            if current.get_child_count() == 1:
                child0 = current.get_child_at_index(0)
                if child0 and child0.get_role_name() == "popup menu":
                    current = child0
            
            if idx >= current.get_child_count():
                return None
            current = current.get_child_at_index(idx)
            if not current:
                return None
        except Exception:
            return None
    return current


def trigger_menu_item(pid, path):
    """
    Trigger menu item action asynchronously so that modal dialogs do not block the daemon.
    """
    app = find_app_node_by_pid(pid)
    if not app:
        return False

    menubar = find_menubar(app)
    if not menubar:
        return False

    target = resolve_node_at_path(menubar, path)
    if not target:
        return False

    def _invoke():
        try:
            n_actions = target.get_n_actions()
            if n_actions > 0:
                target.do_action(0)
            else:
                # Try clicking or pressing if action count reported 0
                target.do_action(0)
        except Exception as e:
            # Timed out or application blocked on dialog
            pass

    t = threading.Thread(target=_invoke, daemon=True)
    t.start()
    return True


def run_standalone_dump(pid):
    print(f"=== AT-SPI Menu Dump for PID {pid} ===")
    app = find_app_node_by_pid(pid)
    if not app:
        print(f"[-] No AT-SPI application node found for PID {pid}.")
        print("    Ensure QT_ACCESSIBILITY=1 or GTK_A11Y=atspi was set before launching the app,")
        print("    and that org.a11y.Status.IsEnabled is true.")
        return

    print(f"[+] Found app node: {app.get_name()!r} (role: {app.get_role_name()})")
    menubar = find_menubar(app)
    if not menubar:
        print("[-] No menu bar found in application hierarchy.")
        return

    print(f"[+] Found menu bar: {menubar.get_name()!r} (children: {menubar.get_child_count()})")
    menu = get_application_menu(pid)
    print(json.dumps(menu, indent=2))


def run_daemon():
    # Process commands from stdin line by line
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
            if not pid:
                print(json.dumps({"type": "error", "msg": "Missing pid"}), flush=True)
                continue
            items = get_application_menu(pid)
            print(json.dumps({
                "type": "menu",
                "pid": pid,
                "available": len(items) > 0,
                "items": items
            }), flush=True)

        elif cmd == "active":
            pid = get_active_hyprland_pid()
            if not pid:
                print(json.dumps({"type": "menu", "pid": 0, "available": False, "items": []}), flush=True)
                continue
            items = get_application_menu(pid)
            print(json.dumps({
                "type": "menu",
                "pid": pid,
                "available": len(items) > 0,
                "items": items
            }), flush=True)

        elif cmd == "trigger":
            pid = req.get("pid")
            path = req.get("path")
            if not pid or path is None:
                print(json.dumps({"type": "error", "msg": "Missing pid or path"}), flush=True)
                continue
            ok = trigger_menu_item(pid, path)
            print(json.dumps({
                "type": "trigger",
                "pid": pid,
                "path": path,
                "success": ok
            }), flush=True)

        else:
            print(json.dumps({"type": "error", "msg": f"Unknown command: {cmd}"}), flush=True)


def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg == "active":
            pid = get_active_hyprland_pid()
            if not pid:
                print("No active Hyprland window found.")
                sys.exit(1)
            run_standalone_dump(pid)
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

    if sys.stdin.isatty():
        print("Usage:")
        print("  python atspi_menu.py <pid>    - Dump menu for PID")
        print("  python atspi_menu.py active   - Dump menu for active Hyprland window")
        print("  python atspi_menu.py --daemon - Run JSON-lines daemon mode")
    else:
        run_daemon()


if __name__ == "__main__":
    main()
