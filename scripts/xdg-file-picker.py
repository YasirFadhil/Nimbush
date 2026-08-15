#!/usr/bin/env python3
import sys
import subprocess
import re
import urllib.parse
import os

def open_file_chooser():
    try:
        # Start gdbus monitor for portal response signals
        monitor_proc = subprocess.Popen(
            ["gdbus", "monitor", "--session", "--dest", "org.freedesktop.portal.Desktop"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Call OpenFile method on XDG Desktop Portal FileChooser
        call_cmd = [
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.portal.Desktop",
            "--object-path", "/org/freedesktop/portal/desktop",
            "--method", "org.freedesktop.portal.FileChooser.OpenFile",
            "", "Select Wallpaper",
            "{}"
        ]
        res = subprocess.run(call_cmd, capture_output=True, text=True)

        # Extract request handle object path
        match = re.search(r"'/org/freedesktop/portal/desktop/request/[^']+'", res.stdout)
        if not match:
            monitor_proc.kill()
            return None

        req_path = match.group(0).strip("'")

        selected_path = None
        while True:
            line = monitor_proc.stdout.readline()
            if not line:
                break
            if req_path in line and "Response" in line:
                payload = ""
                for _ in range(15):
                    l = monitor_proc.stdout.readline()
                    payload += l
                    if "uris" in payload and "]" in payload:
                        break
                file_match = re.search(r"'file://([^']+)'", payload)
                if file_match:
                    selected_path = urllib.parse.unquote(file_match.group(1))
                break

        monitor_proc.kill()
        return selected_path
    except Exception as e:
        return None

if __name__ == "__main__":
    path = open_file_chooser()
    if path and os.path.isfile(path):
        print(path)
        sys.exit(0)
    else:
        sys.exit(1)
