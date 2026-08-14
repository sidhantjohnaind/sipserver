#!/bin/bash
# =====================================================================
# generate_certs.sh - 100% Native TLS Certificate & Android P12 Generator
# (Zero Python Dependency - Uses Native OpenSSL)
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CERTS_DIR="$SCRIPT_DIR/certs"
mkdir -p "$CERTS_DIR"

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
    LAN_IP="192.168.29.195"
fi

# Allow overriding LAN IP via first argument if supplied
if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    LAN_IP="$1"
fi

echo "[*] Local LAN Host IP: $LAN_IP"
echo "[*] Generating 2048-bit RSA Private Key..."
openssl genrsa -out "$CERTS_DIR/key.pem" 2048 >/dev/null 2>&1

echo "[*] Generating X.509 v3 Certificate with SANs & CA:TRUE..."
cat << EOF > /tmp/b2bua_san.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = IN
O = JioB2BUA
CN = $LAN_IP

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

openssl req -x509 -new -nodes -key "$CERTS_DIR/key.pem" -sha256 -days 3650 \
    -out "$CERTS_DIR/cert.pem" -config /tmp/b2bua_san.cnf -extensions v3_ca >/dev/null 2>&1
rm -f /tmp/b2bua_san.cnf

cp "$CERTS_DIR/cert.pem" "$CERTS_DIR/cert.crt"

echo "[*] Packaging Universal Android PKCS#12 bundle (Password: '1234')..."
openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -in "$CERTS_DIR/cert.pem" -inkey "$CERTS_DIR/key.pem" \
    -out "$CERTS_DIR/cert.p12" -passout pass:1234 >/dev/null 2>&1

cp "$CERTS_DIR/cert.p12" "$CERTS_DIR/cert.pfx"

# Write instructions
cat << EOF > "$CERTS_DIR/INSTRUCTIONS.txt"
=====================================================================
  JioFiber SIP B2BUA - Generated TLS Certificate Files
=====================================================================

1. cert.p12 / cert.pfx
   - Password: 1234
   - Use this if Android system asks for "Private key is required"

2. cert.crt / cert.pem
   - Standard X.509 v3 Public Certificate (with SAN & CA:TRUE)
   - Use this inside Linphone (Settings -> Network -> Root CA Certificate)

3. key.pem
   - 2048-bit Private Key for B2BUA server

Configured IP SAN: $LOCAL_IP
=====================================================================
EOF

# Copy to root and Desktop
cp "$CERTS_DIR/cert.pem" "$CERTS_DIR/key.pem" "$SCRIPT_DIR/" 2>/dev/null || true
mkdir -p "$HOME/Desktop/JioFiber_TLS_Certs" 2>/dev/null || true
cp "$CERTS_DIR"/* "$HOME/Desktop/JioFiber_TLS_Certs/" 2>/dev/null || true

echo ""
echo "====================================================================="
echo "   [SUCCESS] Native TLS Certificates Generated (Zero Python)!"
echo "   -----------------------------------------------------------------"
echo "   Certificate:    $CERTS_DIR/cert.pem"
echo "   Private Key:    $CERTS_DIR/key.pem"
echo "   Android P12:    $CERTS_DIR/cert.p12 (Password: '1234')"
echo "   Desktop Folder: $HOME/Desktop/JioFiber_TLS_Certs"
echo "====================================================================="
