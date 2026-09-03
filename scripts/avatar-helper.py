#!/usr/bin/env python3
"""
Avatar helper script for Quickshell.
Synchronizes user profile pictures with:
1. Linux AccountsService DBus (org.freedesktop.Accounts.User.SetIconFile) -> /var/lib/AccountsService/icons/<user>
   (Read by GDM, SDDM, Greetd, LightDM, GNOME Control Center, etc.)
2. Home directory standard files (~/.face, ~/.face.icon)
3. Temporary quickshell cache link
"""

import os
import sys
import json
import shutil
import subprocess
import re

HOME = os.path.expanduser("~")
USER = os.environ.get("USER") or os.path.basename(HOME)
UID = os.getuid()

def clean_path(path_str):
    if not path_str:
        return ""
    p = path_str.strip()
    if p.startswith("file://"):
        p = p[7:]
    return os.path.abspath(os.path.expanduser(p))

def call_accounts_service_set(icon_path):
    """Call org.freedesktop.Accounts.User.SetIconFile via gdbus or dbus-send."""
    target = icon_path if icon_path else ""
    # Try gdbus first
    try:
        res = subprocess.run([
            "gdbus", "call", "--system",
            "--dest", "org.freedesktop.Accounts",
            "--object-path", f"/org/freedesktop/Accounts/User{UID}",
            "--method", "org.freedesktop.Accounts.User.SetIconFile",
            target
        ], capture_output=True, text=True, timeout=3.0)
        if res.returncode == 0:
            return True
    except Exception:
        pass

    # Fallback to dbus-send
    try:
        res = subprocess.run([
            "dbus-send", "--system", "--print-reply",
            "--dest=org.freedesktop.Accounts",
            f"/org/freedesktop/Accounts/User{UID}",
            "org.freedesktop.Accounts.User.SetIconFile",
            f"string:{target}"
        ], capture_output=True, text=True, timeout=3.0)
        return res.returncode == 0
    except Exception:
        pass

    return False

def call_accounts_service_get():
    """Query IconFile property from org.freedesktop.Accounts.User."""
    try:
        res = subprocess.run([
            "gdbus", "call", "--system",
            "--dest", "org.freedesktop.Accounts",
            "--object-path", f"/org/freedesktop/Accounts/User{UID}",
            "--method", "org.freedesktop.DBus.Properties.Get",
            "org.freedesktop.Accounts.User", "IconFile"
        ], capture_output=True, text=True, timeout=3.0)
        if res.returncode == 0 and res.stdout:
            m = re.search(r"'([^']*)'", res.stdout)
            if m:
                p = m.group(1).strip()
                if p and os.path.exists(p):
                    return p
    except Exception:
        pass
    return ""

def update_home_face_files(src_path):
    """Copy given avatar image to ~/.face and ~/.face.icon with 0644 permissions."""
    face_path = os.path.join(HOME, ".face")
    face_icon_path = os.path.join(HOME, ".face.icon")
    if not src_path or not os.path.isfile(src_path):
        return False
    try:
        shutil.copy2(src_path, face_path)
        os.chmod(face_path, 0o644)
    except Exception as e:
        sys.stderr.write(f"Warning copying to .face: {e}\n")

    try:
        if os.path.exists(face_icon_path) or os.path.islink(face_icon_path):
            try:
                os.remove(face_icon_path)
            except Exception:
                pass
        shutil.copy2(src_path, face_icon_path)
        os.chmod(face_icon_path, 0o644)
    except Exception as e:
        sys.stderr.write(f"Warning copying to .face.icon: {e}\n")

    return True

def remove_home_face_files():
    """Remove ~/.face and ~/.face.icon files."""
    for fn in [".face", ".face.icon"]:
        p = os.path.join(HOME, fn)
        if os.path.exists(p) or os.path.islink(p):
            try:
                os.remove(p)
            except Exception as e:
                sys.stderr.write(f"Warning removing {fn}: {e}\n")

def update_tmp_cache_link(src_path):
    """Creates a convenient symlink in /tmp for quick access."""
    tmp_link = f"/tmp/quickshell_avatar_{USER}.jpg"
    if not src_path or not os.path.isfile(src_path):
        if os.path.exists(tmp_link) or os.path.islink(tmp_link):
            try:
                os.remove(tmp_link)
            except Exception:
                pass
        return ""
    try:
        if os.path.exists(tmp_link) or os.path.islink(tmp_link):
            os.remove(tmp_link)
        os.symlink(src_path, tmp_link)
    except Exception:
        pass
    return tmp_link

def cmd_set(raw_path):
    path = clean_path(raw_path)
    if not path or not os.path.isfile(path):
        print(json.dumps({"success": False, "error": "File does not exist or is not a file"}))
        return

    update_home_face_files(path)
    dbus_ok = call_accounts_service_set(path)
    tmp_path = update_tmp_cache_link(path)

    print(json.dumps({
        "success": True,
        "path": path,
        "systemSynced": True,
        "accountsService": dbus_ok,
        "fileUrl": f"file://{path}"
    }))

def cmd_clear():
    remove_home_face_files()
    dbus_ok = call_accounts_service_set("")
    update_tmp_cache_link("")

    print(json.dumps({
        "success": True,
        "cleared": True,
        "accountsService": dbus_ok
    }))

def cmd_get():
    # 1. Check AccountsService DBus
    acct_icon = call_accounts_service_get()
    if acct_icon and os.path.isfile(acct_icon):
        print(json.dumps({"path": acct_icon, "fileUrl": f"file://{acct_icon}", "source": "accountsservice"}))
        return

    # 2. Check /var/lib/AccountsService/icons/<user>
    acct_file = f"/var/lib/AccountsService/icons/{USER}"
    if os.path.isfile(acct_file):
        print(json.dumps({"path": acct_file, "fileUrl": f"file://{acct_file}", "source": "accountsservice_file"}))
        return

    # 3. Check ~/.face or ~/.face.icon
    for f in [".face", ".face.icon", ".face.png", ".face.jpg"]:
        hp = os.path.join(HOME, f)
        if os.path.isfile(hp):
            print(json.dumps({"path": hp, "fileUrl": f"file://{hp}", "source": "home"}))
            return

    print(json.dumps({"path": "", "fileUrl": "", "source": "none"}))

def cmd_sync(custom_path=""):
    """
    If custom_path is provided and exists, sync it everywhere.
    Otherwise, if AccountsService or ~/.face exists, ensure consistency.
    """
    if custom_path:
        cp = clean_path(custom_path)
        if cp and os.path.isfile(cp):
            cmd_set(cp)
            return

    # No custom path supplied -> inspect system
    acct_icon = call_accounts_service_get()
    face_path = os.path.join(HOME, ".face")

    if acct_icon and os.path.isfile(acct_icon):
        update_home_face_files(acct_icon)
        update_tmp_cache_link(acct_icon)
        print(json.dumps({"success": True, "synced": "from_accountsservice", "path": acct_icon, "fileUrl": f"file://{acct_icon}"}))
        return

    if os.path.isfile(face_path):
        call_accounts_service_set(face_path)
        update_tmp_cache_link(face_path)
        print(json.dumps({"success": True, "synced": "from_face", "path": face_path, "fileUrl": f"file://{face_path}"}))
        return

    print(json.dumps({"success": True, "synced": "none", "path": "", "fileUrl": ""}))

def main():
    if len(sys.argv) < 2:
        cmd_get()
        return

    action = sys.argv[1].lower()
    if action == "set":
        if len(sys.argv) < 3:
            print(json.dumps({"success": False, "error": "Missing path argument"}))
            return
        cmd_set(sys.argv[2])
    elif action == "clear":
        cmd_clear()
    elif action == "get":
        cmd_get()
    elif action == "sync":
        cp = sys.argv[2] if len(sys.argv) > 2 else ""
        cmd_sync(cp)
    else:
        cmd_get()

if __name__ == "__main__":
    main()
