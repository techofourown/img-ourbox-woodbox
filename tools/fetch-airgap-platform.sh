#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd tar
need_cmd oras
need_cmd find
need_cmd grep
need_cmd python3

ref_repo_base() {
  local ref="$1"
  local tail="${ref##*/}"

  if [[ "${ref}" == *@* ]]; then
    printf '%s\n' "${ref%%@*}"
    return 0
  fi

  if [[ "${tail}" == *:* ]]; then
    printf '%s\n' "${ref%:*}"
  else
    printf '%s\n' "${ref}"
  fi
}

resolve_selected_bundle_identity() {
  local digest=""
  local pinned_ref=""

  if [[ "${REF}" =~ @sha256:[0-9a-f]{64}$ ]]; then
    digest="${REF##*@}"
    pinned_ref="${REF}"
  else
    digest="$(grep -Eo 'sha256:[0-9a-f]{64}' "${META_DIR}/oras.pull.log" | tail -n1 || true)"
    [[ -n "${digest}" ]] || die "unable to determine fetched airgap-platform digest from ${META_DIR}/oras.pull.log"
    pinned_ref="$(ref_repo_base "${REF}")@${digest}"
  fi

  printf '%s\n%s\n' "${pinned_ref}" "${digest}"
}

write_selected_bundle_metadata() {
  local expected_contract_digest="$1"
  local selected_pinned_ref="$2"
  local selected_digest="$3"
  local manifest="${OUT}/manifest.env"
  local strict_metadata_parser="${ROOT}/tools/strict-kv-metadata.py"
  local manifest_dump=""
  local -a manifest_fields=()

  [[ -f "${manifest}" ]] || die "missing manifest.env in ${OUT}"
  [[ -f "${strict_metadata_parser}" ]] || die "strict metadata parser not found: ${strict_metadata_parser}"
  manifest_dump="$(
    python3 "${strict_metadata_parser}" "${manifest}" \
      --allow OURBOX_AIRGAP_PLATFORM_SCHEMA \
      --allow OURBOX_AIRGAP_PLATFORM_KIND \
      --allow OURBOX_AIRGAP_PLATFORM_SOURCE \
      --allow OURBOX_AIRGAP_PLATFORM_REVISION \
      --allow OURBOX_AIRGAP_PLATFORM_VERSION \
      --allow OURBOX_AIRGAP_PLATFORM_CREATED \
      --allow OURBOX_PLATFORM_CONTRACT_REF \
      --allow OURBOX_PLATFORM_CONTRACT_DIGEST \
      --allow AIRGAP_PLATFORM_ARCH \
      --allow K3S_VERSION \
      --allow OURBOX_PLATFORM_PROFILE \
      --allow OURBOX_PLATFORM_IMAGES_LOCK_PATH \
      --allow OURBOX_PLATFORM_IMAGES_LOCK_SHA256 \
      --require OURBOX_AIRGAP_PLATFORM_SOURCE \
      --require OURBOX_AIRGAP_PLATFORM_REVISION \
      --require OURBOX_AIRGAP_PLATFORM_VERSION \
      --require OURBOX_AIRGAP_PLATFORM_CREATED \
      --require OURBOX_PLATFORM_CONTRACT_DIGEST \
      --require AIRGAP_PLATFORM_ARCH \
      --require K3S_VERSION \
      --require OURBOX_PLATFORM_PROFILE \
      --require OURBOX_PLATFORM_IMAGES_LOCK_SHA256 \
      --print OURBOX_AIRGAP_PLATFORM_SOURCE \
      --print OURBOX_AIRGAP_PLATFORM_REVISION \
      --print OURBOX_AIRGAP_PLATFORM_VERSION \
      --print OURBOX_AIRGAP_PLATFORM_CREATED \
      --print OURBOX_PLATFORM_CONTRACT_REF \
      --print OURBOX_PLATFORM_CONTRACT_DIGEST \
      --print AIRGAP_PLATFORM_ARCH \
      --print K3S_VERSION \
      --print OURBOX_PLATFORM_PROFILE \
      --print OURBOX_PLATFORM_IMAGES_LOCK_SHA256
  )"
  mapfile -t manifest_fields <<<"${manifest_dump}"
  [[ "${#manifest_fields[@]}" -eq 10 ]] || die "failed to parse ${manifest}"

  [[ "${manifest_fields[6]}" == "amd64" ]] || die "airgap-platform arch mismatch: expected amd64, got ${manifest_fields[6]:-unknown}"
  [[ "${manifest_fields[5]}" == "${expected_contract_digest}" ]] || die "airgap-platform contract digest mismatch: expected ${expected_contract_digest}, got ${manifest_fields[5]:-unknown}"
  [[ "${manifest_fields[9]}" =~ ^[0-9a-f]{64}$ ]] || die "airgap-platform manifest carries invalid OURBOX_PLATFORM_IMAGES_LOCK_SHA256"

  cat > "${OUT}/selected-bundle.env" <<EOF
OURBOX_AIRGAP_PLATFORM_REF=${selected_pinned_ref}
OURBOX_AIRGAP_PLATFORM_DIGEST=${selected_digest}
OURBOX_AIRGAP_PLATFORM_SOURCE=${manifest_fields[0]}
OURBOX_AIRGAP_PLATFORM_REVISION=${manifest_fields[1]}
OURBOX_AIRGAP_PLATFORM_VERSION=${manifest_fields[2]}
OURBOX_AIRGAP_PLATFORM_CREATED=${manifest_fields[3]}
OURBOX_AIRGAP_PLATFORM_ARCH=${manifest_fields[6]}
OURBOX_AIRGAP_PLATFORM_PROFILE=${manifest_fields[8]}
OURBOX_AIRGAP_PLATFORM_K3S_VERSION=${manifest_fields[7]}
OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256=${manifest_fields[9]}
OURBOX_PLATFORM_CONTRACT_REF=${manifest_fields[4]}
OURBOX_PLATFORM_CONTRACT_DIGEST=${manifest_fields[5]}
EOF
}

# Resolve airgap platform ref.
# Priority: OURBOX_AIRGAP_PLATFORM_REF env var > release/official-inputs.env > contracts/ (legacy fallback)
if [[ -n "${OURBOX_AIRGAP_PLATFORM_REF:-}" ]]; then
  REF="${OURBOX_AIRGAP_PLATFORM_REF}"
else
  INPUTS_ENV="${ROOT}/release/official-inputs.env"
  if [[ -f "${INPUTS_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${INPUTS_ENV}"
    [[ -n "${AIRGAP_PLATFORM_REF:-}" ]] || die "AIRGAP_PLATFORM_REF not set in ${INPUTS_ENV}"
    REF="${AIRGAP_PLATFORM_REF}"
  else
    # Legacy fallback: contracts/airgap-platform.ref (deprecated — use release/official-inputs.env)
    REF_FILE="${ROOT}/contracts/airgap-platform.ref"
    [[ -f "${REF_FILE}" ]] || die "Missing ${INPUTS_ENV} and no legacy ${REF_FILE} found"
    REF="$(cat "${REF_FILE}")"
  fi
fi

OUT="${ROOT}/artifacts/airgap"
PULL_DIR="${ROOT}/artifacts/.airgap-platform-pull"
META_DIR="${ROOT}/artifacts/.airgap-platform-meta"

log "Using airgap platform ref: ${REF}"

# Enforce digest pinning in official builds.
# Nightly: warn (non-reproducible but permitted for bootstrap).
# Official candidate/release lanes: hard fail.
if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ "${REF}" != *"@sha256:"* ]]; then
  if [[ "${OURBOX_REQUIRE_PINNED_OFFICIAL_INPUTS:-0}" == "1" ]] || [[ "${GITHUB_WORKFLOW:-}" =~ [Rr]elease ]]; then
    die "AIRGAP_PLATFORM_REF '${REF}' is not digest-pinned.
  Official candidate/release builds require @sha256: refs to ensure reproducibility.
  Update the approved upstream snapshot in sw-ourbox-os instead of editing release/official-inputs.env by hand."
  elif [[ "${GITHUB_WORKFLOW:-}" =~ [Nn]ightly ]]; then
    log "WARNING: AIRGAP_PLATFORM_REF is not digest-pinned — nightly build will not be reproducible"
    log "  Update the approved upstream snapshot in sw-ourbox-os once the next release is approved"
  fi
fi

# In CI, skip the interactive confirmation and auto-remove stale artifacts.
# Locally, prompt before removing existing artifacts.
if [[ -d "${OUT}" ]] && find "${OUT}" -mindepth 1 -print -quit >/dev/null 2>&1; then
  if [[ -n "${GITHUB_ACTIONS:-}" || "${CI:-}" == "1" ]]; then
    log "CI mode: removing existing artifacts in ${OUT}"
    rm -rf "${OUT}" || die "Failed to remove ${OUT}"
  else
    log "ERROR: Existing artifacts detected in ${OUT} (refusing to overwrite)"
    find "${OUT}" -maxdepth 2 -type f -print | sed 's/^/  /'
    echo
    log "You can remove them manually, or allow this script to remove them."
    read -r -p "Type REMOVE to delete ${OUT} and continue, or anything else to abort: " confirm
    if [[ "${confirm}" != "REMOVE" ]]; then
      die "Fetch aborted; existing artifacts not removed"
    fi
    log "WARNING: About to remove ${OUT}"
    if [[ -w "${OUT}" ]]; then
      rm -rf "${OUT}" || die "Failed to remove ${OUT}"
    else
      need_cmd sudo
      sudo rm -rf "${OUT}" || die "Failed to remove ${OUT} (sudo)"
    fi
  fi
fi

rm -rf "${PULL_DIR}" "${META_DIR}"
mkdir -p "${PULL_DIR}" "${META_DIR}" "${OUT}"

log "Pulling airgap platform bundle (amd64)"
oras pull "${REF}" -o "${PULL_DIR}" | tee "${META_DIR}/oras.pull.log"

TARBALL="${PULL_DIR}/dist/airgap-platform.tar.gz"
[[ -f "${TARBALL}" ]] || {
  echo "Expected ${TARBALL} not found. Pulled files:" >&2
  find "${PULL_DIR}" -maxdepth 4 -type f -print >&2 || true
  exit 1
}

log "Extracting bundle into ${OUT}"
tar -xzf "${TARBALL}" -C "${OUT}"

# Basic validation
[[ -x "${OUT}/k3s/k3s" ]] || die "Missing k3s binary in ${OUT}/k3s/k3s"
[[ -f "${OUT}/manifest.env" ]] || die "Missing manifest.env in ${OUT}"

shopt -s nullglob
k3s_tars=("${OUT}/k3s/k3s-airgap-images-"*.tar)
platform_tars=("${OUT}/platform/images/"*.tar)
shopt -u nullglob

(( ${#k3s_tars[@]} > 0 )) || die "No k3s airgap image tar found in ${OUT}/k3s"
(( ${#platform_tars[@]} > 0 )) || die "No platform image tars found in ${OUT}/platform/images"

log "Artifacts created:"
ls -lah "${OUT}/k3s" "${OUT}/platform/images" "${OUT}/manifest.env"

log "Deriving platform contract ref from airgap bundle manifest"
BUNDLE_CONTRACT_REF="$(grep '^OURBOX_PLATFORM_CONTRACT_REF=' "${OUT}/manifest.env" | cut -d= -f2- | tr -d '\r')"
[[ -n "${BUNDLE_CONTRACT_REF}" ]] || die "OURBOX_PLATFORM_CONTRACT_REF not found in airgap bundle manifest: ${OUT}/manifest.env"
[[ "${BUNDLE_CONTRACT_REF}" =~ @sha256:[0-9a-f]{64}$ ]] || die "OURBOX_PLATFORM_CONTRACT_REF in bundle manifest is not digest-pinned: ${BUNDLE_CONTRACT_REF}"
export OURBOX_PLATFORM_CONTRACT_REF="${BUNDLE_CONTRACT_REF}"

log "Fetching pinned platform contract (OCI artifact)"
"${ROOT}/tools/fetch-platform-contract.sh"

CONTRACT_DIGEST_FILE="${ROOT}/artifacts/platform-contract/extracted/platform-contract/contract.digest"
[[ -f "${CONTRACT_DIGEST_FILE}" ]] || die "platform contract digest file missing after fetch: ${CONTRACT_DIGEST_FILE}"
EXPECTED_CONTRACT_DIGEST="$(cat "${CONTRACT_DIGEST_FILE}")"
[[ "${EXPECTED_CONTRACT_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "platform contract digest is invalid: ${EXPECTED_CONTRACT_DIGEST}"

mapfile -t bundle_identity < <(resolve_selected_bundle_identity)
SELECTED_AIRGAP_PINNED_REF="${bundle_identity[0]:-}"
SELECTED_AIRGAP_DIGEST="${bundle_identity[1]:-}"
[[ -n "${SELECTED_AIRGAP_PINNED_REF}" ]] || die "selected airgap pinned ref was not resolved"
[[ "${SELECTED_AIRGAP_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "selected airgap digest is invalid: ${SELECTED_AIRGAP_DIGEST:-missing}"

write_selected_bundle_metadata "${EXPECTED_CONTRACT_DIGEST}" "${SELECTED_AIRGAP_PINNED_REF}" "${SELECTED_AIRGAP_DIGEST}"
log "Selected baked airgap bundle recorded at ${OUT}/selected-bundle.env"

log "Syncing pinned platform contract into installer tree"
"${ROOT}/tools/sync-platform-contract-into-installer.sh"

log "Ensuring baked application catalog metadata exists in fetched airgap bundle"
"${ROOT}/tools/ensure-airgap-application-metadata.sh" \
  --bundle-dir "${OUT}" \
  --contract-root "${ROOT}/installer/ourbox/rootfs/opt/ourbox/airgap/platform"
