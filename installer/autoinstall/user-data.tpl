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
  - mkdir -p /opt/ourbox/tools
  - cp /cdrom/ourbox/tools/ourbox-preinstall /opt/ourbox/tools/ourbox-preinstall
  - chmod +x /opt/ourbox/tools/ourbox-preinstall
  - cp /cdrom/ourbox/tools/ourbox-preinstall.service /etc/systemd/system/ourbox-preinstall.service
  - mkdir -p /etc/systemd/system/snap.subiquity.subiquity-server.service.d
  - "printf '[Unit]\\nAfter=ourbox-preinstall.service\\nRequires=ourbox-preinstall.service\\n' > /etc/systemd/system/snap.subiquity.subiquity-server.service.d/ourbox-wait.conf"
  - mkdir -p /etc/systemd/system/snap.subiquity.subiquity-service.service.d
  - "printf '[Unit]\\nAfter=ourbox-preinstall.service\\nRequires=ourbox-preinstall.service\\n' > /etc/systemd/system/snap.subiquity.subiquity-service.service.d/ourbox-wait.conf"
  - systemctl daemon-reload

autoinstall:
  version: 1

  # No interactive-sections: the real config (written by ourbox-preinstall)
  # has none, so Subiquity runs fully automated once it starts.

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
