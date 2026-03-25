#!/usr/bin/env bash
# Sync the pulled upstream platform contract into the Woodbox installer rootfs overlay.
# Must be called after tools/fetch-platform-contract.sh.
# Called automatically by tools/fetch-ourbox-substrate.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC="${ROOT}/artifacts/platform-contract/extracted/platform-contract"
[[ -d "${SRC}" ]] || {
  echo "Missing extracted contract dir: ${SRC}" >&2
  echo "Run: ./tools/fetch-platform-contract.sh" >&2
  exit 1
}

"${ROOT}/tools/validate-platform-contract-shape.sh" "${SRC}"

# Destination: the canonical installer rootfs overlay
ROOTFS="${ROOT}/installer/ourbox/rootfs"
DST_BASE="${ROOTFS}/opt/ourbox/substrate/platform"

rm -rf "${DST_BASE}"
mkdir -p "${DST_BASE}"

cp -a "${SRC}/." "${DST_BASE}/"

echo "Synced platform contract into installer rootfs overlay:"
echo "  ${DST_BASE}"
