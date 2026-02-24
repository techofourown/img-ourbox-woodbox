#!/usr/bin/env bash
set -euo pipefail

# Prepare the DATA disk per OurBox contract:
# - single ext4 partition
# - LABEL=OURBOX_DATA
# - intended mountpoint: /var/lib/ourbox

log(){ echo "[prepare-data-disk] $*"; }
die(){ echo "[prepare-data-disk] ERROR: $*" >&2; exit 1; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

need_cmd lsblk
need_cmd blkid
need_cmd readlink
need_cmd wipefs
need_cmd sgdisk
need_cmd partprobe
need_cmd mkfs.ext4

DATA_DISK="${1:-}"
SYS_DISK="${2:-}"

[[ -n "${DATA_DISK}" ]] || die "usage: $0 DATA_DISK SYS_DISK"
[[ -n "${SYS_DISK}" ]] || die "usage: $0 DATA_DISK SYS_DISK"

DATA_DISK="$(readlink -f "${DATA_DISK}")"
SYS_DISK="$(readlink -f "${SYS_DISK}")"

[[ -b "${DATA_DISK}" ]] || die "DATA_DISK is not a block device: ${DATA_DISK}"
[[ -b "${SYS_DISK}" ]] || die "SYS_DISK is not a block device: ${SYS_DISK}"

[[ "${DATA_DISK}" != "${SYS_DISK}" ]] || die "DATA_DISK and SYS_DISK are the same (${DATA_DISK})"

# If label already exists, keep it (non-destructive)
if blkid -L OURBOX_DATA >/dev/null 2>&1; then
  part="$(blkid -L OURBOX_DATA)"
  real_part="$(readlink -f "${part}")"
  parent="/dev/$(lsblk -no PKNAME "${real_part}")"
  if [[ "${parent}" != "${DATA_DISK}" ]]; then
    die "Found LABEL=OURBOX_DATA on ${parent}, expected on ${DATA_DISK}. Refusing."
  fi
  fstype="$(lsblk -no FSTYPE "${real_part}" 2>/dev/null || true)"
  [[ "${fstype}" == "ext4" ]] || die "LABEL=OURBOX_DATA exists but is not ext4 (fstype=${fstype:-unknown})"
  log "DATA disk already prepared: ${real_part} (LABEL=OURBOX_DATA)"
  exit 0
fi

# Safety: refuse to touch disk if it has any mounted partitions
if lsblk -nr -o MOUNTPOINT "${DATA_DISK}" | awk 'NF && $0 != "" {found=1} END{exit !found}'; then
  lsblk "${DATA_DISK}" || true
  die "DATA_DISK has mounted partitions; refusing to format"
fi

# Safety: refuse if disk appears to have existing filesystems (unless force)
if lsblk -nr -o FSTYPE "${DATA_DISK}" | awk 'NF && $0 != "" {found=1} END{exit !found}'; then
  if [[ "${FORCE_DATA_ERASE:-0}" != "1" ]]; then
    lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${DATA_DISK}" || true
    die "DATA_DISK has existing filesystem signatures. Set FORCE_DATA_ERASE=1 to override."
  fi
  log "FORCE_DATA_ERASE=1 set; will wipe existing signatures"
fi

log "Initializing DATA disk: ${DATA_DISK}"

# Zap partition table + signatures
wipefs -a "${DATA_DISK}" >/dev/null 2>&1 || true
sgdisk --zap-all "${DATA_DISK}" >/dev/null 2>&1 || true

# Create GPT + one partition
sgdisk -n 1:1MiB:0 -t 1:8300 "${DATA_DISK}" >/dev/null
partprobe "${DATA_DISK}" || true

PART="${DATA_DISK}1"
if [[ -b "${DATA_DISK}p1" ]]; then
  PART="${DATA_DISK}p1"
fi

log "Formatting ${PART} as ext4 with LABEL=OURBOX_DATA"
mkfs.ext4 -F -L OURBOX_DATA "${PART}" >/dev/null

# Verify label resolves back
resolved="$(blkid -L OURBOX_DATA 2>/dev/null || true)"
[[ -n "${resolved}" ]] || die "label OURBOX_DATA not resolvable after format"
[[ "$(readlink -f "${resolved}")" == "$(readlink -f "${PART}")" ]] || die "OURBOX_DATA resolves to ${resolved}, expected ${PART}"

log "DATA disk prepared: ${PART} (LABEL=OURBOX_DATA)"
