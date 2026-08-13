#!/bin/bash
# =====================================================================
# install_linux.sh - 1-Click Linux Installer & Service Setup
# =====================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root: sudo bash install_linux.sh"
  exit 1
fi

echo "====================================================================="
echo "   JioFiber SIP B2BUA - 1-Click Linux Installer"
echo "====================================================================="
echo ""

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ARCH="$(uname -m)"

echo "[*] Step 1/3: Detecting System Architecture ($ARCH)..."

if [ "$ARCH" = "x86_64" ]; then
    BIN_NAME="b2bua-linux-amd64"
    LOCAL_BIN="$SCRIPT_DIR/bin/linux-amd64/b2bua"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    BIN_NAME="b2bua-linux-arm64"
    LOCAL_BIN="$SCRIPT_DIR/bin/linux-arm64/b2bua"
else
    BIN_NAME="b2bua-linux-amd64"
    LOCAL_BIN="$SCRIPT_DIR/bin/linux-amd64/b2bua"
fi

TARGET_BIN="$SCRIPT_DIR/b2bua"

if [ -f "$LOCAL_BIN" ]; then
    cp "$LOCAL_BIN" "$TARGET_BIN"
elif [ ! -f "$TARGET_BIN" ]; then
    echo "[*] Downloading pre-built $BIN_NAME binary from GitHub Releases..."
    curl -sSL "https://github.com/sidhantjohnaind/sipserver/releases/download/v1.0.0/$BIN_NAME" -o "$TARGET_BIN"
fi

if [ ! -f "$TARGET_BIN" ]; then
    echo "[!] ERROR: Failed to locate or download b2bua binary."
    exit 1
fi

chmod +x "$TARGET_BIN"
echo "[x] Binary ready at: $TARGET_BIN"
echo ""

# 2. Configure Firewall Ports
echo "[*] Step 2/3: Configuring Firewall Ports (UDP 5061, TCP 5062, UDP 52000-52200)..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 5061/udp >/dev/null 2>&1
    ufw allow 5062/tcp >/dev/null 2>&1
    ufw allow 52000:52200/udp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --add-port=5061/udp --permanent >/dev/null 2>&1
    firewall-cmd --add-port=5062/tcp --permanent >/dev/null 2>&1
    firewall-cmd --add-port=52000-52200/udp --permanent >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
elif command -v iptables >/dev/null 2>&1; then
    iptables -A INPUT -p udp --dport 5061 -j ACCEPT
    iptables -A INPUT -p tcp --dport 5062 -j ACCEPT
    iptables -A INPUT -p udp --dport 52000:52200 -j ACCEPT
fi
echo "[x] Firewall rules applied!"
echo ""

# 3. Create systemd service
echo "[*] Step 3/3: Registering systemd background service..."
cat <<EOF > /etc/systemd/system/jiofiber-b2bua.service
[Unit]
Description=JioFiber SIP B2BUA Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStartPre=/usr/bin/fuser -k -9 5061/udp 5061/tcp 5062/tcp 5062/udp 2>/dev/null || true
ExecStart=$TARGET_BIN
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable jiofiber-b2bua
systemctl restart jiofiber-b2bua

echo "====================================================================="
echo "   [SUCCESS] JioFiber B2BUA Installed & Running as a Linux Service!"
echo "   ------------------------------------------------------------------"
echo "   Status Command:  sudo systemctl status jiofiber-b2bua"
echo "   View Live Logs:  sudo journalctl -u jiofiber-b2bua -f"
echo "====================================================================="
