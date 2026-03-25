#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve platform contract ref.
# Callers must resolve channel intent at workflow/build start and pass the
# selected immutable ref explicitly.
[[ -n "${OURBOX_PLATFORM_CONTRACT_REF:-}" ]] || {
  echo "OURBOX_PLATFORM_CONTRACT_REF is required." >&2
  echo "Resolve the upstream platform-contract channel at workflow/build start and pass" >&2
  echo "the resulting digest-pinned ref in the environment." >&2
  exit 1
}
REF="${OURBOX_PLATFORM_CONTRACT_REF}"

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

if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ "${REF}" != *"@sha256:"* ]]; then
  if [[ "${OURBOX_REQUIRE_PINNED_OFFICIAL_INPUTS:-0}" == "1" ]] || [[ "${GITHUB_WORKFLOW:-}" =~ [Rr]elease ]]; then
    echo "PLATFORM_CONTRACT_REF '${REF}' is not digest-pinned." >&2
    echo "Official candidate/release builds require @sha256: refs to ensure reproducibility." >&2
    echo "Resolve the upstream channel before calling fetch-platform-contract.sh and pass" >&2
    echo "the pinned ref via OURBOX_PLATFORM_CONTRACT_REF." >&2
    exit 1
  elif [[ "${GITHUB_WORKFLOW:-}" =~ [Nn]ightly ]]; then
    echo "WARNING: PLATFORM_CONTRACT_REF is not digest-pinned — nightly build will not be reproducible" >&2
    echo "  Resolve the upstream channel before calling fetch-platform-contract.sh" >&2
  fi
fi

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

"${ROOT}/tools/validate-platform-contract-shape.sh" "${EXTRACT_DIR}/platform-contract"

echo "OK: extracted to ${EXTRACT_DIR}/platform-contract"
