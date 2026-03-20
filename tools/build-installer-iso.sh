#!/usr/bin/env bash
# Build the OurBox Woodbox installer ISO.
#
# This script now produces one of two objects:
# - installer substrate: the target-owned boot/install runtime with no mission bytes
# - mission media: substrate plus an embedded OS payload and mission directory
#
# The supported install path is mission media only. A substrate-only ISO remains
# useful as a host-composition input, but it is not a standalone install path.
#
# Flags:
#   --embed-payload PATH      Embed the specified OS payload tar.gz into the ISO
#                             as part of a composed mission medium.
#   --embed-payload-meta PATH Embed the metadata sidecar that must land at
#                             /cdrom/ourbox/payload/payload.meta.env.
#   --embed-mission-dir PATH  Copy a prepared mission directory into
#                             /cdrom/ourbox/mission/ inside the ISO.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/installer-ssh-helper.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/config.env" ] && source "${ROOT}/tools/config.env"
need_cmd curl
need_cmd xorriso
need_cmd 7z
need_cmd rsync
need_cmd sha256sum
need_cmd envsubst
need_cmd sed
need_cmd awk
need_cmd bash
: "${OURBOX_INSTALLER_TARGET_PACKAGES:=avahi-daemon avahi-utils}"
: "${OURBOX_INSTALLER_TARGET_APT_REPO_EXTRA_PACKAGES:=openssh-server}"
: "${OURBOX_INSTALLER_TARGET_APT_REPO_SOURCE_DIR:=}"

EMBED_PAYLOAD=""
EMBED_PAYLOAD_META=""
EMBED_MISSION_DIR=""
OUT_ISO_PATH=""
: "${OURBOX_VARIANT:=prod}"
: "${DEFAULT_INSTALLER_SSH_MODE:=both}"
: "${OURBOX_INSTALLER_SSH_MODE:=${DEFAULT_INSTALLER_SSH_MODE}}"
: "${OURBOX_INSTALLER_SSH_USER:=ourbox-installer}"
: "${OURBOX_INSTALLER_SSH_PASSWORD_HASH:=}"
: "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS:=}"
: "${OURBOX_INSTALLER_SSH_ALLOW_ROOT:=0}"
: "${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY:=1}"
: "${OURBOX_INSTALLER_SMOKE_CONSOLE:=0}"
: "${OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR:=255.255.255.255}"
: "${OURBOX_INSTALLER_MONITOR_BROADCAST_PORT:=9999}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --embed-payload)
      [[ $# -ge 2 ]] || die "--embed-payload requires a path"
      EMBED_PAYLOAD="$2"
      shift 2
      ;;
    --embed-payload-meta)
      [[ $# -ge 2 ]] || die "--embed-payload-meta requires a path"
      EMBED_PAYLOAD_META="$2"
      shift 2
      ;;
    --embed-mission-dir)
      [[ $# -ge 2 ]] || die "--embed-mission-dir requires a path"
      EMBED_MISSION_DIR="$2"
      shift 2
      ;;
    --out-iso)
      [[ $# -ge 2 ]] || die "--out-iso requires a path"
      OUT_ISO_PATH="$2"
      shift 2
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

ourbox_installer_ssh_normalize_inputs
ourbox_installer_ssh_validate_requested_posture

case "${OURBOX_INSTALLER_SMOKE_CONSOLE}" in
  0|1) ;;
  *) die "invalid OURBOX_INSTALLER_SMOKE_CONSOLE: ${OURBOX_INSTALLER_SMOKE_CONSOLE}" ;;
esac

[[ -n "${OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR}" ]] || die "OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR must not be empty"
[[ "${OURBOX_INSTALLER_MONITOR_BROADCAST_PORT}" =~ ^[0-9]+$ ]] \
  || die "invalid OURBOX_INSTALLER_MONITOR_BROADCAST_PORT: ${OURBOX_INSTALLER_MONITOR_BROADCAST_PORT}"
if (( OURBOX_INSTALLER_MONITOR_BROADCAST_PORT < 1 || OURBOX_INSTALLER_MONITOR_BROADCAST_PORT > 65535 )); then
  die "OURBOX_INSTALLER_MONITOR_BROADCAST_PORT out of range: ${OURBOX_INSTALLER_MONITOR_BROADCAST_PORT}"
fi

if [[ -n "${EMBED_PAYLOAD}" ]]; then
  [[ -f "${EMBED_PAYLOAD}" ]] || die "embedded payload not found: ${EMBED_PAYLOAD}"
fi

if [[ -n "${EMBED_PAYLOAD_META}" ]]; then
  [[ -f "${EMBED_PAYLOAD_META}" ]] || die "embedded payload metadata not found: ${EMBED_PAYLOAD_META}"
fi

if [[ -n "${EMBED_MISSION_DIR}" ]]; then
  [[ -d "${EMBED_MISSION_DIR}" ]] || die "embedded mission dir not found: ${EMBED_MISSION_DIR}"
  [[ -f "${EMBED_MISSION_DIR}/mission-manifest.json" ]] \
    || die "embedded mission dir is missing mission-manifest.json: ${EMBED_MISSION_DIR}"
fi

if [[ -n "${EMBED_PAYLOAD}" && -z "${EMBED_MISSION_DIR}" ]]; then
  die "--embed-payload requires --embed-mission-dir for a supported Woodbox mission medium"
fi

if [[ -n "${EMBED_PAYLOAD}" && -z "${EMBED_PAYLOAD_META}" ]]; then
  die "--embed-payload requires --embed-payload-meta for a supported Woodbox mission medium"
fi

if [[ -z "${EMBED_PAYLOAD}" && -n "${EMBED_PAYLOAD_META}" ]]; then
  die "--embed-payload-meta requires --embed-payload for a supported Woodbox mission medium"
fi

if [[ -z "${EMBED_PAYLOAD}" && -n "${EMBED_MISSION_DIR}" ]]; then
  die "--embed-mission-dir requires --embed-payload for a supported Woodbox mission medium"
fi

if [[ -n "${EMBED_PAYLOAD}" ]]; then
  log "Embedding mission payload from ${EMBED_PAYLOAD}"
  log "Embedding mission payload metadata from ${EMBED_PAYLOAD_META}"
  log "Embedding mission directory from ${EMBED_MISSION_DIR}"
else
  log "Building installer substrate only (no mission bytes embedded)"
fi

mkdir -p "${ROOT}/deploy" "${ROOT}/artifacts"

: "${UBUNTU_ISO_URL:?UBUNTU_ISO_URL must be set (tools/versions.env)}"
: "${UBUNTU_ISO_SHA256:?UBUNTU_ISO_SHA256 must be set (tools/versions.env)}"

# Identity inputs (override by env)
: "${OURBOX_PRODUCT:=ourbox}"
: "${OURBOX_DEVICE:=woodbox}"
: "${OURBOX_TARGET:=x86}"
: "${OURBOX_SKU:=TOO-OBX-WBX-BASE-JU3XK8}"
: "${OURBOX_VARIANT:=prod}"
: "${OURBOX_VERSION:=dev}"

# Slugs for filenames
OURBOX_SKU_SLUG="$(echo "${OURBOX_SKU}" | tr '[:upper:]' '[:lower:]')"
OURBOX_VARIANT_SLUG="$(echo "${OURBOX_VARIANT}" | tr '[:upper:]' '[:lower:]')"
OURBOX_TARGET_SLUG="$(echo "${OURBOX_TARGET}" | tr '[:upper:]' '[:lower:]')"

if [[ -n "${OUT_ISO_PATH}" ]]; then
  OUT_ISO="$(readlink -m "${OUT_ISO_PATH}")"
else
  OUT_ISO="${ROOT}/deploy/installer-${OURBOX_PRODUCT}-${OURBOX_DEVICE}-${OURBOX_TARGET_SLUG}-${OURBOX_SKU_SLUG}-${OURBOX_VARIANT_SLUG}-${OURBOX_VERSION}.iso"
fi
mkdir -p "$(dirname "${OUT_ISO}")"
OUT_SHA="${OUT_ISO}.sha256"

ISO_STORE="${ROOT}/artifacts/ubuntu"
mkdir -p "${ISO_STORE}"
BASE_ISO_NAME="$(basename "${UBUNTU_ISO_URL}")"
BASE_ISO="${ISO_STORE}/${BASE_ISO_NAME}"

# Download Ubuntu ISO if not cached
if [[ ! -f "${BASE_ISO}" ]]; then
  log "Downloading Ubuntu ISO: ${UBUNTU_ISO_URL}"
  curl -fL --retry 3 --retry-delay 2 -o "${BASE_ISO}" "${UBUNTU_ISO_URL}"
else
  log "Using cached Ubuntu ISO: ${BASE_ISO}"
fi

# Verify SHA256 of base ISO
log "Verifying Ubuntu ISO SHA256"
ACTUAL_SHA256="$(sha256sum "${BASE_ISO}" | awk '{print $1}')"
ACTUAL_SHA256="${ACTUAL_SHA256,,}"
EXPECTED_SHA256="${UBUNTU_ISO_SHA256,,}"
if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
  die "Ubuntu ISO SHA256 mismatch!
  Expected: ${EXPECTED_SHA256}
  Actual:   ${ACTUAL_SHA256}
  ISO:      ${BASE_ISO}
  Update UBUNTU_ISO_SHA256 in tools/versions.env if intentional."
fi
log "SHA256 verified: ${ACTUAL_SHA256}"

BASE_VOLID="$(xorriso -indev "${BASE_ISO}" -pvd_info 2>/dev/null \
  | awk -F': *' '/Volume id/ {print $2; exit}' \
  | sed -E "s/[[:space:]]*$//; s/^'//; s/'$//")"
: "${OURBOX_ISO_VOLID:=${BASE_VOLID}}"

WORKDIR_ROOT="${ROOT}/artifacts/work"
mkdir -p "${WORKDIR_ROOT}"
WORKDIR="$(mktemp -d "${WORKDIR_ROOT}/build-installer-iso.XXXXXX")"
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

: "${OURBOX_HOSTNAME:=ourbox-woodbox}"
: "${OURBOX_USERNAME:=ourbox}"
: "${OURBOX_PASSWORD_HASH:=}"
export OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH

# shellcheck disable=SC2016  # single-quoted intentionally — envsubst needs literal $VAR strings
SEED_SUBST_VARS='${OURBOX_HOSTNAME} ${OURBOX_USERNAME} ${OURBOX_PASSWORD_HASH} ${OURBOX_PRODUCT} ${OURBOX_DEVICE} ${OURBOX_TARGET} ${OURBOX_SKU} ${OURBOX_VARIANT} ${OURBOX_VERSION}'
envsubst "${SEED_SUBST_VARS}" < "${ROOT}/installer/autoinstall/user-data.tpl" > "${ISO_DIR}/nocloud/user-data"
bash "${ROOT}/tools/validate-installer-seed.sh" --rendered "${ISO_DIR}/nocloud/user-data"
envsubst "${SEED_SUBST_VARS}" < "${ROOT}/installer/autoinstall/meta-data.tpl"  > "${ISO_DIR}/nocloud/meta-data"
cp -f "${ISO_DIR}/nocloud/user-data" "${ISO_DIR}/autoinstall.yaml"

# Pass-1 substitution of runtime autoinstall template.
mkdir -p "${ISO_DIR}/ourbox"
# shellcheck disable=SC2016  # single-quoted intentionally — envsubst needs literal $VAR strings
RUNTIME_TPL_SUBST='${OURBOX_PRODUCT} ${OURBOX_DEVICE} ${OURBOX_TARGET} ${OURBOX_SKU} ${OURBOX_VARIANT} ${OURBOX_VERSION}'
envsubst "${RUNTIME_TPL_SUBST}" \
  < "${ROOT}/installer/autoinstall/autoinstall.tpl" \
  > "${ISO_DIR}/ourbox/autoinstall.tpl"

# Stage preinstaller tooling
log "Staging OurBox pre-installer assets"
mkdir -p "${ISO_DIR}/ourbox/tools"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" \
  "${ISO_DIR}/ourbox/tools/ourbox-preinstall"
install -m 0644 "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall.service" \
  "${ISO_DIR}/ourbox/tools/ourbox-preinstall.service"
install -m 0644 "${ROOT}/tools/lib.sh" \
  "${ISO_DIR}/ourbox/tools/lib.sh"
install -m 0755 "${ROOT}/tools/strict-kv-metadata.py" \
  "${ISO_DIR}/ourbox/tools/strict-kv-metadata.py"
install -m 0644 "${ROOT}/tools/installer-ssh-helper.sh" \
  "${ISO_DIR}/ourbox/tools/installer-ssh-helper.sh"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/format-data-disk.sh" \
  "${ISO_DIR}/ourbox/tools/format-data-disk.sh"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/ourbox-installer-monitor.py" \
  "${ISO_DIR}/ourbox/tools/ourbox-installer-monitor.py"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/ourbox-installer-ssh-bootstrap.sh" \
  "${ISO_DIR}/ourbox/tools/ourbox-installer-ssh-bootstrap.sh"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/render-target-netplan.py" \
  "${ISO_DIR}/ourbox/tools/render-target-netplan.py"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/install-offline-target-packages.sh" \
  "${ISO_DIR}/ourbox/tools/install-offline-target-packages.sh"

log "Staging offline target package repo"
mkdir -p "${ISO_DIR}/ourbox/apt"
apt_repo_cmd=(
  "${ROOT}/tools/prepare-installer-target-apt-repo.sh"
  --output-dir "${ISO_DIR}/ourbox/apt"
)
if [[ -n "${OURBOX_INSTALLER_TARGET_APT_REPO_SOURCE_DIR}" ]]; then
  apt_repo_cmd+=(--source-deb-dir "${OURBOX_INSTALLER_TARGET_APT_REPO_SOURCE_DIR}")
fi
for pkg in ${OURBOX_INSTALLER_TARGET_PACKAGES}; do
  apt_repo_cmd+=(--package "${pkg}")
done
for pkg in ${OURBOX_INSTALLER_TARGET_APT_REPO_EXTRA_PACKAGES}; do
  apt_repo_cmd+=(--repo-package "${pkg}")
done
"${apt_repo_cmd[@]}"

# Stage installer defaults (installer identity, SSH posture, and monitor settings)
log "Staging installer defaults"
mkdir -p "${ISO_DIR}/ourbox/installer"

OURBOX_RECIPE_GIT_HASH="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"

cat > "${ISO_DIR}/ourbox/installer/defaults.env" <<EOT
# OurBox Woodbox installer local defaults.
# This file carries only installer-local posture. Artifact selection and staging
# happen on the trusted host before mission media is composed.
INSTALLER_ID=woodbox
INSTALLER_VERSION=${OURBOX_VERSION}
INSTALLER_GIT_HASH=${OURBOX_RECIPE_GIT_HASH}
OURBOX_VARIANT='${OURBOX_VARIANT}'
OURBOX_INSTALLER_SSH_MODE='${OURBOX_INSTALLER_SSH_MODE}'
OURBOX_INSTALLER_SSH_USER='${OURBOX_INSTALLER_SSH_USER}'
# Blank password hash means the live installer generates a one-time password
# at boot and shows it only on the attached console.
OURBOX_INSTALLER_SSH_PASSWORD_HASH='${OURBOX_INSTALLER_SSH_PASSWORD_HASH}'
OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS='${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}'
OURBOX_INSTALLER_SSH_ALLOW_ROOT='${OURBOX_INSTALLER_SSH_ALLOW_ROOT}'
OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY='${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}'
OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR='${OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR}'
OURBOX_INSTALLER_MONITOR_BROADCAST_PORT='${OURBOX_INSTALLER_MONITOR_BROADCAST_PORT}'
EOT

# If mission media is being composed, stage the selected OS payload.
if [[ -n "${EMBED_PAYLOAD}" ]]; then
  log "Embedding OS payload: $(basename "${EMBED_PAYLOAD}")"
  mkdir -p "${ISO_DIR}/ourbox/payload"
  cp "${EMBED_PAYLOAD}" "${ISO_DIR}/ourbox/payload/os-payload.tar.gz"
  sha256sum "${ISO_DIR}/ourbox/payload/os-payload.tar.gz" \
    | awk '{print $1}' > "${ISO_DIR}/ourbox/payload/os-payload.tar.gz.sha256"
  cp "${EMBED_PAYLOAD_META}" "${ISO_DIR}/ourbox/payload/payload.meta.env"
  log "  payload staged into mission media"
fi

if [[ -n "${EMBED_MISSION_DIR}" ]]; then
  log "Embedding mission directory"
  mkdir -p "${ISO_DIR}/ourbox/mission"
  rsync -a "${EMBED_MISSION_DIR}/" "${ISO_DIR}/ourbox/mission/"
  [[ -f "${ISO_DIR}/ourbox/mission/mission-manifest.json" ]] \
    || die "mission-manifest.json missing after mission embed"
  log "  mission metadata staged into mission media"
fi

# Patch bootloader configs to force autoinstall
AUTOINSTALL_ARG='autoinstall cloud-config-url=/dev/null ds=nocloud\\;s=file:///cdrom/nocloud/'
if [[ "${OURBOX_INSTALLER_SMOKE_CONSOLE}" == "1" ]]; then
  AUTOINSTALL_ARG="${AUTOINSTALL_ARG} console=ttyS0,115200n8 systemd.journald.forward_to_console=1"
fi
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
if [[ "${OURBOX_INSTALLER_SMOKE_CONSOLE}" == "1" ]] && ! grep -Rqs 'console=ttyS0,115200n8' "${ISO_DIR}/boot/grub"; then
  die "serial console kernel args not found in ISO boot configs after patching"
fi

[[ -s "${ISO_DIR}/nocloud/user-data" ]] || die "missing nocloud/user-data in ISO staging tree"
[[ -s "${ISO_DIR}/nocloud/meta-data" ]] || die "missing nocloud/meta-data in ISO staging tree"
[[ -s "${ISO_DIR}/autoinstall.yaml" ]] || die "missing autoinstall.yaml in ISO staging tree"

VOLID="${OURBOX_ISO_VOLID}"

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
if [[ -n "${EMBED_MISSION_DIR}" ]]; then
  log "Mode: mission media (payload + mission embedded)"
else
  log "Mode: installer substrate only (not a standalone install path)"
fi
