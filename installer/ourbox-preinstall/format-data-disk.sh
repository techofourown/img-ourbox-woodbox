#!/usr/bin/env bash
# format-data-disk.sh — destructive DATA-disk preparation from pre-installer
#
# Runs after the operator confirms INSTALL in ourbox-preinstall.
#
# Destroys old consumers on the selected DATA disk (mounts, swap, dm-crypt,
# LVM, mdraid, stale signatures), then recreates the disk as:
#   GPT + single ext4 partition labeled OURBOX_DATA.
#
# Usage: format-data-disk.sh <data-disk> <os-disk>

set -euo pipefail

log() { echo "[format-data-disk] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: required command not found: $1"
    exit 1
  }
}

need_cmd lsblk
need_cmd readlink
need_cmd findmnt
need_cmd awk
need_cmd sort
need_cmd tac
need_cmd wipefs
need_cmd dd
need_cmd parted
need_cmd mkfs.ext4
need_cmd blkid
need_cmd mount
need_cmd umount
need_cmd partprobe
need_cmd udevadm

DATA_DISK="${1:?Usage: format-data-disk.sh <data-disk> <os-disk>}"
OS_DISK="${2:?Usage: format-data-disk.sh <data-disk> <os-disk>}"

DATA_DISK_REAL="$(readlink -f "${DATA_DISK}")"
OS_DISK_REAL="$(readlink -f "${OS_DISK}")"

if [[ "${DATA_DISK_REAL}" == "${OS_DISK_REAL}" ]]; then
  log "ERROR: DATA disk resolves to the OS disk (${OS_DISK_REAL}) — aborting"
  exit 1
fi

DATA_TYPE="$(lsblk -dn -o TYPE "${DATA_DISK_REAL}" 2>/dev/null | tr -d '[:space:]')"
OS_TYPE="$(lsblk -dn -o TYPE "${OS_DISK_REAL}" 2>/dev/null | tr -d '[:space:]')"
[[ "${DATA_TYPE}" == "disk" ]] || { log "ERROR: DATA target is not a whole disk: ${DATA_DISK_REAL} (${DATA_TYPE:-unknown})"; exit 1; }
[[ "${OS_TYPE}" == "disk" ]] || { log "ERROR: OS target is not a whole disk: ${OS_DISK_REAL} (${OS_TYPE:-unknown})"; exit 1; }

INSTALLER_SRC="$(findmnt -nr -o SOURCE / 2>/dev/null || true)"
if [[ -n "${INSTALLER_SRC}" ]]; then
  INSTALLER_REAL="$(readlink -f "${INSTALLER_SRC}" 2>/dev/null || echo "${INSTALLER_SRC}")"
  INSTALLER_PARENT="$(lsblk -no PKNAME "${INSTALLER_REAL}" 2>/dev/null || true)"
  if [[ -n "${INSTALLER_PARENT}" ]]; then
    INSTALLER_DISK="/dev/${INSTALLER_PARENT}"
  else
    INSTALLER_DISK="${INSTALLER_REAL}"
  fi
  if [[ "${DATA_DISK_REAL}" == "${INSTALLER_DISK}" ]]; then
    log "ERROR: DATA disk resolves to installer medium (${INSTALLER_DISK}) — aborting"
    exit 1
  fi
fi

log "OS disk (excluded): ${OS_DISK_REAL}"
log "DATA disk (will be destroyed): ${DATA_DISK_REAL}"
log "Pre-teardown block trees:"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK_REAL}" || true
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${OS_DISK_REAL}" || true

mapfile -t TREE_DEVICES < <(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}" | awk '{print $1}')
(( ${#TREE_DEVICES[@]} > 0 )) || { log "ERROR: failed to enumerate DATA disk tree"; exit 1; }

mapfile -t TREE_DESC_REVERSED < <(printf '%s\n' "${TREE_DEVICES[@]}" | awk -v disk="${DATA_DISK_REAL}" '$1!=disk' | tac)

# 1) Unmount filesystems from this tree (deepest first).
log "Unmounting filesystems on DATA disk tree (if any)"
mapfile -t MOUNTS < <(
  for dev in "${TREE_DEVICES[@]}"; do
    findmnt -rn -S "$dev" -o TARGET 2>/dev/null || true
  done | awk 'NF>0' | awk '{print length($0) "|" $0}' | sort -nr | cut -d'|' -f2-
)
for mp in "${MOUNTS[@]}"; do
  log "Unmounting ${mp}"
  umount "${mp}" || umount -l "${mp}" || true
done

# 2) Disable swap on this tree.
log "Disabling swap on DATA disk tree (if any)"
if [[ -r /proc/swaps ]]; then
  while read -r swapdev _; do
    [[ "${swapdev}" == Filename || -z "${swapdev}" ]] && continue
    for dev in "${TREE_DEVICES[@]}"; do
      if [[ "${swapdev}" == "${dev}" ]]; then
        log "swapoff ${swapdev}"
        swapoff "${swapdev}" || true
      fi
    done
  done < /proc/swaps
fi

# 3) LVM deactivate pass scoped to PVs on DATA disk tree.
if command -v pvs >/dev/null 2>&1 && command -v vgchange >/dev/null 2>&1; then
  log "Deactivating LVM VGs backed by DATA disk PVs (if any)"
  mapfile -t DATA_VGS < <(
    pvs --noheadings --separator '|' -o pv_name,vg_name 2>/dev/null | \
      awk -F'|' -v disk="${DATA_DISK_REAL}" '{gsub(/^ +| +$/, "", $1); gsub(/^ +| +$/, "", $2); if($1 ~ ("^" disk "p?[0-9]+$")) print $2}' | sort -u
  )
  for vg in "${DATA_VGS[@]}"; do
    [[ -n "${vg}" ]] || continue
    log "vgchange -an ${vg}"
    vgchange -an "${vg}" || true
  done
fi

# 4) Tear down dm/crypt/lvm/md descendants (leaf-first).
for dev in "${TREE_DESC_REVERSED[@]}"; do
  dtype="$(lsblk -dn -o TYPE "$dev" 2>/dev/null | tr -d '[:space:]' || true)"
  base="$(basename "$dev")"

  case "${dtype}" in
    crypt)
      log "Closing crypt mapping ${dev}"
      if command -v cryptsetup >/dev/null 2>&1; then
        cryptsetup close "${base}" || true
      fi
      if command -v dmsetup >/dev/null 2>&1; then
        dmsetup remove -f "${dev}" || true
      fi
      ;;
    lvm)
      log "Removing LVM mapper ${dev}"
      if command -v lvchange >/dev/null 2>&1; then
        lvchange -an "${dev}" || true
      fi
      if command -v dmsetup >/dev/null 2>&1; then
        dmsetup remove -f "${dev}" || true
      fi
      ;;
    raid*|md)
      if command -v mdadm >/dev/null 2>&1; then
        log "Stopping md device ${dev}"
        mdadm --stop "${dev}" || true
      fi
      ;;
  esac

  if [[ "${dev}" == /dev/mapper/* ]] && command -v dmsetup >/dev/null 2>&1; then
    log "Removing device-mapper node ${dev}"
    dmsetup remove -f "${dev}" || true
  fi
done

# 5) Verify holders are gone for disk and its direct partitions.
log "Checking for remaining holders"
holders_found=0
while read -r dev devtype; do
  [[ "${devtype}" == "disk" || "${devtype}" == "part" ]] || continue
  holders_dir="/sys/class/block/$(basename "${dev}")/holders"
  if [[ -d "${holders_dir}" ]]; then
    mapfile -t holder_entries < <(ls -1 "${holders_dir}" 2>/dev/null || true)
    if (( ${#holder_entries[@]} > 0 )); then
      holders_found=1
      log "ERROR: holders remain on ${dev}: ${holder_entries[*]}"
    fi
  fi
done < <(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}")

if (( holders_found != 0 )); then
  log "ERROR: refusing to wipe while holders are still attached"
  lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK_REAL}" || true
  exit 1
fi

# 6) Wipe signatures on descendants, then whole disk.
log "Wiping signatures on descendants"
for dev in "${TREE_DESC_REVERSED[@]}"; do
  [[ -b "${dev}" ]] || continue
  wipefs -a -f "${dev}" || true
done

log "Wiping signatures on DATA disk ${DATA_DISK_REAL}"
wipefs -a -f "${DATA_DISK_REAL}"

# 7) Zero beginning and end metadata areas.
log "Zeroing first 32MiB"
dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M count=32 conv=fsync,notrunc status=none || true

if command -v blockdev >/dev/null 2>&1; then
  disk_bytes="$(blockdev --getsize64 "${DATA_DISK_REAL}" 2>/dev/null || echo 0)"
  if [[ "${disk_bytes}" =~ ^[0-9]+$ ]] && (( disk_bytes > 0 )); then
    disk_mib=$((disk_bytes / 1024 / 1024))
    if (( disk_mib > 32 )); then
      seek_mib=$((disk_mib - 32))
      log "Zeroing last 32MiB (seek=${seek_mib}MiB)"
      dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M seek="${seek_mib}" count=32 conv=fsync,notrunc status=none || true
    fi
  fi
fi

# 8) Create GPT + one ext4 partition.
log "Creating GPT + single partition"
partprobe "${DATA_DISK_REAL}" 2>/dev/null || true
udevadm settle || true
parted -s "${DATA_DISK_REAL}" mklabel gpt
parted -s "${DATA_DISK_REAL}" mkpart primary ext4 1MiB 100%
partprobe "${DATA_DISK_REAL}" 2>/dev/null || true
udevadm settle || true
sleep 1

DATA_PART="$(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}" | awk '$2=="part" {print $1; exit}')"
[[ -n "${DATA_PART}" ]] || { log "ERROR: failed to discover DATA partition after partitioning"; exit 1; }

log "Formatting ${DATA_PART} as ext4 label OURBOX_DATA"
mkfs.ext4 -F -L OURBOX_DATA "${DATA_PART}"
udevadm settle || true

LABEL_DEV="$(blkid -L OURBOX_DATA 2>/dev/null || true)"
if [[ -z "${LABEL_DEV}" ]]; then
  log "ERROR: label OURBOX_DATA not found after format"
  exit 1
fi

# 9) Smoke-mount and unmount.
smoke_dir="/tmp/ourbox-data-smoke.$$"
mkdir -p "${smoke_dir}"
cleanup() {
  umount "${smoke_dir}" >/dev/null 2>&1 || true
  rmdir "${smoke_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

log "Smoke-mounting LABEL=OURBOX_DATA"
mount LABEL=OURBOX_DATA "${smoke_dir}"
umount "${smoke_dir}"
rmdir "${smoke_dir}"
trap - EXIT

log "SUCCESS: DATA disk prepared and mountable at ${LABEL_DEV}"
