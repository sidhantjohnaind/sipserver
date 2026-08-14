#!/bin/bash
# =====================================================================
# sync_to_windows.sh - Quick Helper to Push Configuration to Windows
# (Wraps b2bua_sync.sh with 100% dynamic discovery across all drives)
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -f "$SCRIPT_DIR/b2bua_sync.sh" ]; then
    exec bash "$SCRIPT_DIR/b2bua_sync.sh" push
else
    echo "[ERROR] b2bua_sync.sh not found!"
    exit 1
fi
