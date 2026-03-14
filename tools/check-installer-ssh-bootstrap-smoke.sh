#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

FAKEBIN="${TMPDIR}/bin"
mkdir -p "${FAKEBIN}"
SYSTEMCTL_LOG="${TMPDIR}/systemctl.log"

cat > "${FAKEBIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SYSTEMCTL_LOG:?}"
if [[ "${1:-}" == "--no-block" ]]; then
  shift
fi
if [[ "${1:-}" == "restart" && "${2:-}" == "ssh" ]]; then
  exit 1
fi
if [[ "${1:-}" == "start" && "${2:-}" == "ssh" ]]; then
  exit 0
fi
exit 1
EOF
chmod +x "${FAKEBIN}/systemctl"

export PATH="${FAKEBIN}:${PATH}"
export SYSTEMCTL_LOG
export OURBOX_INSTALLER_SSH_BOOTSTRAP_LIBRARY_ONLY=1
export STATUS_FILE="${TMPDIR}/ssh-status.env"
export PASSWORD_FILE="${TMPDIR}/ssh-password.txt"
export MISSION_AUTHORIZED_KEY_FILE="${TMPDIR}/mission-authorized-key.pub"

printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG7WcC1e1Tt3WkFq6kL9oM9l2u9A2u9mM4nP0FQ2j8xS fixture@host\n' \
  > "${MISSION_AUTHORIZED_KEY_FILE}"

# shellcheck disable=SC1091
source "${ROOT}/installer/ourbox-preinstall/ourbox-installer-ssh-bootstrap.sh"
trap - EXIT TERM INT HUP

export OURBOX_INSTALLER_SSH_MODE="both"
export OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS=""
load_mission_authorized_key_if_present
expected_key="$(cat "${MISSION_AUTHORIZED_KEY_FILE}")"
[[ "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" == "${expected_key}" ]] || {
  echo "expected staged mission SSH key to be loaded into installer SSH posture" >&2
  exit 1
}

export OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS=$'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBbakedexistingkey1234567890 baked@host'
load_mission_authorized_key_if_present
[[ "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" == *"AAAAC3NzaC1lZDI1NTE5AAAAIBbakedexistingkey1234567890 baked@host"* ]] || {
  echo "expected baked installer SSH key to be preserved" >&2
  exit 1
}
[[ "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" == *"${expected_key}"* ]] || {
  echo "expected staged mission SSH key to be merged alongside baked installer SSH keys" >&2
  exit 1
}

restart_ssh_service

grep -Fxq -- "--no-block restart ssh" "${SYSTEMCTL_LOG}" \
  || { echo "missing non-blocking restart attempt for ssh"; exit 1; }
grep -Fxq -- "--no-block start ssh" "${SYSTEMCTL_LOG}" \
  || { echo "missing non-blocking start attempt for ssh"; exit 1; }

export OURBOX_INSTALLER_SSH_STATUS="ready"
export OURBOX_INSTALLER_SSH_USER="ourbox-installer"
export OURBOX_INSTALLER_SSH_MODE="both"
export OURBOX_INSTALLER_SSH_ALLOW_ROOT="0"
export OURBOX_INSTALLER_SSH_PASSWORD_STATE="configured-hash"
export OURBOX_INSTALLER_SSH_KEY_STATE="configured"
write_status_file

status_mode="$(stat -c '%a' "${STATUS_FILE}")"
[[ "${status_mode}" == "644" ]] || {
  echo "expected installer SSH status file mode 644, got ${status_mode}" >&2
  exit 1
}
