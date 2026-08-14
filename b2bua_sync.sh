#!/bin/bash
# =====================================================================
# b2bua_sync.sh  -  JioFiber B2BUA Bidirectional Config Sync
# Works on Linux side of a dual-boot setup.
# The NTFS shared drive acts as the exchange point for both OSes.
#
# Usage:
#   bash b2bua_sync.sh            -> interactive menu
#   bash b2bua_sync.sh push       -> Linux home -> NTFS (for Windows)
#   bash b2bua_sync.sh pull       -> NTFS (from Windows) -> Linux home
#   bash b2bua_sync.sh auto       -> auto-detect newer side and sync
# =====================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# ---- Paths ----------------------------------------------------------
# Linux home install (source of truth on Linux)
LINUX_DIR="/home/${SUDO_USER:-$USER}/sipserver"

# NTFS shared exchange folder (readable/writable by both OSes)
# On Windows this is:  D:\Programming\sipserver\bin\windows-x64\
NTFS_DIR="${SCRIPT_DIR}/bin/windows-x64"

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

# ---- Helpers --------------------------------------------------------
banner() {
    echo -e "${BLU}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║   JioFiber B2BUA — Bidirectional Sync (Linux ↔ Windows) ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${RST}"
}

check_dirs() {
    if [ ! -d "$LINUX_DIR" ]; then
        echo -e "${RED}[ERROR]${RST} Linux install dir not found: $LINUX_DIR"
        exit 1
    fi
    if [ ! -d "$NTFS_DIR" ]; then
        echo -e "${RED}[ERROR]${RST} NTFS dir not found: $NTFS_DIR"
        echo "        Is the NTFS drive mounted?"
        exit 1
    fi
}

get_newest_timestamp() {
    local dir="$1"
    local newest=0
    for f in "${SYNC_FILES[@]}"; do
        [ -f "$dir/$f" ] || continue
        ts=$(stat -c %Y "$dir/$f" 2>/dev/null || echo 0)
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

    for f in "${SYNC_FILES[@]}"; do
        src_file="$SRC/$f"
        dst_file="$DST/$f"

        # Resolve symlinks to real files
        if [ -L "$src_file" ]; then
            src_file="$(readlink -f "$src_file")"
        fi

        if [ -f "$src_file" ]; then
            cp "$src_file" "$dst_file" 2>/dev/null && \
                echo -e "    ${GRN}✓${RST}  $f" || \
                echo -e "    ${YEL}!${RST}  $f (skipped - permission?)"
            copied=$((copied + 1))
        else
            echo -e "    ${YEL}-${RST}  $f (not found in source)"
        fi
    done

    echo ""
    echo -e "  ${GRN}[DONE]${RST} Synced $copied files."
}

push_to_windows() {
    echo -e "${YEL}► Linux home → Windows (NTFS)${RST}"
    check_dirs
    do_copy "$LINUX_DIR" "$NTFS_DIR" "Linux home → NTFS (Windows)"
    echo -e "  ${BLU}[i]${RST} Boot Windows and run b2bua_msvc.exe — config is ready."
    echo -e "  ${BLU}[i]${RST} Windows path: $(echo "$NTFS_DIR" | sed 's|/mnt/94C83957C83938B6|D:|;s|/|\\|g')"
}

pull_from_windows() {
    echo -e "${YEL}◄ Windows (NTFS) → Linux home${RST}"
    check_dirs
    do_copy "$NTFS_DIR" "$LINUX_DIR" "NTFS (Windows) → Linux home"
    echo -e "  ${BLU}[i]${RST} Linux b2bua will pick up the new config on next run."

    # Restart service if running
    if systemctl is-active jiofiber-b2bua &>/dev/null; then
        echo -e "  ${CYN}[↺]${RST} Restarting jiofiber-b2bua service..."
        sudo systemctl restart jiofiber-b2bua && \
            echo -e "  ${GRN}[✓]${RST} Service restarted." || true
    fi
}

auto_sync() {
    echo -e "${YEL}⚡ Auto-detect newer side and sync${RST}"
    check_dirs

    linux_ts=$(get_newest_timestamp "$LINUX_DIR")
    ntfs_ts=$(get_newest_timestamp "$NTFS_DIR")

    echo "  Linux home newest file : $(date -d "@$linux_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$linux_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $linux_ts)"
    echo "  NTFS (Windows) newest  : $(date -d "@$ntfs_ts"  '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$ntfs_ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $ntfs_ts)"
    echo ""

    if [ "$linux_ts" -ge "$ntfs_ts" ]; then
        echo -e "  ${GRN}Linux side is newer → pushing to Windows${RST}"
        push_to_windows
    else
        echo -e "  ${GRN}Windows side is newer → pulling to Linux${RST}"
        pull_from_windows
    fi
}

show_menu() {
    banner
    echo "  Linux dir  : $LINUX_DIR"
    echo "  Windows dir: $(echo "$NTFS_DIR" | sed 's|/mnt/94C83957C83938B6|D:|;s|/|\\|g')"
    echo ""
    echo -e "  ${BLU}1)${RST}  Push  Linux → Windows   (use after changing config on Linux)"
    echo -e "  ${BLU}2)${RST}  Pull  Windows → Linux   (use after changing config on Windows)"
    echo -e "  ${BLU}3)${RST}  Auto  detect newer side and sync"
    echo -e "  ${BLU}4)${RST}  Show  current config diff"
    echo -e "  ${BLU}q)${RST}  Quit"
    echo ""
    read -rp "  Choose [1/2/3/4/q]: " choice

    case "$choice" in
        1) push_to_windows ;;
        2) pull_from_windows ;;
        3) auto_sync ;;
        4) show_diff ;;
        q|Q) echo "Bye!"; exit 0 ;;
        *) echo "Invalid choice."; show_menu ;;
    esac
}

show_diff() {
    echo -e "${YEL}=== Config Diff (Linux vs Windows) ===${RST}"
    for f in "${SYNC_FILES[@]}"; do
        lf="$LINUX_DIR/$f"
        wf="$NTFS_DIR/$f"
        [ -L "$lf" ] && lf="$(readlink -f "$lf")"
        if [ -f "$lf" ] && [ -f "$wf" ]; then
            if ! diff -q "$lf" "$wf" &>/dev/null; then
                echo -e "\n${RED}DIFFER:${RST} $f"
                diff <(cat "$lf") <(cat "$wf") | head -20 || true
            else
                echo -e "  ${GRN}SAME :${RST} $f"
            fi
        elif [ -f "$lf" ]; then
            echo -e "  ${YEL}LINUX only:${RST} $f"
        elif [ -f "$wf" ]; then
            echo -e "  ${YEL}WINDOWS only:${RST} $f"
        fi
    done
    echo ""
}

# ---- Entry point ----------------------------------------------------
case "${1:-menu}" in
    push)   banner; push_to_windows ;;
    pull)   banner; pull_from_windows ;;
    auto)   banner; auto_sync ;;
    diff)   banner; show_diff ;;
    menu|*) show_menu ;;
esac
