#!/bin/bash
# =====================================================================
# generate_certs.sh - 100% Native TLS Certificate & Android P12 Generator
# (Zero Python Dependency - Uses Native OpenSSL)
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CERTS_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERTS_DIR"

CERT_NAME="JioFiberB2BUA"

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

echo "[*] Generating X.509 v3 Certificate with SANs & CA:TRUE..."
cat << EOF > /tmp/b2bua_san.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = IN
O = JioFiberB2BUA
CN = JioFiber B2BUA ($LAN_IP)

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyCertSign, cRLSign, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
IP.1 = $LAN_IP
IP.2 = 127.0.0.1
DNS.1 = $LAN_IP
DNS.2 = localhost
DNS.3 = JioFiberB2BUA
DNS.4 = br.wln.ims.jio.com
EOF

openssl req -x509 -new -nodes -key "$CERTS_DIR/${CERT_NAME}.key" -sha256 -days 3650 \
    -out "$CERTS_DIR/${CERT_NAME}.pem" -config /tmp/b2bua_san.cnf -extensions v3_ca >/dev/null 2>&1
rm -f /tmp/b2bua_san.cnf

# CRT alias (same as PEM, some apps prefer .crt extension)
cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/${CERT_NAME}.crt"

# Keep legacy cert.pem / key.pem symlinks so binary can still find them
ln -sf "${CERT_NAME}.pem" "$CERTS_DIR/cert.pem" 2>/dev/null || cp "$CERTS_DIR/${CERT_NAME}.pem" "$CERTS_DIR/cert.pem"
ln -sf "${CERT_NAME}.key" "$CERTS_DIR/key.pem" 2>/dev/null  || cp "$CERTS_DIR/${CERT_NAME}.key" "$CERTS_DIR/key.pem"
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
   - Standard X.509 v3 Public Certificate (with SAN & CA:TRUE)
   - Install in Linphone: Settings -> Network -> Root CA Certificate
   - CN: JioFiber B2BUA ($LAN_IP)

3. ${CERT_NAME}.key
   - 2048-bit Private Key for B2BUA server
   - Used by: b2bua (TLS_KEY_FILE)

Configured IP SAN: $LAN_IP
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
echo "   Desktop Folder: $DESKTOP_DIR/JioFiber_TLS_Certs"
echo "====================================================================="
