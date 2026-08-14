#!/bin/bash
# =====================================================================
# install_ca_cert.sh - 1-Click Generic CA Certificate Trust Installer
# Works on: Ubuntu, Debian, Fedora, RHEL, CentOS, Arch, openSUSE, Alpine
# Also installs into Chrome / Chromium / Edge / Brave / Firefox NSS databases.
# =====================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CERT_NAME="LocalLAN_RootCA"

# Locate certificate file
CERT_FILE=""
for candidate in \
    "$SCRIPT_DIR/certs/${CERT_NAME}.pem" \
    "$SCRIPT_DIR/certs/${CERT_NAME}.crt" \
    "$SCRIPT_DIR/${CERT_NAME}.pem" \
    "$SCRIPT_DIR/${CERT_NAME}.crt" \
    "$SCRIPT_DIR/cert.pem" \
    "$SCRIPT_DIR/cert.crt" \
    "/home/${SUDO_USER:-$USER}/sipserver/certs/${CERT_NAME}.pem"; do
    if [ -f "$candidate" ]; then
        CERT_FILE="$candidate"
        break
    fi
done

if [ -z "$CERT_FILE" ]; then
    echo "[ERROR] Certificate file not found! Run ./generate_certs.sh first."
    exit 1
fi

echo "====================================================================="
echo "   Installing CA Certificate: $CERT_NAME"
echo "   Source: $CERT_FILE"
echo "====================================================================="

# Check for root / sudo
SUDO=""
if [ "$EUID" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        echo "[ERROR] Please run as root or install sudo."
        exit 1
    fi
fi

# Detect Distro & Install to System Trust Store
if [ -d "/usr/local/share/ca-certificates" ]; then
    # Debian / Ubuntu / Mint / Kali / PopOS
    echo "[*] Detected Debian/Ubuntu family..."
    $SUDO cp "$CERT_FILE" "/usr/local/share/ca-certificates/${CERT_NAME}.crt"
    $SUDO update-ca-certificates
elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
    # Fedora / RHEL / CentOS / Rocky / Alma
    echo "[*] Detected RHEL/Fedora family..."
    $SUDO cp "$CERT_FILE" "/etc/pki/ca-trust/source/anchors/${CERT_NAME}.crt"
    $SUDO update-ca-trust
elif [ -d "/etc/ca-certificates/trust-source/anchors" ]; then
    # Arch Linux / Manjaro
    echo "[*] Detected Arch Linux family..."
    $SUDO cp "$CERT_FILE" "/etc/ca-certificates/trust-source/anchors/${CERT_NAME}.crt"
    $SUDO trust extract-compat
elif [ -d "/etc/pki/trust/anchors" ]; then
    # openSUSE / SLES
    echo "[*] Detected openSUSE family..."
    $SUDO cp "$CERT_FILE" "/etc/pki/trust/anchors/${CERT_NAME}.crt"
    $SUDO update-ca-certificates
elif [ -d "/usr/local/share/ca-certificates" ] || [ -f "/sbin/update-ca-certificates" ]; then
    # Alpine Linux
    echo "[*] Detected Alpine Linux..."
    $SUDO cp "$CERT_FILE" "/usr/local/share/ca-certificates/${CERT_NAME}.crt"
    $SUDO update-ca-certificates
else
    echo "[!] Unknown distribution! Copied to /etc/ssl/certs/ directly."
    $SUDO cp "$CERT_FILE" "/etc/ssl/certs/${CERT_NAME}.pem"
fi

# Install to Browser NSS Databases (Chrome, Brave, Edge, Firefox)
echo "[*] Checking user browser NSS databases..."
if command -v certutil &>/dev/null; then
    # Chrome / Chromium / Edge / Brave default NSS store
    for nssdb in \
        "$HOME/.pki/nssdb" \
        "/home/${SUDO_USER:-$USER}/.pki/nssdb"; do
        if [ -d "$nssdb" ]; then
            certutil -d sql:"$nssdb" -A -t "C,," -n "$CERT_NAME" -i "$CERT_FILE" 2>/dev/null || true
            echo "    -> Added to NSS DB: $nssdb"
        fi
    done

    # Firefox profiles
    for ff_profile in \
        "$HOME/.mozilla/firefox/"*.default* \
        "/home/${SUDO_USER:-$USER}/.mozilla/firefox/"*.default*; do
        if [ -d "$ff_profile" ]; then
            certutil -d sql:"$ff_profile" -A -t "C,," -n "$CERT_NAME" -i "$CERT_FILE" 2>/dev/null || true
            echo "    -> Added to Firefox profile: $ff_profile"
        fi
    done
fi

echo ""
echo "====================================================================="
echo "   [SUCCESS] CA Certificate is now trusted on this Linux machine!"
echo "   All local tools (curl, browsers, Python) now trust HTTPS / TLS."
echo "====================================================================="
