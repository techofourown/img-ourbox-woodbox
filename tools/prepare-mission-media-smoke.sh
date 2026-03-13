#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

OS_PAYLOAD=""
OS_META_ENV=""
SUBSTRATE_ISO=""
OUTPUT_DIR=""
MISSION_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  prepare-mission-media-smoke.sh \
    --os-payload PATH \
    --os-meta-env PATH \
    --output-dir DIR \
    [--substrate-iso PATH] \
    [--mission-only]

Build a mission directory from a branch-built Woodbox payload and, unless
--mission-only is set, compose a bootable mission-media ISO from a substrate ISO.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os-payload)
      [[ $# -ge 2 ]] || die "--os-payload requires a value"
      OS_PAYLOAD="$2"
      shift 2
      ;;
    --os-meta-env)
      [[ $# -ge 2 ]] || die "--os-meta-env requires a value"
      OS_META_ENV="$2"
      shift 2
      ;;
    --substrate-iso)
      [[ $# -ge 2 ]] || die "--substrate-iso requires a value"
      SUBSTRATE_ISO="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --mission-only)
      MISSION_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${OS_PAYLOAD}" ]] || die "--os-payload is required"
[[ -f "${OS_PAYLOAD}" ]] || die "OS payload not found: ${OS_PAYLOAD}"
[[ -n "${OS_META_ENV}" ]] || die "--os-meta-env is required"
[[ -f "${OS_META_ENV}" ]] || die "OS metadata not found: ${OS_META_ENV}"
[[ -n "${OUTPUT_DIR}" ]] || die "--output-dir is required"
if [[ "${MISSION_ONLY}" != "1" ]]; then
  [[ -n "${SUBSTRATE_ISO}" ]] || die "--substrate-iso is required unless --mission-only is set"
  [[ -f "${SUBSTRATE_ISO}" ]] || die "substrate ISO not found: ${SUBSTRATE_ISO}"
fi

need_cmd python3
need_cmd tar
need_cmd sha256sum
need_cmd stat
need_cmd rsync
need_cmd git

STRICT_METADATA_PARSER="${ROOT}/tools/strict-kv-metadata.py"
[[ -f "${STRICT_METADATA_PARSER}" ]] || die "strict metadata parser not found: ${STRICT_METADATA_PARSER}"
ENSURE_AIRGAP_APPLICATION_METADATA="${ROOT}/tools/ensure-airgap-application-metadata.sh"
[[ -f "${ENSURE_AIRGAP_APPLICATION_METADATA}" ]] || die "airgap application metadata helper not found: ${ENSURE_AIRGAP_APPLICATION_METADATA}"

WORK_ROOT="${ROOT}/artifacts/work"
mkdir -p "${WORK_ROOT}"
TMP_DIR="$(mktemp -d "${WORK_ROOT}/prepare-mission-media-smoke.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

PAYLOAD_ROOT="${TMP_DIR}/payload"
MISSION_BUILD_ROOT="${TMP_DIR}/mission-build"
BUNDLE_ROOT="${TMP_DIR}/bundle-root"
MISSION_DIR="${MISSION_BUILD_ROOT}/mission"
MISSION_OS_DIR="${MISSION_DIR}/artifacts/os"
MISSION_AIRGAP_DIR="${MISSION_DIR}/artifacts/airgap"
mkdir -p "${PAYLOAD_ROOT}" "${MISSION_OS_DIR}" "${MISSION_AIRGAP_DIR}" "${BUNDLE_ROOT}"

tar -xzf "${OS_PAYLOAD}" -C "${PAYLOAD_ROOT}"
[[ -f "${PAYLOAD_ROOT}/airgap/manifest.env" ]] || die "OS payload missing airgap/manifest.env"
[[ -x "${PAYLOAD_ROOT}/airgap/k3s/k3s" ]] || die "OS payload missing airgap/k3s/k3s"
if [[ -d "${PAYLOAD_ROOT}/rootfs/opt/ourbox/airgap/platform" ]]; then
  bash "${ENSURE_AIRGAP_APPLICATION_METADATA}" \
    --bundle-dir "${PAYLOAD_ROOT}/airgap" \
    --contract-root "${PAYLOAD_ROOT}/rootfs/opt/ourbox/airgap/platform"
fi
[[ -f "${PAYLOAD_ROOT}/airgap/platform/catalog.json" ]] || die "OS payload missing airgap/platform/catalog.json"

meta_dump="$(
  python3 "${STRICT_METADATA_PARSER}" "${OS_META_ENV}" \
    --allow OS_PAYLOAD_BASENAME \
    --allow OS_PAYLOAD_SHA256 \
    --allow OS_PAYLOAD_SIZE_BYTES \
    --allow OS_ARTIFACT_TYPE \
    --allow OURBOX_PRODUCT \
    --allow OURBOX_DEVICE \
    --allow OURBOX_TARGET \
    --allow OURBOX_SKU \
    --allow OURBOX_VARIANT \
    --allow OURBOX_VERSION \
    --allow OURBOX_RECIPE_GIT_HASH \
    --allow BUILD_TS \
    --allow GIT_SHA \
    --allow OURBOX_PLATFORM_CONTRACT_SOURCE \
    --allow OURBOX_PLATFORM_CONTRACT_REVISION \
    --allow OURBOX_PLATFORM_CONTRACT_VERSION \
    --allow OURBOX_PLATFORM_CONTRACT_CREATED \
    --allow OURBOX_PLATFORM_CONTRACT_DIGEST \
    --allow OURBOX_AIRGAP_PLATFORM_REF \
    --allow OURBOX_AIRGAP_PLATFORM_DIGEST \
    --allow OURBOX_AIRGAP_PLATFORM_SOURCE \
    --allow OURBOX_AIRGAP_PLATFORM_REVISION \
    --allow OURBOX_AIRGAP_PLATFORM_VERSION \
    --allow OURBOX_AIRGAP_PLATFORM_CREATED \
    --allow OURBOX_AIRGAP_PLATFORM_ARCH \
    --allow OURBOX_AIRGAP_PLATFORM_PROFILE \
    --allow OURBOX_AIRGAP_PLATFORM_K3S_VERSION \
    --allow OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256 \
    --allow OURBOX_BASE_ISO_URL \
    --allow OURBOX_BASE_ISO_SHA256 \
    --allow K3S_VERSION \
    --allow GITHUB_RUN_ID \
    --allow GITHUB_RUN_ATTEMPT \
    --require OS_ARTIFACT_TYPE \
    --require OURBOX_PLATFORM_CONTRACT_DIGEST \
    --require OURBOX_AIRGAP_PLATFORM_REF \
    --require OURBOX_AIRGAP_PLATFORM_DIGEST \
    --require OURBOX_AIRGAP_PLATFORM_SOURCE \
    --require OURBOX_AIRGAP_PLATFORM_REVISION \
    --require OURBOX_AIRGAP_PLATFORM_VERSION \
    --require OURBOX_AIRGAP_PLATFORM_CREATED \
    --require OURBOX_AIRGAP_PLATFORM_ARCH \
    --require OURBOX_AIRGAP_PLATFORM_PROFILE \
    --require OURBOX_AIRGAP_PLATFORM_K3S_VERSION \
    --require OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256 \
    --print OS_ARTIFACT_TYPE \
    --print OURBOX_PRODUCT \
    --print OURBOX_DEVICE \
    --print OURBOX_TARGET \
    --print OURBOX_SKU \
    --print OURBOX_VARIANT \
    --print OURBOX_VERSION \
    --print OURBOX_PLATFORM_CONTRACT_SOURCE \
    --print OURBOX_PLATFORM_CONTRACT_REVISION \
    --print OURBOX_PLATFORM_CONTRACT_VERSION \
    --print OURBOX_PLATFORM_CONTRACT_CREATED \
    --print OURBOX_PLATFORM_CONTRACT_DIGEST \
    --print OURBOX_AIRGAP_PLATFORM_REF \
    --print OURBOX_AIRGAP_PLATFORM_DIGEST \
    --print OURBOX_AIRGAP_PLATFORM_SOURCE \
    --print OURBOX_AIRGAP_PLATFORM_REVISION \
    --print OURBOX_AIRGAP_PLATFORM_VERSION \
    --print OURBOX_AIRGAP_PLATFORM_CREATED \
    --print OURBOX_AIRGAP_PLATFORM_ARCH \
    --print OURBOX_AIRGAP_PLATFORM_PROFILE \
    --print OURBOX_AIRGAP_PLATFORM_K3S_VERSION \
    --print OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256
)"
mapfile -t meta_fields <<<"${meta_dump}"
[[ "${#meta_fields[@]}" -eq 22 ]] || die "unexpected metadata parse result from ${OS_META_ENV}"

OS_ARTIFACT_TYPE="${meta_fields[0]}"
OURBOX_PRODUCT="${meta_fields[1]}"
OURBOX_DEVICE="${meta_fields[2]}"
OURBOX_TARGET="${meta_fields[3]}"
OURBOX_SKU="${meta_fields[4]}"
OURBOX_VARIANT="${meta_fields[5]}"
OURBOX_VERSION="${meta_fields[6]}"
PLATFORM_CONTRACT_SOURCE="${meta_fields[7]}"
PLATFORM_CONTRACT_REVISION="${meta_fields[8]}"
PLATFORM_CONTRACT_VERSION="${meta_fields[9]}"
PLATFORM_CONTRACT_CREATED="${meta_fields[10]}"
PLATFORM_CONTRACT_DIGEST="${meta_fields[11]}"
BAKED_AIRGAP_REF="${meta_fields[12]}"
BAKED_AIRGAP_DIGEST="${meta_fields[13]}"
BAKED_AIRGAP_SOURCE="${meta_fields[14]}"
BAKED_AIRGAP_REVISION="${meta_fields[15]}"
BAKED_AIRGAP_VERSION="${meta_fields[16]}"
BAKED_AIRGAP_CREATED="${meta_fields[17]}"
BAKED_AIRGAP_ARCH="${meta_fields[18]}"
BAKED_AIRGAP_PROFILE="${meta_fields[19]}"
BAKED_AIRGAP_K3S_VERSION="${meta_fields[20]}"
BAKED_AIRGAP_IMAGES_LOCK_SHA256="${meta_fields[21]}"

OS_PAYLOAD_SHA="$(sha256sum "${OS_PAYLOAD}" | awk '{print $1}')"
OS_PAYLOAD_SIZE="$(stat -c '%s' "${OS_PAYLOAD}")"
OS_ARTIFACT_REF="ghcr.io/techofourown/ourbox-woodbox-os-smoke@sha256:${OS_PAYLOAD_SHA}"

cp -a "${PAYLOAD_ROOT}/airgap/." "${BUNDLE_ROOT}/"

if [[ -f "${BUNDLE_ROOT}/platform/selected-apps.json" ]]; then
  cp -f "${BUNDLE_ROOT}/platform/selected-apps.json" "${MISSION_AIRGAP_DIR}/selected-apps.json"
else
  python3 - <<'PY' "${BUNDLE_ROOT}/platform/catalog.json" "${MISSION_AIRGAP_DIR}/selected-apps.json"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    catalog = json.load(handle)

default_ids = catalog.get("default_app_ids")
if not isinstance(default_ids, list) or not default_ids:
    raise SystemExit("catalog.json must define a non-empty default_app_ids list for mission-media smoke")

payload = {
    "schema": 1,
    "kind": "ourbox-selected-applications",
    "catalog_id": catalog.get("catalog_id"),
    "selection_mode": "defaults",
    "selected_app_ids": default_ids,
}
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  cp -f "${MISSION_AIRGAP_DIR}/selected-apps.json" "${BUNDLE_ROOT}/platform/selected-apps.json"
fi

cp -f "${BUNDLE_ROOT}/platform/catalog.json" "${MISSION_AIRGAP_DIR}/catalog.json"
cp -f "${BUNDLE_ROOT}/manifest.env" "${MISSION_AIRGAP_DIR}/manifest.env"
tar -C "${BUNDLE_ROOT}" -czf "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz" k3s platform manifest.env
printf '%s  %s\n' "$(sha256sum "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz" | awk '{print $1}')" "airgap-platform.tar.gz" \
  > "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz.sha256"

cp -f "${OS_PAYLOAD}" "${MISSION_OS_DIR}/os-payload.tar.gz"
printf '%s  %s\n' "${OS_PAYLOAD_SHA}" "os-payload.tar.gz" > "${MISSION_OS_DIR}/os-payload.tar.gz.sha256"
cp -f "${OS_META_ENV}" "${MISSION_OS_DIR}/os.meta.env"
printf '%s\n' "${OS_ARTIFACT_REF}" > "${MISSION_OS_DIR}/artifact.ref"
printf '%s\n' "${BAKED_AIRGAP_REF}" > "${MISSION_AIRGAP_DIR}/artifact.ref"

MISSION_CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMPOSER_REVISION="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "${ROOT}" status --short 2>/dev/null || true)" ]]; then
  COMPOSER_REVISION="${COMPOSER_REVISION}-dirty"
fi

export MISSION_DIR
export MISSION_CREATED
export COMPOSER_REVISION
export OS_ARTIFACT_TYPE
export OS_ARTIFACT_REF
export OS_PAYLOAD_SHA
export OS_PAYLOAD_SIZE
export PLATFORM_CONTRACT_SOURCE
export PLATFORM_CONTRACT_REVISION
export PLATFORM_CONTRACT_VERSION
export PLATFORM_CONTRACT_CREATED
export PLATFORM_CONTRACT_DIGEST
export BAKED_AIRGAP_REF
export BAKED_AIRGAP_DIGEST
export BAKED_AIRGAP_SOURCE
export BAKED_AIRGAP_REVISION
export BAKED_AIRGAP_VERSION
export BAKED_AIRGAP_CREATED
export BAKED_AIRGAP_ARCH
export BAKED_AIRGAP_PROFILE
export BAKED_AIRGAP_K3S_VERSION
export BAKED_AIRGAP_IMAGES_LOCK_SHA256
export OURBOX_PRODUCT
export OURBOX_DEVICE
export OURBOX_TARGET
export OURBOX_SKU
export OURBOX_VARIANT
export OURBOX_VERSION

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

mission_dir = Path(os.environ["MISSION_DIR"])
catalog_path = mission_dir / "artifacts" / "airgap" / "catalog.json"
selection_path = mission_dir / "artifacts" / "airgap" / "selected-apps.json"
with catalog_path.open("r", encoding="utf-8") as handle:
    catalog = json.load(handle)
with selection_path.open("r", encoding="utf-8") as handle:
    selection = json.load(handle)

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

staged_files = []
for path in sorted(mission_dir.rglob("*")):
    if not path.is_file():
        continue
    relpath = path.relative_to(mission_dir).as_posix()
    staged_files.append(
        {
            "relpath": relpath,
            "sha256": sha256(path),
            "size_bytes": path.stat().st_size,
        }
    )

manifest = {
    "schema": 1,
    "kind": "ourbox-mission",
    "compose_id": f"woodbox-revalidation-{os.environ['OURBOX_VERSION']}",
    "created": os.environ["MISSION_CREATED"],
    "target": {
        "id": "woodbox",
        "media_kind": "installer-usb",
    },
    "composer": {
        "name": "img-ourbox-woodbox",
        "phase": "revalidation-smoke",
        "source_revision": os.environ["COMPOSER_REVISION"],
    },
    "operator_mode": {
        "mode": "install",
        "prompt_hostname_on_target": True,
        "prompt_identity_on_target": True,
    },
    "platform_contract": {
        "digest": os.environ["PLATFORM_CONTRACT_DIGEST"],
        "source": os.environ["PLATFORM_CONTRACT_SOURCE"],
        "revision": os.environ["PLATFORM_CONTRACT_REVISION"],
        "version": os.environ["PLATFORM_CONTRACT_VERSION"],
        "created": os.environ["PLATFORM_CONTRACT_CREATED"],
    },
    "selected_os": {
        "selection_source": "branch-smoke",
        "release_channel": "revalidation",
        "artifact_ref": os.environ["OS_ARTIFACT_REF"],
        "artifact_digest": f"sha256:{os.environ['OS_PAYLOAD_SHA']}",
        "artifact_type": os.environ["OS_ARTIFACT_TYPE"],
        "platform_contract_digest": os.environ["PLATFORM_CONTRACT_DIGEST"],
        "payload": {
            "relpath": "artifacts/os/os-payload.tar.gz",
            "sha256": os.environ["OS_PAYLOAD_SHA"],
            "size_bytes": int(os.environ["OS_PAYLOAD_SIZE"]),
        },
        "metadata_relpath": "artifacts/os/os.meta.env",
    },
    "selected_airgap": {
        "selection_mode": "baked-from-selected-os",
        "selection_source": "branch-smoke",
        "release_channel": "revalidation",
        "artifact_ref": os.environ["BAKED_AIRGAP_REF"],
        "artifact_digest": os.environ["BAKED_AIRGAP_DIGEST"],
        "platform_contract_digest": os.environ["PLATFORM_CONTRACT_DIGEST"],
        "arch": os.environ["BAKED_AIRGAP_ARCH"],
        "profile": os.environ["BAKED_AIRGAP_PROFILE"],
        "version": os.environ["BAKED_AIRGAP_VERSION"],
        "created": os.environ["BAKED_AIRGAP_CREATED"],
        "k3s_version": os.environ["BAKED_AIRGAP_K3S_VERSION"],
        "images_lock_sha256": os.environ["BAKED_AIRGAP_IMAGES_LOCK_SHA256"],
        "payload_relpath": "artifacts/airgap/airgap-platform.tar.gz",
        "manifest_relpath": "artifacts/airgap/manifest.env",
        "present_in_selected_os_payload": True,
    },
    "selected_applications": {
        "catalog_id": str(catalog.get("catalog_id", "")),
        "catalog_name": str(catalog.get("catalog_name", "")),
        "selection_mode": str(selection.get("selection_mode", "")),
        "selected_app_ids": list(selection.get("selected_app_ids", [])),
        "catalog_relpath": "artifacts/airgap/catalog.json",
        "selection_relpath": "artifacts/airgap/selected-apps.json",
        "source_catalogs": [
            {
                "catalog_id": str(catalog.get("catalog_id", "")),
                "catalog_name": str(catalog.get("catalog_name", "")),
                "artifact_ref": os.environ["BAKED_AIRGAP_REF"],
                "artifact_digest": os.environ["BAKED_AIRGAP_DIGEST"],
            }
        ],
    },
    "staged_files": staged_files,
}

with (mission_dir / "mission-manifest.json").open("w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

OUTPUT_DIR="$(readlink -m "${OUTPUT_DIR}")"
FINAL_MISSION_DIR="${OUTPUT_DIR}/mission"
rm -rf "${FINAL_MISSION_DIR}"
mkdir -p "${OUTPUT_DIR}"
cp -a "${MISSION_DIR}" "${FINAL_MISSION_DIR}"

bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${FINAL_MISSION_DIR}" \
  --os-payload "${FINAL_MISSION_DIR}/artifacts/os/os-payload.tar.gz" \
  --os-meta-env "${FINAL_MISSION_DIR}/artifacts/os/os.meta.env"

log "Mission directory prepared: ${FINAL_MISSION_DIR}"

if [[ "${MISSION_ONLY}" == "1" ]]; then
  exit 0
fi

bash "${ROOT}/tools/media-adapter/compose-media.sh" \
  --mission-dir "${FINAL_MISSION_DIR}" \
  --os-payload "${FINAL_MISSION_DIR}/artifacts/os/os-payload.tar.gz" \
  --os-meta-env "${FINAL_MISSION_DIR}/artifacts/os/os.meta.env" \
  --substrate-iso "${SUBSTRATE_ISO}" \
  --output-dir "${OUTPUT_DIR}/media"
