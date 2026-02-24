#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/config.env" ] && source "${ROOT}/tools/config.env"

usage(){
  cat <<USAGE
Usage: $0

Interactive workflow:
  1) installs build host deps (best-effort)
  2) fetches airgap artifacts
  3) builds a custom Ubuntu Server autoinstall ISO
  4) flashes it to a removable USB disk you select
USAGE
}

if [[ $# -gt 0 && ("${1}" == "-h" || "${1}" == "--help") ]]; then
  usage
  exit 0
fi
[[ $# -eq 0 ]] || { usage; die "no positional args supported"; }

need_cmd lsblk
need_cmd readlink
need_cmd findmnt
need_cmd awk
need_cmd sed
need_cmd openssl

SENTINEL="${ROOT}/.used"

if [[ -f "${SENTINEL}" ]]; then
  echo
  echo "=================================================================="
  echo "  STALE WORKING TREE DETECTED"
  echo "=================================================================="
  echo
  echo "  This repo has been used before. To guarantee a clean, reliable"
  echo "  build, always start from a pristine working tree."
  echo
  echo "  Reset and retry:"
  echo
  echo "    git clean -fdx && ./tools/prepare-installer-media.sh"
  echo
  echo "  Or re-clone from scratch:"
  echo
  echo "    cd .. && rm -rf img-ourbox-woodbox"
  echo "    git clone --recurse-submodules https://github.com/techofourown/img-ourbox-woodbox.git"
  echo "    cd img-ourbox-woodbox && ./tools/prepare-installer-media.sh"
  echo
  echo "=================================================================="
  echo
  exit 1
fi

root_backing_disk() {
  local root_src root_real root_parent
  root_src="$(findmnt -nr -o SOURCE / 2>/dev/null || true)"
  root_real="$(readlink -f "${root_src}" 2>/dev/null || echo "${root_src}")"
  root_parent="$(lsblk -no PKNAME "${root_real}" 2>/dev/null || true)"
  if [[ -n "${root_parent}" ]]; then
    echo "/dev/${root_parent}"
  else
    echo "${root_real}"
  fi
}

ROOT_DISK="$(root_backing_disk)"

preferred_byid_for_disk() {
  local disk="$1"
  local best=""
  local p target base

  for p in /dev/disk/by-id/*; do
    [[ -L "${p}" ]] || continue
    [[ "${p}" == *-part* ]] && continue
    target="$(readlink -f "${p}" 2>/dev/null || true)"
    [[ "${target}" == "${disk}" ]] || continue

    base="$(basename "${p}")"
    if [[ "${base}" == usb-* ]]; then
      echo "${p}"
      return 0
    fi
    [[ -z "${best}" ]] && best="${p}"
  done

  [[ -n "${best}" ]] && echo "${best}" || true
}

is_candidate_media_disk() {
  local disk="$1"
  local type tran rm

  type="$(lsblk -dn -o TYPE "${disk}" 2>/dev/null | tr -d '[:space:]')"
  [[ "${type}" == "disk" ]] || return 1
  [[ "${disk}" != "${ROOT_DISK}" ]] || return 1

  tran="$(lsblk -dn -o TRAN "${disk}" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  rm="$(lsblk -dn -o RM "${disk}" 2>/dev/null | tr -d '[:space:]')"
  [[ "${tran}" == "usb" || "${rm}" == "1" ]] || return 1

  return 0
}

declare -a CANDIDATE_DISKS=()

refresh_candidate_disks() {
  CANDIDATE_DISKS=()
  while read -r disk; do
    [[ -n "${disk}" ]] || continue
    if is_candidate_media_disk "${disk}"; then
      CANDIDATE_DISKS+=("${disk}")
    fi
  done < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}')
}

print_candidate_disks() {
  local idx disk size tran model serial byid

  echo
  echo "Detected removable/USB target candidates:"
  echo
  printf '  %-3s %-14s %-8s %-6s %-22s %-14s\n' "#" "Device" "Size" "Tran" "Model" "Serial"
  for idx in "${!CANDIDATE_DISKS[@]}"; do
    disk="${CANDIDATE_DISKS[$idx]}"
    size="$(lsblk -dn -o SIZE "${disk}" 2>/dev/null | tr -d '[:space:]')"
    tran="$(lsblk -dn -o TRAN "${disk}" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    model="$(lsblk -dn -o MODEL "${disk}" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    serial="$(lsblk -dn -o SERIAL "${disk}" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -n "${tran}" ]] || tran="-"
    [[ -n "${model}" ]] || model="-"
    [[ -n "${serial}" ]] || serial="-"
    printf '  %-3s %-14s %-8s %-6s %-22.22s %-14.14s\n' "$((idx + 1))" "${disk}" "${size}" "${tran}" "${model}" "${serial}"

    byid="$(preferred_byid_for_disk "${disk}" || true)"
    if [[ -n "${byid}" ]]; then
      echo "      by-id: ${byid}"
    fi

    echo "      partitions (name fstype label mountpoints):"
    lsblk -nr -o NAME,FSTYPE,LABEL,MOUNTPOINTS "${disk}" 2>/dev/null | sed 's/^/        /'
  done
  echo
}

validate_target_dev_or_die() {
  local target="$1"
  local target_real target_type

  [[ -n "${target}" ]] || die "target device is empty"
  [[ "${target}" != *"<"* && "${target}" != *">"* ]] || die "target contains angle brackets; use a real /dev path"
  [[ -e "${target}" ]] || die "target device does not exist: ${target}"

  target_real="$(readlink -f "${target}")"
  target_type="$(lsblk -dn -o TYPE "${target_real}" 2>/dev/null | tr -d '[:space:]')"
  [[ "${target_type}" == "disk" ]] || die "target is not a raw disk: ${target_real}"
  [[ "${target_real}" != "${ROOT_DISK}" ]] || die "refusing target that backs / (${ROOT_DISK})"
}

select_target_device_interactive() {
  local choice idx selected byid confirm

  while true; do
    refresh_candidate_disks
    if (( ${#CANDIDATE_DISKS[@]} == 0 )); then
      echo
      echo "No removable/USB disk candidates found."
      echo "Insert the target USB media, then rescan."
      read -r -p "Press ENTER to rescan, or type q to quit: " choice
      [[ "${choice}" == "q" || "${choice}" == "Q" ]] && die "no target media selected"
      continue
    fi

    print_candidate_disks
    read -r -p "Select target number (r=rescan, q=quit): " choice
    case "${choice}" in
      r|R) continue ;;
      q|Q) die "operator canceled target media selection" ;;
    esac

    [[ "${choice}" =~ ^[0-9]+$ ]] || { log "invalid selection: ${choice}"; continue; }
    idx="$((choice - 1))"
    (( idx >= 0 && idx < ${#CANDIDATE_DISKS[@]} )) || { log "selection out of range: ${choice}"; continue; }

    selected="${CANDIDATE_DISKS[$idx]}"
    byid="$(preferred_byid_for_disk "${selected}" || true)"
    if [[ -n "${byid}" ]]; then
      selected="${byid}"
    fi

    validate_target_dev_or_die "${selected}"
    echo
    lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${selected}" || true
    echo
    read -r -p "Type SELECT to use ${selected}: " confirm
    [[ "${confirm}" == "SELECT" ]] || { log "selection not confirmed; returning to list"; continue; }

    TARGET_DEV="${selected}"
    return 0
  done
}

prompt_nonempty() {
  local prompt="$1" default="${2:-}" ans=""
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " ans
    ans="${ans:-${default}}"
  else
    read -r -p "${prompt}: " ans
  fi
  [[ -n "${ans}" ]] || die "value required"
  echo "${ans}"
}

prompt_password_hash() {
  local pw1="" pw2=""
  echo
  echo "Set the initial password for the installed system user."
  echo "(You can change it later with: passwd)"
  echo
  while true; do
    read -r -s -p "Password: " pw1
    echo
    read -r -s -p "Confirm:  " pw2
    echo
    [[ -n "${pw1}" ]] || { echo "Password cannot be empty."; continue; }
    [[ "${pw1}" == "${pw2}" ]] || { echo "Passwords did not match. Try again."; continue; }
    # openssl passwd -6 prompts for salt automatically.
    echo "${pw1}" | openssl passwd -6 -stdin
    return 0
  done
}

banner() {
  echo
  echo "=================================================================="
  echo "OurBox Woodbox — Build USB installer media (destructive on target)"
  echo "=================================================================="
  echo
}

main(){
  banner

  log "Selecting target USB media"
  TARGET_DEV=""
  select_target_device_interactive
  validate_target_dev_or_die "${TARGET_DEV}"
  log "Using target media device: ${TARGET_DEV}"

  # identity prompts
  : "${OURBOX_HOSTNAME:=ourbox-woodbox}"
  local hostname username passhash

  hostname="$(prompt_nonempty "Hostname for the box" "${OURBOX_HOSTNAME}")"
  username="$(prompt_nonempty "Username" "ourbox")"
  passhash="$(prompt_password_hash)"

  export OURBOX_HOSTNAME="${hostname}"
  export OURBOX_USERNAME="${username}"
  export OURBOX_PASSWORD_HASH="${passhash}"

  touch "${SENTINEL}"

  log "Bootstrapping host dependencies"
  "${ROOT}/tools/bootstrap-host.sh"

  log "Fetching airgap artifacts"
  "${ROOT}/tools/fetch-airgap-platform.sh"

  log "Building installer ISO"
  "${ROOT}/tools/build-installer-iso.sh"

  iso="$(ls -1t "${ROOT}"/deploy/installer-ourbox-woodbox-*.iso 2>/dev/null | head -n 1 || true)"
  if [[ -z "${iso}" || ! -f "${iso}" ]]; then
    log "ERROR: no installer ISO found in deploy/"
    ls -lah "${ROOT}/deploy" || true
    die "build did not produce installer ISO"
  fi

  log "Flashing installer ISO to ${TARGET_DEV}"
  "${ROOT}/tools/flash-installer-media.sh" "${iso}" "${TARGET_DEV}"

  echo
  echo "Done."
  echo
  echo "Next steps:"
  echo "  1) Boot the Woodbox from this USB (UEFI boot menu)"
  echo "  2) The installer will run unattended (watch console for progress)"
  echo "  3) When it powers off, remove the USB and boot from NVMe"
  echo
}

main "$@"
