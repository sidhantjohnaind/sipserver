#!/bin/bash
# =====================================================================
# b2bua_sync.sh - Universal Multi-Boot Sync & Backup Tool (Linux)
# 
# Works on ANY setup:
# 1. Direct NTFS/Windows auto-mount discovery across all drives & users
# 2. Universal 1-Click ZIP Archive export/import for USB / Cloud sync
# =====================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ---- 1. Linux Local Install Path Discovery --------------------------
LINUX_DIR=""
for candidate in \
    "$HOME/sipserver" \
    "/home/${SUDO_USER:-$USER}/sipserver" \
    "$SCRIPT_DIR"; do
    if [ -d "$candidate" ] && [ -f "$candidate/.env" -o -d "$candidate/certs" ]; then
        LINUX_DIR="$candidate"
        break
    fi
done
[ -z "$LINUX_DIR" ] && LINUX_DIR="$HOME/sipserver"

# ---- 2. Windows Partition Auto-Discovery ----------------------------
# Scans all mounted Windows drives (/mnt/*, /media/*, /run/media/*)
WIN_DIRS=()

if [ -d "$SCRIPT_DIR/bin/windows-x64" ]; then
    WIN_DIRS+=("$SCRIPT_DIR/bin/windows-x64")
fi

for mount_root in /mnt/* /media/*/* /run/media/*/*; do
    [ -d "$mount_root" ] || continue
    [[ "$mount_root" =~ /mnt/wsl ]] && continue

    for sub in \
        "Program Files/JioFiberB2BUA" \
        "Program Files (x86)/JioFiberB2BUA" \
        "Programming/sipserver/bin/windows-x64" \
        "sipserver/bin/windows-x64" \
        "sipserver" \
        "Users"/*"/sipserver"; do
        
        for target in "$mount_root"/$sub; do
            if [ -d "$target" ]; then
                already_added=0
                for existing in "${WIN_DIRS[@]}"; do
                    [ "$existing" = "$target" ] && already_added=1 && break
                done
                [ $already_added -eq 0 ] && WIN_DIRS+=("$target")
            fi
        done
    done
done

NTFS_DIR="${WIN_DIRS[0]:-$SCRIPT_DIR/bin/windows-x64}"

# Files to sync
SYNC_FILES=(
    ".env"
)

# ---- Colors ---------------------------------------------------------
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
BLU='\033[1;34m'; CYN='\033[0;36m'; RST='\033[0m'

banner() {
    echo -e "${BLU}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║   JioFiber B2BUA — Universal Multi-Boot Sync Tool        ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${RST}"
}

get_newest_timestamp() {
    local dir="$1"
    local newest=0
    for f in "${SYNC_FILES[@]}"; do
        local check_path="$dir/$f"
        [ -f "$check_path" ] || check_path="$dir/certs/$f"
        [ -f "$check_path" ] || continue
        ts=$(stat -c %Y "$check_path" 2>/dev/null || echo 0)
        [ "$ts" -gt "$newest" ] && newest=$ts
    done
    echo "$newest"
}

do_copy() {
    local SRC="$1"
    local DST="$2"
    local label="$3"
    local copied=0

    echo -e "\n${CYN}[→] Syncing: ${label}${RST}"
    echo "    From: $SRC"
    echo "    To  : $DST"
    echo ""

    mkdir -p "$DST" 2>/dev/null || true

    for f in "${SYNC_FILES[@]}"; do
        src_file="$SRC/$f"
        [ ! -f "$src_file" ] && src_file="$SRC/certs/$f"
        dst_file="$DST/$f"

        if [ -L "$src_file" ]; then
            src_file="$(readlink -f "$src_file")"
        fi

        if [ -f "$src_file" ]; then
            cp "$src_file" "$dst_file" 2>/dev/null && \
                echo -e "    ${GRN}✓${RST}  $f" || \
                echo -e "    ${YEL}!${RST}  $f (skipped/permission)"
            copied=$((copied + 1))
        else
            echo -e "    ${YEL}-${RST}  $f (not found in source)"
        fi
    done

    echo ""
    echo -e "  ${GRN}[DONE]${RST} Synced $copied files."
}

push_to_windows() {
    echo -e "${YEL}► Pushing: Linux → All Detected Windows/NTFS Partitions${RST}"
    if [ ${#WIN_DIRS[@]} -eq 0 ]; then
        echo -e "${RED}[ERROR]${RST} No mounted Windows partitions found."
        echo "        Use Option 5 to export a Portable ZIP Archive instead!"
        return
    fi
    for win_dest in "${WIN_DIRS[@]}"; do
        do_copy "$LINUX_DIR" "$win_dest" "Linux -> Windows ($win_dest)"
    done
    echo -e "  ${BLU}[i]${RST} Configuration is updated for Windows boot."
}

pull_from_windows() {
    echo -e "${YEL}◄ Pulling: Windows/NTFS → Linux${RST}"
    if [ ${#WIN_DIRS[@]} -eq 0 ]; then
        echo -e "${RED}[ERROR]${RST} No mounted Windows partitions found."
        echo "        Use Option 6 to import from a Portable ZIP Archive instead!"
        return
    fi
    do_copy "$NTFS_DIR" "$LINUX_DIR" "Windows ($NTFS_DIR) -> Linux"
    
    if command -v systemctl &>/dev/null && systemctl is-active jiofiber-b2bua &>/dev/null; then
        echo -e "  ${CYN}[↺]${RST} Restarting Linux service..."
        sudo systemctl restart jiofiber-b2bua && echo -e "  ${GRN}[✓]${RST} Linux service restarted." || true
    fi
}

auto_sync() {
    echo -e "${YEL}⚡ Auto-detecting newest configuration...${RST}"
    linux_ts=$(get_newest_timestamp "$LINUX_DIR")
    ntfs_ts=$(get_newest_timestamp "$NTFS_DIR")

    echo "  Linux timestamp : $(date -d "@$linux_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$linux_ts")"
    echo "  Windows timestamp: $(date -d "@$ntfs_ts"  '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ntfs_ts")"
    echo ""

    if [ "$linux_ts" -ge "$ntfs_ts" ]; then
        echo -e "  ${GRN}Linux has newer config → pushing to Windows partitions${RST}"
        push_to_windows
    else
        echo -e "  ${GRN}Windows has newer config → pulling to Linux${RST}"
        pull_from_windows
    fi
}

export_zip() {
    echo -e "${YEL}📦 Exporting Portable Config ZIP Archive...${RST}"
    local OUT_ZIP="$HOME/Desktop/JioFiber_Config_Backup.zip"
    [ -d "$HOME/Desktop" ] || OUT_ZIP="$SCRIPT_DIR/JioFiber_Config_Backup.zip"
    
    local TEMP_DIR="/tmp/jiofiber_zip_export"
    rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"

    for f in "${SYNC_FILES[@]}"; do
        src_file="$LINUX_DIR/$f"
        [ ! -f "$src_file" ] && src_file="$LINUX_DIR/certs/$f"
        if [ -f "$src_file" ]; then
            [ -L "$src_file" ] && src_file="$(readlink -f "$src_file")"
            cp "$src_file" "$TEMP_DIR/" 2>/dev/null || true
        fi
    done

    (cd "$TEMP_DIR" && zip -q -r "$OUT_ZIP" ./*)
    rm -rf "$TEMP_DIR"

    echo -e "  ${GRN}[SUCCESS]${RST} Exported backup archive to:"
    echo -e "  ${CYN}$OUT_ZIP${RST}"
    echo "  You can copy this ZIP to any USB drive, Windows partition, or cloud storage!"
}

import_zip() {
    echo -e "${YEL}📥 Import from Portable Config ZIP Archive...${RST}"
    read -rp "  Enter full path to ZIP file: " ZIP_PATH
    if [ ! -f "$ZIP_PATH" ]; then
        echo -e "${RED}[ERROR]${RST} File not found: $ZIP_PATH"
        return
    fi
    local TEMP_DIR="/tmp/jiofiber_zip_import"
    rm -rf "$TEMP_DIR" && mkdir -p "$TEMP_DIR"
    unzip -q -o "$ZIP_PATH" -d "$TEMP_DIR"

    do_copy "$TEMP_DIR" "$LINUX_DIR" "Imported ZIP Archive -> Linux"
    rm -rf "$TEMP_DIR"

    if command -v systemctl &>/dev/null && systemctl is-active jiofiber-b2bua &>/dev/null; then
        sudo systemctl restart jiofiber-b2bua && echo -e "  ${GRN}[✓]${RST} Service restarted." || true
    fi
}

show_menu() {
    banner
    echo "  Linux Source  : $LINUX_DIR"
    if [ ${#WIN_DIRS[@]} -gt 0 ]; then
        echo "  Windows Target: $NTFS_DIR"
        [ ${#WIN_DIRS[@]} -gt 1 ] && echo "  Total Windows Locations Found: ${#WIN_DIRS[@]}"
    else
        echo "  Windows Target: [No mounted Windows partition detected]"
    fi
    echo ""
    echo -e "  ${BLU}1)${RST}  Push Linux ➔ Windows Partitions   (direct disk-to-disk sync)"
    echo -e "  ${BLU}2)${RST}  Pull Windows ➔ Linux              (read from mounted Windows partition)"
    echo -e "  ${BLU}3)${RST}  Auto Sync (Newest Wins)          (auto-resolve newest files)"
    echo -e "  ${BLU}4)${RST}  Export to Portable ZIP Archive   (save .env + certs for USB / other PCs)"
    echo -e "  ${BLU}5)${RST}  Import from Portable ZIP Archive (load .env + certs from ZIP file)"
    echo -e "  ${BLU}q)${RST}  Quit"
    echo ""
    read -rp "  Choose option [1/2/3/4/5/q]: " choice

    case "$choice" in
        1) push_to_windows ;;
        2) pull_from_windows ;;
        3) auto_sync ;;
        4) export_zip ;;
        5) import_zip ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "Invalid option."; show_menu ;;
    esac
}

case "${1:-menu}" in
    push)   banner; push_to_windows ;;
    pull)   banner; pull_from_windows ;;
    auto)   banner; auto_sync ;;
    export) banner; export_zip ;;
    import) banner; import_zip ;;
    menu|*) show_menu ;;
esac
