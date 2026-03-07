#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  check-installer-boot-smoke.sh <installer.iso>

Environment overrides:
  VM_SSH_PORT=22222
  VM_HTTP_PORT=18888
  VM_UDP_PORT=19999
  VM_MEMORY_MB=4096
  VM_CPUS=2
  BOOT_TIMEOUT_SECS=600
  OURBOX_INSTALLER_SSH_USER=ourbox-installer
  OURBOX_INSTALLER_SSH_MODE=both
  OURBOX_INSTALLER_SSH_KEY=/path/to/private_key
  OURBOX_INSTALLER_SSH_PASSWORD=<optional known live-installer password>
  OURBOX_INSTALLER_SSH_PASSWORD_STATE=generated-console-only
  OURBOX_INSTALLER_SSH_ALLOW_ROOT=0
EOF
}

need_cmd qemu-system-x86_64
need_cmd qemu-img
need_cmd ssh
need_cmd sshpass
need_cmd curl
need_cmd python3

ISO_FILE="${1:-}"
[[ -n "${ISO_FILE}" ]] || {
  usage
  exit 1
}
[[ -f "${ISO_FILE}" ]] || die "installer ISO not found: ${ISO_FILE}"

VM_SSH_PORT="${VM_SSH_PORT:-22222}"
VM_HTTP_PORT="${VM_HTTP_PORT:-18888}"
VM_UDP_PORT="${VM_UDP_PORT:-19999}"
VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
VM_CPUS="${VM_CPUS:-2}"
BOOT_TIMEOUT_SECS="${BOOT_TIMEOUT_SECS:-600}"
OURBOX_INSTALLER_SSH_USER="${OURBOX_INSTALLER_SSH_USER:-ourbox-installer}"
OURBOX_INSTALLER_SSH_MODE="${OURBOX_INSTALLER_SSH_MODE:-both}"
OURBOX_INSTALLER_SSH_KEY="${OURBOX_INSTALLER_SSH_KEY:-}"
OURBOX_INSTALLER_SSH_PASSWORD="${OURBOX_INSTALLER_SSH_PASSWORD:-}"
OURBOX_INSTALLER_SSH_PASSWORD_STATE="${OURBOX_INSTALLER_SSH_PASSWORD_STATE:-generated-console-only}"
OURBOX_INSTALLER_SSH_ALLOW_ROOT="${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-0}"
SMOKE_ARTIFACT_DIR="${OURBOX_SMOKE_ARTIFACT_DIR:-}"

if [[ -z "${OURBOX_INSTALLER_SSH_KEY}" && -z "${OURBOX_INSTALLER_SSH_PASSWORD}" ]]; then
  die "smoke test requires OURBOX_INSTALLER_SSH_KEY or OURBOX_INSTALLER_SSH_PASSWORD for initial access"
fi

TMP_DIR="$(mktemp -d)"
SERIAL_LOG="${TMP_DIR}/serial.log"
UDP_CAPTURE="${TMP_DIR}/udp.log"
OS_DISK="${TMP_DIR}/os-disk.qcow2"
DATA_DISK="${TMP_DIR}/data-disk.qcow2"
SSH_LAST_ERROR="${TMP_DIR}/ssh-last-error.log"
SSH_BANNER_DIAG="${TMP_DIR}/ssh-banner-diag.log"
HTTP_DIAG_HEADERS="${TMP_DIR}/http-diag.headers"
HTTP_DIAG_BODY="${TMP_DIR}/http-diag.body"
HTTP_DIAG_ERROR="${TMP_DIR}/http-diag.error"
QEMU_PID=""
UDP_LISTENER_PID=""
HTTP_BODY="${TMP_DIR}/monitor.html"
CLOUD_INIT_STATUS=""

cleanup() {
  local exit_code="$1"

  if [[ -n "${UDP_LISTENER_PID}" ]] && kill -0 "${UDP_LISTENER_PID}" 2>/dev/null; then
    kill "${UDP_LISTENER_PID}" 2>/dev/null || true
    wait "${UDP_LISTENER_PID}" 2>/dev/null || true
  fi

  if [[ -n "${QEMU_PID}" ]] && kill -0 "${QEMU_PID}" 2>/dev/null; then
    kill "${QEMU_PID}" 2>/dev/null || true
    wait "${QEMU_PID}" 2>/dev/null || true
  fi

  if [[ "${exit_code}" != "0" ]]; then
    if [[ -f "${SERIAL_LOG}" ]]; then
      log "Smoke VM serial log tail:"
      if [[ -s "${SERIAL_LOG}" ]]; then
        tail -n 80 "${SERIAL_LOG}" || true
      else
        printf '(serial log empty)\n'
      fi
    fi
    if [[ -f "${UDP_CAPTURE}" ]]; then
      log "Smoke VM UDP capture tail:"
      if [[ -s "${UDP_CAPTURE}" ]]; then
        tail -n 80 "${UDP_CAPTURE}" || true
      else
        printf '(UDP capture empty)\n'
      fi
    fi
  fi

  if [[ -n "${SMOKE_ARTIFACT_DIR}" ]]; then
    mkdir -p "${SMOKE_ARTIFACT_DIR}"
    cp -f "${SERIAL_LOG}" "${SMOKE_ARTIFACT_DIR}/serial.log" 2>/dev/null || true
    cp -f "${UDP_CAPTURE}" "${SMOKE_ARTIFACT_DIR}/udp.log" 2>/dev/null || true
    cp -f "${SSH_LAST_ERROR}" "${SMOKE_ARTIFACT_DIR}/ssh-last-error.log" 2>/dev/null || true
    cp -f "${SSH_BANNER_DIAG}" "${SMOKE_ARTIFACT_DIR}/ssh-banner.log" 2>/dev/null || true
    cp -f "${HTTP_DIAG_HEADERS}" "${SMOKE_ARTIFACT_DIR}/http.headers" 2>/dev/null || true
    cp -f "${HTTP_DIAG_BODY}" "${SMOKE_ARTIFACT_DIR}/http.body" 2>/dev/null || true
    cp -f "${HTTP_DIAG_ERROR}" "${SMOKE_ARTIFACT_DIR}/http.error" 2>/dev/null || true
  fi

  rm -rf "${TMP_DIR}"
}

trap 'cleanup "$?"' EXIT

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
  -p "${VM_SSH_PORT}"
)

wait_for_file_contains() {
  local file="$1" pattern="$2" timeout="$3"
  local deadline
  deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if [[ -f "${file}" ]] && grep -aFq "${pattern}" "${file}"; then
      return 0
    fi
    sleep 2
  done

  return 1
}

wait_for_http_response_contains() {
  local url="$1" timeout="$2" output_file="$3"
  shift 3

  local deadline tmp_output pattern found_all
  deadline=$((SECONDS + timeout))
  tmp_output="${output_file}.tmp"

  while (( SECONDS < deadline )); do
    if curl -fsS --max-time 5 "${url}" > "${tmp_output}" 2>/dev/null; then
      found_all="1"
      for pattern in "$@"; do
        if ! grep -Fq "${pattern}" "${tmp_output}"; then
          found_all="0"
          break
        fi
      done

      if [[ "${found_all}" == "1" ]]; then
        mv "${tmp_output}" "${output_file}"
        return 0
      fi
    fi
    sleep 2
  done

  rm -f "${tmp_output}"
  return 1
}

probe_installer_ssh() {
  local remote_cmd="$1"
  local stderr_file="${TMP_DIR}/ssh-probe.stderr"

  if installer_ssh "${remote_cmd}" >/dev/null 2>"${stderr_file}"; then
    rm -f "${stderr_file}"
    return 0
  fi

  if [[ -s "${stderr_file}" ]]; then
    cp "${stderr_file}" "${SSH_LAST_ERROR}"
  fi
  return 1
}

installer_ssh() {
  local remote_cmd="$1"

  if [[ -n "${OURBOX_INSTALLER_SSH_KEY}" ]]; then
    ssh -o BatchMode=yes "${ssh_opts[@]}" -i "${OURBOX_INSTALLER_SSH_KEY}" \
      "${OURBOX_INSTALLER_SSH_USER}@127.0.0.1" \
      "${remote_cmd}"
  else
    SSHPASS="${OURBOX_INSTALLER_SSH_PASSWORD}" sshpass -e \
      ssh "${ssh_opts[@]}" \
      "${OURBOX_INSTALLER_SSH_USER}@127.0.0.1" \
      "${remote_cmd}"
  fi
}

installer_ssh_password_only() {
  local remote_cmd="$1"
  [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD}" ]] || die "password-only SSH requested before a password was available"

  SSHPASS="${OURBOX_INSTALLER_SSH_PASSWORD}" sshpass -e \
    ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password \
      -p "${VM_SSH_PORT}" \
      "${OURBOX_INSTALLER_SSH_USER}@127.0.0.1" \
      "${remote_cmd}"
}

wait_for_remote_condition() {
  local remote_cmd="$1" timeout="$2"
  local deadline
  deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if probe_installer_ssh "${remote_cmd}"; then
      return 0
    fi
    sleep 2
  done

  return 1
}

probe_ssh_banner() {
  python3 - "${VM_SSH_PORT}" >"${SSH_BANNER_DIAG}" 2>&1 <<'PY'
import socket
import sys

port = int(sys.argv[1])

try:
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.settimeout(5)
        data = sock.recv(256)
except TimeoutError:
    print("timed out waiting for SSH banner")
    raise SystemExit(1)
except OSError as exc:
    print(f"SSH banner probe failed: {exc}")
    raise SystemExit(1)

if not data:
    print("SSH banner probe connected but received no data")
    raise SystemExit(1)

text = data.decode("utf-8", "replace").strip()
print(text)
if text.startswith("SSH-"):
    raise SystemExit(0)

raise SystemExit(1)
PY
}

capture_http_monitor_diagnostics() {
  rm -f "${HTTP_DIAG_HEADERS}" "${HTTP_DIAG_BODY}" "${HTTP_DIAG_ERROR}"

  if curl -sS --max-time 5 -D "${HTTP_DIAG_HEADERS}" \
    "http://127.0.0.1:${VM_HTTP_PORT}/" >"${HTTP_DIAG_BODY}" 2>"${HTTP_DIAG_ERROR}"; then
    return 0
  fi

  return 1
}

log_failure_diagnostics() {
  log "Installer SSH readiness diagnostics:"

  if [[ -s "${SSH_LAST_ERROR}" ]]; then
    log "Last SSH client error:"
    sed -n '1,20p' "${SSH_LAST_ERROR}" || true
  else
    log "No SSH client error text was captured."
  fi

  if probe_ssh_banner; then
    log "Observed SSH banner during failure triage:"
    sed -n '1,5p' "${SSH_BANNER_DIAG}" || true
  else
    log "No usable SSH banner during failure triage:"
    sed -n '1,5p' "${SSH_BANNER_DIAG}" || true
  fi

  if capture_http_monitor_diagnostics; then
    log "Installer HTTP monitor responded during failure triage:"
    sed -n '1,10p' "${HTTP_DIAG_HEADERS}" || true
    sed -n '1,40p' "${HTTP_DIAG_BODY}" || true
  else
    log "Installer HTTP monitor did not respond during failure triage."
    if [[ -s "${HTTP_DIAG_ERROR}" ]]; then
      sed -n '1,10p' "${HTTP_DIAG_ERROR}" || true
    fi
  fi
}

wait_for_cloud_init_healthy() {
  local deadline status
  deadline=$((SECONDS + BOOT_TIMEOUT_SECS))

  while (( SECONDS < deadline )); do
    status="$(installer_ssh "cloud-init status --long 2>/dev/null" 2>/dev/null || true)"
    if [[ -n "${status}" ]] \
      && grep -q '^status: done$' <<<"${status}" \
      && grep -q '^extended_status:' <<<"${status}" \
      && ! grep -q '^extended_status: degraded' <<<"${status}" \
      && grep -q 'DataSourceNoCloud' <<<"${status}"; then
      CLOUD_INIT_STATUS="${status}"
      return 0
    fi
    sleep 5
  done

  return 1
}

start_udp_listener() {
  python3 -u - "${VM_UDP_PORT}" "${UDP_CAPTURE}" <<'PY' &
import pathlib
import socket
import sys

port = int(sys.argv[1])
capture_path = pathlib.Path(sys.argv[2])

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", port))

with capture_path.open("ab", buffering=0) as capture:
    while True:
        data, _ = sock.recvfrom(65535)
        capture.write(data)
PY
  UDP_LISTENER_PID="$!"
}

log "Creating smoke-test disks"
qemu-img create -f qcow2 "${OS_DISK}" 24G >/dev/null
qemu-img create -f qcow2 "${DATA_DISK}" 32G >/dev/null

QEMU_ACCEL="tcg"
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  QEMU_ACCEL="kvm:tcg"
fi

log "Starting UDP capture on localhost:${VM_UDP_PORT}"
start_udp_listener

log "Booting installer ISO in QEMU (ssh=${VM_SSH_PORT} http=${VM_HTTP_PORT} udp=${VM_UDP_PORT} accel=${QEMU_ACCEL})"
qemu-system-x86_64 \
  -machine accel="${QEMU_ACCEL}" \
  -m "${VM_MEMORY_MB}" \
  -smp "${VM_CPUS}" \
  -boot d \
  -cdrom "${ISO_FILE}" \
  -drive file="${OS_DISK}",if=virtio,format=qcow2 \
  -drive file="${DATA_DISK}",if=virtio,format=qcow2 \
  -netdev user,id=n1,hostfwd=tcp::"${VM_SSH_PORT}"-:22,hostfwd=tcp::"${VM_HTTP_PORT}"-:8888 \
  -device virtio-net-pci,netdev=n1 \
  -device virtio-rng-pci \
  -display none \
  -serial file:"${SERIAL_LOG}" \
  -monitor none \
  -no-reboot \
  >/dev/null 2>&1 &
QEMU_PID="$!"

log "Waiting for installer monitor to serve initial status page"
if ! wait_for_http_response_contains \
  "http://127.0.0.1:${VM_HTTP_PORT}/" \
  180 \
  "${HTTP_BODY}" \
  "OurBox Woodbox Installer"; then
  log_failure_diagnostics
  die "timed out waiting for installer HTTP monitor"
fi

log "Waiting for live-installer SSH login to become reachable"
if ! wait_for_remote_condition "true" "${BOOT_TIMEOUT_SECS}"; then
  log_failure_diagnostics
  die "timed out waiting for installer SSH login"
fi

log "Running SSH-level smoke assertions"
ssh_smoke_env=(
  "OURBOX_INSTALLER_SSH_MODE=${OURBOX_INSTALLER_SSH_MODE}"
  "OURBOX_INSTALLER_SSH_ALLOW_ROOT=${OURBOX_INSTALLER_SSH_ALLOW_ROOT}"
  "SSH_PORT=${VM_SSH_PORT}"
  "REMOTE_INSTALLER_LOG_PATH=/run/ourbox-installer.log"
)
if [[ -n "${OURBOX_INSTALLER_SSH_KEY}" ]]; then
  ssh_smoke_env+=("OURBOX_INSTALLER_SSH_KEY=${OURBOX_INSTALLER_SSH_KEY}")
fi
if [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD}" ]]; then
  ssh_smoke_env+=("OURBOX_INSTALLER_SSH_PASSWORD=${OURBOX_INSTALLER_SSH_PASSWORD}")
fi
env "${ssh_smoke_env[@]}" bash "${ROOT}/tools/check-installer-ssh-smoke.sh" 127.0.0.1

log "Waiting for installer runtime artifacts"
wait_for_remote_condition "test -f /run/ourbox-installer.log && grep -Fq '[ourbox-bootcmd] START' /run/ourbox-installer.log" 180 \
  || die "timed out waiting for /run/ourbox-installer.log with bootcmd start marker"
wait_for_remote_condition "test -f /run/ourbox-installer-ssh-status.env && grep -qx 'OURBOX_INSTALLER_SSH_STATUS=ready' /run/ourbox-installer-ssh-status.env" 180 \
  || die "timed out waiting for installer SSH ready status"

log "Waiting for cloud-init to finish without degraded status"
wait_for_cloud_init_healthy || die "timed out waiting for healthy cloud-init status"
printf '%s\n' "${CLOUD_INIT_STATUS}"

if [[ "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" == "generated-console-only" && -z "${OURBOX_INSTALLER_SSH_PASSWORD}" ]]; then
  log "Fetching generated installer SSH password through the additive smoke key"
  wait_for_remote_condition "test -s /run/ourbox-installer-ssh-password.txt" 120 \
    || die "timed out waiting for generated installer SSH password file"
  OURBOX_INSTALLER_SSH_PASSWORD="$(installer_ssh "tr -d '\r\n' < /run/ourbox-installer-ssh-password.txt")"
  [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD}" ]] || die "generated installer SSH password was empty"
fi

log "Checking installer SSH status contract"
installer_ssh "grep -qx 'OURBOX_INSTALLER_SSH_STATUS=ready' /run/ourbox-installer-ssh-status.env"
installer_ssh "grep -qx 'OURBOX_INSTALLER_SSH_MODE=${OURBOX_INSTALLER_SSH_MODE}' /run/ourbox-installer-ssh-status.env"
installer_ssh "grep -qx 'OURBOX_INSTALLER_SSH_ALLOW_ROOT=${OURBOX_INSTALLER_SSH_ALLOW_ROOT}' /run/ourbox-installer-ssh-status.env"
installer_ssh "grep -qx 'OURBOX_INSTALLER_SSH_PASSWORD_STATE=${OURBOX_INSTALLER_SSH_PASSWORD_STATE}' /run/ourbox-installer-ssh-status.env"

if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
  log "Checking password login and root lockout"
  installer_ssh_password_only "true"
  if SSHPASS="${OURBOX_INSTALLER_SSH_PASSWORD}" sshpass -e \
    ssh \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 \
      -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password \
      -p "${VM_SSH_PORT}" \
      "root@127.0.0.1" \
      "true" >/dev/null 2>&1; then
    die "root password login unexpectedly succeeded in smoke VM"
  fi
fi

log "Waiting for installer monitor to serve the expected status page"
wait_for_http_response_contains \
  "http://127.0.0.1:${VM_HTTP_PORT}/" \
  120 \
  "${HTTP_BODY}" \
  "OurBox Woodbox Installer" \
  "ssh ${OURBOX_INSTALLER_SSH_USER}@" \
  || die "timed out waiting for installer HTTP monitor content"

log "Waiting for UDP monitor output on port ${VM_UDP_PORT}"
wait_for_file_contains "${UDP_CAPTURE}" "OurBox Woodbox Installer" 120 \
  || die "timed out waiting for installer UDP monitor traffic"

log "Checking for leaked secrets in installer surfaces"
installer_ssh "! grep -Fq '${OURBOX_INSTALLER_SSH_PASSWORD}' /run/ourbox-installer.log"
installer_ssh "! grep -Fq '${OURBOX_INSTALLER_SSH_PASSWORD}' /run/ourbox-installer-ssh-status.env"
if grep -Fq "${OURBOX_INSTALLER_SSH_PASSWORD}" "${HTTP_BODY}"; then
  die "installer HTTP monitor leaked the installer password"
fi
if grep -aFq "${OURBOX_INSTALLER_SSH_PASSWORD}" "${UDP_CAPTURE}"; then
  die "installer UDP monitor leaked the installer password"
fi

log "Installer boot smoke passed for ${ISO_FILE}"
