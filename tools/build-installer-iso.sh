#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

need_cmd curl
need_cmd xorriso
need_cmd 7z
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

BASE_VOLID="$(xorriso -indev "${BASE_ISO}" -pvd_info 2>/dev/null \
  | awk -F': *' '/Volume id/ {print $2; exit}' \
  | sed -E "s/[[:space:]]*$//; s/^'//; s/'$//")"
: "${OURBOX_ISO_VOLID:=${BASE_VOLID}}"

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

# Build-time vars substituted in user-data.tpl (the nocloud seed / cloud-init file).
# OURBOX_HOSTNAME/USERNAME/PASSWORD_HASH are kept as fallback defaults only;
# the real identity is collected at install time by ourbox-preinstall.
: "${OURBOX_HOSTNAME:=ourbox-woodbox}"
: "${OURBOX_USERNAME:=ourbox}"
: "${OURBOX_PASSWORD_HASH:=}"
export OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH

SEED_SUBST_VARS='${OURBOX_HOSTNAME} ${OURBOX_USERNAME} ${OURBOX_PASSWORD_HASH} ${OURBOX_PRODUCT} ${OURBOX_DEVICE} ${OURBOX_TARGET} ${OURBOX_SKU} ${OURBOX_VARIANT} ${OURBOX_VERSION}'
envsubst "${SEED_SUBST_VARS}" < "${ROOT}/installer/autoinstall/user-data.tpl" > "${ISO_DIR}/nocloud/user-data"
envsubst "${SEED_SUBST_VARS}" < "${ROOT}/installer/autoinstall/meta-data.tpl"  > "${ISO_DIR}/nocloud/meta-data"
cp -f "${ISO_DIR}/nocloud/user-data" "${ISO_DIR}/autoinstall.yaml"

# Build-time pass-1 substitution of the runtime autoinstall template.
# Substitutes product/version vars; leaves runtime vars (OURBOX_STORAGE_MATCH,
# OURBOX_HOSTNAME, OURBOX_USERNAME, OURBOX_PASSWORD_HASH) intact for
# ourbox-preinstall to fill in at install time.
mkdir -p "${ISO_DIR}/ourbox"
RUNTIME_TPL_SUBST='${OURBOX_PRODUCT} ${OURBOX_DEVICE} ${OURBOX_TARGET} ${OURBOX_SKU} ${OURBOX_VARIANT} ${OURBOX_VERSION}'
envsubst "${RUNTIME_TPL_SUBST}" \
  < "${ROOT}/installer/autoinstall/autoinstall.tpl" \
  > "${ISO_DIR}/ourbox/autoinstall.tpl"

# Copy OurBox overlay + generate /etc/ourbox/release inside it
log "Staging OurBox rootfs overlay"
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

# Stage ourbox-preinstall script and service unit onto the ISO.
# bootcmd in user-data.tpl copies these into the live system at boot time.
log "Staging OurBox pre-installer assets"
mkdir -p "${ISO_DIR}/ourbox/tools"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" \
  "${ISO_DIR}/ourbox/tools/ourbox-preinstall"
install -m 0644 "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall.service" \
  "${ISO_DIR}/ourbox/tools/ourbox-preinstall.service"
# lib.sh is sourced by ourbox-preinstall at runtime (/cdrom/ourbox/tools/lib.sh)
install -m 0644 "${ROOT}/tools/lib.sh" \
  "${ISO_DIR}/ourbox/tools/lib.sh"

# Copy airgap artifacts onto ISO (will be copied into /target/opt/ourbox/airgap)
log "Staging airgap artifacts onto ISO"
rsync -a "${ROOT}/artifacts/airgap/" "${ISO_DIR}/ourbox/airgap/"

# Patch bootloader configs to force autoinstall
AUTOINSTALL_ARG='autoinstall cloud-config-url=/dev/null ds=nocloud\\;s=file:///cdrom/nocloud/'
: "${OURBOX_GRUB_TIMEOUT:=1}"

patch_boot_cfg() {
  local f="$1"
  [[ -f "${f}" ]] || return 0

  if grep -qE '^[[:space:]]*set[[:space:]]+timeout=' "${f}"; then
    sed -i -E "s/^[[:space:]]*set[[:space:]]+timeout=.*/set timeout=${OURBOX_GRUB_TIMEOUT}/" "${f}" || true
  fi
  if grep -qE '^[[:space:]]*set[[:space:]]+timeout_style=' "${f}"; then
    sed -i -E 's/^[[:space:]]*set[[:space:]]+timeout_style=.*/set timeout_style=hidden/' "${f}" || true
  fi

  if grep -q 'ds=nocloud' "${f}"; then
    return 0
  fi
  # Add args immediately before the existing '---' delimiter
  sed -i -E "/^[[:space:]]*(linux|linuxefi|append)[[:space:]]/ s| ---| ${AUTOINSTALL_ARG} ---|g" "${f}" || true
}

log "Patching boot configs for autoinstall"
while IFS= read -r -d '' f; do
  patch_boot_cfg "$f"
done < <(find "${ISO_DIR}" -type f \( -name 'grub.cfg' -o -name 'loopback.cfg' -o -name 'txt.cfg' -o -name '*.cfg' \) -print0)

if ! grep -Rqs 'autoinstall' "${ISO_DIR}/boot/grub"; then
  die "autoinstall kernel args not found in ISO boot configs after patching"
fi
if ! grep -Rqs 'ds=nocloud' "${ISO_DIR}/boot/grub"; then
  die "ds=nocloud kernel args not found in ISO boot configs after patching"
fi

[[ -s "${ISO_DIR}/nocloud/user-data" ]] || die "missing nocloud/user-data in ISO staging tree"
[[ -s "${ISO_DIR}/nocloud/meta-data" ]] || die "missing nocloud/meta-data in ISO staging tree"
[[ -s "${ISO_DIR}/autoinstall.yaml" ]] || die "missing autoinstall.yaml in ISO staging tree"

VOLID="${OURBOX_ISO_VOLID}"

# Ubuntu 24.04+ uses a hybrid GPT/EFI ISO where the EFI boot image is an
# appended partition outside the ISO 9660 filesystem. xorriso's -boot_image
# replay cannot reconstruct this from a remapped directory tree.
# Solution: extract the two hidden boot images with 7z, then rebuild using
# xorriso -as mkisofs with explicit hybrid boot parameters.
log "Extracting boot images from source ISO"
mkdir -p "${WORKDIR}/BOOT"
7z e "${BASE_ISO}" -o"${WORKDIR}/BOOT" \
  '[BOOT]/1-Boot-NoEmul.img' \
  '[BOOT]/2-Boot-NoEmul.img' \
  >/dev/null 2>&1 \
  || die "Failed to extract boot images from base ISO"

log "Repacking ISO: ${OUT_ISO}"
rm -f "${OUT_ISO}" "${OUT_SHA}"

xorriso -as mkisofs \
  -r \
  -V "${VOLID}" \
  -o "${OUT_ISO}" \
  --grub2-mbr "${WORKDIR}/BOOT/1-Boot-NoEmul.img" \
  -partition_offset 16 \
  --mbr-force-bootable \
  -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "${WORKDIR}/BOOT/2-Boot-NoEmul.img" \
  -appended_part_as_gpt \
  -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
  -c '/boot.catalog' \
  -b '/boot/grub/i386-pc/eltorito.img' \
  -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:::' \
  -no-emul-boot \
  "${ISO_DIR}" \
  >/dev/null

log "Computing sha256"
( cd "$(dirname "${OUT_ISO}")" && sha256sum "$(basename "${OUT_ISO}")" > "$(basename "${OUT_SHA}")" )

log "Installer ISO ready: ${OUT_ISO}"
log "SHA256: ${OUT_SHA}"
