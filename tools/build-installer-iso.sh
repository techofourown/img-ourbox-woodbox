#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

need_cmd curl
need_cmd xorriso
need_cmd rsync
need_cmd sha256sum
need_cmd envsubst
need_cmd sed
need_cmd awk

mkdir -p "${ROOT}/deploy" "${ROOT}/artifacts"

: "${UBUNTU_ISO_URL:?UBUNTU_ISO_URL must be set (tools/versions.env)}"

# Identity inputs (override by env)
: "${OURBOX_PRODUCT:=ourbox}"
: "${OURBOX_DEVICE:=woodbox}"
: "${OURBOX_TARGET:=forge}"
: "${OURBOX_SKU:=TOO-OBX-WBX-FORGE-JU3XK8}"
: "${OURBOX_VARIANT:=prod}"
: "${OURBOX_VERSION:=dev}"

# OS defaults (interactive identity in installer; these act as defaults)
: "${OURBOX_HOSTNAME:=ourbox-woodbox}"
: "${OURBOX_USERNAME:=ourbox}"
# Placeholder hash (installer prompts for identity; do not rely on this)
: "${OURBOX_PASSWORD_HASH:='$6$placeholder$u4o2q0nN6d0fPp7kqzN0R5rH6G3a8uM0IhYf9wq3Zq2IY9xQO2O3sZVnO0Xo0c8zVx7Qz5yT3uEJq0mY1/'}"

# Slugs for filenames
OURBOX_SKU_SLUG="$(echo "${OURBOX_SKU}" | tr 'A-Z' 'a-z')"
OURBOX_VARIANT_SLUG="$(echo "${OURBOX_VARIANT}" | tr 'A-Z' 'a-z')"
OURBOX_TARGET_SLUG="$(echo "${OURBOX_TARGET}" | tr 'A-Z' 'a-z')"

OUT_ISO="${ROOT}/deploy/installer-${OURBOX_PRODUCT}-${OURBOX_DEVICE}-${OURBOX_TARGET_SLUG}-${OURBOX_SKU_SLUG}-${OURBOX_VARIANT_SLUG}-${OURBOX_VERSION}.iso"
OUT_SHA="${OUT_ISO}.sha256"

ISO_STORE="${ROOT}/artifacts/ubuntu"
mkdir -p "${ISO_STORE}"
BASE_ISO_NAME="$(basename "${UBUNTU_ISO_URL}")"
BASE_ISO="${ISO_STORE}/${BASE_ISO_NAME}"

if [[ ! -f "${BASE_ISO}" ]]; then
  log "Downloading Ubuntu ISO: ${UBUNTU_ISO_URL}"
  curl -fL --retry 3 --retry-delay 2 -o "${BASE_ISO}" "${UBUNTU_ISO_URL}"
else
  log "Using cached Ubuntu ISO: ${BASE_ISO}" 
fi

# Require airgap artifacts
if [[ ! -x "${ROOT}/artifacts/airgap/k3s/k3s" ]]; then
  die "missing artifacts/airgap payloads. Run: ./tools/fetch-airgap-platform.sh"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf -- "${WORKDIR}"' EXIT
ISO_DIR="${WORKDIR}/iso"
mkdir -p "${ISO_DIR}"

log "Extracting ISO contents"
xorriso -osirrox on -indev "${BASE_ISO}" -extract / "${ISO_DIR}" >/dev/null 2>&1
chmod -R u+w "${ISO_DIR}" || true

# Add NoCloud autoinstall seed
log "Rendering autoinstall NoCloud seed"
mkdir -p "${ISO_DIR}/nocloud"
export OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH
export OURBOX_PRODUCT OURBOX_DEVICE OURBOX_TARGET OURBOX_SKU OURBOX_VARIANT OURBOX_VERSION

envsubst < "${ROOT}/installer/autoinstall/user-data.tpl" > "${ISO_DIR}/nocloud/user-data"
envsubst < "${ROOT}/installer/autoinstall/meta-data.tpl" > "${ISO_DIR}/nocloud/meta-data"

# Copy OurBox overlay + generate /etc/ourbox/release inside it
log "Staging OurBox rootfs overlay"
mkdir -p "${ISO_DIR}/ourbox"
rsync -a "${ROOT}/installer/ourbox/rootfs/" "${ISO_DIR}/ourbox/rootfs/"

OURBOX_RECIPE_GIT_HASH="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
install -d -m 0755 "${ISO_DIR}/ourbox/rootfs/etc/ourbox"
cat > "${ISO_DIR}/ourbox/rootfs/etc/ourbox/release" <<EOT
OURBOX_PRODUCT=${OURBOX_PRODUCT}
OURBOX_DEVICE=${OURBOX_DEVICE}
OURBOX_TARGET=${OURBOX_TARGET}
OURBOX_SKU=${OURBOX_SKU}
OURBOX_VARIANT=${OURBOX_VARIANT}
OURBOX_VERSION=${OURBOX_VERSION}
OURBOX_RECIPE_GIT_HASH=${OURBOX_RECIPE_GIT_HASH}
EOT
chmod 0644 "${ISO_DIR}/ourbox/rootfs/etc/ourbox/release"

# Copy airgap artifacts onto ISO (will be copied into /target/opt/ourbox/airgap)
log "Staging airgap artifacts onto ISO"
rsync -a "${ROOT}/artifacts/airgap/" "${ISO_DIR}/ourbox/airgap/"

# Patch bootloader configs to force autoinstall
AUTOINSTALL_ARG='autoinstall ds=nocloud\\;s=/cdrom/nocloud/'

patch_boot_cfg() {
  local f="$1"
  [[ -f "${f}" ]] || return 0
  if grep -q 'ds=nocloud' "${f}"; then
    return 0
  fi
  # Add args immediately before the existing '---' delimiter
  sed -i "s/ ---/ ${AUTOINSTALL_ARG} ---/g" "${f}" || true
}

log "Patching boot configs for autoinstall"
while IFS= read -r -d '' f; do
  patch_boot_cfg "$f"
done < <(find "${ISO_DIR}" -type f \( -name 'grub.cfg' -o -name 'loopback.cfg' -o -name 'txt.cfg' -o -name '*.cfg' \) -print0)

VOLID="OURBOX_${OURBOX_DEVICE^^}_${OURBOX_TARGET^^}"
log "Repacking ISO: ${OUT_ISO}"

rm -f "${OUT_ISO}" "${OUT_SHA}"

xorriso \
  -indev "${BASE_ISO}" \
  -outdev "${OUT_ISO}" \
  -map "${ISO_DIR}" / \
  -boot_image any replay \
  -volid "${VOLID}" \
  -compliance no_emul_toc \
  >/dev/null 2>&1

log "Computing sha256"
( cd "$(dirname "${OUT_ISO}")" && sha256sum "$(basename "${OUT_ISO}")" > "$(basename "${OUT_SHA}")" )

log "Installer ISO ready: ${OUT_ISO}"
log "SHA256: ${OUT_SHA}"
