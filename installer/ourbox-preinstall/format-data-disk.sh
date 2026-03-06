#!/usr/bin/env bash
# format-data-disk.sh — destructive DATA disk preparation from pre-installer
#
# Runs in the live installer environment after final INSTALL confirmation.
# Destroys all storage stacks on the selected DATA disk (LVM/dm-crypt/md/swap,
# old filesystems/signatures), then creates:
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

DATA_DISK="${1:?Usage: format-data-disk.sh <data-disk> <os-disk>}"
OS_DISK="${2:?Usage: format-data-disk.sh <data-disk> <os-disk>}"

need_cmd lsblk
need_cmd readlink
need_cmd wipefs
need_cmd dd
need_cmd partprobe
need_cmd parted
need_cmd mkfs.ext4
need_cmd blkid
need_cmd blockdev
need_cmd mount
need_cmd umount
need_cmd awk
need_cmd udevadm

DATA_DISK_REAL="$(readlink -f "${DATA_DISK}")"
OS_DISK_REAL="$(readlink -f "${OS_DISK}")"

if [[ "${DATA_DISK_REAL}" == "${OS_DISK_REAL}" ]]; then
  log "ERROR: DATA disk resolves to the OS disk (${OS_DISK_REAL}) — aborting"
  exit 1
fi

if [[ "$(lsblk -dn -o TYPE "${DATA_DISK_REAL}" 2>/dev/null || true)" != "disk" ]]; then
  log "ERROR: DATA target is not a whole disk: ${DATA_DISK_REAL}"
  exit 1
fi
if [[ "$(lsblk -dn -o TYPE "${OS_DISK_REAL}" 2>/dev/null || true)" != "disk" ]]; then
  log "ERROR: OS target is not a whole disk: ${OS_DISK_REAL}"
  exit 1
fi

log "OS disk (protected): ${OS_DISK_REAL}"
log "DATA disk (will be destroyed): ${DATA_DISK_REAL}"
log "Block tree snapshot (DATA disk):"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK_REAL}" || true
log "Block tree snapshot (OS disk):"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${OS_DISK_REAL}" || true

mapfile -t TREE_LINES < <(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}")
mapfile -t TREE_DEVS < <(printf '%s\n' "${TREE_LINES[@]}" | awk '{print $1}')
mapfile -t TREE_DEVS_REV < <(printf '%s\n' "${TREE_DEVS[@]}" | tac)

is_on_data_tree() {
  local dev="$1"
  local t
  for t in "${TREE_DEVS[@]}"; do
    [[ "${dev}" == "${t}" ]] && return 0
  done
  return 1
}

log "Unmounting filesystems on DATA disk tree (deepest first)"
for dev in "${TREE_DEVS_REV[@]}"; do
  while read -r mp; do
    [[ -n "${mp}" ]] || continue
    log "Unmounting ${dev} from ${mp}"
    umount "${mp}" || umount -l "${mp}" || true
  done < <(findmnt -rn -S "${dev}" -o TARGET 2>/dev/null || true)
done

log "Disabling active swap on DATA disk tree"
while read -r swap_dev _; do
  [[ -n "${swap_dev}" ]] || continue
  is_on_data_tree "${swap_dev}" || continue
  log "swapoff ${swap_dev}"
  swapoff "${swap_dev}" || true
done < <(tail -n +2 /proc/swaps 2>/dev/null || true)

log "Best-effort LVM deactivation scoped to DATA disk PVs"
if command -v pvs >/dev/null 2>&1; then
  declare -A data_vgs=()
  while read -r vg pv; do
    [[ -n "${vg}" && -n "${pv}" ]] || continue
    is_on_data_tree "${pv}" || continue
    data_vgs["${vg}"]=1
  done < <(pvs --noheadings --separator '|' -o vg_name,pv_name 2>/dev/null | sed 's/^ *//;s/ *$//' | tr -d ' ' | tr '|' ' ')

  for vg in "${!data_vgs[@]}"; do
    log "vgchange -an ${vg}"
    vgchange -an "${vg}" || true
  done
fi

log "Tearing down crypt/LVM/device-mapper/md descendants"
while read -r dev typ; do
  [[ -n "${dev}" && -n "${typ}" ]] || continue

  if [[ "${typ}" == "crypt" ]]; then
    if command -v cryptsetup >/dev/null 2>&1; then
      map_name="$(basename "${dev}")"
      log "cryptsetup close ${map_name}"
      cryptsetup close "${map_name}" || true
    fi
    if command -v dmsetup >/dev/null 2>&1; then
      log "dmsetup remove -f ${dev}"
      dmsetup remove -f "${dev}" || dmsetup remove -f "$(basename "${dev}")" || true
    fi
    continue
  fi

  if [[ "${typ}" == "lvm" ]]; then
    if command -v lvchange >/dev/null 2>&1; then
      log "lvchange -an ${dev}"
      lvchange -an "${dev}" || true
    fi
    if command -v dmsetup >/dev/null 2>&1; then
      log "dmsetup remove -f ${dev}"
      dmsetup remove -f "${dev}" || dmsetup remove -f "$(basename "${dev}")" || true
    fi
    continue
  fi

  if [[ "${typ}" =~ ^(md|raid) ]]; then
    if command -v mdadm >/dev/null 2>&1; then
      log "mdadm --stop ${dev}"
      mdadm --stop "${dev}" || true
    fi
    if command -v dmsetup >/dev/null 2>&1; then
      log "dmsetup remove -f ${dev}"
      dmsetup remove -f "${dev}" || dmsetup remove -f "$(basename "${dev}")" || true
    fi
  fi
done < <(printf '%s\n' "${TREE_LINES[@]}" | tac)

assert_no_holders() {
  local dev="$1" base holder_dir holder
  base="$(basename "${dev}")"
  holder_dir="/sys/class/block/${base}/holders"
  [[ -d "${holder_dir}" ]] || return 0

  shopt -s nullglob
  local holders=("${holder_dir}"/*)
  shopt -u nullglob
  if (( ${#holders[@]} > 0 )); then
    log "ERROR: holders remain on ${dev}:"
    for holder in "${holders[@]}"; do
      log "  - $(basename "${holder}")"
    done
    return 1
  fi
  return 0
}

log "Checking for remaining holders"
for dev in "${TREE_DEVS[@]}"; do
  assert_no_holders "${dev}"
done

log "Wiping signatures on DATA disk descendants"
for dev in "${TREE_DEVS_REV[@]}"; do
  [[ "${dev}" == "${DATA_DISK_REAL}" ]] && continue
  log "wipefs -a -f ${dev}"
  wipefs -a -f "${dev}" || true
done

log "Wiping signatures on DATA disk"
wipefs -a -f "${DATA_DISK_REAL}"

log "Zeroing first 32 MiB"
dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M count=32 conv=fsync status=none || true

log "Zeroing last 32 MiB"
DISK_SIZE_BYTES="$(blockdev --getsize64 "${DATA_DISK_REAL}")"
if (( DISK_SIZE_BYTES > 0 )); then
  SEEK_MIB=$(( (DISK_SIZE_BYTES / 1048576) - 32 ))
  if (( SEEK_MIB > 0 )); then
    dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M seek="${SEEK_MIB}" count=32 conv=fsync status=none || true
  fi
fi

log "Creating GPT and single ext4 partition"
parted -s "${DATA_DISK_REAL}" mklabel gpt
parted -s "${DATA_DISK_REAL}" mkpart primary ext4 1MiB 100%

partprobe "${DATA_DISK_REAL}" 2>/dev/null || true
udevadm settle || true
sleep 2

DATA_PART="$(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}" | awk '$2=="part" {print $1; exit}')"
if [[ -z "${DATA_PART}" ]]; then
  log "ERROR: could not locate first partition on ${DATA_DISK_REAL}"
  exit 1
fi

log "Formatting ${DATA_PART} as ext4 label OURBOX_DATA"
mkfs.ext4 -F -L OURBOX_DATA "${DATA_PART}"

udevadm settle || true
sleep 1

LABEL_DEV="$(blkid -L OURBOX_DATA 2>/dev/null || true)"
if [[ -z "${LABEL_DEV}" ]]; then
  log "ERROR: OURBOX_DATA label not found after format"
  exit 1
fi
log "Label resolution: OURBOX_DATA -> ${LABEL_DEV}"

SMOKE_MNT="/run/ourbox-data-smoke"
mkdir -p "${SMOKE_MNT}"
log "Smoke-mounting LABEL=OURBOX_DATA"
mount LABEL=OURBOX_DATA "${SMOKE_MNT}"
umount "${SMOKE_MNT}"
rmdir "${SMOKE_MNT}" || true

log "SUCCESS: DATA disk prepared and mount smoke test passed"
