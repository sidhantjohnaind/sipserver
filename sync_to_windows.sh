#!/bin/bash
# =====================================================================
# sync_to_windows.sh
# Copies the Linux-generated .env and certs into the Windows b2bua
# folder on the shared NTFS drive (accessible from Windows on reboot).
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ---------- Source paths (Linux) ------------------------------------
LINUX_ENV="${SCRIPT_DIR}/.env"
LINUX_CERTS="${SCRIPT_DIR}/certs"

# ---------- Destination: Windows folder on NTFS ---------------------
# This is the NTFS partition mounted in Linux - same drive Windows boots from.
WIN_B2BUA_DIR="${SCRIPT_DIR}/bin/windows-x64"

# Optionally, also copy to a secondary Windows user folder if it exists.
# Change this to your Windows username if needed (e.g. "Sidhant", "Admin").
WIN_USER_FOLDER=""
for candidate in \
    "/mnt/94C83957C83938B6/Users/sidhant-aind/sipserver" \
    "/mnt/94C83957C83938B6/Users/Sidhant/sipserver" \
    "/mnt/94C83957C83938B6/sipserver" \
    "/mnt/94C83957C83938B6/Admin/sipserver"; do
    if [ -d "$candidate" ]; then
        WIN_USER_FOLDER="$candidate"
        break
    fi
done

echo "====================================================================="
echo "   JioFiber B2BUA - Linux -> Windows Sync"
echo "====================================================================="
echo ""

# ---- Verify source files exist --------------------------------------
if [ ! -f "$LINUX_ENV" ]; then
    echo "[ERROR] .env not found at $LINUX_ENV"
    echo "        Run the b2bua provisioning first: ./b2bua --setup"
    exit 1
fi
if [ ! -f "$LINUX_CERTS/JioFiberB2BUA.pem" ]; then
    echo "[ERROR] Certs not found. Run: bash generate_certs.sh"
    exit 1
fi
if [ ! -d "$WIN_B2BUA_DIR" ]; then
    echo "[ERROR] Windows b2bua folder not found: $WIN_B2BUA_DIR"
    exit 1
fi

# ---- Copy .env ------------------------------------------------------
echo "[1/2] Copying .env -> $WIN_B2BUA_DIR/.env"
cp "$LINUX_ENV" "$WIN_B2BUA_DIR/.env"

# Also convert LF to CRLF so Windows Notepad shows it correctly
if command -v unix2dos &>/dev/null; then
    unix2dos "$WIN_B2BUA_DIR/.env" 2>/dev/null
fi

# ---- Copy certs -----------------------------------------------------
echo "[2/2] Copying JioFiberB2BUA certs -> $WIN_B2BUA_DIR/"
for f in \
    JioFiberB2BUA.pem \
    JioFiberB2BUA.key \
    JioFiberB2BUA.crt \
    JioFiberB2BUA.p12 \
    JioFiberB2BUA.pfx; do
    if [ -f "$LINUX_CERTS/$f" ]; then
        cp "$LINUX_CERTS/$f" "$WIN_B2BUA_DIR/$f"
        echo "    -> $f"
    fi
done

# Legacy names too (cert.pem / key.pem) so Windows b2bua picks them up
cp "$LINUX_CERTS/JioFiberB2BUA.pem" "$WIN_B2BUA_DIR/cert.pem"
cp "$LINUX_CERTS/JioFiberB2BUA.key" "$WIN_B2BUA_DIR/key.pem"
cp "$LINUX_CERTS/JioFiberB2BUA.crt" "$WIN_B2BUA_DIR/cert.crt"
cp "$LINUX_CERTS/JioFiberB2BUA.p12" "$WIN_B2BUA_DIR/cert.p12"
cp "$LINUX_CERTS/JioFiberB2BUA.pfx" "$WIN_B2BUA_DIR/cert.pfx"
echo "    -> Legacy aliases: cert.pem, key.pem, cert.p12"

# ---- Optional: copy to secondary Windows user folder ----------------
if [ -n "$WIN_USER_FOLDER" ]; then
    echo ""
    echo "[+] Also syncing to $WIN_USER_FOLDER"
    mkdir -p "$WIN_USER_FOLDER/certs"
    cp "$LINUX_ENV" "$WIN_USER_FOLDER/.env"
    cp -r "$LINUX_CERTS"/. "$WIN_USER_FOLDER/certs/"
fi

echo ""
echo "====================================================================="
echo "   [DONE] Files synced to Windows folder!"
echo ""
echo "   On Windows, run b2bua_msvc.exe from:"
echo "   $(echo $WIN_B2BUA_DIR | sed 's|/mnt/94C83957C83938B6|D:|;s|/|\\|g')"
echo ""
echo "   Files ready in Windows:"
echo "   .env               <- your SIP credentials & config"
echo "   JioFiberB2BUA.pem  <- install as Root CA in Linphone"
echo "   JioFiberB2BUA.p12  <- install on Android (password: 1234)"
echo "   cert.pem / key.pem <- auto-loaded by b2bua_msvc.exe"
echo "====================================================================="
