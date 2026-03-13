#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
PREINSTALL_DIR="${FIXTURE_ROOT}/installer/ourbox-preinstall"
APT_DIR="${TMP}/apt"
SYSFS_DIR="${TMP}/sys-class-net"
CACHE_DIR="${TMP}/cache"
mkdir -p "${TOOLS_DIR}" "${PREINSTALL_DIR}" "${APT_DIR}" "${SYSFS_DIR}/enp2s0" "${CACHE_DIR}"

cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" "${PREINSTALL_DIR}/ourbox-preinstall"
cp "${ROOT}/installer/ourbox-preinstall/render-target-netplan.py" "${TOOLS_DIR}/render-target-netplan.py"
cp "${ROOT}/installer/ourbox-preinstall/install-offline-target-packages.sh" "${TOOLS_DIR}/install-offline-target-packages.sh"

printf 'Package: avahi-daemon\n' > "${APT_DIR}/Packages"
printf 'avahi-daemon\navahi-utils\n' > "${APT_DIR}/target-packages.txt"
printf '1\n' > "${SYSFS_DIR}/enp2s0/type"
printf 'aa:bb:cc:dd:ee:01\n' > "${SYSFS_DIR}/enp2s0/address"
ln -s "/devices/pci0000:00/0000:00:1f.6" "${SYSFS_DIR}/enp2s0/device"

# shellcheck disable=SC1091
OURBOX_PREINSTALL_LIBRARY_ONLY=1 \
OURBOX_PREINSTALL_TOOLS_ROOT="${TOOLS_DIR}" \
OURBOX_PREINSTALL_OFFLINE_TARGET_APT_REPO_DIR="${APT_DIR}" \
OURBOX_PREINSTALL_SYS_CLASS_NET_ROOT="${SYSFS_DIR}" \
  source "${PREINSTALL_DIR}/ourbox-preinstall"

export INSTALLER_CACHE_DIR="${CACHE_DIR}"
write_offline_install_helpers

[[ -f "${CACHE_DIR}/target-netplan.yaml" ]] || {
  echo "target-netplan.yaml was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/apply-target-netplan.sh" ]] || {
  echo "apply-target-netplan.sh was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/install-target-packages.sh" ]] || {
  echo "install-target-packages.sh was not generated" >&2
  exit 1
}

grep -q 'macaddress: aa:bb:cc:dd:ee:01' "${CACHE_DIR}/target-netplan.yaml" || {
  echo "prepared netplan missing expected MAC match" >&2
  exit 1
}
grep -q 'optional: true' "${CACHE_DIR}/target-netplan.yaml" || {
  echo "prepared netplan must mark the NIC optional" >&2
  exit 1
}
grep -q 'install-offline-target-packages.sh' "${CACHE_DIR}/install-target-packages.sh" || {
  echo "install-target-packages helper must delegate to the staged offline package installer" >&2
  exit 1
}

printf '[%s] Woodbox preinstall offline helpers smoke passed\n' "$(date -Is)"
