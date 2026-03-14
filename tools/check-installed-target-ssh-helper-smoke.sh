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
TARGET_DIR="${TMP}/target"
BIN_DIR="${TMP}/bin"
MISSION_SSH_KEY="${TMP}/mission-authorized-key.pub"
PACKAGE_INSTALL_LOG="${TMP}/package-install.log"
CURTIN_LOG="${TMP}/curtin.log"
mkdir -p "${TOOLS_DIR}" "${PREINSTALL_DIR}" "${APT_DIR}" "${SYSFS_DIR}/enp2s0" "${CACHE_DIR}" "${TARGET_DIR}/etc" "${BIN_DIR}"

cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" "${PREINSTALL_DIR}/ourbox-preinstall"
cp "${ROOT}/installer/ourbox-preinstall/render-target-netplan.py" "${TOOLS_DIR}/render-target-netplan.py"

cat > "${TOOLS_DIR}/install-offline-target-packages.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

manifest=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-manifest)
      manifest="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "${manifest}" ]] || {
  echo "package manifest not provided" >&2
  exit 1
}
[[ -f "${manifest}" ]] || {
  echo "package manifest missing: ${manifest}" >&2
  exit 1
}
grep -q '^openssh-server$' "${manifest}" || {
  echo "openssh-server missing from SSH package manifest" >&2
  exit 1
}
printf '%s\n' "${manifest}" > "${PACKAGE_INSTALL_LOG:?}"
SCRIPT
chmod +x "${TOOLS_DIR}/install-offline-target-packages.sh"

cat > "${BIN_DIR}/curtin" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${CURTIN_LOG:?}"
SCRIPT
chmod +x "${BIN_DIR}/curtin"

printf 'Package: avahi-daemon\nPackage: openssh-server\n' > "${APT_DIR}/Packages"
printf 'avahi-daemon\navahi-utils\n' > "${APT_DIR}/target-packages.txt"
printf '1\n' > "${SYSFS_DIR}/enp2s0/type"
printf 'aa:bb:cc:dd:ee:01\n' > "${SYSFS_DIR}/enp2s0/address"
ln -s "/devices/pci0000:00/0000:00:1f.6" "${SYSFS_DIR}/enp2s0/device"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMB6X2P4sR1iQ7oXnU7m9S6v7Qy7j8PqR2m4n6p8t0w1 fixture@host\n' > "${MISSION_SSH_KEY}"

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

cat > "${TARGET_DIR}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
ourbox:x:1000:1000:OurBox:/home/ourbox:/bin/bash
EOF

PATH="${BIN_DIR}:${PATH}" PACKAGE_INSTALL_LOG="${PACKAGE_INSTALL_LOG}" CURTIN_LOG="${CURTIN_LOG}" \
  "${CACHE_DIR}/configure-installed-target-ssh.sh" "${TARGET_DIR}"

[[ -f "${PACKAGE_INSTALL_LOG}" ]] || {
  echo "expected the SSH helper to invoke the offline package installer" >&2
  exit 1
}
grep -q 'installed-target-ssh-packages.txt' "${PACKAGE_INSTALL_LOG}" || {
  echo "expected configure-installed-target-ssh.sh to use the SSH package manifest" >&2
  exit 1
}
[[ -f "${TARGET_DIR}/etc/ssh/sshd_config.d/60-ourbox-installed-target.conf" ]] || {
  echo "expected SSH helper to write an sshd drop-in config" >&2
  exit 1
}
grep -q '^PasswordAuthentication yes$' "${TARGET_DIR}/etc/ssh/sshd_config.d/60-ourbox-installed-target.conf" || {
  echo "expected installed-target SSH helper to enable password authentication when requested" >&2
  exit 1
}
[[ -f "${TARGET_DIR}/home/ourbox/.ssh/authorized_keys" ]] || {
  echo "expected installed-target SSH helper to stage authorized_keys" >&2
  exit 1
}
cmp -s "${MISSION_SSH_KEY}" "${TARGET_DIR}/home/ourbox/.ssh/authorized_keys" || {
  echo "authorized_keys content did not match the staged mission SSH key" >&2
  exit 1
}
[[ "$(stat -c '%a' "${TARGET_DIR}/home/ourbox/.ssh")" == "700" ]] || {
  echo "expected .ssh directory permissions to be 700" >&2
  exit 1
}
[[ "$(stat -c '%a' "${TARGET_DIR}/home/ourbox/.ssh/authorized_keys")" == "600" ]] || {
  echo "expected authorized_keys permissions to be 600" >&2
  exit 1
}
grep -q 'systemctl enable ssh.service' "${CURTIN_LOG}" || {
  echo "expected installed-target SSH helper to enable ssh.service in the target" >&2
  exit 1
}

printf '[%s] Woodbox installed-target SSH helper smoke passed\n' "$(date -Is)"
