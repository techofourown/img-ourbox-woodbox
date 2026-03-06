#!/usr/bin/env bash
# format-data-disk.sh — destructive DATA-disk preparation in pre-installer
#
# Runs in the live installer environment immediately after the operator
# confirms INSTALL in ourbox-preinstall.
#
# Rebuilds the selected DATA disk as:
#   GPT + single ext4 partition labeled OURBOX_DATA.
#
# Usage: format-data-disk.sh <data-disk> <os-disk>
#   e.g. format-data-disk.sh /dev/sda /dev/nvme0n1
#
# Always formats — the operator already confirmed FORMAT-AS-DATA and INSTALL.

set -euo pipefail

log() { echo "[format-data-disk] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR: required command not found: $1"
    exit 1
  }
}

for cmd in lsblk readlink awk sort mountpoint umount findmnt wipefs dd partprobe udevadm mkfs.ext4 blkid mount blockdev parted dmsetup find; do
  need_cmd "${cmd}"
done

DATA_DISK="${1:?Usage: format-data-disk.sh <data-disk> <os-disk>}"
OS_DISK="${2:?Usage: format-data-disk.sh <data-disk> <os-disk>}"

DATA_DISK_REAL="$(readlink -f "${DATA_DISK}")"
OS_DISK_REAL="$(readlink -f "${OS_DISK}")"

[[ -b "${DATA_DISK_REAL}" ]] || { log "ERROR: DATA disk is not a block device: ${DATA_DISK_REAL}"; exit 1; }
[[ -b "${OS_DISK_REAL}" ]] || { log "ERROR: OS disk is not a block device: ${OS_DISK_REAL}"; exit 1; }

if [[ "${DATA_DISK_REAL}" == "${OS_DISK_REAL}" ]]; then
  log "ERROR: DATA disk resolves to the OS disk (${OS_DISK_REAL}) — aborting"
  exit 1
fi

DATA_TYPE="$(lsblk -dn -o TYPE "${DATA_DISK_REAL}" 2>/dev/null | tr -d '[:space:]')"
OS_TYPE="$(lsblk -dn -o TYPE "${OS_DISK_REAL}" 2>/dev/null | tr -d '[:space:]')"
[[ "${DATA_TYPE}" == "disk" ]] || { log "ERROR: DATA target is not a whole disk: ${DATA_DISK_REAL} (type=${DATA_TYPE:-unknown})"; exit 1; }
[[ "${OS_TYPE}" == "disk" ]] || { log "ERROR: OS target is not a whole disk: ${OS_DISK_REAL} (type=${OS_TYPE:-unknown})"; exit 1; }

log "OS disk (protected): ${OS_DISK_REAL}"
log "DATA disk (destructive): ${DATA_DISK_REAL}"
log "Current DATA disk tree:"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK_REAL}" || true
log "Current OS disk tree:"
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${OS_DISK_REAL}" || true

mapfile -t TREE_LINES < <(lsblk -pnro NAME,TYPE,MOUNTPOINTS "${DATA_DISK_REAL}")
(( ${#TREE_LINES[@]} > 0 )) || { log "ERROR: unable to enumerate DATA disk tree for ${DATA_DISK_REAL}"; exit 1; }

mapfile -t TREE_DEVS < <(printf '%s\n' "${TREE_LINES[@]}" | awk '{print $1}')

# Unmount leaf-first by mountpoint depth.
mapfile -t TREE_MOUNTS < <(printf '%s\n' "${TREE_LINES[@]}" | awk '{
  if (NF <= 2) next
  mp=""
  for (i=3; i<=NF; i++) {
    if ($i ~ /^\[/) continue
    if (mp != "") mp = mp " "
    mp = mp $i
  }
  if (mp != "") print mp
}' | awk '{d=gsub("/","/"); print d, $0}' | sort -rn | cut -d' ' -f2- | awk '!seen[$0]++')

for mp in "${TREE_MOUNTS[@]}"; do
  [[ -n "${mp}" ]] || continue
  if mountpoint -q "${mp}" 2>/dev/null; then
    log "Unmounting ${mp}"
    umount "${mp}" || umount -l "${mp}" || true
  fi
done

# Disable swap devices located on this tree.
if command -v swapon >/dev/null 2>&1 && command -v swapoff >/dev/null 2>&1; then
  while read -r swap_dev _rest; do
    [[ -n "${swap_dev}" && "${swap_dev}" != "NAME" ]] || continue
    for tree_dev in "${TREE_DEVS[@]}"; do
      if [[ "${swap_dev}" == "${tree_dev}" ]]; then
        log "Disabling swap on ${swap_dev}"
        swapoff "${swap_dev}" || true
      fi
    done
  done < <(swapon --noheadings --raw --show=NAME 2>/dev/null || true)
fi

# Tear down mapped leaves first.
for (( idx=${#TREE_LINES[@]}-1; idx>=0; idx-- )); do
  line="${TREE_LINES[$idx]}"
  dev="$(awk '{print $1}' <<<"${line}")"
  typ="$(awk '{print $2}' <<<"${line}")"

  case "${typ}" in
    crypt)
      map_name="${dev##*/}"
      if command -v cryptsetup >/dev/null 2>&1; then
        log "Closing crypt mapping ${map_name} (${dev})"
        cryptsetup close "${map_name}" || dmsetup remove -f "${dev}" || true
      else
        log "Removing crypt mapping via dmsetup: ${dev}"
        dmsetup remove -f "${dev}" || true
      fi
      ;;
    lvm)
      log "Removing LVM device-mapper node: ${dev}"
      dmsetup remove -f "${dev}" || true
      ;;
    raid*|md)
      if command -v mdadm >/dev/null 2>&1; then
        log "Stopping md array ${dev}"
        mdadm --stop "${dev}" || true
      fi
      ;;
  esac
done

# Deactivate only VGs that use PVs from this DATA disk tree.
if command -v pvs >/dev/null 2>&1 && command -v vgchange >/dev/null 2>&1; then
  mapfile -t DATA_PVS < <(printf '%s\n' "${TREE_LINES[@]}" | awk '$2=="part" {print $1}')
  if (( ${#DATA_PVS[@]} > 0 )); then
    mapfile -t VGS_TO_DEACTIVATE < <(
      pvs --noheadings --readonly -o pv_name,vg_name 2>/dev/null | awk '{print $1, $2}' | while read -r pv vg; do
        [[ -n "${pv}" && -n "${vg}" ]] || continue
        for data_pv in "${DATA_PVS[@]}"; do
          if [[ "${pv}" == "${data_pv}" ]]; then
            echo "${vg}"
          fi
        done
      done | sort -u
    )

    for vg in "${VGS_TO_DEACTIVATE[@]}"; do
      [[ -n "${vg}" ]] || continue
      log "Deactivating LVs in VG ${vg} (scoped to DATA disk PVs)"
      vgchange -an "${vg}" || true
    done
  fi
fi

udevadm settle || true

# Holders must be gone before destructive wipe.
holders_remaining=0
for dev in "${TREE_DEVS[@]}"; do
  dev_name="${dev##*/}"
  holders_dir="/sys/class/block/${dev_name}/holders"
  [[ -d "${holders_dir}" ]] || continue
  mapfile -t holders < <(find "${holders_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)
  if (( ${#holders[@]} > 0 )); then
    holders_remaining=1
    log "ERROR: holders remain on ${dev}: ${holders[*]}"
  fi
done

if (( holders_remaining != 0 )); then
  log "ERROR: refusing to wipe ${DATA_DISK_REAL} while holders are still active"
  lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK_REAL}" || true
  exit 1
fi

# Wipe descendant signatures first, then whole disk.
for (( idx=${#TREE_LINES[@]}-1; idx>=0; idx-- )); do
  dev="$(awk '{print $1}' <<<"${TREE_LINES[$idx]}")"
  [[ "${dev}" == "${DATA_DISK_REAL}" ]] && continue
  log "Wiping signatures on descendant ${dev}"
  wipefs -a -f "${dev}" || true
done

log "Wiping signatures on whole disk ${DATA_DISK_REAL}"
wipefs -a -f "${DATA_DISK_REAL}"

log "Zeroing first 32MiB of ${DATA_DISK_REAL}"
dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M count=32 conv=fsync status=none || true

disk_size_bytes="$(blockdev --getsize64 "${DATA_DISK_REAL}")"
bs=$((1024 * 1024))
tail_mib=32
tail_bytes=$((tail_mib * bs))
if (( disk_size_bytes > tail_bytes )); then
  seek_mib=$(((disk_size_bytes / bs) - tail_mib))
  log "Zeroing last ${tail_mib}MiB of ${DATA_DISK_REAL}"
  dd if=/dev/zero of="${DATA_DISK_REAL}" bs=1M count="${tail_mib}" seek="${seek_mib}" conv=fsync status=none || true
fi

log "Re-reading partition table for ${DATA_DISK_REAL}"
partprobe "${DATA_DISK_REAL}" 2>/dev/null || true
udevadm settle || true

log "Creating fresh GPT + single ext4 partition on ${DATA_DISK_REAL}"
parted -s "${DATA_DISK_REAL}" mklabel gpt
parted -s "${DATA_DISK_REAL}" mkpart primary ext4 1MiB 100%

partprobe "${DATA_DISK_REAL}" 2>/dev/null || true
udevadm settle || true
sleep 1

DATA_PART="$(lsblk -pnro NAME,TYPE "${DATA_DISK_REAL}" | awk '$2=="part" {print $1; exit}')"
[[ -n "${DATA_PART}" ]] || { log "ERROR: failed to locate new partition under ${DATA_DISK_REAL}"; exit 1; }

log "Formatting ${DATA_PART} as ext4 (label=OURBOX_DATA)"
mkfs.ext4 -F -L OURBOX_DATA "${DATA_PART}"
udevadm settle || true
sleep 1

DATA_LABEL_DEV="$(blkid -L OURBOX_DATA 2>/dev/null || true)"
[[ -n "${DATA_LABEL_DEV}" ]] || { log "ERROR: OURBOX_DATA label not found after mkfs"; exit 1; }

smoke_mount="/run/ourbox-data-smoke-mount"
mkdir -p "${smoke_mount}"
log "Smoke-mounting LABEL=OURBOX_DATA at ${smoke_mount}"
mount LABEL=OURBOX_DATA "${smoke_mount}"
umount "${smoke_mount}"
rmdir "${smoke_mount}" 2>/dev/null || true

log "SUCCESS: DATA disk ready at ${DATA_LABEL_DEV}"
