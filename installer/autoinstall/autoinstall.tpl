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
  # ourbox-preinstall sets OURBOX_STORAGE_MATCH to "        path: /dev/nvme0n1"
  # (or whichever device the operator picked).  Path matching is used instead
  # of serial because Subiquity's prober reads serials from sysfs verbatim,
  # including trailing spaces that lsblk strips, making serial matches fail.
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

    # OurBox DATA mount contract (by label).
    # Written directly to /target/etc/fstab — late-commands run in the live
    # env with the target already mounted, so curtin in-target is not needed.
    # Single-line to avoid YAML plain-scalar newline folding (bash exit 2).
    - 'mkdir -p /target/var/lib/ourbox && grep -qF "LABEL=OURBOX_DATA" /target/etc/fstab || echo "LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2" >> /target/etc/fstab'

    # Rewrite netplan to match any en* interface by wildcard so DHCP works
    # regardless of whether the installed kernel names the NIC enp1s0, enp2s0, etc.
    # Subiquity writes the config based on the live-installer's PCI enumeration,
    # which differs from the installed system (NVMe changes slot ordering).
    - 'printf "network:\n  version: 2\n  ethernets:\n    id0:\n      match:\n        name: \"en*\"\n      dhcp4: true\n" > /target/etc/netplan/00-installer-config.yaml'

    # Format the operator-selected DATA disk as OURBOX_DATA.
    # Skips if OURBOX_DATA label already exists (idempotent).
    - '/bin/bash /cdrom/ourbox/tools/format-data-disk.sh ${OURBOX_DATA_DISK}'

    # Clear static MOTD so only our dynamic status script runs
    - truncate -s 0 /target/etc/motd

    # Try to install NVIDIA drivers (requires internet); safe to fail.
    # If you are fully airgapped, remove this line.
    - curtin in-target --target=/target -- /bin/bash -lc 'ubuntu-drivers install --gpgpu || true'
