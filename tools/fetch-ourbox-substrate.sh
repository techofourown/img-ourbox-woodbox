#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd tar
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
    [[ -n "${digest}" ]] || die "unable to determine fetched ourbox-substrate digest from ${META_DIR}/oras.pull.log"
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
      --allow OURBOX_SUBSTRATE_SCHEMA \
      --allow OURBOX_SUBSTRATE_KIND \
      --allow OURBOX_SUBSTRATE_SOURCE \
      --allow OURBOX_SUBSTRATE_REVISION \
      --allow OURBOX_SUBSTRATE_VERSION \
      --allow OURBOX_SUBSTRATE_CREATED \
      --allow OURBOX_PLATFORM_CONTRACT_REF \
      --allow OURBOX_PLATFORM_CONTRACT_DIGEST \
      --allow OURBOX_SUBSTRATE_ARCH \
      --allow K3S_VERSION \
      --allow OURBOX_PLATFORM_PROFILE \
      --allow OURBOX_PLATFORM_IMAGES_LOCK_PATH \
      --allow OURBOX_PLATFORM_IMAGES_LOCK_SHA256 \
      --require OURBOX_SUBSTRATE_SOURCE \
      --require OURBOX_SUBSTRATE_REVISION \
      --require OURBOX_SUBSTRATE_VERSION \
      --require OURBOX_SUBSTRATE_CREATED \
      --require OURBOX_PLATFORM_CONTRACT_DIGEST \
      --require OURBOX_SUBSTRATE_ARCH \
      --require K3S_VERSION \
      --require OURBOX_PLATFORM_PROFILE \
      --require OURBOX_PLATFORM_IMAGES_LOCK_SHA256 \
      --print OURBOX_SUBSTRATE_SOURCE \
      --print OURBOX_SUBSTRATE_REVISION \
      --print OURBOX_SUBSTRATE_VERSION \
      --print OURBOX_SUBSTRATE_CREATED \
      --print OURBOX_PLATFORM_CONTRACT_REF \
      --print OURBOX_PLATFORM_CONTRACT_DIGEST \
      --print OURBOX_SUBSTRATE_ARCH \
      --print K3S_VERSION \
      --print OURBOX_PLATFORM_PROFILE \
      --print OURBOX_PLATFORM_IMAGES_LOCK_SHA256
  )"
  mapfile -t manifest_fields <<<"${manifest_dump}"
  [[ "${#manifest_fields[@]}" -eq 10 ]] || die "failed to parse ${manifest}"

  [[ "${manifest_fields[6]}" == "amd64" ]] || die "ourbox-substrate arch mismatch: expected amd64, got ${manifest_fields[6]:-unknown}"
  [[ "${manifest_fields[5]}" == "${expected_contract_digest}" ]] || die "ourbox-substrate contract digest mismatch: expected ${expected_contract_digest}, got ${manifest_fields[5]:-unknown}"
  [[ "${manifest_fields[9]}" =~ ^[0-9a-f]{64}$ ]] || die "ourbox-substrate manifest carries invalid OURBOX_PLATFORM_IMAGES_LOCK_SHA256"

  cat > "${OUT}/selected-bundle.env" <<EOF
OURBOX_SUBSTRATE_REF=${selected_pinned_ref}
OURBOX_SUBSTRATE_DIGEST=${selected_digest}
OURBOX_SUBSTRATE_SOURCE=${manifest_fields[0]}
OURBOX_SUBSTRATE_REVISION=${manifest_fields[1]}
OURBOX_SUBSTRATE_VERSION=${manifest_fields[2]}
OURBOX_SUBSTRATE_CREATED=${manifest_fields[3]}
OURBOX_SUBSTRATE_ARCH=${manifest_fields[6]}
OURBOX_SUBSTRATE_PROFILE=${manifest_fields[8]}
OURBOX_SUBSTRATE_K3S_VERSION=${manifest_fields[7]}
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${manifest_fields[9]}
OURBOX_PLATFORM_CONTRACT_REF=${manifest_fields[4]}
OURBOX_PLATFORM_CONTRACT_DIGEST=${manifest_fields[5]}
EOF
}

validate_complete_application_metadata() {
  local bundle_dir="$1"
  local catalog_path="${bundle_dir}/platform/catalog.json"
  local selected_apps_path="${bundle_dir}/platform/selected-apps.json"
  local images_lock_path="${bundle_dir}/platform/images.lock.json"

  [[ -f "${catalog_path}" ]] || die "substrate bundle missing platform/catalog.json"
  [[ -f "${selected_apps_path}" ]] || die "substrate bundle missing platform/selected-apps.json"
  [[ -f "${images_lock_path}" ]] || die "substrate bundle missing platform/images.lock.json"

  python3 - <<'PY' "${catalog_path}" "${selected_apps_path}" "${images_lock_path}"
import json
import pathlib
import sys

catalog_path = pathlib.Path(sys.argv[1])
selected_apps_path = pathlib.Path(sys.argv[2])
images_lock_path = pathlib.Path(sys.argv[3])
supported_selection_modes = {"catalog-defaults", "all-apps", "custom"}

with catalog_path.open("r", encoding="utf-8") as handle:
    catalog = json.load(handle)
with selected_apps_path.open("r", encoding="utf-8") as handle:
    selected = json.load(handle)
with images_lock_path.open("r", encoding="utf-8") as handle:
    images_lock = json.load(handle)

if catalog.get("schema") != 1:
    raise SystemExit("substrate bundle platform/catalog.json must declare schema=1")
if catalog.get("kind") != "ourbox-application-catalog":
    raise SystemExit("substrate bundle platform/catalog.json must declare kind=ourbox-application-catalog")
catalog_id = str(catalog.get("catalog_id", "")).strip()
if not catalog_id:
    raise SystemExit("substrate bundle platform/catalog.json must declare catalog_id")
catalog_apps = catalog.get("apps")
if not isinstance(catalog_apps, list) or not catalog_apps:
    raise SystemExit("substrate bundle platform/catalog.json must declare a non-empty apps list")
catalog_app_ids = []
seen_catalog_ids = set()
for app in catalog_apps:
    app_id = str(app.get("id", "")).strip()
    if not app_id:
        raise SystemExit("substrate bundle platform/catalog.json contains an app without an id")
    if app_id in seen_catalog_ids:
        raise SystemExit(f"substrate bundle platform/catalog.json duplicates app id {app_id}")
    seen_catalog_ids.add(app_id)
    catalog_app_ids.append(app_id)

if selected.get("schema") != 1:
    raise SystemExit("substrate bundle platform/selected-apps.json must declare schema=1")
if selected.get("kind") != "ourbox-selected-applications":
    raise SystemExit("substrate bundle platform/selected-apps.json must declare kind=ourbox-selected-applications")
if str(selected.get("catalog_id", "")).strip() != catalog_id:
    raise SystemExit("substrate bundle platform/selected-apps.json catalog_id must match platform/catalog.json")
selection_mode = str(selected.get("selection_mode", "")).strip()
if selection_mode not in supported_selection_modes:
    raise SystemExit(
        "substrate bundle platform/selected-apps.json selection_mode must be one of "
        "catalog-defaults, all-apps, custom"
    )
selected_ids = selected.get("selected_app_ids")
if not isinstance(selected_ids, list) or not selected_ids:
    raise SystemExit("substrate bundle platform/selected-apps.json must declare a non-empty selected_app_ids list")
normalized_selected_ids = []
seen_selected_ids = set()
for raw_app_id in selected_ids:
    app_id = str(raw_app_id).strip()
    if not app_id:
        raise SystemExit("substrate bundle platform/selected-apps.json contains an empty app id")
    if app_id in seen_selected_ids:
        raise SystemExit(f"substrate bundle platform/selected-apps.json duplicates app id {app_id}")
    if app_id not in seen_catalog_ids:
        raise SystemExit(f"substrate bundle platform/selected-apps.json references unknown app id {app_id}")
    seen_selected_ids.add(app_id)
    normalized_selected_ids.append(app_id)

images = images_lock.get("images")
if not isinstance(images, list) or not images:
    raise SystemExit("substrate bundle platform/images.lock.json must declare a non-empty images list")
for image in images:
    name = str(image.get("name", "")).strip()
    ref = str(image.get("ref", "")).strip()
    if not name:
        raise SystemExit("substrate bundle platform/images.lock.json contains an image without a name")
    if not ref:
        raise SystemExit("substrate bundle platform/images.lock.json contains an image without a ref")
PY
}

# Resolve ourbox-substrate ref.
# Callers must resolve channel intent at workflow/build start and pass the
# selected immutable ref explicitly.
[[ -n "${OURBOX_SUBSTRATE_REF:-}" ]] || die \
  "OURBOX_SUBSTRATE_REF is required.
Resolve the upstream ourbox-substrate channel at workflow/build start and pass
the resulting digest-pinned ref in the environment."
REF="${OURBOX_SUBSTRATE_REF}"

need_cmd oras

OUT="${ROOT}/artifacts/airgap"
PULL_DIR="${ROOT}/artifacts/.ourbox-substrate-pull"
META_DIR="${ROOT}/artifacts/.ourbox-substrate-meta"

log "Using ourbox-substrate ref: ${REF}"

# Enforce digest pinning in official builds.
# Nightly: warn (non-reproducible but permitted for bootstrap).
# Official candidate/release lanes: hard fail.
if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ "${REF}" != *"@sha256:"* ]]; then
  if [[ "${OURBOX_REQUIRE_PINNED_OFFICIAL_INPUTS:-0}" == "1" ]] || [[ "${GITHUB_WORKFLOW:-}" =~ [Rr]elease ]]; then
    die "OURBOX_SUBSTRATE_REF '${REF}' is not digest-pinned.
  Official candidate/release builds require @sha256: refs to ensure reproducibility.
  Resolve the upstream channel before calling fetch-ourbox-substrate.sh and pass
  the pinned ref via OURBOX_SUBSTRATE_REF."
  elif [[ "${GITHUB_WORKFLOW:-}" =~ [Nn]ightly ]]; then
    log "WARNING: OURBOX_SUBSTRATE_REF is not digest-pinned — nightly build will not be reproducible"
    log "  Resolve the upstream channel before calling fetch-ourbox-substrate.sh"
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

log "Pulling ourbox-substrate bundle (amd64)"
oras pull "${REF}" -o "${PULL_DIR}" | tee "${META_DIR}/oras.pull.log"

TARBALL="${PULL_DIR}/dist/ourbox-substrate.tar.gz"
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
validate_complete_application_metadata "${OUT}"

log "Artifacts created:"
ls -lah "${OUT}/k3s" "${OUT}/platform/images" "${OUT}/manifest.env"

log "Deriving platform contract ref from substrate bundle manifest"
BUNDLE_CONTRACT_REF="$(grep '^OURBOX_PLATFORM_CONTRACT_REF=' "${OUT}/manifest.env" | cut -d= -f2- | tr -d '\r')"
[[ -n "${BUNDLE_CONTRACT_REF}" ]] || die "OURBOX_PLATFORM_CONTRACT_REF not found in substrate bundle manifest: ${OUT}/manifest.env"
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
[[ -n "${SELECTED_AIRGAP_PINNED_REF}" ]] || die "selected substrate pinned ref was not resolved"
[[ "${SELECTED_AIRGAP_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "selected substrate digest is invalid: ${SELECTED_AIRGAP_DIGEST:-missing}"

write_selected_bundle_metadata "${EXPECTED_CONTRACT_DIGEST}" "${SELECTED_AIRGAP_PINNED_REF}" "${SELECTED_AIRGAP_DIGEST}"
log "Selected baked substrate bundle recorded at ${OUT}/selected-bundle.env"

log "Syncing pinned platform contract into installer tree"
"${ROOT}/tools/sync-platform-contract-into-installer.sh"
log "Validated complete baked application metadata in fetched substrate bundle"
