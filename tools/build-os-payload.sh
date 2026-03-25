#!/usr/bin/env bash
# Build the Woodbox OS payload artifact.
#
# The OS payload contains everything needed to install Woodbox onto a target:
#   - rootfs overlay (installer/ourbox/rootfs/)
#   - substrate bundle (k3s binary + platform image tars from artifacts/substrate/)
#   - platform contract content (synced from sw-ourbox-os by fetch-ourbox-substrate.sh)
#   - payload provenance metadata (payload.meta.env)
#
# Output: deploy/os-payload-ourbox-woodbox-<target>-<sku>-<variant>-<version>.tar.gz
#
# Run fetch-ourbox-substrate.sh first (which also fetches and syncs the platform contract).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/config.env" ] && source "${ROOT}/tools/config.env"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

need_cmd tar
need_cmd rsync
need_cmd sha256sum
need_cmd date
need_cmd git

mkdir -p "${ROOT}/deploy"

: "${OURBOX_PRODUCT:=ourbox}"
: "${OURBOX_DEVICE:=woodbox}"
: "${OURBOX_TARGET:=x86}"
: "${OURBOX_SKU:=TOO-OBX-WBX-BASE-JU3XK8}"
: "${OURBOX_VARIANT:=prod}"
: "${OURBOX_VERSION:=dev}"
: "${OS_ARTIFACT_TYPE:=application/vnd.techofourown.ourbox.woodbox.os-payload.v1}"

# Slugs for filenames
OURBOX_TARGET_SLUG="$(echo "${OURBOX_TARGET}" | tr '[:upper:]' '[:lower:]')"
OURBOX_SKU_SLUG="$(echo "${OURBOX_SKU}" | tr '[:upper:]' '[:lower:]')"
OURBOX_VARIANT_SLUG="$(echo "${OURBOX_VARIANT}" | tr '[:upper:]' '[:lower:]')"

BASE="os-payload-${OURBOX_PRODUCT}-${OURBOX_DEVICE}-${OURBOX_TARGET_SLUG}-${OURBOX_SKU_SLUG}-${OURBOX_VARIANT_SLUG}-${OURBOX_VERSION}"
OUT_TAR="${ROOT}/deploy/${BASE}.tar.gz"
OUT_SHA="${OUT_TAR}.sha256"

# Require substrate artifacts
[[ -x "${ROOT}/artifacts/substrate/k3s/k3s" ]] || \
  die "missing artifacts/substrate/k3s/k3s — run: ./tools/fetch-ourbox-substrate.sh"
[[ -f "${ROOT}/artifacts/substrate/manifest.env" ]] || \
  die "missing artifacts/substrate/manifest.env — run: ./tools/fetch-ourbox-substrate.sh"
[[ -f "${ROOT}/artifacts/substrate/platform/images.lock.json" ]] || \
  die "missing artifacts/substrate/platform/images.lock.json — run: ./tools/fetch-ourbox-substrate.sh"

# Require platform contract sync
[[ -d "${ROOT}/installer/ourbox/rootfs/opt/ourbox/substrate/platform" ]] || \
  die "missing synced platform contract — run: ./tools/fetch-ourbox-substrate.sh"

# Load upstream metadata for provenance recording
SUBSTRATE_SELECTED_BUNDLE_ENV="${ROOT}/artifacts/substrate/selected-bundle.env"
[[ -f "${SUBSTRATE_SELECTED_BUNDLE_ENV}" ]] || \
  die "missing artifacts/substrate/selected-bundle.env — run: ./tools/fetch-ourbox-substrate.sh"
# shellcheck disable=SC1090
source "${SUBSTRATE_SELECTED_BUNDLE_ENV}"

OURBOX_SUBSTRATE_REF="${OURBOX_SUBSTRATE_REF:-unknown}"
OURBOX_SUBSTRATE_DIGEST="${OURBOX_SUBSTRATE_DIGEST:-unknown}"
OURBOX_SUBSTRATE_SOURCE="${OURBOX_SUBSTRATE_SOURCE:-unknown}"
OURBOX_SUBSTRATE_REVISION="${OURBOX_SUBSTRATE_REVISION:-unknown}"
OURBOX_SUBSTRATE_VERSION="${OURBOX_SUBSTRATE_VERSION:-unknown}"
OURBOX_SUBSTRATE_CREATED="${OURBOX_SUBSTRATE_CREATED:-unknown}"
OURBOX_SUBSTRATE_ARCH="${OURBOX_SUBSTRATE_ARCH:-unknown}"
OURBOX_SUBSTRATE_PROFILE="${OURBOX_SUBSTRATE_PROFILE:-unknown}"
OURBOX_SUBSTRATE_K3S_VERSION="${OURBOX_SUBSTRATE_K3S_VERSION:-unknown}"
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256="${OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256:-unknown}"
K3S_VERSION="${OURBOX_SUBSTRATE_K3S_VERSION:-unknown}"

GIT_SHA="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_SHA_SHORT="$(git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

PAYLOAD_DIR="${WORKDIR}/payload"
mkdir -p \
  "${PAYLOAD_DIR}/rootfs" \
  "${PAYLOAD_DIR}/substrate"

log "Staging rootfs overlay"
rsync -a "${ROOT}/installer/ourbox/rootfs/" "${PAYLOAD_DIR}/rootfs/"

log "Staging substrate artifacts"
rsync -a "${ROOT}/artifacts/substrate/" "${PAYLOAD_DIR}/substrate/"

log "Writing expanded /etc/ourbox/release into payload rootfs"
install -d -m 0755 "${PAYLOAD_DIR}/rootfs/etc/ourbox"
cat > "${PAYLOAD_DIR}/rootfs/etc/ourbox/release" <<EOT
OURBOX_PRODUCT=${OURBOX_PRODUCT}
OURBOX_DEVICE=${OURBOX_DEVICE}
OURBOX_TARGET=${OURBOX_TARGET}
OURBOX_SKU=${OURBOX_SKU}
OURBOX_VARIANT=${OURBOX_VARIANT}
OURBOX_VERSION=${OURBOX_VERSION}
OURBOX_RECIPE_GIT_HASH=${GIT_SHA}
OURBOX_BASE_ISO_URL=${UBUNTU_ISO_URL:-unknown}
OURBOX_BASE_ISO_SHA256=${UBUNTU_ISO_SHA256:-unknown}
OURBOX_BUILD_TS=${BUILD_TS}
EOT
# Install-time provenance fields (appended by autoinstall late-commands via append-provenance.sh):
#   OURBOX_INSTALLER_ID, OURBOX_OS_ARTIFACT_SOURCE, OURBOX_OS_ARTIFACT_REF,
#   OURBOX_OS_ARTIFACT_DIGEST, OURBOX_OS_IMAGE_SHA256, OURBOX_RELEASE_CHANNEL
chmod 0644 "${PAYLOAD_DIR}/rootfs/etc/ourbox/release"

log "Writing payload provenance metadata"
cat > "${PAYLOAD_DIR}/payload.meta.env" <<EOT
OS_PAYLOAD_BASENAME=${BASE}
OS_ARTIFACT_TYPE=${OS_ARTIFACT_TYPE}
OURBOX_PRODUCT=${OURBOX_PRODUCT}
OURBOX_DEVICE=${OURBOX_DEVICE}
OURBOX_TARGET=${OURBOX_TARGET}
OURBOX_SKU=${OURBOX_SKU}
OURBOX_VARIANT=${OURBOX_VARIANT}
OURBOX_VERSION=${OURBOX_VERSION}
OURBOX_RECIPE_GIT_HASH=${GIT_SHA}
GIT_SHA=${GIT_SHA_SHORT}
BUILD_TS=${BUILD_TS}
OURBOX_SUBSTRATE_REF=${OURBOX_SUBSTRATE_REF}
OURBOX_SUBSTRATE_DIGEST=${OURBOX_SUBSTRATE_DIGEST}
OURBOX_SUBSTRATE_SOURCE=${OURBOX_SUBSTRATE_SOURCE}
OURBOX_SUBSTRATE_REVISION=${OURBOX_SUBSTRATE_REVISION}
OURBOX_SUBSTRATE_VERSION=${OURBOX_SUBSTRATE_VERSION}
OURBOX_SUBSTRATE_CREATED=${OURBOX_SUBSTRATE_CREATED}
OURBOX_SUBSTRATE_ARCH=${OURBOX_SUBSTRATE_ARCH}
OURBOX_SUBSTRATE_PROFILE=${OURBOX_SUBSTRATE_PROFILE}
OURBOX_SUBSTRATE_K3S_VERSION=${OURBOX_SUBSTRATE_K3S_VERSION}
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256}
OURBOX_BASE_ISO_URL=${UBUNTU_ISO_URL:-unknown}
OURBOX_BASE_ISO_SHA256=${UBUNTU_ISO_SHA256:-unknown}
K3S_VERSION=${K3S_VERSION:-unknown}
GITHUB_RUN_ID=${GITHUB_RUN_ID:-}
GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-}
EOT

log "Packing OS payload tarball: ${OUT_TAR}"
rm -f "${OUT_TAR}" "${OUT_SHA}"
tar -czf "${OUT_TAR}" -C "${PAYLOAD_DIR}" .

log "Computing sha256"
( cd "$(dirname "${OUT_TAR}")" && sha256sum "$(basename "${OUT_TAR}")" > "$(basename "${OUT_SHA}")" )

# Write a deploy-side metadata sidecar for use by publish-os-artifact.sh and
# build-installer-iso.sh (embedded-payload path). This duplicates the fields
# in payload.meta.env but lives next to the tarball in deploy/, not inside it.
OUT_META="${ROOT}/deploy/${BASE}.meta.env"
cp "${PAYLOAD_DIR}/payload.meta.env" "${OUT_META}"
log "Metadata sidecar: ${OUT_META}"

log "OS payload ready: ${OUT_TAR}"
log "SHA256: ${OUT_SHA}"
log "Build timestamp: ${BUILD_TS}"
log "Recipe git SHA: ${GIT_SHA_SHORT}"
