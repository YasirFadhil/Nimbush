#!/usr/bin/env bash
#
# Nimbush Screenshot
# Fullscreen / focused output / region / window picker / focused window
# Requires: grim, slurp, jq, wl-clipboard, swappy, libnotify
#
# Window mode uses Hyprland's live client geometry and slurp's predefined
# rectangle picker. Press Escape to cancel.

set -Eeuo pipefail

MODE="${1:-region}"
NOTIF_APP="Screenshot"
ICON="swappy"
SCREENSHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "$NOTIF_APP" -i "$ICON" "$1" "$2" || true
    fi
}

die() {
    printf 'screenshot: %s\n' "$*" >&2
    notify "Screenshot failed" "$*"
    exit 1
}

require() {
    command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

usage() {
    cat <<'EOF'
Usage: screenshot.sh [mode]

Modes:
  full       Capture the entire desktop (all outputs).
  screen     Capture the currently focused output.
  region     Select an arbitrary screen region.
  window     Pick a visible window by clicking its highlighted rectangle.
  focused    Capture the currently focused window.
  help       Show this help.

Window/region selection can be cancelled with Escape.
EOF
}

capture_and_open() {
    local geometry="${1:-}"
    local output="${2:-}"
    local label="${3:-Screenshot}"
    local tmp

    mkdir -p "$SCREENSHOT_DIR" || die "Cannot create $SCREENSHOT_DIR"
    tmp="$(mktemp --tmpdir="${XDG_RUNTIME_DIR:-/tmp}" screenshot-XXXXXX.png)" \
        || die "Cannot create temporary screenshot"

    # Keep the temporary image until Swappy exits. wl-copy owns its own copy.
    if [[ -n "$output" ]]; then
        grim -c -o "$output" "$tmp" || {
            rm -f "$tmp"
            die "Could not capture output: $output"
        }
    elif [[ -n "$geometry" ]]; then
        grim -c -g "$geometry" "$tmp" || {
            rm -f "$tmp"
            die "Could not capture selected area"
        }
    else
        grim -c "$tmp" || {
            rm -f "$tmp"
            die "Could not capture the desktop"
        }
    fi

    [[ -s "$tmp" ]] || {
        rm -f "$tmp"
        die "Screenshot image is empty"
    }

    wl-copy --type image/png < "$tmp" || {
        rm -f "$tmp"
        die "Could not copy screenshot to clipboard"
    }

    notify "$label" "Screenshot copied to clipboard. Opening Swappy."
    local swappy_status=0
    swappy -f "$tmp" || swappy_status=$?

    rm -f "$tmp"

    if (( swappy_status != 0 )); then
        notify "$label" "Screenshot remains available in the clipboard."
        return "$swappy_status"
    fi
}

select_region() {
    local geometry
    geometry="$(slurp 2>/dev/null)" || return 1
    [[ -n "$geometry" ]] || return 1
    printf '%s\n' "$geometry"
}

select_window() {
    local active_workspaces rectangles geometry

    # A window is eligible when it is mapped, not hidden, has a real size,
    # and belongs to a workspace currently visible on any output. Pinned
    # windows are visible across workspaces, so include them too.
    active_workspaces="$(
        hyprctl -j monitors |
            jq -c '[.[] | .activeWorkspace.id] | unique'
    )" || die "Could not read active Hyprland workspaces"

    rectangles="$(
        hyprctl -j clients |
            jq -r --argjson active "$active_workspaces" '
                .[]
                | select(.mapped == true)
                | select((.hidden // false) == false)
                | select((.size[0] // 0) > 0 and (.size[1] // 0) > 0)
                | . as $client
                | select(
                    ($client.pinned // false) == true
                    or (($active | index($client.workspace.id)) != null)
                  )
                | [
                    ($client.at[0] | floor),
                    ($client.at[1] | floor),
                    ($client.size[0] | floor),
                    ($client.size[1] | floor),
                    (
                      (($client.class // "Window") + " · " + ($client.title // ""))
                      | gsub("[\\r\\n]"; " ")
                    )
                  ]
                | "\(.[0]),\(.[1]) \(.[2])x\(.[3]) \(.[4])"
            '
    )" || die "Could not read Hyprland window geometry"

    [[ -n "$rectangles" ]] || {
        notify "Window Screenshot" "No visible windows to select."
        return 1
    }

    # -r restricts selection to the supplied window rectangles. Clicking a
    # highlighted rectangle selects that window; Escape cancels.
    geometry="$(
        printf '%s\n' "$rectangles" |
            slurp -r -f '%x,%y %wx%h' 2>/dev/null
    )" || return 1

    [[ -n "$geometry" ]] || return 1
    printf '%s\n' "$geometry"
}

focused_window_geometry() {
    hyprctl -j activewindow |
        jq -er '
            select(.mapped == true)
            | select((.size[0] // 0) > 0 and (.size[1] // 0) > 0)
            | "\(.at[0] | floor),\(.at[1] | floor) \(.size[0] | floor)x\(.size[1] | floor)"
        '
}

focused_output() {
    hyprctl -j monitors |
        jq -er '.[] | select(.focused == true) | .name' |
        head -n 1
}

case "$MODE" in
    full)
        require grim
        require wl-copy
        require swappy
        require notify-send
        capture_and_open "" "" "Fullscreen Screenshot"
        ;;

    screen)
        require grim
        require hyprctl
        require jq
        require wl-copy
        require swappy
        require notify-send
        OUTPUT="$(focused_output)" || die "Could not determine the focused output"
        capture_and_open "" "$OUTPUT" "Screen Screenshot"
        ;;

    region)
        if [[ "${SCREENSHOT_LEGACY:-0}" != "1" ]] && command -v qs >/dev/null 2>&1; then
            if qs ipc call screenshot region >/dev/null 2>&1; then
                exit 0
            fi
        fi
        require grim
        require slurp
        require wl-copy
        require swappy
        require notify-send
        GEOMETRY="$(select_region)" || exit 0
        capture_and_open "$GEOMETRY" "" "Region Screenshot"
        ;;

    window)
        require grim
        require slurp
        require hyprctl
        require jq
        require wl-copy
        require swappy
        require notify-send
        GEOMETRY="$(select_window)" || exit 0
        capture_and_open "$GEOMETRY" "" "Window Screenshot"
        ;;

    focused)
        require grim
        require hyprctl
        require jq
        require wl-copy
        require swappy
        require notify-send
        GEOMETRY="$(focused_window_geometry)" ||
            die "There is no capturable focused window"
        capture_and_open "$GEOMETRY" "" "Focused Window Screenshot"
        ;;

    help|-h|--help)
        usage
        ;;

    *)
        usage >&2
        exit 2
        ;;
esac
