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

  # Enable SSH in the live environment for interactive installer inspection.
  # Password is fixed and documented — for installer diagnostics only.
  # The installed system will use the operator-chosen password, not this one.
  - "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true"
  - "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true"
  - "echo 'ubuntu:ourbox-install' | chpasswd 2>/dev/null || true"
  - "systemctl start ssh 2>/dev/null || systemctl start openssh-server 2>/dev/null || true"
  - "echo '[ourbox-bootcmd] SSH enabled (ubuntu / ourbox-install)' >> /run/ourbox-installer.log"

  # Start avahi-daemon if available for mDNS (.local) discoverability.
  - "systemctl start avahi-daemon 2>/dev/null || true"
  - "echo '[ourbox-bootcmd] avahi-daemon start attempted' >> /run/ourbox-installer.log"

  # Copy and launch the network monitor (UDP broadcast + HTTP log server).
  # Runs in the background; tails /run/ourbox-installer.log and rebroadcasts.
  - cp /cdrom/ourbox/tools/ourbox-installer-monitor.py /run/ourbox-installer-monitor.py
  - "python3 /run/ourbox-installer-monitor.py >> /run/ourbox-installer.log 2>&1 &"
  - "echo '[ourbox-bootcmd] network monitor started' >> /run/ourbox-installer.log"
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
  # To verify these landed: ssh ubuntu@<ip> and cat /run/ourbox-installer.log
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
