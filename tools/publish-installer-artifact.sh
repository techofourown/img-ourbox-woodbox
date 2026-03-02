#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd oras
need_cmd sha256sum
need_cmd date
need_cmd stat

DEPLOY_DIR="${1:-deploy}"
: "${OURBOX_TARGET:=x86}"
: "${OURBOX_VARIANT:=prod}"
: "${OURBOX_VERSION:=dev}"
: "${OURBOX_SKU:=TOO-OBX-WBX-BASE-JU3XK8}"
: "${INSTALLER_REPO:=ghcr.io/techofourown/ourbox-woodbox-installer}"
: "${INSTALLER_ARTIFACT_TYPE:=application/vnd.techofourown.ourbox.woodbox.installer.v1}"
: "${INSTALLER_CHANNEL_TAGS:=${OURBOX_TARGET}-installer-stable}"
: "${INSTALLER_REGISTRY_USERNAME:=}"
: "${INSTALLER_REGISTRY_PASSWORD:=}"
: "${INSTALLER_INCLUDE_BUILD_LOG:=0}"

# shellcheck disable=SC2012
ISO_FILE="$(ls -1t "${DEPLOY_DIR}"/installer-ourbox-woodbox-"${OURBOX_TARGET,,}"-*.iso 2>/dev/null | head -n 1 || true)"
if [[ -z "${ISO_FILE}" || ! -f "${ISO_FILE}" ]]; then
  die "No ${DEPLOY_DIR}/installer-ourbox-woodbox-${OURBOX_TARGET,,}-*.iso found. Did the build finish?"
fi

BASE="$(basename "${ISO_FILE}" .iso)"
INSTALLER_IMMUTABLE_TAG="${INSTALLER_IMMUTABLE_TAG:-${BASE}}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

log "Preparing installer artifact payload for ${INSTALLER_REPO}"

cp "${ISO_FILE}" "${TMP}/installer.iso"
SHA256="$(sha256sum "${TMP}/installer.iso" | awk '{print $1}')"
SIZE_BYTES="$(stat -c%s "${TMP}/installer.iso")"
cat > "${TMP}/installer.iso.sha256" <<EOF
${SHA256}  installer.iso
EOF

GIT_SHA="$(git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "${TMP}/installer.meta.env" <<EOF
INSTALLER_BASENAME=${BASE}
INSTALLER_SHA256=${SHA256}
INSTALLER_SIZE_BYTES=${SIZE_BYTES}
INSTALLER_ARTIFACT_TYPE=${INSTALLER_ARTIFACT_TYPE}
OURBOX_TARGET=${OURBOX_TARGET}
OURBOX_VARIANT=${OURBOX_VARIANT}
OURBOX_VERSION=${OURBOX_VERSION}
OURBOX_SKU=${OURBOX_SKU}
BUILD_TS=${BUILD_TS}
GIT_SHA=${GIT_SHA}
GITHUB_WORKFLOW=${GITHUB_WORKFLOW:-}
GITHUB_RUN_ID=${GITHUB_RUN_ID:-}
GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-}
EOF

push_ref() {
  local tag="$1"
  local ref="${INSTALLER_REPO}:${tag}"
  log ">> Pushing ${ref}"
  local args=(
    "${ref}"
    --artifact-type "${INSTALLER_ARTIFACT_TYPE}"
    --annotation "org.opencontainers.image.source=https://github.com/techofourown/img-ourbox-woodbox"
    --annotation "org.opencontainers.image.revision=${GIT_SHA}"
    --annotation "org.opencontainers.image.version=${OURBOX_VERSION}"
    --annotation "org.opencontainers.image.created=${BUILD_TS}"
    --annotation "techofourown.artifact.kind=installer"
    --annotation "techofourown.target=${OURBOX_TARGET}"
    --annotation "techofourown.variant=${OURBOX_VARIANT}"
    --annotation "techofourown.sku=${OURBOX_SKU}"
    --annotation "techofourown.build.workflow=${GITHUB_WORKFLOW:-local}"
    --annotation "techofourown.build.run-id=${GITHUB_RUN_ID:-local}"
    --annotation "techofourown.build.run-attempt=${GITHUB_RUN_ATTEMPT:-1}"
    "installer.iso:application/octet-stream"
    "installer.iso.sha256:text/plain"
    "installer.meta.env:text/plain"
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
  if [[ -n "${INSTALLER_REGISTRY_USERNAME}" ]]; then
    local registry="${INSTALLER_REPO%%/*}"
    log "Logging into ${registry} for publish"
    oras login "${registry}" -u "${INSTALLER_REGISTRY_USERNAME}" --password "${INSTALLER_REGISTRY_PASSWORD:-}"
  fi
}

maybe_login
LAST_PUSH_DIGEST=""
push_ref "${INSTALLER_IMMUTABLE_TAG}"
IMMUTABLE_DIGEST="${LAST_PUSH_DIGEST}"
IMMUTABLE_PINNED_REF="${INSTALLER_REPO}@${IMMUTABLE_DIGEST}"
echo "${INSTALLER_REPO}:${INSTALLER_IMMUTABLE_TAG}" > "${DEPLOY_DIR}/installer-artifact.ref"
echo "${IMMUTABLE_PINNED_REF}" > "${DEPLOY_DIR}/installer-artifact.pinned.ref"
echo "${IMMUTABLE_DIGEST}" > "${DEPLOY_DIR}/installer-artifact.digest"

for ch in ${INSTALLER_CHANNEL_TAGS}; do
  push_ref "${ch}"
done

log "DONE: published ${INSTALLER_IMMUTABLE_TAG} (and channels: ${INSTALLER_CHANNEL_TAGS:-none}) to ${INSTALLER_REPO}"
