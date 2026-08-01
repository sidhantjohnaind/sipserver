#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load and sanitize .env (strip Windows \r carriage returns)
load_env() {
  local ef="$1"
  if [[ -f "$ef" ]]; then
    echo "[run_native] Loading environment variables from $(basename "$ef")..."
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      [[ -z "$key" || "$key" =~ ^# ]] && continue
      key="$(echo "$key" | tr -d '\r' | xargs)"
      value="$(echo "$value" | tr -d '\r' | xargs)"
      if [[ -n "$key" ]]; then
        export "$key"="$value"
      fi
    done < "$ef"
  fi
}

if [[ -f "${ROOT_DIR}/.env" ]]; then
  load_env "${ROOT_DIR}/.env"
elif [[ -f "${SCRIPT_DIR}/.env" ]]; then
  load_env "${SCRIPT_DIR}/.env"
fi

# Ensure bind address is 0.0.0.0 so socket bind() succeeds inside WSL
export TLS_BOUND_ADDR="0.0.0.0"

# Detect Architecture
ARCH="$(uname -m)"
if [[ "${ARCH}" == "x86_64" || "${ARCH}" == "amd64" ]]; then
  TARGET_DIR="${ROOT_DIR}/bin/linux-amd64"
elif [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
  TARGET_DIR="${ROOT_DIR}/bin/linux-arm64"
else
  TARGET_DIR="${ROOT_DIR}/bin/linux-amd64"
fi

B2BUA_BIN="${TARGET_DIR}/b2bua"
LIB_DIR="${TARGET_DIR}/lib"

if [[ ! -f "${B2BUA_BIN}" ]]; then
  echo "[run_native] Error: Executable not found at ${B2BUA_BIN}"
  exit 1
fi

chmod +x "${B2BUA_BIN}"

if [[ -d "${LIB_DIR}" ]]; then
  [[ -f "${LIB_DIR}/libopencore-amrnb.so.0.0.5" && ! -f "${LIB_DIR}/libopencore-amrnb.so.0" ]] && cp "${LIB_DIR}/libopencore-amrnb.so.0.0.5" "${LIB_DIR}/libopencore-amrnb.so.0" || true
  [[ -f "${LIB_DIR}/libopencore-amrwb.so.0.0.5" && ! -f "${LIB_DIR}/libopencore-amrwb.so.0" ]] && cp "${LIB_DIR}/libopencore-amrwb.so.0.0.5" "${LIB_DIR}/libopencore-amrwb.so.0" || true
  [[ -f "${LIB_DIR}/libvo-amrwbenc.so.0.0.4" && ! -f "${LIB_DIR}/libvo-amrwbenc.so.0" ]] && cp "${LIB_DIR}/libvo-amrwbenc.so.0.0.4" "${LIB_DIR}/libvo-amrwbenc.so.0" || true
fi

export LD_LIBRARY_PATH="${LIB_DIR}:${LD_LIBRARY_PATH:-}"

echo "[run_native] Starting JioFiber SIP Proxy on WSL (${ARCH})..."
exec "${B2BUA_BIN}" "$@"
