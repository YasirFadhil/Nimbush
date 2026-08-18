#!/usr/bin/env bash

# Screenshot helper script with Swappy & Quickshell notification
MODE="${1:-region}"
NOTIF_APP="Screenshot"
ICON="swappy"

case "$MODE" in
    full)
        grim - | wl-copy && wl-paste | swappy -f - && notify-send -a "$NOTIF_APP" -i "$ICON" "Fullscreen Screenshot" "Screenshot processed and copied to clipboard"
        ;;
    region)
        GEOM=$(slurp 2>/dev/null)
        if [ -n "$GEOM" ]; then
            grim -g "$GEOM" - | wl-copy && wl-paste | swappy -f - && notify-send -a "$NOTIF_APP" -i "$ICON" "Area Screenshot" "Selected area processed and copied to clipboard"
        fi
        ;;
    window)
        GEOM=$(slurp -p 2>/dev/null)
        if [ -n "$GEOM" ]; then
            grim -g "$GEOM" - | wl-copy && wl-paste | swappy -f - && notify-send -a "$NOTIF_APP" -i "$ICON" "Window Screenshot" "Window screenshot processed and copied to clipboard"
        fi
        ;;
    *)
        echo "Usage: $0 [full|region|window]"
        exit 1
        ;;
esac
