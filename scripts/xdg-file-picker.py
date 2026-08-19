#!/usr/bin/env python3
import sys
import os
import urllib.parse

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
        filter_img.set_name("Image files (*.jpg, *.png, *.webp, *.jpeg)")
        filter_img.add_mime_type("image/png")
        filter_img.add_mime_type("image/jpeg")
        filter_img.add_mime_type("image/webp")
        filter_img.add_pattern("*.png")
        filter_img.add_pattern("*.jpg")
        filter_img.add_pattern("*.jpeg")
        filter_img.add_pattern("*.webp")
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
    except Exception as e:
        return None

def pick_via_portal():
    try:
        import dbus
        from dbus.mainloop.glib import DBusGMainLoop
        from gi.repository import GLib
        import time

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

if __name__ == "__main__":
    path = pick_via_gtk()
    if not path:
        path = pick_via_portal()

    if path and os.path.isfile(path):
        print(path)
        sys.stdout.flush()
        sys.exit(0)
    else:
        sys.exit(1)
