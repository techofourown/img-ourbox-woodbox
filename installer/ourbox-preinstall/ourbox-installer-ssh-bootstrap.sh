#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${LOG_FILE:-/run/ourbox-installer.log}"
DEFAULTS_FILE="${DEFAULTS_FILE:-/cdrom/ourbox/installer/defaults.env}"
STATUS_FILE="${STATUS_FILE:-/run/ourbox-installer-ssh-status.env}"
PASSWORD_FILE="${PASSWORD_FILE:-/run/ourbox-installer-ssh-password.txt}"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssh/sshd_config.d/60-ourbox-installer.conf}"

OURBOX_INSTALLER_SSH_STATUS="pending"
OURBOX_INSTALLER_SSH_USER="ourbox-installer"
OURBOX_INSTALLER_SSH_MODE="both"
OURBOX_INSTALLER_SSH_ALLOW_ROOT="0"
OURBOX_INSTALLER_SSH_PASSWORD_STATE="disabled"
OURBOX_INSTALLER_SSH_KEY_STATE="disabled"
OURBOX_INSTALLER_SSH_PASSWORD_HASH=""
OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS=""

GENERATED_PASSWORD=""

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
  local deadline=$((SECONDS + 30))

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
  systemctl --no-block restart ssh >/dev/null 2>&1 \
    || systemctl --no-block restart openssh-server >/dev/null 2>&1 \
    || systemctl --no-block start ssh >/dev/null 2>&1 \
    || systemctl --no-block start openssh-server >/dev/null 2>&1
}

assert_valid_mode() {
  case "${OURBOX_INSTALLER_SSH_MODE}" in
    off|key|password|both) ;;
    *)
      log "WARNING: invalid installer SSH mode '${OURBOX_INSTALLER_SSH_MODE}'; defaulting to both"
      OURBOX_INSTALLER_SSH_MODE="both"
      ;;
  esac

  case "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" in
    0|1) ;;
    *)
      log "WARNING: invalid installer SSH root flag '${OURBOX_INSTALLER_SSH_ALLOW_ROOT}'; defaulting to 0"
      OURBOX_INSTALLER_SSH_ALLOW_ROOT="0"
      ;;
  esac
}

ensure_user() {
  if id -u "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1; then
    return 0
  fi

  adduser --disabled-password --gecos "" "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 \
    || useradd -m -s /bin/bash "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1
}

configure_authorized_keys() {
  local ssh_home ssh_group ssh_dir ssh_auth_keys

  ssh_home="$(getent passwd "${OURBOX_INSTALLER_SSH_USER}" | awk -F: '{print $6}' | head -n1)"
  if [[ -z "${ssh_home}" ]]; then
    ssh_home="/home/${OURBOX_INSTALLER_SSH_USER}"
  fi
  ssh_group="$(id -gn "${OURBOX_INSTALLER_SSH_USER}" 2>/dev/null || printf '%s' "${OURBOX_INSTALLER_SSH_USER}")"
  ssh_dir="${ssh_home}/.ssh"
  ssh_auth_keys="${ssh_dir}/authorized_keys"

  install -d -m 0700 "${ssh_dir}"
  chown "${OURBOX_INSTALLER_SSH_USER}:${ssh_group}" "${ssh_dir}"

  if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "key" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
    if [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
      printf '%s\n' "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" > "${ssh_auth_keys}"
      chown "${OURBOX_INSTALLER_SSH_USER}:${ssh_group}" "${ssh_auth_keys}"
      chmod 0600 "${ssh_auth_keys}"
    else
      rm -f "${ssh_auth_keys}"
    fi
  else
    rm -f "${ssh_auth_keys}"
  fi
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
  OURBOX_INSTALLER_SSH_STATUS="pending"
  OURBOX_INSTALLER_SSH_PASSWORD_STATE="disabled"
  OURBOX_INSTALLER_SSH_KEY_STATE="disabled"

  assert_valid_mode
  clear_password_file

  if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "key" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
    if [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
      OURBOX_INSTALLER_SSH_KEY_STATE="configured"
    else
      OURBOX_INSTALLER_SSH_KEY_STATE="absent"
    fi
  fi

  if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
    if [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]]; then
      OURBOX_INSTALLER_SSH_PASSWORD_STATE="configured-hash"
    elif command -v openssl >/dev/null 2>&1 && generate_installer_ssh_password; then
      log "installer SSH password generated for attached console"
    else
      OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
      log "ERROR: could not generate installer SSH password"
      write_status_file
    fi
  fi

  write_status_file

  if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" ]]; then
    if ! ensure_user; then
      OURBOX_INSTALLER_SSH_STATUS="error"
      OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
      log "ERROR: failed to create installer SSH user '${OURBOX_INSTALLER_SSH_USER}'"
      finalize_status
      return 1
    fi
    log "installer SSH user ensured"

    if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
      if [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]]; then
        if ! printf '%s:%s\n' "${OURBOX_INSTALLER_SSH_USER}" "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" | chpasswd -e >/dev/null 2>&1; then
          OURBOX_INSTALLER_SSH_STATUS="error"
          OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
          log "ERROR: failed to apply installer SSH password hash"
          finalize_status
          return 1
        fi
      fi
    else
      passwd -l "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 || true
    fi

    if ! configure_authorized_keys; then
      OURBOX_INSTALLER_SSH_STATUS="error"
      log "ERROR: failed to configure installer SSH authorized_keys"
      finalize_status
      return 1
    fi

    log "installer SSH auth material prepared"
  fi

  local has_usable_auth="0"
  if [[ "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" == "configured-hash" || "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" == "generated-console-only" ]]; then
    has_usable_auth="1"
  fi
  if [[ "${OURBOX_INSTALLER_SSH_KEY_STATE}" == "configured" ]]; then
    has_usable_auth="1"
  fi
  if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" && "${has_usable_auth}" != "1" ]]; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: installer SSH has no usable auth path (mode=${OURBOX_INSTALLER_SSH_MODE})"
    write_status_file
    return 1
  fi

  mkdir -p /etc/ssh/sshd_config.d
  {
    if [[ "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" == "1" ]]; then
      if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
        echo "PermitRootLogin prohibit-password"
      else
        echo "PermitRootLogin yes"
      fi
    else
      echo "PermitRootLogin no"
    fi

    if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
      echo "PasswordAuthentication yes"
    else
      echo "PasswordAuthentication no"
    fi

    echo "PubkeyAuthentication yes"
    echo "KbdInteractiveAuthentication no"
    echo "X11Forwarding no"
    echo "AllowTcpForwarding no"

    if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "off" ]]; then
      if [[ "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" == "1" ]]; then
        echo "AllowUsers root"
      else
        echo "AllowUsers nobody"
      fi
    else
      if [[ "${OURBOX_INSTALLER_SSH_ALLOW_ROOT}" == "1" ]]; then
        echo "AllowUsers ${OURBOX_INSTALLER_SSH_USER} root"
      else
        echo "AllowUsers ${OURBOX_INSTALLER_SSH_USER}"
      fi
    fi
  } > "${CONFIG_FILE}"
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

  if [[ "${has_usable_auth}" != "1" ]]; then
    OURBOX_INSTALLER_SSH_STATUS="error"
    log "ERROR: sshd started but installer SSH is not usable"
    finalize_status
    return 1
  fi

  OURBOX_INSTALLER_SSH_STATUS="ready"
  log "SSH ready (user=${OURBOX_INSTALLER_SSH_USER} mode=${OURBOX_INSTALLER_SSH_MODE} root=${OURBOX_INSTALLER_SSH_ALLOW_ROOT} password=${OURBOX_INSTALLER_SSH_PASSWORD_STATE} key=${OURBOX_INSTALLER_SSH_KEY_STATE})"
  finalize_status
}

main "$@"
