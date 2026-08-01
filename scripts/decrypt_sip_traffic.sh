#!/bin/bash
# =====================================================================
# decrypt_sip_traffic.sh - Linux Cleartext Network Capture Tools Guide
# =====================================================================

echo "====================================================================="
echo " Linux Cleartext Network Traffic Sniffing Commands"
echo "====================================================================="

# Method 1: Python Raw Socket Sniffer (Custom script created in scripts/sip_sniffer.py)
echo "[1] Run Custom Cleartext Python Sniffer:"
echo "    sudo python3 scripts/sip_sniffer.py eth0"
echo ""

# Method 2: tcpdump (Displays raw cleartext ASCII packets for SIP/HTTP)
echo "[2] Capture SIP/HTTP cleartext traffic via tcpdump:"
echo "    sudo tcpdump -i eth0 -nn -s 0 -A 'port 5060 or port 5061 or port 80 or port 8443'"
echo ""

# Method 3: ngrep (Network Grep for SIP headers and HTTP payloads)
echo "[3] Capture SIP/HTTP traffic using ngrep:"
echo "    sudo ngrep -W byline -d eth0 'REGISTER|INVITE|SIP/2.0|HTTP' 'port 5060 or port 5061 or port 5068'"
echo ""

# Method 4: tshark (Wireshark CLI for SIP packet breakdown)
echo "[4] Capture cleartext SIP protocol headers via tshark:"
echo "    sudo tshark -i eth0 -f 'port 5060 or port 5061' -Y 'sip' -V"
echo ""

# Method 5: TLS Decryption using SSLKEYLOGFILE for PJSIP / Curl / Chrome
echo "[5] Decrypt TLS traffic using Pre-Master Secret Key Log:"
echo "    export SSLKEYLOGFILE=/tmp/tls_keys.log"
echo "    sudo tshark -i eth0 -o 'tls.keylog_file:/tmp/tls_keys.log' -Y 'sip or http'"
echo "====================================================================="
