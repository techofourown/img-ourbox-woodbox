#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/registry.sh"

need_cmd oras
need_cmd python3
need_cmd sha256sum
need_cmd date
need_cmd stat

DEPLOY_DIR="${1:-deploy}"
: "${OURBOX_TARGET:=x86}"
: "${OURBOX_VARIANT:=prod}"
: "${OURBOX_VERSION:=dev}"
: "${OURBOX_SKU:=TOO-OBX-WBX-BASE-JU3XK8}"
: "${OURBOX_GIT_SHA:=}"
: "${OURBOX_ARTIFACT_KIND:=os-payload}"
: "${OS_REPO:=ghcr.io/techofourown/ourbox-woodbox-os}"
: "${OS_ARTIFACT_TYPE:=application/vnd.techofourown.ourbox.woodbox.os-payload.v1}"
: "${OS_CATALOG_TAG:=${OURBOX_TARGET}-catalog}"
: "${OS_CATALOG_ARTIFACT_TYPE:=application/vnd.techofourown.ourbox.woodbox.os-catalog.v1}"
: "${OS_CATALOG_CHANNEL_MODE:=short}"
: "${OS_CATALOG_SHA_COLUMN:=payload_sha256}"
: "${OS_CHANNEL_TAGS:=${OURBOX_TARGET}-stable}"
: "${OS_REGISTRY_USERNAME:=}"
: "${OS_REGISTRY_PASSWORD:=}"
: "${OS_INCLUDE_BUILD_LOG:=0}"

resolve_git_sha() {
  if [[ -n "${OURBOX_GIT_SHA}" ]]; then
    printf '%s\n' "${OURBOX_GIT_SHA}"
    return 0
  fi
  if [[ -n "${GITHUB_SHA:-}" ]]; then
    printf '%s\n' "${GITHUB_SHA:0:12}"
    return 0
  fi
  if git -C "${ROOT}" rev-parse --short=12 HEAD >/dev/null 2>&1; then
    git -C "${ROOT}" rev-parse --short=12 HEAD
    return 0
  fi
  die "unable to resolve GIT_SHA for OS artifact publication"
}

# shellcheck disable=SC2012
PAYLOAD_TAR="$(ls -1t "${DEPLOY_DIR}"/os-payload-ourbox-woodbox-"${OURBOX_TARGET,,}"-*.tar.gz 2>/dev/null | head -n 1 || true)"
if [[ -z "${PAYLOAD_TAR}" || ! -f "${PAYLOAD_TAR}" ]]; then
  die "No ${DEPLOY_DIR}/os-payload-ourbox-woodbox-${OURBOX_TARGET,,}-*.tar.gz found. Did the build finish?"
fi

BASE="$(basename "${PAYLOAD_TAR}" .tar.gz)"
OS_IMMUTABLE_TAG="${OS_IMMUTABLE_TAG:-${BASE}}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

log "Preparing OS artifact payload for ${OS_REPO}"

cp "${PAYLOAD_TAR}" "${TMP}/os-payload.tar.gz"
SHA256="$(sha256sum "${TMP}/os-payload.tar.gz" | awk '{print $1}')"
SIZE_BYTES="$(stat -c%s "${TMP}/os-payload.tar.gz")"
cat > "${TMP}/os-payload.tar.gz.sha256" <<EOF
${SHA256}  os-payload.tar.gz
EOF

META_ENV="${DEPLOY_DIR}/${BASE}.meta.env"
[[ -f "${META_ENV}" ]] || META_ENV="${PAYLOAD_TAR%.tar.gz}.meta.env"

PUBLISH_PLATFORM_CONTRACT_DIGEST_OVERRIDE="${OURBOX_PLATFORM_CONTRACT_DIGEST:-}"
CONTRACT_DIGEST="unknown"
if [[ -f "${META_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${META_ENV}"
  CONTRACT_DIGEST="${OURBOX_PLATFORM_CONTRACT_DIGEST:-unknown}"
fi
K3S_VERSION="${K3S_VERSION:-unknown}"

GIT_SHA="$(resolve_git_sha)"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export BASE SHA256 SIZE_BYTES OS_ARTIFACT_TYPE OURBOX_TARGET OURBOX_VARIANT OURBOX_VERSION OURBOX_SKU BUILD_TS GIT_SHA
export OURBOX_PLATFORM_CONTRACT_DIGEST="${PUBLISH_PLATFORM_CONTRACT_DIGEST_OVERRIDE:-${CONTRACT_DIGEST}}"
export OURBOX_PLATFORM_CONTRACT_SOURCE="${OURBOX_PLATFORM_CONTRACT_SOURCE:-unknown}"
export OURBOX_PLATFORM_CONTRACT_REVISION="${OURBOX_PLATFORM_CONTRACT_REVISION:-unknown}"
export OURBOX_PLATFORM_CONTRACT_VERSION="${OURBOX_PLATFORM_CONTRACT_VERSION:-unknown}"
export K3S_VERSION
export GITHUB_WORKFLOW="${GITHUB_WORKFLOW:-}"
export GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
export GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-}"

python3 - "${TMP}/os.meta.values.json" <<'PY'
import json
import os
import sys

payload = {
    "OS_PAYLOAD_BASENAME": os.environ["BASE"],
    "OS_PAYLOAD_SHA256": os.environ["SHA256"],
    "OS_PAYLOAD_SIZE_BYTES": os.environ["SIZE_BYTES"],
    "OS_ARTIFACT_TYPE": os.environ["OS_ARTIFACT_TYPE"],
    "OURBOX_TARGET": os.environ["OURBOX_TARGET"],
    "OURBOX_VARIANT": os.environ["OURBOX_VARIANT"],
    "OURBOX_VERSION": os.environ["OURBOX_VERSION"],
    "OURBOX_SKU": os.environ["OURBOX_SKU"],
    "BUILD_TS": os.environ["BUILD_TS"],
    "GIT_SHA": os.environ["GIT_SHA"],
    "OURBOX_PLATFORM_CONTRACT_DIGEST": os.environ["OURBOX_PLATFORM_CONTRACT_DIGEST"],
    "OURBOX_PLATFORM_CONTRACT_SOURCE": os.environ["OURBOX_PLATFORM_CONTRACT_SOURCE"],
    "OURBOX_PLATFORM_CONTRACT_REVISION": os.environ["OURBOX_PLATFORM_CONTRACT_REVISION"],
    "OURBOX_PLATFORM_CONTRACT_VERSION": os.environ["OURBOX_PLATFORM_CONTRACT_VERSION"],
    "K3S_VERSION": os.environ["K3S_VERSION"],
    "GITHUB_WORKFLOW": os.environ["GITHUB_WORKFLOW"],
    "GITHUB_RUN_ID": os.environ["GITHUB_RUN_ID"],
    "GITHUB_RUN_ATTEMPT": os.environ["GITHUB_RUN_ATTEMPT"],
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
PY

python3 "${ROOT}/tools/release-control/release_control.py" write-metadata \
  --input-json "${TMP}/os.meta.values.json" \
  --env-output "${TMP}/os.meta.env" \
  --json-output "${TMP}/os.meta.json"

cp "${TMP}/os.meta.env" "${DEPLOY_DIR}/os-artifact.meta.env"
cp "${TMP}/os.meta.json" "${DEPLOY_DIR}/os-artifact.meta.json"

push_ref() {
  local tag="$1"
  local ref="${OS_REPO}:${tag}"
  log ">> Pushing ${ref}"
  local args=(
    "${ref}"
    --artifact-type "${OS_ARTIFACT_TYPE}"
    --annotation "org.opencontainers.image.source=https://github.com/techofourown/img-ourbox-woodbox"
    --annotation "org.opencontainers.image.revision=${GIT_SHA}"
    --annotation "org.opencontainers.image.version=${OURBOX_VERSION}"
    --annotation "org.opencontainers.image.created=${BUILD_TS}"
    --annotation "techofourown.artifact.kind=${OURBOX_ARTIFACT_KIND}"
    --annotation "techofourown.target=${OURBOX_TARGET}"
    --annotation "techofourown.variant=${OURBOX_VARIANT}"
    --annotation "techofourown.sku=${OURBOX_SKU}"
    --annotation "techofourown.platform-contract.digest=${OURBOX_PLATFORM_CONTRACT_DIGEST}"
    --annotation "techofourown.build.workflow=${GITHUB_WORKFLOW:-local}"
    --annotation "techofourown.build.run-id=${GITHUB_RUN_ID:-local}"
    --annotation "techofourown.build.run-attempt=${GITHUB_RUN_ATTEMPT:-1}"
    "os-payload.tar.gz:application/octet-stream"
    "os-payload.tar.gz.sha256:text/plain"
    "os.meta.env:text/plain"
    "os.meta.json:application/json"
  )
  local out status digest
  set +e
  out="$(cd "${TMP}" && oras push "${args[@]}" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "${out}"
  if [[ "${status}" -ne 0 ]]; then
    die "oras push failed for ${ref} (exit ${status})"
  fi
  digest="$(printf '%s\n' "${out}" | grep -Eo 'sha256:[0-9a-f]{64}' | tail -n1)"
  [[ -n "${digest}" ]] || die "Failed to capture digest from oras output for ${ref}"
  LAST_PUSH_DIGEST="${digest}"
  log ">> Digest ${tag}: ${digest}"
}

maybe_login() {
  if [[ -n "${OS_REGISTRY_USERNAME}" ]]; then
    local registry="${OS_REPO%%/*}"
    log "Logging into ${registry} for publish"
    oras login "${registry}" -u "${OS_REGISTRY_USERNAME}" --password "${OS_REGISTRY_PASSWORD:-}"
  fi
}

maybe_login
LAST_PUSH_DIGEST=""
push_ref "${OS_IMMUTABLE_TAG}"
IMMUTABLE_DIGEST="${LAST_PUSH_DIGEST}"
IMMUTABLE_PINNED_REF="${OS_REPO}@${IMMUTABLE_DIGEST}"
printf '%s\n' "${OS_REPO}:${OS_IMMUTABLE_TAG}" > "${DEPLOY_DIR}/os-artifact.ref"
printf '%s\n' "${IMMUTABLE_PINNED_REF}" > "${DEPLOY_DIR}/os-artifact.pinned.ref"
printf '%s\n' "${IMMUTABLE_DIGEST}" > "${DEPLOY_DIR}/os-artifact.digest"

export OS_REPO OS_IMMUTABLE_TAG IMMUTABLE_PINNED_REF IMMUTABLE_DIGEST OURBOX_ARTIFACT_KIND K3S_VERSION
python3 - "${TMP}/os.meta.values.json" "${DEPLOY_DIR}/os-artifact.publish.json" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    meta_env = json.load(fh)

payload = {
    "schema": 1,
    "artifact_role": "os",
    "artifact_kind": os.environ["OURBOX_ARTIFACT_KIND"],
    "artifact_type": os.environ["OS_ARTIFACT_TYPE"],
    "artifact_repo": os.environ["OS_REPO"],
    "artifact_ref": f'{os.environ["OS_REPO"]}:{os.environ["OS_IMMUTABLE_TAG"]}',
    "artifact_pinned_ref": os.environ["IMMUTABLE_PINNED_REF"],
    "artifact_digest": os.environ["IMMUTABLE_DIGEST"],
    "payload_filename": "os-payload.tar.gz",
    "payload_sha256": os.environ["SHA256"],
    "payload_size_bytes": int(os.environ["SIZE_BYTES"]),
    "control_fields": {
        "version": os.environ["OURBOX_VERSION"],
        "variant": os.environ["OURBOX_VARIANT"],
        "target": os.environ["OURBOX_TARGET"],
        "sku": os.environ["OURBOX_SKU"],
        "git_sha": os.environ["GIT_SHA"],
        "platform_contract_digest": os.environ["OURBOX_PLATFORM_CONTRACT_DIGEST"],
        "k3s_version": os.environ["K3S_VERSION"],
    },
    "meta_env": meta_env,
}

with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
PY

for ch in ${OS_CHANNEL_TAGS}; do
  push_ref "${ch}"
  python3 "${ROOT}/tools/release-control/release_control.py" update-catalog \
    --artifact-record "${DEPLOY_DIR}/os-artifact.publish.json" \
    --artifact-repo "${OS_REPO}" \
    --catalog-tag "${OS_CATALOG_TAG}" \
    --catalog-artifact-type "${OS_CATALOG_ARTIFACT_TYPE}" \
    --channel-tag "${ch}" \
    --channel-mode "${OS_CATALOG_CHANNEL_MODE}" \
    --sha-column "${OS_CATALOG_SHA_COLUMN}" \
    --timestamp "${BUILD_TS}"
done

log "DONE: published ${OS_IMMUTABLE_TAG} (and channels: ${OS_CHANNEL_TAGS:-none}) to ${OS_REPO}"
