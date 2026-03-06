#!/usr/bin/env bash
# Sync the pulled upstream platform contract into the Woodbox installer rootfs overlay.
# Must be called after tools/fetch-platform-contract.sh.
# Called automatically by tools/fetch-airgap-platform.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONTRACT_DIGEST_FILE="${ROOT}/artifacts/platform-contract/extracted/platform-contract/contract.digest"
if [[ -f "${CONTRACT_DIGEST_FILE}" ]]; then
  DIGEST="$(cat "${CONTRACT_DIGEST_FILE}")"
  # Validate it is actually a sha256 digest, not a stale ref or tag
  if [[ ! "${DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "WARNING: contract.digest contains non-digest value '${DIGEST}'; treating as unknown" >&2
    DIGEST="unknown"
  fi
else
  # No digest file — this means fetch-platform-contract.sh was called with a
  # floating tag and oras resolve did not capture a digest. Fall back to unknown
  # rather than writing a full ref string as the digest (which would be incorrect).
  echo "WARNING: No contract.digest file found. Platform contract digest will be 'unknown'." >&2
  echo "  Re-run ./tools/fetch-platform-contract.sh to capture a digest." >&2
  DIGEST="unknown"
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

rm -rf "${DST_BASE}"
mkdir -p "${DST_BASE}"

cp -a "${SRC}/." "${DST_BASE}/"
printf '%s\n' "${DIGEST}" > "${DST_BASE}/contract.digest"

echo "Synced platform contract into installer rootfs overlay:"
echo "  ${DST_BASE}"
