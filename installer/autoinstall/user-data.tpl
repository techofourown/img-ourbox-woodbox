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
  #   OURBOX_INSTALLER_SSH_PASSWORD_HASH='$6$...'
  #   OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAA...'
  #   OURBOX_INSTALLER_SSH_ALLOW_ROOT=0|1
  - |
      /bin/bash <<'EOF'
      set -uo pipefail

      LOG_FILE="/run/ourbox-installer.log"
      DEFAULTS_FILE="/cdrom/ourbox/installer/defaults.env"

      if [[ -f "${DEFAULTS_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${DEFAULTS_FILE}"
      fi

      if [[ -z "${OURBOX_INSTALLER_SSH_MODE:-}" ]]; then
        case "$(printf '%s' "${OURBOX_VARIANT:-prod}" | tr '[:upper:]' '[:lower:]')" in
          dev|support|debug|diag|diagnostic|lab|labs) OURBOX_INSTALLER_SSH_MODE="both" ;;
          *) OURBOX_INSTALLER_SSH_MODE="key" ;;
        esac
      fi
      OURBOX_INSTALLER_SSH_USER="${OURBOX_INSTALLER_SSH_USER:-ourbox-installer}"
      DEFAULT_INSTALLER_SSH_PASSWORD_HASH='$6$ourboxinstall$GgJGorVZ2X.yl0cQk8yIqYDawhEuB47d9m.k9t9HP1afvwC3ALmMxTDtKT2NjDBMqkUOVzvm7LK2ZHxBt2KxH1'
      OURBOX_INSTALLER_SSH_PASSWORD_HASH="${OURBOX_INSTALLER_SSH_PASSWORD_HASH:-${DEFAULT_INSTALLER_SSH_PASSWORD_HASH}}"
      OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS="${OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS:-}"
      OURBOX_INSTALLER_SSH_ALLOW_ROOT="${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-0}"

      case "${OURBOX_INSTALLER_SSH_MODE}" in
        off|key|password|both) ;;
        *) OURBOX_INSTALLER_SSH_MODE="key" ;;
      esac

      if [[ "${OURBOX_INSTALLER_SSH_MODE}" != "off" ]]; then
        if ! id -u "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1; then
          adduser --disabled-password --gecos "" "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1 \
            || useradd -m -s /bin/bash "${OURBOX_INSTALLER_SSH_USER}" >/dev/null 2>&1
        fi

        if [[ "${OURBOX_INSTALLER_SSH_MODE}" == "password" || "${OURBOX_INSTALLER_SSH_MODE}" == "both" ]]; then
          if [[ -n "${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" ]]; then
            echo "${OURBOX_INSTALLER_SSH_USER}:${OURBOX_INSTALLER_SSH_PASSWORD_HASH}" | chpasswd -e >/dev/null 2>&1 || true
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
      if sshd -t >/dev/null 2>&1; then
        if systemctl restart ssh >/dev/null 2>&1 \
          || systemctl restart openssh-server >/dev/null 2>&1 \
          || systemctl --no-block start ssh >/dev/null 2>&1 \
          || systemctl --no-block start openssh-server >/dev/null 2>&1; then
          echo "[ourbox-bootcmd] SSH ready (user=${OURBOX_INSTALLER_SSH_USER} mode=${OURBOX_INSTALLER_SSH_MODE} root=${OURBOX_INSTALLER_SSH_ALLOW_ROOT})" >> "${LOG_FILE}"
        else
          echo "[ourbox-bootcmd] ERROR: sshd config valid but ssh service restart/start failed" >> "${LOG_FILE}"
        fi
      else
        echo "[ourbox-bootcmd] ERROR: sshd -t failed for /etc/ssh/sshd_config.d/60-ourbox-installer.conf" >> "${LOG_FILE}"
      fi
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
