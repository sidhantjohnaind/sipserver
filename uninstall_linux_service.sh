#!/bin/bash
# =====================================================================
# uninstall_linux_service.sh - Remove JioFiber B2BUA systemd service
# =====================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root (sudo ./uninstall_linux_service.sh)"
  exit 1
fi

echo "[*] Stopping and disabling jiofiber-b2bua service..."
systemctl stop jiofiber-b2bua 2>/dev/null || true
systemctl disable jiofiber-b2bua 2>/dev/null || true

echo "[*] Removing /etc/systemd/system/jiofiber-b2bua.service..."
rm -f /etc/systemd/system/jiofiber-b2bua.service
systemctl daemon-reload

echo "====================================================================="
echo "   [SUCCESS] JioFiber B2BUA systemd service removed!"
echo "====================================================================="
