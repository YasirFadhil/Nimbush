#!/usr/bin/env python3
import sys
import os
import shutil
import subprocess
import time
import re
import urllib.parse

def pick_via_zenity():
    zenity_bin = shutil.which("zenity")
    if not zenity_bin:
        if shutil.which("nix-shell"):
            try:
                cmd = ["nix-shell", "-p", "zenity", "--run", "zenity --file-selection --title='Select Wallpaper Image'"]
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
                if proc.returncode == 0:
                    selected = proc.stdout.strip()
                    if selected and os.path.isfile(selected):
                        return selected
            except Exception:
                pass
        return None
    try:
        pictures_dir = os.path.expanduser("~/Pictures")
        cmd = [
            zenity_bin,
            "--file-selection",
            "--title=Select Wallpaper Image",
            "--file-filter=Image files (*.jpg, *.png, *.webp, *.jpeg, *.gif, *.bmp, *.avif, *.svg) | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.avif *.svg *.JPG *.JPEG *.PNG *.WEBP",
            "--file-filter=All files (*.*) | *"
        ]
        if os.path.isdir(pictures_dir):
            cmd.append(f"--filename={pictures_dir}/")
        
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            selected = proc.stdout.strip()
            if selected and os.path.isfile(selected):
                return selected
    except Exception:
        pass
    return None

def pick_via_kdialog():
    if not shutil.which("kdialog"):
        return None
    try:
        pictures_dir = os.path.expanduser("~/Pictures")
        start_dir = pictures_dir if os.path.isdir(pictures_dir) else os.path.expanduser("~")
        cmd = [
            "kdialog",
            "--getopenfilename",
            start_dir,
            "Image files (*.jpg *.jpeg *.png *.webp *.gif *.bmp *.avif *.svg);;All files (*)"
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            selected = proc.stdout.strip()
            if selected and os.path.isfile(selected):
                return selected
    except Exception:
        pass
    return None

def pick_via_yad():
    if not shutil.which("yad"):
        return None
    try:
        pictures_dir = os.path.expanduser("~/Pictures")
        cmd = [
            "yad",
            "--file",
            "--title=Select Wallpaper Image",
            "--file-filter=Image files | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.avif *.svg *.JPG *.PNG",
            "--file-filter=All files | *"
        ]
        if os.path.isdir(pictures_dir):
            cmd.append(f"--filename={pictures_dir}/")
        
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode == 0:
            selected = proc.stdout.strip()
            if selected and os.path.isfile(selected):
                return selected
    except Exception:
        pass
    return None

def pick_via_gdbus():
    """Fallback via gdbus tool to talk with org.freedesktop.portal.Desktop (no python-dbus required)."""
    if not shutil.which("gdbus"):
        return None
    token = f"qs_wp_{int(time.time())}_{os.getpid()}"
    monitor_proc = None
    try:
        monitor_proc = subprocess.Popen(
            ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.portal.Desktop"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True
        )
        time.sleep(0.05)

        options = f"{{'handle_token': <'{token}'>, 'multiple': <false>}}"
        call_res = subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", "org.freedesktop.portal.Desktop",
                "--object-path", "/org/freedesktop/portal/desktop",
                "--method", "org.freedesktop.portal.FileChooser.OpenFile",
                "", "Select Wallpaper Image", options
            ],
            capture_output=True,
            text=True,
            timeout=5
        )
        if call_res.returncode != 0:
            return None

        handle_match = re.search(r"/org/freedesktop/portal/desktop/request/[^\s',]+", call_res.stdout)
        target_handle = handle_match.group(0) if handle_match else token

        selected_file = None
        start_time = time.time()
        buf = ""
        while time.time() - start_time < 300:
            line = monitor_proc.stdout.readline()
            if not line:
                if monitor_proc.poll() is not None:
                    break
                continue
            buf += line
            if target_handle in buf and "Response" in buf:
                m = re.search(r"file://([^\s'\">\]]+)", buf)
                if m:
                    path = urllib.parse.unquote(m.group(1))
                    if not path.startswith("/"):
                        path = "/" + path
                    if os.path.exists(path):
                        selected_file = path
                        break
                if "uint32 1" in buf or "uint32 2" in buf or "Response (1" in buf or "Response (2" in buf:
                    break
                if "}" in line or ")" in line:
                    break

        return selected_file
    except Exception:
        return None
    finally:
        if monitor_proc:
            try:
                monitor_proc.terminate()
                monitor_proc.wait(timeout=0.5)
            except Exception:
                try:
                    monitor_proc.kill()
                except Exception:
                    pass

def pick_via_gtk():
    try:
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk

        dialog = Gtk.FileChooserDialog(
            title="Select Wallpaper Image",
            parent=None,
            action=Gtk.FileChooserAction.OPEN
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK
        )

        filter_img = Gtk.FileFilter()
        filter_img.set_name("Image files (*.jpg, *.png, *.webp, *.jpeg, *.gif, *.bmp, *.avif, *.svg)")
        filter_img.add_mime_type("image/png")
        filter_img.add_mime_type("image/jpeg")
        filter_img.add_mime_type("image/webp")
        filter_img.add_mime_type("image/gif")
        filter_img.add_mime_type("image/bmp")
        filter_img.add_mime_type("image/avif")
        filter_img.add_mime_type("image/svg+xml")
        filter_img.add_pattern("*.png")
        filter_img.add_pattern("*.jpg")
        filter_img.add_pattern("*.jpeg")
        filter_img.add_pattern("*.webp")
        filter_img.add_pattern("*.gif")
        filter_img.add_pattern("*.bmp")
        filter_img.add_pattern("*.avif")
        filter_img.add_pattern("*.svg")
        dialog.add_filter(filter_img)

        filter_all = Gtk.FileFilter()
        filter_all.set_name("All files (*.*)")
        filter_all.add_pattern("*")
        dialog.add_filter(filter_all)

        pictures_dir = os.path.expanduser("~/Pictures")
        if os.path.isdir(pictures_dir):
            dialog.set_current_folder(pictures_dir)

        dialog.set_modal(True)
        response = dialog.run()
        selected = None
        if response == Gtk.ResponseType.OK:
            selected = dialog.get_filename()
        dialog.destroy()
        while Gtk.events_pending():
            Gtk.main_iteration()
        return selected
    except Exception:
        return None

def pick_via_portal():
    try:
        import dbus
        from dbus.mainloop.glib import DBusGMainLoop
        from gi.repository import GLib

        DBusGMainLoop(set_as_default=True)
        bus = dbus.SessionBus()
        loop = GLib.MainLoop()

        portal = bus.get_object('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop')
        file_chooser = dbus.Interface(portal, 'org.freedesktop.portal.FileChooser')

        selected_file = [None]

        def on_response(response, results):
            try:
                if response == 0 and 'uris' in results:
                    for uri in results['uris']:
                        uri_str = str(uri)
                        if uri_str.startswith('file://'):
                            path = urllib.parse.unquote(uri_str[7:])
                            if os.path.exists(path):
                                selected_file[0] = path
                                break
            finally:
                loop.quit()

        token = f"wp_{int(time.time())}"
        options = {
            'handle_token': token,
            'multiple': False
        }

        bus.add_signal_receiver(
            on_response,
            dbus_interface='org.freedesktop.portal.Request',
            signal_name='Response'
        )

        file_chooser.OpenFile('', 'Select Wallpaper Image', options)
        loop.run()
        return selected_file[0]
    except Exception:
        return None

def main():
    # Try backends in order of reliability and user environment
    backends = [
        ("zenity", pick_via_zenity),
        ("kdialog", pick_via_kdialog),
        ("yad", pick_via_yad),
        ("gtk", pick_via_gtk),
        ("portal_dbus", pick_via_portal),
        ("gdbus", pick_via_gdbus),
    ]

    path = None
    for name, backend in backends:
        try:
            path = backend()
            if path and os.path.isfile(path):
                break
        except Exception:
            continue

    if path and os.path.isfile(path):
        print(path)
        sys.stdout.flush()
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
