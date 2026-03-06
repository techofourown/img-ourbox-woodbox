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
need_cmd nc
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

if [[ -z "${OURBOX_INSTALLER_SSH_KEY}" && -z "${OURBOX_INSTALLER_SSH_PASSWORD}" ]]; then
  die "smoke test requires OURBOX_INSTALLER_SSH_KEY or OURBOX_INSTALLER_SSH_PASSWORD for initial access"
fi

TMP_DIR="$(mktemp -d)"
SERIAL_LOG="${TMP_DIR}/serial.log"
UDP_CAPTURE="${TMP_DIR}/udp.log"
OS_DISK="${TMP_DIR}/os-disk.qcow2"
DATA_DISK="${TMP_DIR}/data-disk.qcow2"
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
      tail -n 80 "${SERIAL_LOG}" || true
    fi
    if [[ -f "${UDP_CAPTURE}" ]]; then
      log "Smoke VM UDP capture tail:"
      tail -n 80 "${UDP_CAPTURE}" || true
    fi
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

wait_for_port() {
  local port="$1" timeout="$2"
  local deadline
  deadline=$((SECONDS + timeout))

  while (( SECONDS < deadline )); do
    if nc -z -w 2 127.0.0.1 "${port}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

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

installer_ssh() {
  local remote_cmd="$1"

  if [[ -n "${OURBOX_INSTALLER_SSH_KEY}" ]]; then
    ssh "${ssh_opts[@]}" -i "${OURBOX_INSTALLER_SSH_KEY}" \
      "${OURBOX_INSTALLER_SSH_USER}@127.0.0.1" \
      "${remote_cmd}"
    return 0
  fi

  SSHPASS="${OURBOX_INSTALLER_SSH_PASSWORD}" sshpass -e \
    ssh "${ssh_opts[@]}" \
      "${OURBOX_INSTALLER_SSH_USER}@127.0.0.1" \
      "${remote_cmd}"
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
    if installer_ssh "${remote_cmd}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
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
  -display none \
  -serial file:"${SERIAL_LOG}" \
  -monitor none \
  -no-reboot \
  >/dev/null 2>&1 &
QEMU_PID="$!"

log "Waiting for live-installer SSH to become reachable"
wait_for_port "${VM_SSH_PORT}" "${BOOT_TIMEOUT_SECS}" || die "timed out waiting for installer SSH on localhost:${VM_SSH_PORT}"

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

log "Waiting for installer monitor on port ${VM_HTTP_PORT}"
wait_for_port "${VM_HTTP_PORT}" 120 || die "timed out waiting for installer HTTP monitor on localhost:${VM_HTTP_PORT}"
curl -fsS "http://127.0.0.1:${VM_HTTP_PORT}/" > "${HTTP_BODY}"
grep -Fq "OurBox Woodbox Installer" "${HTTP_BODY}" || die "installer HTTP monitor response did not contain the expected header"
grep -Fq "ssh ${OURBOX_INSTALLER_SSH_USER}@" "${HTTP_BODY}" || \
  die "installer HTTP monitor response did not advertise installer SSH"

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
