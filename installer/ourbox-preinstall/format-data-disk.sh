#!/usr/bin/env bash
# format-data-disk.sh — destructive DATA-disk preparation from pre-installer.
#
# Runs in the live installer environment after final INSTALL confirmation.
# Fully tears down existing holders/metadata on the selected DATA disk, then
# creates: GPT + single ext4 partition labeled OURBOX_DATA.
#
# Usage: format-data-disk.sh <data-disk> <os-disk>

set -euo pipefail

log() { echo "[format-data-disk] $*"; }

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

DATA_SIZE_HUMAN="$(lsblk -dn -o SIZE "${DATA_DISK_REAL}" 2>/dev/null | tr -d '[:space:]')"
log "OS disk (protected): ${OS_DISK_REAL}"
log "DATA disk (destructive prepare): ${DATA_DISK_REAL} (${DATA_SIZE_HUMAN})"
log "Pre-teardown DATA tree:"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK_REAL}" || true
log "Pre-teardown OS tree:"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${OS_DISK_REAL}" || true

mapfile -t TREE_DEVICES < <(lsblk -pnro NAME "${DATA_DISK_REAL}")
mapfile -t TREE_TYPES < <(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}")

if (( ${#TREE_DEVICES[@]} == 0 )); then
  log "ERROR: failed to enumerate DATA disk tree for ${DATA_DISK_REAL}"
  exit 1
fi

declare -A IN_TREE=()
for dev in "${TREE_DEVICES[@]}"; do
  IN_TREE["${dev}"]=1
done

# 1) Unmount anything mounted from the DATA disk tree (deepest mount first).
mapfile -t MOUNTS < <(
  lsblk -pnro NAME,MOUNTPOINTS "${DATA_DISK_REAL}" \
    | awk '{$1=""; sub(/^ /, ""); if(length($0)>0) print $0}' \
    | tr ',' '\n' \
    | sed '/^$/d' \
    | awk '{print length($0) "|" $0}' \
    | sort -t'|' -k1,1nr -k2,2 \
    | cut -d'|' -f2-
)
for mountpoint in "${MOUNTS[@]}"; do
  log "Unmounting ${mountpoint}"
  umount "${mountpoint}" || umount -l "${mountpoint}" || true
done

# 2) Disable swap anywhere in the DATA disk tree.
while read -r swapdev _; do
  [[ -n "${swapdev}" ]] || continue
  if [[ -n "${IN_TREE["${swapdev}"]+x}" ]]; then
    log "swapoff ${swapdev}"
    swapoff "${swapdev}" || true
  fi
done < <(tail -n +2 /proc/swaps 2>/dev/null || true)

# 3) Deactivate LVM VGs scoped to PVs on this DATA disk.
if command -v pvs >/dev/null 2>&1 && command -v vgchange >/dev/null 2>&1; then
  while IFS='|' read -r pv_name vg_name; do
    pv_name="$(echo "${pv_name}" | xargs)"
    vg_name="$(echo "${vg_name}" | xargs)"
    [[ -n "${pv_name}" && -n "${vg_name}" ]] || continue
    if [[ -n "${IN_TREE["${pv_name}"]+x}" ]]; then
      log "Deactivating VG via PV scope: pv=${pv_name} vg=${vg_name}"
      vgchange -an --select "pv_name=${pv_name}" || true
    fi
  done < <(pvs --noheadings --separator '|' -o pv_name,vg_name 2>/dev/null || true)
fi

# 4) Tear down child device-mapper stacks (leaves first).
for (( i=${#TREE_TYPES[@]}-1; i>=0; i-- )); do
  line="${TREE_TYPES[${i}]}"
  dev="${line%% *}"
  type="${line##* }"

  case "${type}" in
    crypt)
      map_name="$(basename "${dev}")"
      if command -v cryptsetup >/dev/null 2>&1; then
        log "Closing crypt mapping ${map_name} (${dev})"
        cryptsetup close "${map_name}" || dmsetup remove -f "${dev}" || true
      else
        log "Removing crypt mapping via dmsetup ${dev}"
        dmsetup remove -f "${dev}" || true
      fi
      ;;
    lvm)
      log "Removing LVM dm node ${dev}"
      dmsetup remove -f "${dev}" || true
      ;;
    md|raid* )
      if command -v mdadm >/dev/null 2>&1; then
        log "Stopping md raid device ${dev}"
        mdadm --stop "${dev}" || true
      fi
      ;;
  esac
done

# 5) Verify holders are gone from DATA disk and partitions.
check_holders() {
  local dev="$1"
  local base
  base="$(basename "${dev}")"
  if [[ -d "/sys/class/block/${base}/holders" ]]; then
    find "/sys/class/block/${base}/holders" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null || true
  fi
}

remaining_holders=""
for dev in "${TREE_DEVICES[@]}"; do
  holders="$(check_holders "${dev}")"
  if [[ -n "${holders}" ]]; then
    remaining_holders+="${dev}: ${holders}"$'\n'
  fi
done
if [[ -n "${remaining_holders}" ]]; then
  log "ERROR: holders remain on DATA disk tree after teardown:"
  echo "${remaining_holders}" | sed 's/^/[format-data-disk]   /'
  exit 1
fi

# 6) Wipe descendants first, then whole disk.
for (( i=${#TREE_TYPES[@]}-1; i>=0; i-- )); do
  dev="${TREE_TYPES[${i}]%% *}"
  [[ "${dev}" == "${DATA_DISK_REAL}" ]] && continue
  [[ -b "${dev}" ]] || continue
  log "wipefs -a -f ${dev}"
  wipefs -a -f "${dev}" || true
done

log "wipefs -a -f ${DATA_DISK_REAL}"
wipefs -a -f "${DATA_DISK_REAL}"

log "Zeroing first 32 MiB on ${DATA_DISK_REAL}"
dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M count=32 conv=fsync,notrunc 2>/dev/null || true

# Clear tail metadata area as well (backup GPT / stale metadata).
disk_bytes="$(blockdev --getsize64 "${DATA_DISK_REAL}")"
if [[ -n "${disk_bytes}" && "${disk_bytes}" -gt $((64*1024*1024)) ]]; then
  tail_seek_mib=$(( disk_bytes / 1024 / 1024 - 32 ))
  log "Zeroing last 32 MiB on ${DATA_DISK_REAL} (seek=${tail_seek_mib}MiB)"
  dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M count=32 seek="${tail_seek_mib}" conv=fsync,notrunc 2>/dev/null || true
fi

# 7) Partition as GPT + one full ext4 partition.
log "Partitioning ${DATA_DISK_REAL}"
parted -s "${DATA_DISK_REAL}" mklabel gpt
parted -s "${DATA_DISK_REAL}" mkpart primary ext4 1MiB 100%
partprobe "${DATA_DISK_REAL}" 2>/dev/null || true
udevadm settle || true
sleep 1

DATA_PART="$(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}" | awk '$2=="part" {print $1; exit}')"
[[ -n "${DATA_PART}" ]] || { log "ERROR: failed to discover new partition on ${DATA_DISK_REAL}"; exit 1; }

log "Formatting ${DATA_PART} as ext4 with label OURBOX_DATA"
mkfs.ext4 -F -L OURBOX_DATA "${DATA_PART}"
udevadm settle || true
sleep 1

label_dev="$(blkid -L OURBOX_DATA 2>/dev/null || true)"
if [[ -z "${label_dev}" ]]; then
  log "ERROR: OURBOX_DATA label not found after mkfs"
  exit 1
fi

# 8) Smoke-test mountability.
smoke_mnt="/run/ourbox-data-smoketest"
mkdir -p "${smoke_mnt}"
log "Smoke-mounting LABEL=OURBOX_DATA at ${smoke_mnt}"
mount "LABEL=OURBOX_DATA" "${smoke_mnt}"
umount "${smoke_mnt}"
rmdir "${smoke_mnt}" 2>/dev/null || true

log "SUCCESS: DATA disk prepared at ${label_dev}"
