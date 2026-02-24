#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

need_cmd curl
need_cmd chmod
need_cmd sed

cd "${ROOT}"

: "${K3S_VERSION:=}"
: "${NGINX_IMAGE:=docker.io/library/nginx:1.27-alpine}"
: "${DUFS_IMAGE:=docker.io/sigoden/dufs:v0.42.0}"
: "${FLATNOTES_IMAGE:=docker.io/dullage/flatnotes:v5.0.0}"

[[ -n "${K3S_VERSION}" ]] || die "K3S_VERSION not set (edit tools/versions.env)"

NGINX_IMAGE="$(canonicalize_image_ref "${NGINX_IMAGE}")"
DUFS_IMAGE="$(canonicalize_image_ref "${DUFS_IMAGE}")"
FLATNOTES_IMAGE="$(canonicalize_image_ref "${FLATNOTES_IMAGE}")"

log "Using K3S_VERSION=${K3S_VERSION}"
log "Using NGINX_IMAGE=${NGINX_IMAGE}"
log "Using DUFS_IMAGE=${DUFS_IMAGE}"
log "Using FLATNOTES_IMAGE=${FLATNOTES_IMAGE}"

OUT="artifacts/airgap"

# Preflight: refuse to overwrite unless confirmed
blocking=()
[[ -f "${OUT}/k3s/k3s" ]] && blocking+=("${OUT}/k3s/k3s")
[[ -f "${OUT}/k3s/k3s-airgap-images-amd64.tar" ]] && blocking+=("${OUT}/k3s/k3s-airgap-images-amd64.tar")
[[ -d "${OUT}/platform/images" ]] && blocking+=("${OUT}/platform/images")
[[ -d "${OUT}/platform/todo-bloom" ]] && blocking+=("${OUT}/platform/todo-bloom")

if (( ${#blocking[@]} > 0 )); then
  log "Existing artifacts detected (refusing to overwrite):"
  for f in "${blocking[@]}"; do
    echo "  ${f}"
  done
  echo
  read -r -p "Type REMOVE to delete artifacts/airgap and continue, or anything else to abort: " confirm
  [[ "${confirm}" == "REMOVE" ]] || die "Fetch aborted"
  rm -rf "${OUT}"
fi

mkdir -p "${OUT}/k3s" "${OUT}/platform/images" "${OUT}/platform/todo-bloom"

log "Fetch k3s binary (amd64) @ ${K3S_VERSION}"
curl -fsSL -o "${OUT}/k3s/k3s" \
  "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s"
chmod +x "${OUT}/k3s/k3s"

log "Fetch k3s airgap images (amd64) @ ${K3S_VERSION}"
curl -fsSL -o "${OUT}/k3s/k3s-airgap-images-amd64.tar" \
  "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar"

CLI="$(pick_container_cli)"
log "Using container CLI: ${CLI}"

NGINX_TAR="$(echo "${NGINX_IMAGE}" | sed 's|/|_|g; s|:|_|g').tar"
DUFS_TAR="$(echo "${DUFS_IMAGE}" | sed 's|/|_|g; s|:|_|g').tar"
FLATNOTES_TAR="$(echo "${FLATNOTES_IMAGE}" | sed 's|/|_|g; s|:|_|g').tar"

save_image_amd64() {
  local image="$1" tarfile="$2"
  case "$(cli_base "${CLI}")" in
    docker|nerdctl)
      # shellcheck disable=SC2086
      ${CLI} pull --platform=linux/amd64 "${image}"
      if [[ "$(cli_base "${CLI}")" == "nerdctl" ]]; then
        # shellcheck disable=SC2086
        ${CLI} save --platform=linux/amd64 -o "${tarfile}" "${image}"
      else
        # shellcheck disable=SC2086
        ${CLI} save -o "${tarfile}" "${image}"
      fi
      ;;
    podman)
      # shellcheck disable=SC2086
      ${CLI} pull --arch=amd64 --os=linux "${image}"
      # shellcheck disable=SC2086
      ${CLI} save -o "${tarfile}" "${image}"
      ;;
    *)
      die "Unsupported container CLI: ${CLI}"
      ;;
  esac
}

log "Pull + save (amd64): ${NGINX_IMAGE}"
save_image_amd64 "${NGINX_IMAGE}" "${OUT}/platform/images/${NGINX_TAR}"

log "Pull + save (amd64): ${DUFS_IMAGE}"
save_image_amd64 "${DUFS_IMAGE}" "${OUT}/platform/images/${DUFS_TAR}"

log "Pull + save (amd64): ${FLATNOTES_IMAGE}"
save_image_amd64 "${FLATNOTES_IMAGE}" "${OUT}/platform/images/${FLATNOTES_TAR}"

TODO_BLOOM_REPO="https://raw.githubusercontent.com/EverybodyCode/todo/main"
log "Fetch Todo Bloom static files from ${TODO_BLOOM_REPO}"
curl -fsSL -o "${OUT}/platform/todo-bloom/index.html" "${TODO_BLOOM_REPO}/index.html"
curl -fsSL -o "${OUT}/platform/todo-bloom/app.js"     "${TODO_BLOOM_REPO}/app.js"
curl -fsSL -o "${OUT}/platform/todo-bloom/styles.css" "${TODO_BLOOM_REPO}/styles.css"

log "Writing airgap manifest"
cat > "${OUT}/manifest.env" <<EOF_MANIFEST
K3S_VERSION=${K3S_VERSION}
NGINX_IMAGE=${NGINX_IMAGE}
DUFS_IMAGE=${DUFS_IMAGE}
FLATNOTES_IMAGE=${FLATNOTES_IMAGE}
EOF_MANIFEST

log "Artifacts created:"
ls -lah "${OUT}/k3s" "${OUT}/platform/images" "${OUT}/platform/todo-bloom" "${OUT}/manifest.env"
