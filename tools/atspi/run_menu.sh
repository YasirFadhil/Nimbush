#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if python3 -c "import gi; gi.require_version('Atspi', '2.0')" 2>/dev/null; then
    exec python3 "$SCRIPT_DIR/atspi_menu.py" "$@"
elif [ -f "$SCRIPT_DIR/shell.nix" ] && command -v nix-shell >/dev/null 2>&1; then
    ARGS=""
    for arg in "$@"; do
        ARGS+="$(printf '%q ' "$arg")"
    done
    exec nix-shell "$SCRIPT_DIR/shell.nix" --run "exec python3 \"$SCRIPT_DIR/atspi_menu.py\" $ARGS"
else
    exec python3 "$SCRIPT_DIR/atspi_menu.py" "$@"
fi
