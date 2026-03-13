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

# shellcheck disable=SC1091
source "${ROOT}/installer/ourbox-preinstall/ourbox-installer-ssh-bootstrap.sh"
trap - EXIT TERM INT HUP

restart_ssh_service

grep -Fxq -- "--no-block restart ssh" "${SYSTEMCTL_LOG}" \
  || { echo "missing non-blocking restart attempt for ssh"; exit 1; }
grep -Fxq -- "--no-block start ssh" "${SYSTEMCTL_LOG}" \
  || { echo "missing non-blocking start attempt for ssh"; exit 1; }
