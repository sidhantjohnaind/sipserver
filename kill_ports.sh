#!/bin/bash
# =====================================================================
# kill_ports.sh - Free ports 5061 and 5062 on Linux / WSL
# =====================================================================

echo "[*] Terminating b2bua processes..."
pkill -9 -f b2bua 2>/dev/null || true

echo "[*] Killing sockets bound to ports 5061 and 5062..."
fuser -k -9 5061/udp 5061/tcp 5062/udp 5062/tcp 2>/dev/null || true

echo "[*] Done! Ports 5061 and 5062 are now free."
