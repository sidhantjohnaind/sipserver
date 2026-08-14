#!/bin/bash
# =====================================================================
# generate_certs.sh - 100% Native TLS Certificate & Android P12 Generator
# (Zero Python Dependency - Uses Native OpenSSL)
# Covers all .1-.254 on every common home subnet - one cert, any device.
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CERTS_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERTS_DIR"

CERT_NAME="LocalLAN_RootCA"

echo "====================================================================="
echo "   JioFiber SIP B2BUA - Native TLS Certificate Generator"
echo "====================================================================="
echo ""

# Detect the primary local LAN IP of the host machine
LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
if [ -z "$LAN_IP" ]; then
    LAN_IP="192.168.29.4"
fi

# Allow overriding LAN IP via first argument if supplied
if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    LAN_IP="$1"
fi

echo "[*] Local LAN Host IP: $LAN_IP"

# Auto-update IPV4_ADDRESS in .env if present
for ENV_FILE in "$SCRIPT_DIR/.env" "/home/${SUDO_USER:-$USER}/sipserver/.env"; do
    if [ -f "$ENV_FILE" ]; then
        if grep -q "^IPV4_ADDRESS=" "$ENV_FILE"; then
            sed -i "s/^IPV4_ADDRESS=.*/IPV4_ADDRESS=$LAN_IP/" "$ENV_FILE"
        fi
    fi
done

echo "[*] Generating 2048-bit RSA Private Key..."
openssl genrsa -out "$CERTS_DIR/${CERT_NAME}.key" 2048 >/dev/null 2>&1

echo "[*] Generating X.509 v3 Certificate - full /24 SANs (every device on any LAN)..."

CNF_FILE=/tmp/b2bua_san.cnf

# Write static header
cat << 'HEADER' > "$CNF_FILE"
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = IN
O = LocalLAN
CN = LocalLAN_RootCA

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyCertSign, cRLSign, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
HEADER

# Subnets to cover — all hosts .1 to .254
# Covers JioFiber, all common home routers, and VPN ranges
SUBNETS=(
    "192.168.29"   # JioFiber default subnet
    "192.168.0"    # Common home router (Netgear, TP-Link)
    "192.168.1"    # Common home router (most ISPs)
    "192.168.2"    # Some ISP/BSNL routers
    "192.168.3"    # Some routers
    "192.168.31"   # Xiaomi / Mi routers
    "192.168.100"  # Huawei routers
    "10.0.0"       # Common home/VPN range
    "10.0.1"       # Common VPN range
    "10.8.0"       # OpenVPN default
)

IDX=1

# Primary detected IP first
echo "IP.$IDX = $LAN_IP" >> "$CNF_FILE"; IDX=$((IDX+1))
echo "IP.$IDX = 127.0.0.1" >> "$CNF_FILE"; IDX=$((IDX+1))

# Detect Active VPN Overlays (Tailscale, WireGuard, NetBird, ZeroTier, Nebula, OpenVPN)
DETECTED_VPNS=()

# Tailscale
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || ip -4 addr show tailscale0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
[ -n "$TAILSCALE_IP" ] && DETECTED_VPNS+=("Tailscale:$TAILSCALE_IP")

# WireGuard (wg0, wg1)
for wg_dev in wg0 wg1; do
    wg_ip=$(ip -4 addr show "$wg_dev" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    [ -n "$wg_ip" ] && DETECTED_VPNS+=("WireGuard($wg_dev):$wg_ip")
done

# NetBird (wt0)
NETBIRD_IP=$(ip -4 addr show wt0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
[ -n "$NETBIRD_IP" ] && DETECTED_VPNS+=("NetBird:$NETBIRD_IP")

# ZeroTier (zt*, ztuga*, etc.)
for zt_dev in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^zt'); do
    zt_ip=$(ip -4 addr show "$zt_dev" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    [ -n "$zt_ip" ] && DETECTED_VPNS+=("ZeroTier($zt_dev):$zt_ip")
done

# Nebula (nebula0, nebula1)
for neb_dev in nebula0 nebula1; do
    neb_ip=$(ip -4 addr show "$neb_dev" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    [ -n "$neb_ip" ] && DETECTED_VPNS+=("Nebula:$neb_ip")
done

# OpenVPN (tun0, tun1)
for tun_dev in tun0 tun1; do
    tun_ip=$(ip -4 addr show "$tun_dev" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
    [ -n "$tun_ip" ] && DETECTED_VPNS+=("OpenVPN:$tun_ip")
done

# Register all detected VPN IPs into certificate SANs
for vpn_entry in "${DETECTED_VPNS[@]}"; do
    v_name="${vpn_entry%%:*}"
    v_ip="${vpn_entry##*:}"
    echo "[*] Detected Active $v_name IP: $v_ip"
    echo "IP.$IDX = $v_ip" >> "$CNF_FILE"
    IDX=$((IDX+1))
done

# All subnets, all hosts 1-254
for SUBNET in "${SUBNETS[@]}"; do
    for HOST in $(seq 1 254); do
        IP="${SUBNET}.${HOST}"
        # Skip if already added
        [ "$IP" = "$LAN_IP" ] && continue
        echo "IP.$IDX = $IP" >> "$CNF_FILE"
        IDX=$((IDX+1))
    done
done

# DNS names — Mesh VPN domains, local mDNS, hostnames
DIDX=1
DNS_DOMAINS=(
    "LocalLAN_RootCA" "locallan-rootca" "JioFiberB2BUA" "jiofiber-b2bua"
    "localhost" "br.wln.ims.jio.com"
    "*.ts.net" "*.netbird.cloud" "*.netbird.selfhosted"
    "*.local" "*.lan" "*.home" "*.homelab" "*.internal" "*.trycloudflare.com"
    "$LAN_IP" "$TAILSCALE_IP" "$NETBIRD_IP"
)

for DNS_NAME in "${DNS_DOMAINS[@]}"; do
    [ -z "$DNS_NAME" ] && continue
    echo "DNS.$DIDX = $DNS_NAME" >> "$CNF_FILE"
    DIDX=$((DIDX+1))
done

TOTAL_IPS=$((IDX - 1))
TOTAL_DNS=$((DIDX - 1))
echo "[*] SAN coverage: $TOTAL_IPS IP addresses + $TOTAL_DNS Mesh VPN / DNS domains"

openssl req -x509 -new -nodes -key "$CERTS_DIR/${CERT_NAME}.key" -sha256 -days 3650 \
    -out "$CERTS_DIR/${CERT_NAME}.pem" -config "$CNF_FILE" -extensions v3_ca >/dev/null 2>&1
rm -f "$CNF_FILE"

# CRT alias (same as PEM, some apps prefer .crt extension)
cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/${CERT_NAME}.crt"

# Keep legacy cert.pem / key.pem symlinks so binary can still find them
ln -sf "${CERT_NAME}.pem" "$CERTS_DIR/cert.pem" 2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/cert.pem"
ln -sf "${CERT_NAME}.key" "$CERTS_DIR/key.pem"  2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.key" "$CERTS_DIR/key.pem"
cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/cert.crt"

echo "[*] Packaging Universal Android PKCS#12 bundle (Password: '1234')..."
openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -name "$CERT_NAME" \
    -in "$CERTS_DIR/${CERT_NAME}.pem" -inkey "$CERTS_DIR/${CERT_NAME}.key" \
    -out "$CERTS_DIR/${CERT_NAME}.p12" -passout pass:1234 >/dev/null 2>&1

cp "$CERTS_DIR/${CERT_NAME}.p12" "$CERTS_DIR/${CERT_NAME}.pfx"
# Legacy aliases
ln -sf "${CERT_NAME}.p12" "$CERTS_DIR/cert.p12" 2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.p12" "$CERTS_DIR/cert.p12"
ln -sf "${CERT_NAME}.pfx" "$CERTS_DIR/cert.pfx" 2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.pfx" "$CERTS_DIR/cert.pfx"

# Write instructions
cat << EOF > "$CERTS_DIR/INSTRUCTIONS.txt"
=====================================================================
  JioFiber SIP B2BUA - Generated TLS Certificate Files
=====================================================================

1. ${CERT_NAME}.p12 / ${CERT_NAME}.pfx
   - Friendly Name: $CERT_NAME
   - Password: 1234
   - Install on Android: Settings -> Security -> Install from storage
   - Use this if Android/iOS asks for "Private key is required"

2. ${CERT_NAME}.crt / ${CERT_NAME}.pem
   - Standard X.509 v3 Public Certificate
   - Full /24 SAN coverage: $TOTAL_IPS IPs on all common home subnets
   - Install in Linphone: Settings -> Network -> Root CA Certificate
   - Works on ANY home router — no need to regenerate for new devices

3. ${CERT_NAME}.key
   - 2048-bit Private Key for B2BUA server
   - Used by: b2bua (TLS_KEY_FILE)

Primary detected IP: $LAN_IP
Subnets covered: 192.168.29.x, 192.168.0-3.x, 192.168.31.x,
                 192.168.100.x, 10.0.0-1.x, 10.8.0.x
=====================================================================
EOF

# Copy to script root and user home sipserver
cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/${CERT_NAME}.key" "$SCRIPT_DIR/" 2>/dev/null || true
# Legacy names in root too
ln -sf "${CERT_NAME}.pem" "$SCRIPT_DIR/cert.pem" 2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.pem" "$SCRIPT_DIR/cert.pem"
ln -sf "${CERT_NAME}.key" "$SCRIPT_DIR/key.pem"  2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.key" "$SCRIPT_DIR/key.pem"

if [ -d "/home/${SUDO_USER:-$USER}/sipserver" ] && [ "$SCRIPT_DIR" != "/home/${SUDO_USER:-$USER}/sipserver" ]; then
    cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/${CERT_NAME}.key" "/home/${SUDO_USER:-$USER}/sipserver/" 2>/dev/null || true
    mkdir -p "/home/${SUDO_USER:-$USER}/sipserver/certs"
    cp -r "$CERTS_DIR"/. "/home/${SUDO_USER:-$USER}/sipserver/certs/" 2>/dev/null || true
fi

DESKTOP_DIR="/home/${SUDO_USER:-$USER}/Desktop"
mkdir -p "$DESKTOP_DIR/JioFiber_TLS_Certs" 2>/dev/null || true
cp -r "$CERTS_DIR"/. "$DESKTOP_DIR/JioFiber_TLS_Certs/" 2>/dev/null || true

echo ""
echo "====================================================================="
echo "   [SUCCESS] Native TLS Certificates Generated (Zero Python)!"
echo "   -----------------------------------------------------------------"
echo "   Certificate:    $CERTS_DIR/${CERT_NAME}.pem"
echo "   Private Key:    $CERTS_DIR/${CERT_NAME}.key"
echo "   Android P12:    $CERTS_DIR/${CERT_NAME}.p12  (Password: '1234')"
echo "   SAN Coverage:   $TOTAL_IPS IPs across all common home subnets"
echo "   Desktop Folder: $DESKTOP_DIR/JioFiber_TLS_Certs"
echo "====================================================================="
