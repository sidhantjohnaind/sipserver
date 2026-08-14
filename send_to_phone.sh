#!/bin/bash
# =====================================================================
# send_to_phone.sh - 1-Click Mobile Certificate Delivery Web Server
# Launches local Python HTTP server on port 8000 for phone download.
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if command -v python3 &>/dev/null; then
    python3 "$SCRIPT_DIR/send_to_phone.py"
elif command -v python &>/dev/null; then
    python "$SCRIPT_DIR/send_to_phone.py"
else
    echo "[ERROR] Python 3 is required to run the local delivery server."
    exit 1
fi
