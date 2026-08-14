#!/bin/bash
# =====================================================================
# open_tls_cert.sh - Open directory containing cert.pem in file manager
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CERTS_DIR="$SCRIPT_DIR/certs"

if [ ! -d "$CERTS_DIR" ]; then
    mkdir -p "$CERTS_DIR"
    cp "$SCRIPT_DIR/cert.pem" "$SCRIPT_DIR/key.pem" "$CERTS_DIR/" 2>/dev/null || true
fi

if command -v nautilus >/dev/null 2>&1; then
    nautilus --new-window "$CERTS_DIR" 2>/dev/null &
elif command -v gio >/dev/null 2>&1; then
    gio open "$CERTS_DIR" 2>/dev/null &
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$CERTS_DIR" 2>/dev/null &
elif command -v dolphin >/dev/null 2>&1; then
    dolphin "$CERTS_DIR" 2>/dev/null &
elif command -v nemo >/dev/null 2>&1; then
    nemo "$CERTS_DIR" 2>/dev/null &
elif command -v thunar >/dev/null 2>&1; then
    thunar "$CERTS_DIR" 2>/dev/null &
else
    echo "[*] TLS Certificates Folder: $CERTS_DIR"
    ls -la "$CERTS_DIR"
fi
