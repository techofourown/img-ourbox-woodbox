#cloud-config

# OurBox Woodbox autoinstall config — RUNTIME template
# Two-pass substitution:
#   Pass 1 (build time, build-installer-iso.sh):
#     Substitutes: OURBOX_PRODUCT OURBOX_DEVICE OURBOX_TARGET OURBOX_SKU
#                  OURBOX_VARIANT OURBOX_VERSION
#   Pass 2 (install time, ourbox-preinstall):
#     Substitutes: OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH
#                  OURBOX_STORAGE_MATCH

autoinstall:
  version: 1

  locale: en_US
  keyboard:
    layout: us
    variant: ''

  # Target the specific disk the operator selected.
  # ourbox-preinstall sets OURBOX_STORAGE_MATCH to either:
  #   "        serial: <serial>"  (when disk has a serial number)
  #   "        ssd: true"         (fallback when serial is unavailable)
  storage:
    layout:
      name: lvm
      match:
${OURBOX_STORAGE_MATCH}

  identity:
    hostname: ${OURBOX_HOSTNAME}
    username: ${OURBOX_USERNAME}
    password: ${OURBOX_PASSWORD_HASH}

  ssh:
    install-server: true
    allow-pw: true

  packages:
    - curl
    - ca-certificates
    - openssl
    - xz-utils
    - jq
    - avahi-daemon
    - avahi-utils

  late-commands:
    # Copy OurBox overlay rootfs into the installed system
    # (includes /etc/ourbox/release written by build-installer-iso.sh)
    - curtin in-target --target=/target -- /bin/bash -lc 'echo "==> Installing OurBox rootfs overlay"'
    - cp -a /cdrom/ourbox/rootfs/. /target/

    # Copy airgap payloads into /opt/ourbox/airgap
    - curtin in-target --target=/target -- /bin/bash -lc 'echo "==> Copying airgap artifacts"'
    - mkdir -p /target/opt/ourbox/airgap
    - cp -a /cdrom/ourbox/airgap/. /target/opt/ourbox/airgap/

    # Install k3s binary from airgap payload
    - install -D -m 0755 /cdrom/ourbox/airgap/k3s/k3s /target/usr/local/bin/k3s

    # Enable required services
    - curtin in-target --target=/target -- systemctl enable ourbox-bootstrap.service
    - curtin in-target --target=/target -- systemctl enable ourbox-status.service
    - curtin in-target --target=/target -- systemctl enable avahi-daemon.service
    - curtin in-target --target=/target -- systemctl enable ourbox-mdns-aliases.service

    # OurBox DATA mount contract (by label)
    - curtin in-target --target=/target -- /bin/bash -lc '
        set -euo pipefail
        FSTAB_LINE="LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2"
        mkdir -p /var/lib/ourbox
        if ! grep -qF "LABEL=OURBOX_DATA /var/lib/ourbox" /etc/fstab; then
          echo "${FSTAB_LINE}" >> /etc/fstab
        fi
      '

    # Clear static MOTD so only our dynamic status script runs
    - curtin in-target --target=/target -- truncate -s 0 /etc/motd

    # Try to install NVIDIA drivers (requires internet); safe to fail.
    # If you are fully airgapped, remove this line.
    - curtin in-target --target=/target -- /bin/bash -lc 'ubuntu-drivers install --gpgpu || true'
