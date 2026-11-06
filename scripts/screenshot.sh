#!/usr/bin/env bash

# Screenshot helper for grim, wl-clipboard, Swappy, and notifications.
set -o pipefail

MODE="${1:-region}"
NOTIF_APP="Screenshot"
ICON="swappy"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"

save_screenshot() {
    local geometry="$1"

    if ! mkdir -p "$SCREENSHOT_DIR"; then
        echo "Failed to create screenshot directory: $SCREENSHOT_DIR" >&2
        return 1
    fi

    # Copy the original screenshot to the clipboard, then open it in Swappy.
    # Swappy's config handles the single save when its window exits.
    if [ -n "$geometry" ]; then
        grim -g "$geometry" - | wl-copy || return 1
    else
        grim - | wl-copy || return 1
    fi

    wl-paste | swappy -f -
}

case "$MODE" in
    full)
        save_screenshot "" && notify-send -a "$NOTIF_APP" -i "$ICON" "Fullscreen Screenshot" "Screenshot saved and copied to clipboard"
        ;;
    region)
        GEOM=$(slurp 2>/dev/null)
        if [ -n "$GEOM" ]; then
            save_screenshot "$GEOM" && notify-send -a "$NOTIF_APP" -i "$ICON" "Area Screenshot" "Screenshot saved and copied to clipboard"
        fi
        ;;
    window)
        GEOM=$(slurp -p 2>/dev/null)
        if [ -n "$GEOM" ]; then
            save_screenshot "$GEOM" && notify-send -a "$NOTIF_APP" -i "$ICON" "Window Screenshot" "Screenshot saved and copied to clipboard"
        fi
        ;;
    *)
        echo "Usage: $0 [full|region|window]"
        exit 1
        ;;
esac
