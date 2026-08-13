#!/bin/bash
# =====================================================================
# build_appimage.sh - Build Linux 1-Click AppImage Package
# =====================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$ROOT_DIR/AppDir"

echo "====================================================================="
echo "   Building Linux 1-Click AppImage Package (JioFiber_B2BUA-x86_64.AppImage)"
echo "====================================================================="

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin"
mkdir -p "$APP_DIR/usr/share/icons/hicolor/256x256/apps"

# 1. Copy Binary
BIN_PATH="$ROOT_DIR/bin/linux-amd64/b2bua"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$ROOT_DIR/b2bua"
fi

if [ ! -f "$BIN_PATH" ]; then
    echo "[!] Error: Linux b2bua binary not found at $BIN_PATH"
    exit 1
fi

cp "$BIN_PATH" "$APP_DIR/usr/bin/b2bua"
chmod +x "$APP_DIR/usr/bin/b2bua"

# 2. Create AppRun Launcher Script
cat <<'EOF' > "$APP_DIR/AppRun"
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export PATH="$HERE/usr/bin:$PATH"

if [ "$EUID" -ne 0 ]; then
  echo "[!] Note: AppImage running in interactive user mode."
fi

exec "$HERE/usr/bin/b2bua" "$@"
EOF
chmod +x "$APP_DIR/AppRun"

# 3. Create .desktop file
cat <<EOF > "$APP_DIR/b2bua.desktop"
[Desktop Entry]
Type=Application
Name=JioFiber SIP B2BUA
Comment=Lightweight native SIP B2BUA proxy for JioFiber VoIP
Exec=b2bua
Icon=jiofiber-b2bua
Categories=Network;Telephony;
Terminal=true
EOF

# 4. Download appimagetool if missing
APPIMAGETOOL="$ROOT_DIR/appimagetool-x86_64.AppImage"
if [ ! -f "$APPIMAGETOOL" ]; then
    echo "[*] Downloading appimagetool..."
    curl -sSL -L "https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage" -o "$APPIMAGETOOL"
    chmod +x "$APPIMAGETOOL"
fi

# 5. Package into AppImage
OUTPUT_APPIMAGE="$ROOT_DIR/JioFiber_B2BUA-x86_64.AppImage"
ARCH=x86_64 "$APPIMAGETOOL" "$APP_DIR" "$OUTPUT_APPIMAGE"

echo "====================================================================="
echo "   [SUCCESS] Built Linux AppImage: $OUTPUT_APPIMAGE"
echo "====================================================================="
