#!/usr/bin/env bash

# Screenshot helper script with Swappy & Quickshell notification
set -o pipefail

MODE="${1:-region}"
NOTIF_APP="Screenshot"
ICON="swappy"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"

save_screenshot() {
    local geometry="$1"
    local timestamp
    local output_file

    if ! mkdir -p "$SCREENSHOT_DIR"; then
        echo "Failed to create screenshot directory: $SCREENSHOT_DIR" >&2
        return 1
    fi

    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    output_file="$SCREENSHOT_DIR/Screenshot_from_${timestamp}.png"

    if [ -n "$geometry" ]; then
        grim -g "$geometry" - | wl-copy
    else
        grim - | wl-copy
    fi

    wl-paste | swappy -f - -o "$output_file"
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
