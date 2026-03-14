#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
FAKE_SSH_LOG="${TMP_DIR}/ssh.log"
FAKE_REMOTE_LOG="${TMP_DIR}/remote-installer.log"

cat > "${FAKE_BIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_SSH_LOG}"

user_host=""
for arg in "$@"; do
  if [[ "${arg}" == *@* ]]; then
    user_host="${arg}"
  fi
done

remote_cmd="${*: -1}"

if [[ "${user_host}" == root@* ]]; then
  exit 255
fi

if [[ "${remote_cmd}" == "true" ]]; then
  exit 0
fi

if [[ "${remote_cmd}" == *"grep -Fq --"* ]]; then
  if [[ "${FAKE_LEAK_PRESENT:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

exit 0
EOF
chmod +x "${FAKE_BIN}/ssh"

cat > "${FAKE_BIN}/sshpass" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-e" ]]; then
  shift
fi

exec "$@"
EOF
chmod +x "${FAKE_BIN}/sshpass"

run_smoke() {
  local leak_present="$1"
  local expected_status="$2"

  : > "${FAKE_SSH_LOG}"
  export FAKE_SSH_LOG FAKE_REMOTE_LOG FAKE_LEAK_PRESENT="${leak_present}"

  set +e
  PATH="${FAKE_BIN}:${PATH}" \
  SSH_PORT=22222 \
  OURBOX_INSTALLER_SSH_MODE=password \
  OURBOX_INSTALLER_SSH_USER=ourbox-installer \
  OURBOX_INSTALLER_SSH_PASSWORD="smoke-pass" \
  OURBOX_INSTALLER_SSH_ALLOW_ROOT=0 \
  REMOTE_INSTALLER_LOG_PATH="${FAKE_REMOTE_LOG}" \
  bash "${ROOT}/tools/check-installer-ssh-smoke.sh" 127.0.0.1 >/dev/null 2>&1
  status=$?
  set -e

  [[ "${status}" == "${expected_status}" ]] || {
    echo "unexpected exit status: got ${status}, expected ${expected_status}" >&2
    return 1
  }
}

run_smoke 0 0
grep -Fq "grep -Fq -- 'smoke-pass'" "${FAKE_SSH_LOG}" \
  || { echo "installer SSH smoke did not check for the actual password literal" >&2; exit 1; }
grep -Fq "BEGIN OPENSSH PRIVATE KEY" "${FAKE_SSH_LOG}" \
  || { echo "installer SSH smoke did not check for private key leakage" >&2; exit 1; }

run_smoke 1 1

echo "installer SSH log leak smoke passed"
