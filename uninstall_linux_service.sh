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

echo "[*] Removing firewall rules..."
if command -v ufw &>/dev/null; then
    ufw delete allow 5061/udp >/dev/null 2>&1 || true
    ufw delete allow 5062/tcp >/dev/null 2>&1 || true
    ufw delete allow 4000:4050/udp >/dev/null 2>&1 || true
    ufw delete allow 52000:52200/udp >/dev/null 2>&1 || true
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --remove-port=5061/udp --permanent >/dev/null 2>&1 || true
    firewall-cmd --remove-port=5062/tcp --permanent >/dev/null 2>&1 || true
    firewall-cmd --remove-port=4000-4050/udp --permanent >/dev/null 2>&1 || true
    firewall-cmd --remove-port=52000-52200/udp --permanent >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

echo "====================================================================="
echo "   [SUCCESS] JioFiber B2BUA systemd service removed!"
echo "====================================================================="
