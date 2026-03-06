#cloud-config

# Ubuntu Server autoinstall — cloud-init seed (build-time rendered)
#
# This file is rendered at USB BUILD TIME by build-installer-iso.sh
# and placed at /cdrom/nocloud/user-data on the installer ISO.
#
# Its primary jobs:
#   1. bootcmd: inject ourbox-preinstall.service into the live system early,
#      before Subiquity starts, so OurBox controls TTY1 first.
#   2. autoinstall: minimal placeholder so Subiquity knows autoinstall mode
#      is active. The REAL config (/autoinstall.yaml) is written by
#      ourbox-preinstall at install time.

# cloud-init bootcmd runs during cloud-init-local.service — before networking,
# before Subiquity snap services start. We use it to inject our systemd service
# and drop-ins so that Subiquity waits for ourbox-preinstall to finish first.
bootcmd:
  # All bootcmd log lines go to /run/ourbox-installer.log — the same file tailed
  # by ourbox-installer-monitor.py for UDP broadcast and HTTP viewing.
  - "echo '[ourbox-bootcmd] START' > /run/ourbox-installer.log"

  # --- Network monitoring setup -------------------------------------------
  # Set a stable hostname so the machine is discoverable as
  # ourbox-woodbox-installer.local on the network.
  - hostname ourbox-woodbox-installer
  - "echo 'ourbox-woodbox-installer' > /etc/hostname"
  - "echo '[ourbox-bootcmd] hostname set to ourbox-woodbox-installer' >> /run/ourbox-installer.log"

  # Configure installer-time SSH using a dedicated diagnostics account.
  # Load optional overrides from /cdrom/ourbox/installer/defaults.env:
  #   OURBOX_INSTALLER_SSH_MODE=off|key|password|both
  #   OURBOX_INSTALLER_SSH_USER=ourbox-installer
  #   OURBOX_INSTALLER_SSH_PASSWORD_HASH='$6$...' (blank => generated at boot)
  #   OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAA...'
  #   OURBOX_INSTALLER_SSH_ALLOW_ROOT=0|1
  - |
      /bin/bash <<'EOF'
      set -uo pipefail

      LOG_FILE="/run/ourbox-installer.log"
      DEFAULTS_FILE="/cdrom/ourbox/installer/defaults.env"
      STATUS_FILE="/run/ourbox-installer-ssh-status.env"
      PASSWORD_FILE="/run/ourbox-installer-ssh-password.txt"

      write_status_file() {
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

      generate_installer_ssh_password() {
        local generated_password generated_hash

        generated_password="$(
          openssl rand -base64 18 2>/dev/null \
            | tr -d '\n' \
            | tr '/+' '89' \
            | cut -c1-20
        )"
        [[ -n "${generated_password}" ]] || return 1

        generated_hash="$(printf '%s' "${generated_password}" | openssl passwd -6 -stdin 2>/dev/null)" || return 1
        [[ -n "${generated_hash}" ]] || return 1

        umask 077
        printf '%s\n' "${generated_password}" > "${PASSWORD_FILE}" || return 1

        OURBOX_INSTALLER_SSH_PASSWORD_HASH="${generated_hash}"
        OURBOX_INSTALLER_SSH_PASSWORD_STATE="generated-console-only"
        return 0
      }

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

      case "${OURBOX_INSTALLER_SSH_MODE}" in
        off|key|password|both) ;;
        *)
          echo "[ourbox-bootcmd] WARNING: invalid installer SSH mode '${OURBOX_INSTALLER_SSH_MODE}'; defaulting to both" >> "${LOG_FILE}"
          OURBOX_INSTALLER_SSH_MODE="both"
          ;;
      esac

      rm -f "${PASSWORD_FILE}"

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
          echo "[ourbox-bootcmd] installer SSH password generated for attached console" >> "${LOG_FILE}"
        else
          OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
          echo "[ourbox-bootcmd] ERROR: could not generate installer SSH password" >> "${LOG_FILE}"
        fi
      fi

      write_status_file

      if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" ]]; then
        if ! id -u "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1; then
          adduser --disabled-password --gecos "" "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 \
            || useradd -m -s /bin/bash "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1
        fi

        if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
          if [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]]; then
            if ! echo "${OURBOX_INSTALLER_SSH_USER}:${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" | chpasswd -e >/dev/null 2>&1; then
              OURBOX_INSTALLER_SSH_PASSWORD_STATE="error"
              echo "[ourbox-bootcmd] ERROR: failed to apply installer SSH password hash" >> "${LOG_FILE}"
            fi
          fi
        else
          passwd -l "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 || true
        fi

        SSH_HOME="$(getent passwd "${OURBOX_INSTALLER_SSH_USER}" | awk -F: '{print $6}' | head -n1)"
        if [[ -z "${SSH_HOME}" ]]; then
          SSH_HOME="/home/${OURBOX_INSTALLER_SSH_USER}"
        fi
        SSH_GROUP="$(id -gn "${OURBOX_INSTALLER_SSH_USER}" 2>/dev/null || printf '%s' "${OURBOX_INSTALLER_SSH_USER}")"
        SSH_DIR="${SSH_HOME}/.ssh"
        SSH_AUTH_KEYS="${SSH_DIR}/authorized_keys"

        install -d -m 0700 "${SSH_DIR}"
        chown "${OURBOX_INSTALLER_SSH_USER}:${SSH_GROUP}" "${SSH_DIR}"

        if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "key" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
          if [[ -n "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" ]]; then
            printf '%s\n' "${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS}" > "${SSH_AUTH_KEYS}"
            chown "${OURBOX_INSTALLER_SSH_USER}:${SSH_GROUP}" "${SSH_AUTH_KEYS}"
            chmod 0600 "${SSH_AUTH_KEYS}"
          else
            rm -f "${SSH_AUTH_KEYS}"
          fi
        else
          rm -f "${SSH_AUTH_KEYS}"
        fi
      fi

      HAS_USABLE_AUTH="0"
      if [[ "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" == "configured-hash" || "${OURBOX_INSTALLER_SSH_PASSWORD_STATE}" == "generated-console-only" ]]; then
        HAS_USABLE_AUTH="1"
      fi
      if [[ "${OURBOX_INSTALLER_SSH_KEY_STATE}" == "configured" ]]; then
        HAS_USABLE_AUTH="1"
      fi
      if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" && "${HAS_USABLE_AUTH}" != "1" ]]; then
        echo "[ourbox-bootcmd] ERROR: installer SSH has no usable auth path (mode=${OURBOX_INSTALLER_SSH_MODE})" >> "${LOG_FILE}"
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
      } > /etc/ssh/sshd_config.d/60-ourbox-installer.conf

      install -d -m 0755 /run/sshd
      ssh-keygen -A >> "${LOG_FILE}" 2>&1 || true
      if sshd -t >> "${LOG_FILE}" 2>&1; then
        if systemctl restart ssh >/dev/null 2>&1 \
          || systemctl restart openssh-server >/dev/null 2>&1 \
          || systemctl --no-block start ssh >/dev/null 2>&1 \
          || systemctl --no-block start openssh-server >/dev/null 2>&1; then
          if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "off" ]]; then
            OURBOX_INSTALLER_SSH_STATUS="disabled"
            echo "[ourbox-bootcmd] SSH disabled by installer media config" >> "${LOG_FILE}"
          elif [[ "${HAS_USABLE_AUTH}" == "1" ]]; then
            OURBOX_INSTALLER_SSH_STATUS="ready"
            echo "[ourbox-bootcmd] SSH ready (user=${OURBOX_INSTALLER_SSH_USER} mode=${OURBOX_INSTALLER_SSH_MODE} root=${OURBOX_INSTALLER_SSH_ALLOW_ROOT} password=${OURBOX_INSTALLER_SSH_PASSWORD_STATE} key=${OURBOX_INSTALLER_SSH_KEY_STATE})" >> "${LOG_FILE}"
          else
            OURBOX_INSTALLER_SSH_STATUS="error"
            echo "[ourbox-bootcmd] ERROR: sshd started but installer SSH is not usable" >> "${LOG_FILE}"
          fi
        else
          OURBOX_INSTALLER_SSH_STATUS="error"
          echo "[ourbox-bootcmd] ERROR: sshd config valid but ssh service restart/start failed" >> "${LOG_FILE}"
        fi
      else
        OURBOX_INSTALLER_SSH_STATUS="error"
        echo "[ourbox-bootcmd] ERROR: sshd -t failed for /etc/ssh/sshd_config.d/60-ourbox-installer.conf" >> "${LOG_FILE}"
      fi
      write_status_file
      EOF

  # Start avahi-daemon if available for mDNS (.local) discoverability.
  - "systemctl --no-block start avahi-daemon 2>/dev/null || true"
  - "echo '[ourbox-bootcmd] avahi-daemon start queued' >> /run/ourbox-installer.log"

  # Copy and launch the network monitor (UDP broadcast + HTTP log server).
  # Runs in the background; tails /run/ourbox-installer.log and rebroadcasts.
  - "cp /cdrom/ourbox/tools/ourbox-installer-monitor.py /run/ourbox-installer-monitor.py 2>/dev/null || true"
  - "python3 /run/ourbox-installer-monitor.py >> /run/ourbox-installer.log 2>&1 &"
  - "echo '[ourbox-bootcmd] network monitor launch requested' >> /run/ourbox-installer.log"
  # --- End network monitoring setup ----------------------------------------

  # Make ORAS available to ourbox-preinstall for installer-time artifact pulls
  - cp /cdrom/ourbox/tools/oras /usr/local/bin/oras
  - chmod 0755 /usr/local/bin/oras
  - "echo '[ourbox-bootcmd] oras installed' >> /run/ourbox-installer.log"

  - mkdir -p /opt/ourbox/tools
  - cp /cdrom/ourbox/tools/ourbox-preinstall /opt/ourbox/tools/ourbox-preinstall
  - chmod +x /opt/ourbox/tools/ourbox-preinstall
  - cp /cdrom/ourbox/tools/ourbox-preinstall.service /etc/systemd/system/ourbox-preinstall.service
  - "echo '[ourbox-bootcmd] ourbox-preinstall.service installed' >> /run/ourbox-installer.log"

  # Drop-ins: make Subiquity's snap services wait for ourbox-preinstall.
  # Targets both known Ubuntu 24.04 service names for belt-and-suspenders.
  # To verify these landed: ssh ourbox-installer@<ip> and cat /run/ourbox-installer.log
  - mkdir -p /etc/systemd/system/snap.subiquity.subiquity-server.service.d
  - "printf '[Unit]\\nAfter=ourbox-preinstall.service\\nRequires=ourbox-preinstall.service\\n' > /etc/systemd/system/snap.subiquity.subiquity-server.service.d/ourbox-wait.conf"
  - mkdir -p /etc/systemd/system/snap.subiquity.subiquity-service.service.d
  - "printf '[Unit]\\nAfter=ourbox-preinstall.service\\nRequires=ourbox-preinstall.service\\n' > /etc/systemd/system/snap.subiquity.subiquity-service.service.d/ourbox-wait.conf"
  - systemctl daemon-reload
  - "echo '[ourbox-bootcmd] subiquity drop-ins written and daemon-reloaded' >> /run/ourbox-installer.log"

  # Log what subiquity snap services exist at bootcmd time (diagnostic).
  # Expected: none visible yet — snap seeding hasn't started.
  - "systemctl list-units --type=service --state=loaded,active,inactive,failed 2>/dev/null | grep -i subiquity >> /run/ourbox-installer.log 2>&1 || echo '[ourbox-bootcmd] no subiquity units visible yet (expected)' >> /run/ourbox-installer.log"
  - "echo '[ourbox-bootcmd] DONE' >> /run/ourbox-installer.log"

autoinstall:
  version: 1

  # No interactive-sections: the real config (written by ourbox-preinstall)
  # has none, so Subiquity runs fully automated once it starts.

  # Power off so the operator knows when to remove the USB.
  # Ubuntu 24.04 Subiquity defaults to "reboot" when this is absent.
  shutdown: poweroff

  locale: en_US
  keyboard:
    layout: us
    variant: ''

  # Fallback identity (never used if ourbox-preinstall runs successfully,
  # because it overwrites /autoinstall.yaml before Subiquity starts).
  identity:
    hostname: ${OURBOX_HOSTNAME}
    username: ${OURBOX_USERNAME}
    password: ${OURBOX_PASSWORD_HASH}

  storage:
    layout:
      name: lvm
      match:
        ssd: true

  ssh:
    install-server: true
    allow-pw: true
