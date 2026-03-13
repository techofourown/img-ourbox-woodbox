#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${LOG_FILE:-/run/ourbox-installer.log}"
DEFAULTS_FILE="${DEFAULTS_FILE:-/cdrom/ourbox/installer/defaults.env}"
STATUS_FILE="${STATUS_FILE:-/run/ourbox-installer-ssh-status.env}"
PASSWORD_FILE="${PASSWORD_FILE:-/run/ourbox-installer-ssh-password.txt}"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssh/sshd_config.d/60-ourbox-installer.conf}"
HELPER_FILE="${HELPER_FILE:-/cdrom/ourbox/tools/installer-ssh-helper.sh}"

OURBOX_INSTALLER_SSH_STATUS="pending"
OURBOX_INSTALLER_SSH_USER="ourbox-installer"
OURBOX_INSTALLER_SSH_MODE="both"
OURBOX_INSTALLER_SSH_ALLOW_ROOT="0"
OURBOX_INSTALLER_SSH_PASSWORD_STATE="disabled"
OURBOX_INSTALLER_SSH_KEY_STATE="disabled"
OURBOX_INSTALLER_SSH_PASSWORD_HASH=""
OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS=""

GENERATED_PASSWORD=""
: "${OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS:=180}"

log() {
  printf '[ourbox-bootcmd] %s\n' "$*"
}

write_status_file() {
  umask 077
  printf '%s\n' \
    "OURBOX_INSTALLER_SSH_STATUS=${OURBOX_INSTALLER_SSH_STATUS}" \
    "OURBOX_INSTALLER_SSH_USER=${OURBOX_INSTALLER_SSH_USER}" \
    "OURBOX_INSTALLER_SSH_MODE=${OURBOX_INSTALLER_SSH_MODE}" \
    "OURBOX_INSTALLER_SSH_ALLOW_ROOT=${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" \
    "OURBOX_INSTALLER_SSH_PASSWORD_STATE=${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" \
    "OURBOX_INSTALLER_SSH_KEY_STATE=${OURBOX_INSTALLER_SSH_KEY_STATE}" \
    > "${STATUS_FILE}"
  chmod 0600 "${STATUS_FILE}" >/dev/null 2>&1 || true
}

clear_password_file() {
  rm -f "${PASSWORD_FILE}"
}

write_password_file_if_ready() {
  clear_password_file

  if [[ "${OURBOX_INSTALLER_SSH_STATUS}" != "ready" ]]; then
    return 0
  fi
  if [[ "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" != "generated-console-only" ]]; then
    return 0
  fi
  [[ -n "${GENERATED_PASSWORD}" ]] || return 0

  umask 077
  printf '%s\n' "${GENERATED_PASSWORD}" > "${PASSWORD_FILE}"
  chmod 0600 "${PASSWORD_FILE}" >/dev/null 2>&1 || true
}

finalize_status() {
  write_password_file_if_ready
  write_status_file
}

on_exit() {
  local exit_code="$1"
  if [[ "${exit_code}" != "0" && "${OURBOX_INSTALLER_SSH_STATUS}" == "pending" ]]; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
    log "ERROR: installer SSH bootstrap exited unexpectedly"
  fi
  finalize_status
}

on_signal() {
  OURBOX_INSTALLER_SSH_STATUS="error"
  if [[ "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" == "disabled" ]]; then
    OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
  fi
  log "ERROR: installer SSH bootstrap terminated by signal"
  finalize_status
  exit 1
}

trap 'on_exit "$?"' EXIT
trap on_signal TERM
trap on_signal INT
trap on_signal HUP

wait_for_local_ssh_banner() {
  local deadline=$((SECONDS + OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS))

  while (( SECONDS < deadline )); do
    if python3 - <<'PY' >/dev/null 2>&1
import socket
try:
    with socket.create_connection(("127.0.0.1", 22), timeout=2) as sock:
        sock.settimeout(2)
        data = sock.recv(64)
    raise SystemExit(0 if data.startswith(b"SSH-") else 1)
except OSError:
    raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done

  return 1
}

generate_installer_ssh_password() {
  local salt generated_hash

  GENERATED_PASSWORD="$(openssl rand -hex 16 2>/dev/null)" || return 1
  GENERATED_PASSWORD="${GENERATED_PASSWORD:0:20}"
  [[ ${#GENERATED_PASSWORD} -eq 20 ]] || return 1

  salt="$(printf '%s' "${GENERATED_PASSWORD}" | sha256sum | awk '{print substr($1,1,16)}')" || return 1
  generated_hash="$(printf '%s' "${GENERATED_PASSWORD}" | openssl passwd -6 -stdin -salt "${salt}" 2>/dev/null)" || return 1
  [[ -n "${generated_hash}" ]] || return 1

  OURBOX_INSTALLER_SSH_PASSWORD_HASH="${generated_hash}"
  OURBOX_INSTALLER_SSH_PASSWORD_STATE="generated-console-only"
  return 0
}

restart_ssh_service() {
  local unit=""
  local action=""

  for unit in ssh openssh-server; do
    for action in restart start; do
      log "installer SSH attempting: systemctl --no-block ${action} ${unit}"
      if timeout 15 systemctl --no-block "${action}" "${unit}" >/dev/null 2>&1; then
        log "installer SSH requested: systemctl --no-block ${action} ${unit}"
        return 0
      fi
    done
  done

  return 1
}

main() {
  log "installer SSH bootstrap begin"

  if [[ -f "${DEFAULTS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${DEFAULTS_FILE}"
  fi

  OURBOX_INSTALLER_SSH_MODE="${OURBOX_INSTALLER_SSH_MODE:-both}"
  OURBOX_INSTALLER_SSH_USER="${OURBOX_INSTALLER_SSH_USER:-ourbox-installer}"
  OURBOX_INSTALLER_SSH_PASSWORD_HASH="${OURBOX_INSTALLER_SSH_PASSWORD_HASH:-}"
  OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS="${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS:-}"
  OURBOX_INSTALLER_SSH_ALLOW_ROOT="${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-0}"
  OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY:-1}"
  OURBOX_INSTALLER_SSH_STATUS="pending"
  OURBOX_INSTALLER_SSH_PASSWORD_STATE="disabled"
  OURBOX_INSTALLER_SSH_KEY_STATE="disabled"

  [[ -f "${HELPER_FILE}" ]] || {
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: missing installer SSH helper: ${HELPER_FILE}"
    finalize_status
    return 1
  }

  # shellcheck disable=SC1090
  source "${HELPER_FILE}"

  ourbox_installer_ssh_log() {
    log "$*"
  }

  if ! ourbox_installer_ssh_normalize_inputs; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    finalize_status
    return 1
  fi

  if ! ourbox_installer_ssh_validate_requested_posture; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    finalize_status
    return 1
  fi

  clear_password_file

  if ourbox_installer_ssh_mode_has_keys; then
    if [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
      OURBOX_INSTALLER_SSH_KEY_STATE="configured"
    else
      OURBOX_INSTALLER_SSH_KEY_STATE="absent"
    fi
  fi

  if ourbox_installer_ssh_mode_has_password; then
    if [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]]; then
      OURBOX_INSTALLER_SSH_PASSWORD_STATE="configured-hash"
    else
      OURBOX_INSTALLER_SSH_PASSWORD_STATE="absent"
      if [[ "${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}" == "1" ]]; then
        if command -v openssl >/dev/null 2>&1 && generate_installer_ssh_password; then
          log "installer SSH password generated for attached console"
        else
          OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
          log "ERROR: could not generate installer SSH password"
        fi
      fi
    fi
  fi

  write_status_file

  if ! ourbox_installer_ssh_validate_materialized_auth; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: installer SSH has no usable auth path (mode=${OURBOX_INSTALLER_SSH_MODE})"
    finalize_status
    return 1
  fi

  if ! ourbox_installer_ssh_apply_common_state "${CONFIG_FILE}"; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    finalize_status
    return 1
  fi
  if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" ]]; then
    log "installer SSH auth material prepared"
  fi
  log "installer SSH config written"

  install -d -m 0755 /run/sshd
  log "installer SSH host key generation starting"
  if ! timeout 60 ssh-keygen -A >> "${LOG_FILE}" 2>&1; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: ssh-keygen -A failed or timed out"
    finalize_status
    return 1
  fi

  if ! sshd -t >> "${LOG_FILE}" 2>&1; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: sshd -t failed for ${CONFIG_FILE}"
    finalize_status
    return 1
  fi
  log "installer SSH config validated"

  log "installer SSH service start requested"
  if ! restart_ssh_service; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: sshd config valid but ssh service restart/start failed"
    finalize_status
    return 1
  fi

  if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "off" ]]; then
    OURBOX_INSTALLER_SSH_STATUS="disabled"
    log "SSH disabled by installer media config"
    finalize_status
    return 0
  fi

  if ! wait_for_local_ssh_banner; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: sshd start was requested but no local SSH banner was observed"
    finalize_status
    return 1
  fi

  OURBOX_INSTALLER_SSH_STATUS="ready"
  log "SSH ready (user=${OURBOX_INSTALLER_SSH_USER} mode=${OURBOX_INSTALLER_SSH_MODE} root=${OURBOX_INSTALLER_SSH_ALLOW_ROOT} password=${OURBOX_INSTALLER_SSH_PASSWORD_STATE} key=${OURBOX_INSTALLER_SSH_KEY_STATE})"
  finalize_status
}

if [[ "${OURBOX_INSTALLER_SSH_BOOTSTRAP_LIBRARY_ONLY:-0}" == "1" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

main "$@"
