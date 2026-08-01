#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEC_DIR="${SCRIPT_DIR}/extracted_executables"

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

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  load_env "${SCRIPT_DIR}/.env"
elif [[ -f "${SCRIPT_DIR}/../.env" ]]; then
  load_env "${SCRIPT_DIR}/../.env"
fi

# Ensure bind address is 0.0.0.0 so socket bind() succeeds inside WSL / containers / VMs
export TLS_BOUND_ADDR="0.0.0.0"

B2BUA_BIN="${EXEC_DIR}/b2bua"
LIB_DIR="${EXEC_DIR}/lib"

if [[ ! -f "${B2BUA_BIN}" ]]; then
  ARCH="$(uname -m)"
  if [[ "${ARCH}" == "x86_64" || "${ARCH}" == "amd64" ]]; then
    B2BUA_BIN="${EXEC_DIR}/b2bua_linux_amd64"
    LIB_DIR="${EXEC_DIR}/lib_amd64"
  elif [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
    B2BUA_BIN="${EXEC_DIR}/b2bua_linux_arm64"
    LIB_DIR="${EXEC_DIR}/lib_arm64"
  fi
fi

if [[ ! -f "${B2BUA_BIN}" ]]; then
  echo "[run_native] Error: Binary not found at ${B2BUA_BIN}"
  exit 1
fi

chmod +x "${B2BUA_BIN}" "${EXEC_DIR}/entrypoint.sh"

if [[ -d "${LIB_DIR}" ]]; then
  [[ -f "${LIB_DIR}/libopencore-amrnb.so.0.0.5" && ! -f "${LIB_DIR}/libopencore-amrnb.so.0" ]] && cp "${LIB_DIR}/libopencore-amrnb.so.0.0.5" "${LIB_DIR}/libopencore-amrnb.so.0" || true
  [[ -f "${LIB_DIR}/libopencore-amrwb.so.0.0.5" && ! -f "${LIB_DIR}/libopencore-amrwb.so.0" ]] && cp "${LIB_DIR}/libopencore-amrwb.so.0.0.5" "${LIB_DIR}/libopencore-amrwb.so.0" || true
  [[ -f "${LIB_DIR}/libvo-amrwbenc.so.0.0.4" && ! -f "${LIB_DIR}/libvo-amrwbenc.so.0" ]] && cp "${LIB_DIR}/libvo-amrwbenc.so.0.0.4" "${LIB_DIR}/libvo-amrwbenc.so.0" || true
fi

export LD_LIBRARY_PATH="${LIB_DIR}:${LD_LIBRARY_PATH:-}"

BIN_TMP="$(mktemp -d)"
trap 'rm -rf "${BIN_TMP}"' EXIT

ln -sf "${B2BUA_BIN}" "${BIN_TMP}/b2bua"
export PATH="${BIN_TMP}:${PATH}"

sed -e 's|exec /usr/local/bin/b2bua|exec b2bua|g' \
    -e 's|>> /etc/hosts||g' \
    -e 's|: > /etc/resolv.conf||g' \
    -e 's|>> /etc/resolv.conf||g' \
    "${EXEC_DIR}/entrypoint.sh" > "${BIN_TMP}/entrypoint_runner.sh"
chmod +x "${BIN_TMP}/entrypoint_runner.sh"

echo "[run_native] Starting JioFiber SIP Proxy..."
exec "${BIN_TMP}/entrypoint_runner.sh" "$@"
