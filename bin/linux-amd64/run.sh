#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  export $(grep -v '^#' "${SCRIPT_DIR}/.env" | tr -d '\r' | xargs)
elif [[ -f "${SCRIPT_DIR}/../../.env" ]]; then
  export $(grep -v '^#' "${SCRIPT_DIR}/../../.env" | tr -d '\r' | xargs)
fi

export TLS_BOUND_ADDR="0.0.0.0"
export LD_LIBRARY_PATH="${SCRIPT_DIR}/lib:${LD_LIBRARY_PATH:-}"

chmod +x "${SCRIPT_DIR}/b2bua"
echo "[run] Starting JioFiber SIP Proxy..."
exec "${SCRIPT_DIR}/b2bua" "$@"
