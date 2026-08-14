#!/bin/bash
# =====================================================================
# b2bua_sync.sh - Universal Bidirectional Dual-Boot / Multi-OS Sync
# Auto-detects Linux home, WSL, and all mounted Windows / NTFS partitions.
#
# Usage:
#   bash b2bua_sync.sh            -> interactive menu
#   bash b2bua_sync.sh push       -> Linux -> Windows / NTFS partitions
#   bash b2bua_sync.sh pull       -> Windows / NTFS -> Linux
#   bash b2bua_sync.sh auto       -> auto-detect newer timestamp & sync
#   bash b2bua_sync.sh diff       -> inspect differences between OSes
# =====================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ---- Dynamic Path Discovery -----------------------------------------

# 1. Linux / WSL Home Directory
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

# 2. Windows / NTFS Shared Partition Discovery
# Automatically scans /mnt/*, /media/*, and /run/media/* for sipserver windows binaries/data
WIN_DIRS=()

# Local repo windows binary folder (if on NTFS)
if [ -d "$SCRIPT_DIR/bin/windows-x64" ]; then
    WIN_DIRS+=("$SCRIPT_DIR/bin/windows-x64")
fi

# Search mounted drives
for mount_root in /mnt/* /media/*/* /run/media/*/*; do
    [ -d "$mount_root" ] || continue
    # Skip standard Linux mounts like /mnt/wsl
    [[ "$mount_root" =~ /mnt/wsl ]] && continue

    # Check for sipserver folders on mounted drive
    for sub in "Programming/sipserver/bin/windows-x64" "sipserver/bin/windows-x64" "sipserver" "Program Files/JioFiber SIP Server"; do
        target="$mount_root/$sub"
        if [ -d "$target" ]; then
            # Avoid duplicates
            already_added=0
            for existing in "${WIN_DIRS[@]}"; do
                [ "$existing" = "$target" ] && already_added=1 && break
            done
            [ $already_added -eq 0 ] && WIN_DIRS+=("$target")
        fi
    done
done

# Primary Windows Target
NTFS_DIR="${WIN_DIRS[0]:-$SCRIPT_DIR/bin/windows-x64}"

# Files to sync
SYNC_FILES=(
    ".env"
    "JioFiberB2BUA.pem"
    "JioFiberB2BUA.key"
    "JioFiberB2BUA.crt"
    "JioFiberB2BUA.p12"
    "JioFiberB2BUA.pfx"
    "cert.pem"
    "key.pem"
    "cert.crt"
    "cert.p12"
    "cert.pfx"
)

# ---- Colors ---------------------------------------------------------
RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'
BLU='\033[1;34m'; CYN='\033[0;36m'; RST='\033[0m'

banner() {
    echo -e "${BLU}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║   JioFiber B2BUA — Universal Multi-Boot OS Sync Tool     ║"
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
    for win_dest in "${WIN_DIRS[@]}"; do
        do_copy "$LINUX_DIR" "$win_dest" "Linux -> Windows Target ($win_dest)"
    done
    echo -e "  ${BLU}[i]${RST} Configuration is now updated for Windows boot."
}

pull_from_windows() {
    echo -e "${YEL}◄ Pulling: Windows/NTFS → Linux${RST}"
    do_copy "$NTFS_DIR" "$LINUX_DIR" "Windows Target ($NTFS_DIR) -> Linux"
    
    # Restart service if active
    if command -v systemctl &>/dev/null && systemctl is-active jiofiber-b2bua &>/dev/null; then
        echo -e "  ${CYN}[↺]${RST} Restarting Linux service..."
        sudo systemctl restart jiofiber-b2bua && echo -e "  ${GRN}[✓]${RST} Linux service restarted." || true
    fi
}

auto_sync() {
    echo -e "${YEL}⚡ Auto-detecting newest configuration between OSes...${RST}"
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

show_diff() {
    echo -e "${YEL}=== Configuration Difference Check ===${RST}"
    for f in "${SYNC_FILES[@]}"; do
        lf="$LINUX_DIR/$f"; [ ! -f "$lf" ] && lf="$LINUX_DIR/certs/$f"
        wf="$NTFS_DIR/$f";  [ ! -f "$wf" ] && wf="$NTFS_DIR/certs/$f"
        [ -L "$lf" ] && lf="$(readlink -f "$lf")"
        [ -L "$wf" ] && wf="$(readlink -f "$wf")"

        if [ -f "$lf" ] && [ -f "$wf" ]; then
            if ! diff -q "$lf" "$wf" &>/dev/null; then
                echo -e "\n${RED}DIFFER:${RST} $f"
                diff -u "$lf" "$wf" | head -15 || true
            else
                echo -e "  ${GRN}IDENTICAL:${RST} $f"
            fi
        elif [ -f "$lf" ]; then
            echo -e "  ${YEL}LINUX ONLY:${RST} $f"
        elif [ -f "$wf" ]; then
            echo -e "  ${YEL}WINDOWS ONLY:${RST} $f"
        fi
    done
    echo ""
}

show_menu() {
    banner
    echo "  Linux Source  : $LINUX_DIR"
    echo "  Windows Target: $NTFS_DIR"
    if [ ${#WIN_DIRS[@]} -gt 1 ]; then
        echo "  Additional Windows Partitions Found: $((${#WIN_DIRS[@]} - 1))"
    fi
    echo ""
    echo -e "  ${BLU}1)${RST}  Push Linux ➔ Windows     (sync credentials/certs to Windows)"
    echo -e "  ${BLU}2)${RST}  Pull Windows ➔ Linux     (update Linux with changes made on Windows)"
    echo -e "  ${BLU}3)${RST}  Auto Sync (Newest Wins)   (automatic bidirectional resolution)"
    echo -e "  ${BLU}4)${RST}  Show File Differences     (compare .env and certificates)"
    echo -e "  ${BLU}q)${RST}  Quit"
    echo ""
    read -rp "  Choose option [1/2/3/4/q]: " choice

    case "$choice" in
        1) push_to_windows ;;
        2) pull_from_windows ;;
        3) auto_sync ;;
        4) show_diff ;;
        q|Q) echo "Exiting."; exit 0 ;;
        *) echo "Invalid option."; show_menu ;;
    esac
}

case "${1:-menu}" in
    push)   banner; push_to_windows ;;
    pull)   banner; pull_from_windows ;;
    auto)   banner; auto_sync ;;
    diff)   banner; show_diff ;;
    menu|*) show_menu ;;
esac
