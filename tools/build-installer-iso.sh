#!/usr/bin/env bash
# Build the OurBox Woodbox installer ISO.
#
# The installer ISO is a thin installer: it contains the installer tooling,
# ORAS binary (for artifact pulls at install time), and local fallback defaults.
# It does NOT embed the full OS payload by default — the payload is resolved
# and pulled at install time by ourbox-preinstall.
#
# For fully local/offline builds (--build-local mode), a local OS payload
# tarball can be baked into the ISO for offline operation. In that case the
# preinstaller detects the local payload and uses it directly, applying the
# same verification flow.
#
# Flags:
#   --embed-payload PATH  Embed the specified OS payload tar.gz into the ISO
#                         (for offline/local-build operation).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/config.env" ] && source "${ROOT}/tools/config.env"
# shellcheck disable=SC1091
# Official pinned inputs take precedence over versions.env defaults.
[ -f "${ROOT}/release/official-inputs.env" ] && source "${ROOT}/release/official-inputs.env"

need_cmd curl
need_cmd xorriso
need_cmd 7z
need_cmd rsync
need_cmd sha256sum
need_cmd envsubst
need_cmd sed
need_cmd awk
need_cmd bash

EMBED_PAYLOAD=""
# OS_CHANNEL controls the default channel baked into the installer defaults.
# For nightly installer builds, set OS_CHANNEL=nightly so that the baked
# fallback points at the nightly OS lane rather than stable.
: "${OS_CHANNEL:=stable}"
: "${OURBOX_VARIANT:=prod}"
: "${DEFAULT_INSTALLER_SSH_MODE:=both}"
: "${OURBOX_INSTALLER_SSH_MODE:=${DEFAULT_INSTALLER_SSH_MODE}}"
: "${OURBOX_INSTALLER_SSH_USER:=ourbox-installer}"
: "${OURBOX_INSTALLER_SSH_PASSWORD_HASH:=}"
: "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS:=}"
: "${OURBOX_INSTALLER_SSH_ALLOW_ROOT:=0}"
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
    --os-channel)
      [[ $# -ge 2 ]] || die "--os-channel requires a value"
      OS_CHANNEL="$2"
      shift 2
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "${OURBOX_INSTALLER_SSH_MODE}" in
  off|key|password|both) ;;
  *) die "invalid OURBOX_INSTALLER_SSH_MODE: ${OURBOX_INSTALLER_SSH_MODE}" ;;
esac

case "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" in
  0|1) ;;
  *) die "invalid OURBOX_INSTALLER_SSH_ALLOW_ROOT: ${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" ;;
esac

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

if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "key" && -z "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
  die "OURBOX_INSTALLER_SSH_MODE=key requires OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS"
fi

if [[ -n "${EMBED_PAYLOAD}" ]]; then
  [[ -f "${EMBED_PAYLOAD}" ]] || die "embedded payload not found: ${EMBED_PAYLOAD}"
  log "Local-build mode: embedding OS payload from ${EMBED_PAYLOAD}"
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

OUT_ISO="${ROOT}/deploy/installer-${OURBOX_PRODUCT}-${OURBOX_DEVICE}-${OURBOX_TARGET_SLUG}-${OURBOX_SKU_SLUG}-${OURBOX_VARIANT_SLUG}-${OURBOX_VERSION}.iso"
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
  Update UBUNTU_ISO_SHA256 in tools/versions.env or release/official-inputs.env if intentional."
fi
log "SHA256 verified: ${ACTUAL_SHA256}"

BASE_VOLID="$(xorriso -indev "${BASE_ISO}" -pvd_info 2>/dev/null \
  | awk -F': *' '/Volume id/ {print $2; exit}' \
  | sed -E "s/[[:space:]]*$//; s/^'//; s/'$//")"
: "${OURBOX_ISO_VOLID:=${BASE_VOLID}}"

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
install -m 0755 "${ROOT}/installer/ourbox-preinstall/format-data-disk.sh" \
  "${ISO_DIR}/ourbox/tools/format-data-disk.sh"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/ourbox-installer-monitor.py" \
  "${ISO_DIR}/ourbox/tools/ourbox-installer-monitor.py"
install -m 0755 "${ROOT}/installer/ourbox-preinstall/ourbox-installer-ssh-bootstrap.sh" \
  "${ISO_DIR}/ourbox/tools/ourbox-installer-ssh-bootstrap.sh"

# Bundle the linux-amd64 ORAS binary for use at install time (offline-capable).
# Always download the target-arch binary explicitly — never copy the host oras
# binary, which may be arm64 if building on a non-x86 host.
log "Bundling linux-amd64 ORAS binary into installer"
: "${ORAS_VERSION:=1.3.0}"
ORAS_BASE_URL="https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}"
ORAS_TARBALL="oras_${ORAS_VERSION}_linux_amd64.tar.gz"
ORAS_TMP="${WORKDIR}/oras-download"
mkdir -p "${ORAS_TMP}"
log "  Downloading ORAS ${ORAS_VERSION} linux-amd64"
curl -fsSL --retry 3 --retry-delay 2 \
  -o "${ORAS_TMP}/${ORAS_TARBALL}" \
  "${ORAS_BASE_URL}/${ORAS_TARBALL}"
log "  Verifying ORAS ${ORAS_VERSION} checksum"
curl -fsSL --retry 3 --retry-delay 2 \
  -o "${ORAS_TMP}/checksums.txt" \
  "${ORAS_BASE_URL}/oras_${ORAS_VERSION}_checksums.txt"
ORAS_EXPECTED_SHA="$(grep " ${ORAS_TARBALL}\$" "${ORAS_TMP}/checksums.txt" | awk '{print $1}')"
[[ -n "${ORAS_EXPECTED_SHA}" ]] || die "oras checksum not found in checksums.txt for ${ORAS_TARBALL}"
ORAS_ACTUAL_SHA="$(sha256sum "${ORAS_TMP}/${ORAS_TARBALL}" | awk '{print $1}')"
if [[ "${ORAS_EXPECTED_SHA}" != "${ORAS_ACTUAL_SHA}" ]]; then
  die "ORAS binary checksum mismatch
  Expected: ${ORAS_EXPECTED_SHA}
  Actual:   ${ORAS_ACTUAL_SHA}
  File:     ${ORAS_TMP}/${ORAS_TARBALL}"
fi
log "  ORAS checksum verified: ${ORAS_ACTUAL_SHA}"
tar -xzf "${ORAS_TMP}/${ORAS_TARBALL}" -C "${ORAS_TMP}" oras
[[ -f "${ORAS_TMP}/oras" ]] || die "oras binary not found after extraction"
install -m 0755 "${ORAS_TMP}/oras" "${ISO_DIR}/ourbox/tools/oras"
log "  oras: ${ORAS_VERSION} linux-amd64 bundled and verified"

# Stage installer defaults (baked fallback for offline operation)
log "Staging installer defaults"
mkdir -p "${ISO_DIR}/ourbox/installer"

OURBOX_RECIPE_GIT_HASH="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"

# Build the baked defaults.env for the installer.
# This is the local fallback loaded by ourbox-preinstall when the remote
# install-defaults bundle cannot be fetched (offline/degraded-network mode).
# OS_CHANNEL must reflect the build context: stable for release, nightly for
# nightly builds (so the baked fallback points at the correct OS lane).
#
# INSTALL_DEFAULTS_REF resolution:
#   1. INSTALL_DEFAULTS_REF env var (set in release/official-inputs.env or by caller)
#   2. contracts/install-defaults.ref legacy fallback
#   3. empty (no remote defaults bundle configured)
INSTALL_DEFAULTS_REF_BAKED="${INSTALL_DEFAULTS_REF:-}"
if [[ -z "${INSTALL_DEFAULTS_REF_BAKED}" ]]; then
  _idr_file="${ROOT}/contracts/install-defaults.ref"
  if [[ -f "${_idr_file}" ]]; then
    # Read first non-comment non-blank line
    _idr_val="$(grep -v '^[[:space:]]*#' "${_idr_file}" | grep -v '^[[:space:]]*$' | head -n1 || true)"
    INSTALL_DEFAULTS_REF_BAKED="${_idr_val:-}"
    unset _idr_val
  fi
  unset _idr_file
fi
cat > "${ISO_DIR}/ourbox/installer/defaults.env" <<EOT
# OurBox Woodbox installer baked defaults.
# Remote install-defaults (INSTALL_DEFAULTS_REF) override these at install time
# if the registry is reachable. This file is the offline/no-network fallback.
INSTALLER_ID=woodbox
OS_REPO=${OFFICIAL_OS_REPO:-ghcr.io/techofourown/ourbox-woodbox-os}
OS_TARGET=${OURBOX_TARGET}
OS_CHANNEL=${OS_CHANNEL}
OS_DEFAULT_REF=
OS_CATALOG_ENABLED=1
OS_CATALOG_TAG=${OURBOX_TARGET}-catalog
INSTALL_DEFAULTS_REF=${INSTALL_DEFAULTS_REF_BAKED}
OS_ORAS_VERSION=${ORAS_VERSION:-1.3.0}
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
OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR='${OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR}'
OURBOX_INSTALLER_MONITOR_BROADCAST_PORT='${OURBOX_INSTALLER_MONITOR_BROADCAST_PORT}'
EOT

# If an OS payload is being embedded (local/offline build), stage it
if [[ -n "${EMBED_PAYLOAD}" ]]; then
  log "Embedding OS payload: $(basename "${EMBED_PAYLOAD}")"
  mkdir -p "${ISO_DIR}/ourbox/payload"
  cp "${EMBED_PAYLOAD}" "${ISO_DIR}/ourbox/payload/os-payload.tar.gz"
  sha256sum "${ISO_DIR}/ourbox/payload/os-payload.tar.gz" \
    | awk '{print $1}' > "${ISO_DIR}/ourbox/payload/os-payload.tar.gz.sha256"
  # Copy meta.env if it exists alongside the payload
  PAYLOAD_META="${EMBED_PAYLOAD%.tar.gz}.meta.env"
  if [[ -f "${PAYLOAD_META}" ]]; then
    cp "${PAYLOAD_META}" "${ISO_DIR}/ourbox/payload/payload.meta.env"
  fi
  log "  payload baked into ISO for offline operation"
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
if [[ -n "${EMBED_PAYLOAD}" ]]; then
  log "Mode: local-build (OS payload embedded)"
else
  log "Mode: thin installer (OS payload resolved at install time)"
fi
