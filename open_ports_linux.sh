#!/bin/bash
# =====================================================================
# open_ports_linux.sh - Configure Linux Firewall (ufw / iptables) for JioFiber B2BUA
# Opens UDP 5061 (SIP) and UDP 4000-4050 (RTP Audio Ports)
# =====================================================================

if [ "$EUID" -ne 0 ]; then
    echo "[!] ERROR: Please run as root (sudo bash open_ports_linux.sh)"
    exit 1
fi

echo "[*] Configuring Linux Firewall for JioFiber B2BUA..."

if command -v ufw >/dev/null 2>&1; then
    echo "[*] Configuring UFW (Uncomplicated Firewall)..."
    ufw allow 5061/udp
    ufw allow 4000:4050/udp
    ufw reload
elif command -v iptables >/dev/null 2>&1; then
    echo "[*] Configuring iptables..."
    iptables -A INPUT -p udp --dport 5061 -j ACCEPT
    iptables -A INPUT -p udp --dport 4000:4050 -j ACCEPT
fi

echo ""
echo "====================================================================="
echo "[SUCCESS] Linux Firewall ports opened successfully!"
echo "  - Allowed UDP 5061 (SIP Softphone Listener)"
echo "  - Allowed UDP 4000:4050 (RTP Audio Media Stream Ports)"
echo "====================================================================="
