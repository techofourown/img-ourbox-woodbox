#!/usr/bin/env bash
# Sync the pulled upstream platform contract into the Woodbox installer rootfs overlay.
# Must be called after tools/fetch-platform-contract.sh.
# Called automatically by tools/fetch-airgap-platform.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTRACT_DIGEST_FILE="${ROOT}/artifacts/platform-contract/extracted/platform-contract/contract.digest"
if [[ -f "${CONTRACT_DIGEST_FILE}" ]]; then
  DIGEST="$(cat "${CONTRACT_DIGEST_FILE}")"
else
  # Fall back to reading from contracts/ ref if digest was not captured
  REF_FILE="${ROOT}/contracts/platform-contract.ref"
  [[ -f "${REF_FILE}" ]] || { echo "Missing ${REF_FILE}" >&2; exit 1; }
  DIGEST="$(cat "${REF_FILE}")"
fi

SRC="${ROOT}/artifacts/platform-contract/extracted/platform-contract"
[[ -d "${SRC}" ]] || {
  echo "Missing extracted contract dir: ${SRC}" >&2
  echo "Run: ./tools/fetch-platform-contract.sh" >&2
  exit 1
}

# Destination: the canonical installer rootfs overlay
ROOTFS="${ROOT}/installer/ourbox/rootfs"
DST_BASE="${ROOTFS}/opt/ourbox/airgap/platform"
DST_MAN="${DST_BASE}/manifests"
DST_LAND="${DST_BASE}/landing"
DST_TODO="${DST_BASE}/todo-bloom"

rm -rf "${DST_MAN}" "${DST_LAND}" "${DST_TODO}"
mkdir -p "${DST_MAN}" "${DST_LAND}" "${DST_TODO}"

cp -a "${SRC}/manifests/." "${DST_MAN}/"
cp -a "${SRC}/landing/." "${DST_LAND}/"
if [[ -d "${SRC}/todo-bloom" ]]; then
  cp -a "${SRC}/todo-bloom/." "${DST_TODO}/"
fi
cp -a "${SRC}/contract.env" "${DST_BASE}/contract.env"
printf '%s\n' "${DIGEST}" > "${DST_BASE}/contract.digest"
touch "${DST_MAN}/.gitkeep" "${DST_LAND}/.gitkeep" "${DST_TODO}/.gitkeep"

echo "Synced platform contract into installer rootfs overlay:"
echo "  ${DST_BASE}"
