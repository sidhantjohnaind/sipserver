#!/bin/bash
# =====================================================================
# run_wsl.sh - Run JioFiber B2BUA inside WSL (Windows Subsystem for Linux)
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

echo "====================================================================="
echo "    JioFiber SIP Back-to-Back User Agent (WSL Linux Version)"
echo "====================================================================="
echo ""

# Ensure executable permissions on Linux binary
chmod +x bin/linux-amd64/b2bua

# Check for .env file
if [ ! -f ".env" ]; then
    echo "[!] .env file not found. Running python3 create_env_jfibersip.py..."
    python3 create_env_jfibersip.py
fi

# Stop any background processes holding port 5061/5068
echo "[*] Cleaning up any processes holding port 5061/5068..."
fuser -k 5061/udp 2>/dev/null || true
pkill -f b2bua 2>/dev/null || true

# Copy .env to bin/linux-amd64 directory if needed
cp -f .env bin/linux-amd64/.env 2>/dev/null || true

echo "[*] Launching Linux B2BUA binary in WSL..."
echo "[*] Upstream Jio IMS TLS Target:  192.168.29.1:5068"
echo ""

# Run Linux B2BUA binary inside bin/linux-amd64 directory
cd "$SCRIPT_DIR/bin/linux-amd64"
export LD_LIBRARY_PATH="./lib:$LD_LIBRARY_PATH"
./b2bua
