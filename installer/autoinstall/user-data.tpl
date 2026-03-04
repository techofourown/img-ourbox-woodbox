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
  # Log file visible on TTY2 (Alt-F2) and in the journal during the live session
  - "echo '[ourbox-bootcmd] START' > /run/ourbox-bootcmd.log"

  # Make ORAS available to ourbox-preinstall for installer-time artifact pulls
  - cp /cdrom/ourbox/tools/oras /usr/local/bin/oras
  - chmod 0755 /usr/local/bin/oras
  - "echo '[ourbox-bootcmd] oras installed' >> /run/ourbox-bootcmd.log"

  - mkdir -p /opt/ourbox/tools
  - cp /cdrom/ourbox/tools/ourbox-preinstall /opt/ourbox/tools/ourbox-preinstall
  - chmod +x /opt/ourbox/tools/ourbox-preinstall
  - cp /cdrom/ourbox/tools/ourbox-preinstall.service /etc/systemd/system/ourbox-preinstall.service
  - "echo '[ourbox-bootcmd] ourbox-preinstall.service installed' >> /run/ourbox-bootcmd.log"

  # Drop-ins: make Subiquity's snap services wait for ourbox-preinstall.
  # Targets both known Ubuntu 24.04 service names for belt-and-suspenders.
  # To verify these landed: cat /run/ourbox-bootcmd.log on TTY2 after boot.
  - mkdir -p /etc/systemd/system/snap.subiquity.subiquity-server.service.d
  - "printf '[Unit]\\nAfter=ourbox-preinstall.service\\nRequires=ourbox-preinstall.service\\n' > /etc/systemd/system/snap.subiquity.subiquity-server.service.d/ourbox-wait.conf"
  - mkdir -p /etc/systemd/system/snap.subiquity.subiquity-service.service.d
  - "printf '[Unit]\\nAfter=ourbox-preinstall.service\\nRequires=ourbox-preinstall.service\\n' > /etc/systemd/system/snap.subiquity.subiquity-service.service.d/ourbox-wait.conf"
  - systemctl daemon-reload
  - "echo '[ourbox-bootcmd] subiquity drop-ins written and daemon-reloaded' >> /run/ourbox-bootcmd.log"

  # Log what subiquity snap services actually exist at this point (diagnostic)
  - "systemctl list-units --type=service --state=loaded,active,inactive,failed 2>/dev/null | grep -i subiquity >> /run/ourbox-bootcmd.log 2>&1 || echo '[ourbox-bootcmd] no subiquity units visible yet (expected at bootcmd time)' >> /run/ourbox-bootcmd.log"
  - "echo '[ourbox-bootcmd] DONE — check this file + journalctl -u ourbox-preinstall.service for diagnostics' >> /run/ourbox-bootcmd.log"

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
