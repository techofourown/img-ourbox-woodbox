#!/usr/bin/env bash
# Build the Woodbox OS payload artifact.
#
# The OS payload contains everything needed to install Woodbox onto a target:
#   - rootfs overlay (installer/ourbox/rootfs/)
#   - airgap bundle (k3s binary + image tars from artifacts/airgap/)
#   - platform contract content (synced from sw-ourbox-os by fetch-airgap-platform.sh)
#   - payload provenance metadata (payload.meta.env)
#
# Output: deploy/os-payload-ourbox-woodbox-<target>-<sku>-<variant>-<version>.tar.gz
#
# Run fetch-airgap-platform.sh first (which also fetches and syncs the platform contract).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/config.env" ] && source "${ROOT}/tools/config.env"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"
# shellcheck disable=SC1091
# Official pinned inputs take precedence over versions.env defaults.
[ -f "${ROOT}/release/official-inputs.env" ] && source "${ROOT}/release/official-inputs.env"

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

# Slugs for filenames
OURBOX_TARGET_SLUG="$(echo "${OURBOX_TARGET}" | tr '[:upper:]' '[:lower:]')"
OURBOX_SKU_SLUG="$(echo "${OURBOX_SKU}" | tr '[:upper:]' '[:lower:]')"
OURBOX_VARIANT_SLUG="$(echo "${OURBOX_VARIANT}" | tr '[:upper:]' '[:lower:]')"

BASE="os-payload-${OURBOX_PRODUCT}-${OURBOX_DEVICE}-${OURBOX_TARGET_SLUG}-${OURBOX_SKU_SLUG}-${OURBOX_VARIANT_SLUG}-${OURBOX_VERSION}"
OUT_TAR="${ROOT}/deploy/${BASE}.tar.gz"
OUT_SHA="${OUT_TAR}.sha256"

# Require airgap artifacts
[[ -x "${ROOT}/artifacts/airgap/k3s/k3s" ]] || \
  die "missing artifacts/airgap/k3s/k3s — run: ./tools/fetch-airgap-platform.sh"
[[ -f "${ROOT}/artifacts/airgap/manifest.env" ]] || \
  die "missing artifacts/airgap/manifest.env — run: ./tools/fetch-airgap-platform.sh"

# Require platform contract sync
[[ -f "${ROOT}/installer/ourbox/rootfs/opt/ourbox/airgap/platform/contract.env" ]] || \
  die "missing synced platform contract — run: ./tools/fetch-airgap-platform.sh"

# Load upstream metadata for provenance recording
AIRGAP_MANIFEST="${ROOT}/artifacts/airgap/manifest.env"
# shellcheck disable=SC1090
source "${AIRGAP_MANIFEST}"

CONTRACT_ENV="${ROOT}/installer/ourbox/rootfs/opt/ourbox/airgap/platform/contract.env"
CONTRACT_DIGEST_FILE="${ROOT}/installer/ourbox/rootfs/opt/ourbox/airgap/platform/contract.digest"
# shellcheck disable=SC1090
source "${CONTRACT_ENV}"
CONTRACT_DIGEST="$(cat "${CONTRACT_DIGEST_FILE}" 2>/dev/null || echo unknown)"

# Capture airgap-platform ref and digest for provenance.
# OURBOX_AIRGAP_PLATFORM_REF is the resolved fetch ref from workflows when present.
# AIRGAP_PLATFORM_REF is the pinned fallback from release/official-inputs.env.
# The actual digest is stored in artifacts/.airgap-platform-meta/oras.pull.log if available.
AIRGAP_PLATFORM_REF_USED="${OURBOX_AIRGAP_PLATFORM_REF:-${AIRGAP_PLATFORM_REF:-unknown}}"
AIRGAP_PLATFORM_DIGEST="unknown"
AIRGAP_META_LOG="${ROOT}/artifacts/.airgap-platform-meta/oras.pull.log"
if [[ -f "${AIRGAP_META_LOG}" ]]; then
  _d="$(grep -Eo 'sha256:[0-9a-f]{64}' "${AIRGAP_META_LOG}" | tail -n1 || true)"
  [[ -n "${_d}" ]] && AIRGAP_PLATFORM_DIGEST="${_d}"
  unset _d
fi

GIT_SHA="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_SHA_SHORT="$(git -C "${ROOT}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
BUILD_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

PAYLOAD_DIR="${WORKDIR}/payload"
mkdir -p \
  "${PAYLOAD_DIR}/rootfs" \
  "${PAYLOAD_DIR}/airgap"

log "Staging rootfs overlay"
rsync -a "${ROOT}/installer/ourbox/rootfs/" "${PAYLOAD_DIR}/rootfs/"

log "Staging airgap artifacts"
rsync -a "${ROOT}/artifacts/airgap/" "${PAYLOAD_DIR}/airgap/"

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
OURBOX_PLATFORM_CONTRACT_SOURCE=${OURBOX_PLATFORM_CONTRACT_SOURCE:-https://github.com/techofourown/sw-ourbox-os}
OURBOX_PLATFORM_CONTRACT_REVISION=${OURBOX_PLATFORM_CONTRACT_REVISION:-unknown}
OURBOX_PLATFORM_CONTRACT_VERSION=${OURBOX_PLATFORM_CONTRACT_VERSION:-unknown}
OURBOX_PLATFORM_CONTRACT_CREATED=${OURBOX_PLATFORM_CONTRACT_CREATED:-unknown}
OURBOX_PLATFORM_CONTRACT_DIGEST=${CONTRACT_DIGEST}
OURBOX_AIRGAP_PLATFORM_REF=${AIRGAP_PLATFORM_REF_USED}
OURBOX_AIRGAP_PLATFORM_DIGEST=${AIRGAP_PLATFORM_DIGEST}
OURBOX_BASE_ISO_URL=${UBUNTU_ISO_URL:-unknown}
OURBOX_BASE_ISO_SHA256=${UBUNTU_ISO_SHA256:-unknown}
OURBOX_BUILD_TS=${BUILD_TS}
EOT
# Install-time provenance fields (appended by autoinstall late-commands via append-provenance.sh):
#   OURBOX_INSTALLER_ID, OURBOX_OS_ARTIFACT_SOURCE, OURBOX_OS_ARTIFACT_REF,
#   OURBOX_OS_ARTIFACT_DIGEST, OURBOX_OS_IMAGE_SHA256, OURBOX_RELEASE_CHANNEL,
#   OURBOX_INSTALL_DEFAULTS_SOURCE, OURBOX_INSTALL_DEFAULTS_REF
chmod 0644 "${PAYLOAD_DIR}/rootfs/etc/ourbox/release"

log "Writing payload provenance metadata"
cat > "${PAYLOAD_DIR}/payload.meta.env" <<EOT
OS_PAYLOAD_BASENAME=${BASE}
OURBOX_PRODUCT=${OURBOX_PRODUCT}
OURBOX_DEVICE=${OURBOX_DEVICE}
OURBOX_TARGET=${OURBOX_TARGET}
OURBOX_SKU=${OURBOX_SKU}
OURBOX_VARIANT=${OURBOX_VARIANT}
OURBOX_VERSION=${OURBOX_VERSION}
OURBOX_RECIPE_GIT_HASH=${GIT_SHA}
BUILD_TS=${BUILD_TS}
OURBOX_PLATFORM_CONTRACT_SOURCE=${OURBOX_PLATFORM_CONTRACT_SOURCE:-https://github.com/techofourown/sw-ourbox-os}
OURBOX_PLATFORM_CONTRACT_REVISION=${OURBOX_PLATFORM_CONTRACT_REVISION:-unknown}
OURBOX_PLATFORM_CONTRACT_VERSION=${OURBOX_PLATFORM_CONTRACT_VERSION:-unknown}
OURBOX_PLATFORM_CONTRACT_DIGEST=${CONTRACT_DIGEST}
OURBOX_AIRGAP_PLATFORM_REF=${AIRGAP_PLATFORM_REF_USED}
OURBOX_AIRGAP_PLATFORM_DIGEST=${AIRGAP_PLATFORM_DIGEST}
OURBOX_BASE_ISO_URL=${UBUNTU_ISO_URL:-unknown}
OURBOX_BASE_ISO_SHA256=${UBUNTU_ISO_SHA256:-unknown}
K3S_VERSION=${K3S_VERSION:-unknown}
GITHUB_WORKFLOW="${GITHUB_WORKFLOW:-}"
GITHUB_RUN_ID="${GITHUB_RUN_ID:-}"
GITHUB_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:-}"
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
log "Platform contract digest: ${CONTRACT_DIGEST}"
log "Recipe git SHA: ${GIT_SHA_SHORT}"
