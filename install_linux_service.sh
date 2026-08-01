#!/bin/bash
# =====================================================================
# install_linux_service.sh - Install JioFiber B2BUA as Linux Systemd Service
# (Runs automatically at system boot before user login)
# =====================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[!] ERROR: Please run as root (sudo bash install_linux_service.sh)"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

INSTALL_DIR="/opt/jiofiber-b2bua"
echo "[*] Creating installation directory $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/bin"

# Detect architecture
ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    BIN_SRC="bin/linux-arm64/b2bua"
    echo "[*] Detected ARM64 architecture"
else
    BIN_SRC="bin/linux-amd64/b2bua"
    echo "[*] Detected x86_64 architecture"
fi

if [ ! -f "$BIN_SRC" ]; then
    echo "[!] Binary $BIN_SRC not found!"
    exit 1
fi

echo "[*] Copying binary and environment..."
cp -f "$BIN_SRC" "$INSTALL_DIR/bin/b2bua"
chmod +x "$INSTALL_DIR/bin/b2bua"

if [ -f ".env" ]; then
    cp -f .env "$INSTALL_DIR/.env"
fi

echo "[*] Installing Systemd service..."
cp -f jiofiber-b2bua.service /etc/systemd/system/jiofiber-b2bua.service

systemctl daemon-reload
systemctl enable jiofiber-b2bua.service
systemctl restart jiofiber-b2bua.service

echo ""
echo "====================================================================="
echo "[SUCCESS] JioFiber B2BUA installed as Linux Systemd Service!"
echo "It will now start automatically at Linux boot before login."
echo ""
echo "Commands to manage:"
echo "  - Check status:  sudo systemctl status jiofiber-b2bua"
echo "  - View live logs: sudo journalctl -u jiofiber-b2bua -f"
echo "  - Restart service: sudo systemctl restart jiofiber-b2bua"
echo "  - Stop service:    sudo systemctl stop jiofiber-b2bua"
echo "====================================================================="
