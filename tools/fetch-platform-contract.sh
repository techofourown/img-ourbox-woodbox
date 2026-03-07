#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve platform contract ref.
# Priority: OURBOX_PLATFORM_CONTRACT_REF env var > release/official-inputs.env > contracts/ (legacy fallback)
if [[ -n "${OURBOX_PLATFORM_CONTRACT_REF:-}" ]]; then
  REF="${OURBOX_PLATFORM_CONTRACT_REF}"
else
  INPUTS_ENV="${ROOT}/release/official-inputs.env"
  if [[ -f "${INPUTS_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${INPUTS_ENV}"
    [[ -n "${PLATFORM_CONTRACT_REF:-}" ]] || { echo "PLATFORM_CONTRACT_REF not set in ${INPUTS_ENV}" >&2; exit 1; }
    REF="${PLATFORM_CONTRACT_REF}"
  else
    # Legacy fallback: contracts/platform-contract.ref (deprecated — use release/official-inputs.env)
    REF_FILE="${ROOT}/contracts/platform-contract.ref"
    [[ -f "${REF_FILE}" ]] || { echo "Missing ${INPUTS_ENV} and no legacy ${REF_FILE} found" >&2; exit 1; }
    REF="$(cat "${REF_FILE}")"
  fi
fi

command -v oras >/dev/null 2>&1 || {
  echo "oras is required. Run ./tools/bootstrap-host.sh or install ORAS v${ORAS_VERSION:-1.3.0}." >&2
  exit 1
}

OUT_BASE="${ROOT}/artifacts/platform-contract"
PULL_DIR="${OUT_BASE}/pull"
EXTRACT_DIR="${OUT_BASE}/extracted"
META_DIR="${OUT_BASE}/meta"

rm -rf "${PULL_DIR}" "${EXTRACT_DIR}" "${META_DIR}"
mkdir -p "${PULL_DIR}" "${EXTRACT_DIR}" "${META_DIR}"

echo "Pulling platform contract:"
echo "  ${REF}"

# Resolve to an immutable digest before pulling.
# This is required for reliable provenance recording — grepping pull output
# is fragile. oras resolve gives a definitive sha256: digest string.
RESOLVED_DIGEST=""
if [[ "${REF}" =~ @sha256:[0-9a-f]{64}$ ]]; then
  # Ref already contains a digest — extract it directly.
  RESOLVED_DIGEST="${REF##*@}"
else
  echo "  Resolving digest for ${REF}"
  set +e
  RESOLVED_DIGEST="$(oras resolve "${REF}" 2>/dev/null)"
  resolve_status=$?
  set -e
  if [[ "${resolve_status}" -ne 0 || ! "${RESOLVED_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "  WARNING: oras resolve failed; digest will not be captured" >&2
    RESOLVED_DIGEST=""
  else
    echo "  Resolved: ${RESOLVED_DIGEST}"
  fi
fi

oras pull "${REF}" -o "${PULL_DIR}" | tee "${META_DIR}/oras.pull.log"

TARBALL="${PULL_DIR}/dist/platform-contract.tar.gz"
if [[ ! -f "${TARBALL}" ]]; then
  echo "Expected ${TARBALL} not found. Pulled files:" >&2
  find "${PULL_DIR}" -maxdepth 4 -type f -print >&2 || true
  exit 1
fi

tar -xzf "${TARBALL}" -C "${EXTRACT_DIR}"

[[ -f "${EXTRACT_DIR}/platform-contract/contract.env" ]] || {
  echo "Missing platform-contract/contract.env in extracted payload" >&2
  exit 1
}

"${ROOT}/tools/validate-platform-contract-shape.sh" "${EXTRACT_DIR}/platform-contract"

if [[ -n "${RESOLVED_DIGEST}" ]]; then
  printf '%s\n' "${RESOLVED_DIGEST}" > "${EXTRACT_DIR}/platform-contract/contract.digest"
  echo "  Digest recorded: ${RESOLVED_DIGEST}"
else
  echo "  WARNING: no digest captured; contract.digest will not be written" >&2
fi

echo "OK: extracted to ${EXTRACT_DIR}/platform-contract"
