#!/bin/bash
# =====================================================================
# uninstall_linux_service.sh - Remove JioFiber B2BUA Systemd Service
# =====================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[!] ERROR: Please run as root (sudo bash uninstall_linux_service.sh)"
    exit 1
fi

echo "[*] Stopping and disabling JioFiber B2BUA service..."
systemctl stop jiofiber-b2bua.service 2>/dev/null || true
systemctl disable jiofiber-b2bua.service 2>/dev/null || true
rm -f /etc/systemd/system/jiofiber-b2bua.service
systemctl daemon-reload

echo "[*] Removing installation directory /opt/jiofiber-b2bua..."
rm -rf /opt/jiofiber-b2bua

echo "[SUCCESS] JioFiber B2BUA Linux Systemd Service removed."
