#!/usr/bin/env bash
# ==============================================================================
# bluetooth-pair.sh - Reliable Bluetooth Pairing Helper for Quickshell
# Handles PINless / JustWorks auto-authorization, trust, pairing, and connection
# specifically tuned for TWS earbuds, headphones, and modern Bluetooth devices.
# ==============================================================================

MAC="$1"
if [ -z "$MAC" ]; then
    echo "Usage: bluetooth-pair.sh <MAC_ADDRESS>"
    exit 1
fi

# Ensure bluetooth controller is powered and in pairable state
bluetoothctl power on >/dev/null 2>&1
bluetoothctl pairable on >/dev/null 2>&1

# Run automated bluetoothctl session with NoInputNoOutput agent
# This allows JustWorks / PINless pairing confirmation automatically
# without blocking or waiting for manual confirmation.
(
    echo "agent NoInputNoOutput"
    echo "default-agent"
    echo "trust $MAC"
    echo "pair $MAC"
    echo "trust $MAC"
    echo "connect $MAC"
    sleep 1
    echo "connect $MAC"
    echo "quit"
) | bluetoothctl --timeout 25 >/dev/null 2>&1

# Extra safety: ensure device is trusted so BlueZ permanently remembers it
bluetoothctl trust "$MAC" >/dev/null 2>&1

# Give audio sink / profiles 0.5s to register
sleep 0.5

# Check if device is paired, trusted, or connected
if bluetoothctl info "$MAC" 2>/dev/null | grep -q -E "(Paired: yes|Connected: yes|Trusted: yes)"; then
    exit 0
else
    exit 1
fi
