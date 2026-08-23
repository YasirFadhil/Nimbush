#!/usr/bin/env python3
"""
KDE Connect Notification Helper for Quickshell
Handles:
  1. Live monitoring of KDE Connect notification signals (dismissed/posted/removed)
  2. Sending inline replies to messaging apps via KDE Connect DBus
  3. Dismissing notifications on the phone when dismissed on the desktop
  4. Syncing active notifications list
"""

import sys
import os
import json
import time
import subprocess
import argparse
import select

def get_kde_device_notification_paths():
    try:
        raw = subprocess.check_output(
            ["busctl", "--user", "tree", "org.kde.kdeconnect"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1.2
        )
        paths = []
        for line in raw.splitlines():
            line = line.strip().split()[-1] if line.strip() else ""
            if line.startswith("/modules/kdeconnect/devices/") and line.endswith("/notifications"):
                paths.append(line)
        return paths
    except Exception:
        return []

def get_active_notifications():
    devs = get_kde_device_notification_paths()
    notifs = []
    for d in devs:
        try:
            ids_raw = subprocess.check_output(
                ["busctl", "--user", "call", "org.kde.kdeconnect", d, "org.kde.kdeconnect.device.notifications", "activeNotifications"],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1.0
            )
            parts = ids_raw.strip().split()
            if len(parts) >= 2 and parts[0] == "as":
                ids = [p.strip('"') for p in parts[2:]]
                for nid in ids:
                    p = f"{d}/{nid}"
                    try:
                        app = subprocess.check_output(
                            ["busctl", "--user", "get-property", "org.kde.kdeconnect", p, "org.kde.kdeconnect.device.notifications.notification", "appName"],
                            stderr=subprocess.DEVNULL,
                            text=True,
                            timeout=0.6
                        ).strip().split(" ", 1)[-1].strip('"')
                        title = subprocess.check_output(
                            ["busctl", "--user", "get-property", "org.kde.kdeconnect", p, "org.kde.kdeconnect.device.notifications.notification", "title"],
                            stderr=subprocess.DEVNULL,
                            text=True,
                            timeout=0.6
                        ).strip().split(" ", 1)[-1].strip('"')
                        text = subprocess.check_output(
                            ["busctl", "--user", "get-property", "org.kde.kdeconnect", p, "org.kde.kdeconnect.device.notifications.notification", "text"],
                            stderr=subprocess.DEVNULL,
                            text=True,
                            timeout=0.6
                        ).strip().split(" ", 1)[-1].strip('"')
                        reply_id = subprocess.check_output(
                            ["busctl", "--user", "get-property", "org.kde.kdeconnect", p, "org.kde.kdeconnect.device.notifications.notification", "replyId"],
                            stderr=subprocess.DEVNULL,
                            text=True,
                            timeout=0.6
                        ).strip().split(" ", 1)[-1].strip('"')
                        notifs.append({
                            "id": nid,
                            "app": app,
                            "title": title,
                            "text": text,
                            "replyId": reply_id,
                            "path": p,
                            "devPath": d
                        })
                    except Exception:
                        pass
        except Exception:
            pass
    return notifs

def do_reply(reply_id, notif_id, summary, body, message):
    if not message:
        print(json.dumps({"status": "error", "error": "empty message"}))
        return

    devs = get_kde_device_notification_paths()
    active = get_active_notifications()
    replied = False

    # 1. Match by notif_id in active KDE notifications
    if notif_id:
        for item in active:
            if str(item.get("id")) == str(notif_id):
                try:
                    res = subprocess.run(
                        ["busctl", "--user", "call", "org.kde.kdeconnect", item["path"],
                         "org.kde.kdeconnect.device.notifications.notification", "sendReply", "s", message],
                        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                    )
                    if res.returncode == 0:
                        replied = True
                        break
                except Exception:
                    pass

                if not replied and item.get("replyId"):
                    try:
                        res = subprocess.run(
                            ["busctl", "--user", "call", "org.kde.kdeconnect", item["devPath"],
                             "org.kde.kdeconnect.device.notifications", "sendReply", "ss", item["replyId"], message],
                            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                        )
                        if res.returncode == 0:
                            replied = True
                            break
                    except Exception:
                        pass

    # 2. Match by direct reply_id on device if not yet replied
    if not replied and reply_id and reply_id != "inline-reply":
        for d in devs:
            try:
                res = subprocess.run(
                    ["busctl", "--user", "call", "org.kde.kdeconnect", d,
                     "org.kde.kdeconnect.device.notifications", "sendReply", "ss", reply_id, message],
                    check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                if res.returncode == 0:
                    replied = True
                    break
            except Exception:
                pass

    # 3. Match by content (summary/title/body) if not yet replied
    if not replied and (summary or body):
        sum_l = (summary or "").lower()
        bod_l = (body or "").lower()
        for item in active:
            app_l = item.get("app", "").lower()
            title_l = item.get("title", "").lower()
            text_l = item.get("text", "").lower()

            matched = False
            if app_l and (app_l in sum_l or sum_l in app_l):
                if title_l and (title_l in bod_l or title_l in sum_l or bod_l in title_l):
                    matched = True
                elif text_l and (text_l[:15] in bod_l or bod_l[:15] in text_l):
                    matched = True
                elif len(active) == 1:
                    matched = True
            elif title_l and (title_l in bod_l or title_l in sum_l):
                matched = True

            if matched:
                try:
                    res = subprocess.run(
                        ["busctl", "--user", "call", "org.kde.kdeconnect", item["path"],
                         "org.kde.kdeconnect.device.notifications.notification", "sendReply", "s", message],
                        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                    )
                    if res.returncode == 0:
                        replied = True
                        break
                except Exception:
                    pass

                if not replied and item.get("replyId"):
                    try:
                        res = subprocess.run(
                            ["busctl", "--user", "call", "org.kde.kdeconnect", item["devPath"],
                             "org.kde.kdeconnect.device.notifications", "sendReply", "ss", item["replyId"], message],
                            check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                        )
                        if res.returncode == 0:
                            replied = True
                            break
                    except Exception:
                        pass
                if replied:
                    break

    print(json.dumps({"status": "ok", "replied": replied, "count": 1 if replied else 0}))

def do_dismiss(notif_id, summary, body):
    active = get_active_notifications()
    dismissed = False

    sum_l = (summary or "").lower()
    bod_l = (body or "").lower()

    for item in active:
        matched = False
        if notif_id and str(item.get("id")) == str(notif_id):
            matched = True
        elif sum_l or bod_l:
            app_l = item.get("app", "").lower()
            title_l = item.get("title", "").lower()
            text_l = item.get("text", "").lower()

            if app_l and (app_l in sum_l or sum_l in app_l):
                if title_l and (title_l in bod_l or title_l in sum_l or bod_l in title_l):
                    matched = True
                elif text_l and (text_l[:15] in bod_l or bod_l[:15] in text_l):
                    matched = True
            elif title_l and (title_l in bod_l or title_l in sum_l):
                matched = True

        if matched:
            try:
                res = subprocess.run(
                    ["busctl", "--user", "call", "org.kde.kdeconnect", item["path"],
                     "org.kde.kdeconnect.device.notifications.notification", "dismiss"],
                    check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                if res.returncode == 0:
                    dismissed = True
                    break
            except Exception:
                pass

    print(json.dumps({"status": "ok", "dismissed": dismissed, "count": 1 if dismissed else 0}))

def do_watch():
    # Initial sync
    initial_notifs = get_active_notifications()
    active_ids = [n["id"] for n in initial_notifs]
    print(json.dumps({
        "event": "sync",
        "activeIds": active_ids,
        "notifications": initial_notifs
    }), flush=True)

    # Start dbus-monitor process
    try:
        monitor_proc = subprocess.Popen(
            ["dbus-monitor", "--session", "type='signal',interface='org.kde.kdeconnect.device.notifications'"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1
        )
    except Exception as e:
        print(json.dumps({"event": "error", "message": str(e)}), flush=True)
        return

    last_sync_time = time.time()
    last_active_ids = set(active_ids)

    while True:
        try:
            # Non-blocking read with timeout
            rlist, _, _ = select.select([monitor_proc.stdout], [], [], 5.0)

            if rlist:
                line = monitor_proc.stdout.readline()
                if not line:
                    break
                line = line.strip()

                if "member=notificationRemoved" in line:
                    time.sleep(0.1)
                    current = get_active_notifications()
                    current_ids = set(n["id"] for n in current)
                    removed_ids = list(last_active_ids - current_ids)
                    last_active_ids = current_ids
                    print(json.dumps({
                        "event": "removed",
                        "removedIds": removed_ids,
                        "activeIds": list(current_ids),
                        "notifications": current
                    }), flush=True)
                elif "member=allNotificationsRemoved" in line:
                    last_active_ids = set()
                    print(json.dumps({
                        "event": "all_removed",
                        "activeIds": [],
                        "notifications": []
                    }), flush=True)
                elif "member=notificationPosted" in line or "member=notificationUpdated" in line:
                    time.sleep(0.1)
                    current = get_active_notifications()
                    last_active_ids = set(n["id"] for n in current)
                    print(json.dumps({
                        "event": "sync",
                        "activeIds": list(last_active_ids),
                        "notifications": current
                    }), flush=True)

            # Periodic sync fallback (every 45 seconds) - live events handled immediately above
            now = time.time()
            if now - last_sync_time >= 45.0:
                last_sync_time = now
                current = get_active_notifications()
                current_ids = set(n["id"] for n in current)
                if current_ids != last_active_ids:
                    removed_ids = list(last_active_ids - current_ids)
                    last_active_ids = current_ids
                    print(json.dumps({
                        "event": "sync",
                        "removedIds": removed_ids,
                        "activeIds": list(current_ids),
                        "notifications": current
                    }), flush=True)

        except KeyboardInterrupt:
            break
        except Exception as e:
            time.sleep(1)

    if monitor_proc:
        monitor_proc.terminate()

def main():
    parser = argparse.ArgumentParser(description="KDE Connect notification helper")
    subparsers = parser.add_subparsers(dest="command")

    # Watch mode
    subparsers.add_parser("watch")

    # List mode
    subparsers.add_parser("list")

    # Reply mode
    reply_p = subparsers.add_parser("reply")
    reply_p.add_argument("--reply-id", default="")
    reply_p.add_argument("--notif-id", default="")
    reply_p.add_argument("--summary", default="")
    reply_p.add_argument("--body", default="")
    reply_p.add_argument("--message", required=True)

    # Dismiss mode
    dismiss_p = subparsers.add_parser("dismiss")
    dismiss_p.add_argument("--notif-id", default="")
    dismiss_p.add_argument("--summary", default="")
    dismiss_p.add_argument("--body", default="")

    args = parser.parse_args()

    if args.command == "watch":
        do_watch()
    elif args.command == "list":
        print(json.dumps(get_active_notifications()))
    elif args.command == "reply":
        do_reply(args.reply_id, args.notif_id, args.summary, args.body, args.message)
    elif args.command == "dismiss":
        do_dismiss(args.notif_id, args.summary, args.body)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
