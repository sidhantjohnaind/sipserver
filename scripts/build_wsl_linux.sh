#!/bin/bash
# =====================================================================
# build_wsl_linux.sh - Build Linux B2BUA Binary in WSL
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

echo "====================================================================="
echo "    Building JioFiber SIP B2BUA for Linux (x86_64)"
echo "====================================================================="

# Ensure build tools are installed
if ! command -v gcc &> /dev/null; then
    echo "[*] Installing GCC and build dependencies in WSL..."
    sudo apt-get update && sudo apt-get install -y build-essential libssl-dev
fi

PJ_DIR="$SCRIPT_DIR/third_party/pjproject-2.15.1"

# Compile src/b2bua.c with PJSIP headers and libraries
echo "[*] Compiling src/b2bua.c into bin/linux-amd64/b2bua..."

gcc -O2 -DPJ_IS_BIG_ENDIAN=0 -DPJ_IS_LITTLE_ENDIAN=1 \
    -I"$PJ_DIR" \
    -I"$PJ_DIR/pjlib/include" \
    -I"$PJ_DIR/pjlib-util/include" \
    -I"$PJ_DIR/pjnath/include" \
    -I"$PJ_DIR/pjmedia/include" \
    -I"$PJ_DIR/pjsip/include" \
    -L"$SCRIPT_DIR/bin/linux-amd64/lib" \
    src/b2bua.c -o bin/linux-amd64/b2bua \
    -lpjsua -lpjsip-ua -lpjsip-simple -lpjsip -lpjmedia -lpjmedia-codec -lpjmedia-videodev -lpjmedia-audiodev -lpj-ssl -lpj -lssl -lcrypto -lm -lrt -lpthread -ldl

if [ $? -eq 0 ]; then
    echo ""
    echo "====================================================================="
    echo " [SUCCESS] Compiled bin/linux-amd64/b2bua successfully!"
    echo "====================================================================="
else
    echo "[!] Build failed."
fi
