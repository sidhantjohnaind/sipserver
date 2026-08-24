#!/bin/bash
# =====================================================================
# uninstall_linux.sh - Complete Clean Uninstaller for JioFiber B2BUA
# Removes systemd service, firewall rules, and CA certificates.
# =====================================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "[!] Please run as root: sudo ./uninstall_linux.sh"
    exit 1
fi

echo "====================================================================="
echo "   JioFiber SIP B2BUA — Linux Uninstaller"
echo "====================================================================="
echo ""

# 1. Stop & Disable Systemd Service
echo "[1/4] Stopping and removing systemd service..."
systemctl stop jiofiber-b2bua 2>/dev/null || true
systemctl disable jiofiber-b2bua 2>/dev/null || true
rm -f /etc/systemd/system/jiofiber-b2bua.service
systemctl daemon-reload

# 2. Remove CA Certificate from Trust Stores
echo "[2/4] Removing CA certificate from system trust store..."
rm -f /usr/local/share/ca-certificates/LocalLAN_RootCA.crt \
      /etc/pki/ca-trust/source/anchors/LocalLAN_RootCA.crt \
      /etc/ca-certificates/trust-source/anchors/LocalLAN_RootCA.crt \
      /etc/ssl/certs/LocalLAN_RootCA.pem 2>/dev/null || true

if command -v update-ca-certificates &>/dev/null; then
    update-ca-certificates --fresh >/dev/null 2>&1 || update-ca-certificates >/dev/null 2>&1
elif command -v update-ca-trust &>/dev/null; then
    update-ca-trust >/dev/null 2>&1
fi

# 3. Clean up Firewall rules (UFW / Firewalld / iptables)
echo "[3/4] Cleaning up firewall rules..."
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

# 4. Optional Data Directory Cleanup
echo "[4/4] Installation cleanup completed."
echo ""
echo "====================================================================="
echo "   [SUCCESS] JioFiber B2BUA service & certificates removed!"
echo "   Note: Your .env and certs in ~/sipserver were preserved."
echo "====================================================================="
