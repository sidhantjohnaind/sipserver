#!/bin/bash
# =====================================================================
# install_linux_service.sh - Install JioFiber B2BUA as a systemd service
# =====================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run as root (sudo ./install_linux_service.sh)"
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BINARY_PATH="$SCRIPT_DIR/bin/linux-amd64/b2bua"

if [ ! -f "$BINARY_PATH" ]; then
    BINARY_PATH="$SCRIPT_DIR/b2bua"
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "[!] Error: B2BUA Linux binary not found at $BINARY_PATH"
    exit 1
fi

chmod +x "$BINARY_PATH"

cat <<EOF > /etc/systemd/system/jiofiber-b2bua.service
[Unit]
Description=JioFiber SIP B2BUA Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStartPre=/usr/bin/fuser -k -9 5061/udp 5061/tcp 5062/udp 5062/tcp
ExecStart=$BINARY_PATH
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
echo "   [SUCCESS] JioFiber B2BUA systemd service installed!"
echo "   Status:   sudo systemctl status jiofiber-b2bua"
echo "   Logs:     sudo journalctl -u jiofiber-b2bua -f"
echo "====================================================================="
