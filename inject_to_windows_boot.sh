#!/bin/bash
# =====================================================================
# inject_to_windows_boot.sh - 1-Click Multi-Boot Windows Auto-Installer
# 
# Scans all mounted Windows partitions from Linux, copies certificates
# to Windows Desktops, and schedules a 1-time self-deleting auto-installer
# in the Windows Startup directory so certificates are trusted on next boot.
# =====================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CERT_NAME="LocalLAN_RootCA"

# Locate certificate file
CERT_FILE=""
for c in "$SCRIPT_DIR/certs/${CERT_NAME}.crt" "$SCRIPT_DIR/${CERT_NAME}.crt" "$SCRIPT_DIR/certs/${CERT_NAME}.pem"; do
    if [ -f "$c" ]; then
        CERT_FILE="$c"
        break
    fi
done

if [ -z "$CERT_FILE" ]; then
    echo "[!] Certificates not found. Generating now..."
    bash "$SCRIPT_DIR/generate_certs.sh"
    CERT_FILE="$SCRIPT_DIR/certs/${CERT_NAME}.crt"
fi

echo "====================================================================="
echo "   Universal Multi-Boot Windows Auto-Trust Injector"
echo "====================================================================="
echo "[*] Using Certificate: $CERT_FILE"
echo ""

# Create One-Time Self-Deleting Windows Startup Batch File
AUTO_BAT="/tmp/AutoInstall_${CERT_NAME}.bat"
cat << 'BAT_EOF' > "$AUTO_BAT"
@echo off
setlocal EnableDelayedExpansion

:: 1. Check if certificate is already in Windows Trusted Root Store
certutil -verifystore "ROOT" "LocalLAN_RootCA" >nul 2>&1
if %errorlevel% equ 0 (
    del "%~f0" >nul 2>&1
    exit /b 0
)

:: 2. Auto-elevate to Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: 3. Find certificate on any local drive
set "FOUND_CERT="
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\" (
        for %%P in (
            "%%D:\Users\%USERNAME%\Desktop\LocalLAN_TLS_Certs\LocalLAN_RootCA.crt"
            "%%D:\Program Files\LocalLAN_TLS\LocalLAN_RootCA.crt"
            "%%D:\Program Files\JioFiberB2BUA\LocalLAN_RootCA.crt"
            "%%D:\Programming\sipserver\bin\windows-x64\LocalLAN_RootCA.crt"
            "%%D:\Programming\lan-tls\certs\LocalLAN_RootCA.crt"
            "%%D:\LocalLAN_RootCA.crt"
        ) do (
            if exist "%%~P" (
                set "FOUND_CERT=%%~P"
                goto :install_cert
            )
        )
    )
)

:install_cert
if defined FOUND_CERT (
    certutil -addstore -f "ROOT" "%FOUND_CERT%" >nul 2>&1
    if %errorlevel% equ 0 (
        :: Success -> Clean up and delete self from Startup permanently
        del "%~f0" >nul 2>&1
        exit /b 0
    )
)
exit /b 0
BAT_EOF

# Scan all mounted partitions for Windows OS installations
WINDOWS_FOUND=0

for mount in /mnt/* /media/*/* /run/media/*/*; do
    [ -d "$mount" ] || continue
    
    # Check if this mount is a Windows system drive
    if [ -d "$mount/Windows/System32" ] || [ -d "$mount/windows/system32" ]; then
        WINDOWS_FOUND=$((WINDOWS_FOUND + 1))
        echo "[+] Found Windows OS Partition: $mount"
        
        # 1. Copy cert folder to all User Desktops
        if [ -d "$mount/Users" ]; then
            for user_dir in "$mount/Users"/*; do
                if [ -d "$user_dir/Desktop" ]; then
                    u_name=$(basename "$user_dir")
                    [[ "$u_name" =~ ^(Public|Default|All Users)$ ]] && continue
                    dest_desktop="$user_dir/Desktop/LocalLAN_TLS_Certs"
                    mkdir -p "$dest_desktop"
                    cp -r "$SCRIPT_DIR/certs"/* "$dest_desktop/" 2>/dev/null || true
                    cp "$SCRIPT_DIR/install_ca.bat" "$dest_desktop/install_ca_cert.bat" 2>/dev/null || true
                    echo "    -> Injected certificates to Desktop of user: $u_name"
                fi
            done
        fi
        
        # 2. Inject 1-Time Self-Deleting Auto-Installer into Startup
        for s_dir in \
            "$mount/ProgramData/Microsoft/Windows/Start Menu/Programs/Startup" \
            "$mount/ProgramData/Microsoft/Windows/Start menu/Programs/Startup"; do
            if [ -d "$s_dir" ]; then
                cp "$AUTO_BAT" "$s_dir/AutoInstall_${CERT_NAME}.bat"
                echo "    -> Injected 1-time Auto-Installer into Windows Startup: $s_dir"
            fi
        done
        echo ""
    fi
done

rm -f "$AUTO_BAT"

if [ $WINDOWS_FOUND -eq 0 ]; then
    echo "[!] No mounted Windows partitions found on /mnt or /media."
    echo "    Mount your Windows drive first (e.g. sudo mount /dev/nvme0n1p3 /mnt/win) and re-run!"
else
    echo "====================================================================="
    echo "   [SUCCESS] Injected into $WINDOWS_FOUND Windows installations!"
    echo "   When you boot into Windows, the certificate will automatically"
    echo "   install into Windows Trusted Root Authorities and clean itself up."
    echo "====================================================================="
fi
