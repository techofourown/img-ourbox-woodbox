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
MISSION_SSH_KEY="${TMP}/mission-authorized-key.pub"
mkdir -p "${TOOLS_DIR}" "${PREINSTALL_DIR}" "${APT_DIR}" "${SYSFS_DIR}/enp2s0" "${CACHE_DIR}"

cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" "${PREINSTALL_DIR}/ourbox-preinstall"
cp "${ROOT}/installer/ourbox-preinstall/render-target-netplan.py" "${TOOLS_DIR}/render-target-netplan.py"
cp "${ROOT}/installer/ourbox-preinstall/install-offline-target-packages.sh" "${TOOLS_DIR}/install-offline-target-packages.sh"

printf 'Package: avahi-daemon\nPackage: openssh-server\n' > "${APT_DIR}/Packages"
printf 'avahi-daemon\navahi-utils\n' > "${APT_DIR}/target-packages.txt"
printf '1\n' > "${SYSFS_DIR}/enp2s0/type"
printf 'aa:bb:cc:dd:ee:01\n' > "${SYSFS_DIR}/enp2s0/address"
ln -s "/devices/pci0000:00/0000:00:1f.6" "${SYSFS_DIR}/enp2s0/device"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJtq4zUjV1X3cM4wUx2u1g0qzW3N0Pqf7sXc7gXvQxQn fixture@host\n' > "${MISSION_SSH_KEY}"

# shellcheck disable=SC1091
OURBOX_PREINSTALL_LIBRARY_ONLY=1 \
OURBOX_PREINSTALL_TOOLS_ROOT="${TOOLS_DIR}" \
OURBOX_PREINSTALL_OFFLINE_TARGET_APT_REPO_DIR="${APT_DIR}" \
OURBOX_PREINSTALL_SYS_CLASS_NET_ROOT="${SYSFS_DIR}" \
  source "${PREINSTALL_DIR}/ourbox-preinstall"

export INSTALLER_CACHE_DIR="${CACHE_DIR}"
export OURBOX_USERNAME="ourbox"
export OURBOX_INSTALLED_TARGET_SSH_PASSWORD_ENABLED=1
export MISSION_INSTALLED_TARGET_SSH_PRESENT=1
export MISSION_INSTALLED_TARGET_SSH_KEY_NAME="fixture-shared-dev"
export MISSION_INSTALLED_TARGET_SSH_AUTHORIZED_KEY_PATH="${MISSION_SSH_KEY}"
export MISSION_INSTALLED_TARGET_SSH_PUBLIC_KEY_FINGERPRINT="SHA256:fixtureFingerprint0123456789abcdef=="
write_offline_install_helpers
ssh_block="$(render_installed_target_ssh_autoinstall_block)"

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
[[ -f "${CACHE_DIR}/configure-installed-target-ssh.sh" ]] || {
  echo "configure-installed-target-ssh.sh was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/installed-target-ssh-packages.txt" ]] || {
  echo "installed-target-ssh-packages.txt was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/installed-target-authorized-key.pub" ]] || {
  echo "installed-target-authorized-key.pub was not staged into the installer cache" >&2
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
grep -q '^openssh-server$' "${CACHE_DIR}/installed-target-ssh-packages.txt" || {
  echo "installed-target SSH package manifest must include openssh-server" >&2
  exit 1
}
grep -q 'sshd_config.d/60-ourbox-installed-target.conf' "${CACHE_DIR}/configure-installed-target-ssh.sh" || {
  echo "configure-installed-target-ssh helper must render sshd drop-in config" >&2
  exit 1
}
grep -q 'Installed-target SSH inputs: key=' "${CACHE_DIR}/configure-installed-target-ssh.sh" || {
  echo "configure-installed-target-ssh helper must log its input posture" >&2
  exit 1
}
[[ "${ssh_block}" == *'install-server: true'* ]] || {
  echo "autoinstall SSH block must install the SSH server when SSH is enabled" >&2
  exit 1
}
[[ "${ssh_block}" == *'allow-pw: true'* ]] || {
  echo "autoinstall SSH block must allow passwords when password SSH is enabled" >&2
  exit 1
}
[[ "${ssh_block}" == *'authorized-keys:'* ]] || {
  echo "autoinstall SSH block must include authorized-keys when a mission SSH key is present" >&2
  exit 1
}
[[ "${ssh_block}" == *'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJtq4zUjV1X3cM4wUx2u1g0qzW3N0Pqf7sXc7gXvQxQn fixture@host'* ]] || {
  echo "autoinstall SSH block must embed the selected mission SSH public key" >&2
  exit 1
}

export OURBOX_INSTALLED_TARGET_SSH_PASSWORD_ENABLED=0
ssh_key_only_block="$(render_installed_target_ssh_autoinstall_block)"
[[ "${ssh_key_only_block}" == *'allow-pw: false'* ]] || {
  echo "key-only autoinstall SSH block must disable password login" >&2
  exit 1
}
grep -q '\${OURBOX_INSTALLED_TARGET_SSH_AUTOINSTALL_BLOCK}' "${ROOT}/installer/autoinstall/autoinstall.tpl" || {
  echo "runtime autoinstall template must include the installed-target SSH block placeholder" >&2
  exit 1
}

printf '[%s] Woodbox preinstall offline helpers smoke passed\n' "$(date -Is)"
