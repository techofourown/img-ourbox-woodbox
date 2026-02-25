#!/usr/bin/env bash
# format-data-disk.sh — run from autoinstall late-commands (live env, not chroot)
#
# Formats the operator-selected disk as the OurBox DATA disk:
#   GPT + single ext4 partition labeled OURBOX_DATA.
#
# Usage: format-data-disk.sh <disk>   e.g. format-data-disk.sh /dev/sda
#
# Skips entirely if a disk with label OURBOX_DATA already exists.
# Safe to run multiple times (idempotent via blkid check).

set -euo pipefail

log() { echo "[format-data-disk] $*"; }

DATA_DISK="${1:?Usage: format-data-disk.sh <disk-device>}"

# Already exists — nothing to do.
if blkid -L OURBOX_DATA >/dev/null 2>&1; then
  log "OURBOX_DATA label already present on $(blkid -L OURBOX_DATA) — skipping"
  exit 0
fi

# Safety: refuse to format the system disk.
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

DATA_DISK_REAL="$(readlink -f "${DATA_DISK}")"
if [[ -n "${SYSTEM_DISK}" && "${DATA_DISK_REAL}" == "${SYSTEM_DISK}" ]]; then
  log "ERROR: ${DATA_DISK} resolves to the system disk ${SYSTEM_DISK} — aborting"
  exit 1
fi

DATA_SIZE_HUMAN="$(lsblk -dn -o SIZE "${DATA_DISK}" 2>/dev/null | tr -d '[:space:]')"
log "Formatting DATA disk: ${DATA_DISK} (${DATA_SIZE_HUMAN})"

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
