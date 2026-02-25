#!/usr/bin/env bash
# format-data-disk.sh — run from autoinstall late-commands (live env, not chroot)
#
# Finds the largest non-system, non-USB SATA/SAS disk and formats it as the
# OurBox DATA disk (GPT + single ext4 partition labeled OURBOX_DATA).
#
# Skips entirely if a disk with label OURBOX_DATA already exists.
# Safe to run multiple times (idempotent via blkid check).

set -euo pipefail

log() { echo "[format-data-disk] $*"; }

# Already exists — nothing to do.
if blkid -L OURBOX_DATA >/dev/null 2>&1; then
  log "OURBOX_DATA label already present on $(blkid -L OURBOX_DATA) — skipping"
  exit 0
fi

# Identify the system (boot) disk — the one / is installed on.
# In the late-command context the target is mounted at /target;
# the live root is the installer USB.
SYSTEM_DISK=""
ROOT_DEV="$(findmnt -nr -o SOURCE /target 2>/dev/null || true)"
if [[ -n "${ROOT_DEV}" ]]; then
  ROOT_REAL="$(readlink -f "${ROOT_DEV}" 2>/dev/null || echo "${ROOT_DEV}")"
  PKNAME="$(lsblk -no PKNAME "${ROOT_REAL}" 2>/dev/null || true)"
  if [[ -n "${PKNAME}" ]]; then
    SYSTEM_DISK="/dev/${PKNAME}"
  else
    SYSTEM_DISK="${ROOT_REAL}"
  fi
fi
log "System disk (will be excluded): ${SYSTEM_DISK:-unknown}"

# Identify the installer USB (the live media — the disk / of the live env is on).
INSTALLER_DISK=""
LIVE_ROOT_DEV="$(findmnt -nr -o SOURCE / 2>/dev/null || true)"
if [[ -n "${LIVE_ROOT_DEV}" ]]; then
  LIVE_REAL="$(readlink -f "${LIVE_ROOT_DEV}" 2>/dev/null || echo "${LIVE_ROOT_DEV}")"
  LIVE_PKNAME="$(lsblk -no PKNAME "${LIVE_REAL}" 2>/dev/null || true)"
  if [[ -n "${LIVE_PKNAME}" ]]; then
    INSTALLER_DISK="/dev/${LIVE_PKNAME}"
  else
    INSTALLER_DISK="${LIVE_REAL}"
  fi
fi
log "Installer disk (will be excluded): ${INSTALLER_DISK:-unknown}"

# Find DATA disk candidate: non-removable, non-system, non-installer, prefer SATA.
# Takes the largest remaining disk — for Woodbox that's the 6TB SATA.
DATA_DISK=""
DATA_SIZE=0

while read -r name; do
  disk="/dev/${name}"
  [[ "${disk}" != "${SYSTEM_DISK}" ]]    || continue
  [[ "${disk}" != "${INSTALLER_DISK}" ]] || continue

  rm="$(lsblk -dn -o RM "${disk}" 2>/dev/null | tr -d '[:space:]')"
  [[ "${rm}" != "1" ]] || continue  # skip removable (USB sticks)

  size_bytes="$(lsblk -dn -o SIZE --bytes "${disk}" 2>/dev/null | tr -d '[:space:]')"
  [[ -n "${size_bytes}" ]] || continue

  if (( size_bytes > DATA_SIZE )); then
    DATA_SIZE="${size_bytes}"
    DATA_DISK="${disk}"
  fi
done < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}')

if [[ -z "${DATA_DISK}" ]]; then
  log "WARNING: no DATA disk candidate found — skipping format"
  exit 0
fi

DATA_SIZE_HUMAN="$(lsblk -dn -o SIZE "${DATA_DISK}" 2>/dev/null | tr -d '[:space:]')"
log "Selected DATA disk: ${DATA_DISK} (${DATA_SIZE_HUMAN})"

# Wipe existing signatures and partition table.
log "Wiping ${DATA_DISK}"
wipefs -a "${DATA_DISK}"
dd if=/dev/zero of="${DATA_DISK}" bs=1M count=32 conv=fsync 2>/dev/null || true

# Create GPT + single partition spanning the disk.
log "Partitioning ${DATA_DISK}"
parted -s "${DATA_DISK}" mklabel gpt
parted -s "${DATA_DISK}" mkpart primary ext4 1MiB 100%

# Let the kernel re-read the partition table.
partprobe "${DATA_DISK}" 2>/dev/null || true
sleep 2

# Find the new partition (first partition).
DATA_PART=""
if [[ "${DATA_DISK}" == *nvme* ]]; then
  DATA_PART="${DATA_DISK}p1"
else
  DATA_PART="${DATA_DISK}1"
fi

log "Formatting ${DATA_PART} as ext4 with label OURBOX_DATA"
mkfs.ext4 -F -L OURBOX_DATA "${DATA_PART}"

# Verify the label is visible.
sleep 1
if blkid -L OURBOX_DATA >/dev/null 2>&1; then
  log "SUCCESS: OURBOX_DATA label confirmed on $(blkid -L OURBOX_DATA)"
else
  log "WARNING: label not immediately visible — udev may need a moment"
fi
