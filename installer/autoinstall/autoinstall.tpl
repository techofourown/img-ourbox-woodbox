#cloud-config

# OurBox Woodbox autoinstall config — RUNTIME template
# Two-pass substitution:
#   Pass 1 (build time, build-installer-iso.sh):
#     Substitutes: OURBOX_PRODUCT OURBOX_DEVICE OURBOX_TARGET OURBOX_SKU
#                  OURBOX_VARIANT OURBOX_VERSION
#   Pass 2 (install time, ourbox-preinstall):
#     Substitutes: OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH
#                  OURBOX_STORAGE_MATCH OURBOX_DATA_DISK

autoinstall:
  version: 1

  # Power off after installation so the operator knows when to remove the USB.
  # Ubuntu 24.04 Subiquity defaults to "reboot" when this key is absent, which
  # causes the machine to boot from the USB again (USB is first in EFI boot order
  # per the efibootmgr late-command) — creating a loop that repeats the installer.
  shutdown: poweroff

  locale: en_US
  keyboard:
    layout: us
    variant: ''

  # Target the specific disk the operator selected.
  # ourbox-preinstall sets OURBOX_STORAGE_MATCH to e.g. "        path: /dev/sda"
  # or "        path: /dev/nvme0n1" depending on the operator's selection.
  # Path matching is used instead of serial because Subiquity's prober reads
  # serials from sysfs verbatim, including trailing spaces that lsblk strips,
  # making serial matches fail.
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
    # -----------------------------------------------------------------------
    # [1/8] Extract staged OS payload (rootfs overlay + airgap artifacts).
    #       Payload staged by ourbox-preinstall from embedded ISO or registry.
    # -----------------------------------------------------------------------
    - echo "==> [1/8] Extracting OS payload"
    - 'echo "==>       payload: $(ls -lh /opt/ourbox/installer/cache/payload/os-payload.tar.gz 2>/dev/null || echo NOT FOUND)"'
    - rm -rf /opt/ourbox/installer/cache/payload-staging
    - mkdir -p /opt/ourbox/installer/cache/payload-staging
    - tar -xzf /opt/ourbox/installer/cache/payload/os-payload.tar.gz -C /opt/ourbox/installer/cache/payload-staging
    - echo "==>       payload extracted OK"
    - 'echo "==>       rootfs entries: $(ls /opt/ourbox/installer/cache/payload-staging/rootfs/ 2>/dev/null | head -5 | tr "\n" " ")"'
    - cp -a /opt/ourbox/installer/cache/payload-staging/rootfs/. /target/
    - mkdir -p /target/opt/ourbox/airgap
    - cp -a /opt/ourbox/installer/cache/payload-staging/airgap/. /target/opt/ourbox/airgap/
    - echo "==>       rootfs + airgap copied to /target"

    # -----------------------------------------------------------------------
    # [2/8] Install k3s binary from staged airgap payload
    # -----------------------------------------------------------------------
    - echo "==> [2/8] Installing k3s binary"
    - install -D -m 0755 /opt/ourbox/installer/cache/payload-staging/airgap/k3s/k3s /target/usr/local/bin/k3s
    - 'echo "==>       k3s installed: $(ls -lh /target/usr/local/bin/k3s 2>/dev/null)"'

    # -----------------------------------------------------------------------
    # [3/8] Append install-time provenance to /etc/ourbox/release
    # -----------------------------------------------------------------------
    - echo "==> [3/8] Appending install provenance"
    - /bin/bash /opt/ourbox/installer/cache/append-provenance.sh
    - echo "==>       provenance appended"

    # -----------------------------------------------------------------------
    # [4/8] Enable required services
    # -----------------------------------------------------------------------
    - echo "==> [4/8] Enabling OurBox services"
    - curtin in-target --target=/target -- systemctl enable ourbox-bootstrap.service
    - curtin in-target --target=/target -- systemctl enable ourbox-status.service
    - curtin in-target --target=/target -- systemctl enable avahi-daemon.service
    - curtin in-target --target=/target -- systemctl enable ourbox-mdns-aliases.service
    - curtin in-target --target=/target -- systemctl enable k3s.service
    - echo "==>       services enabled"

    # -----------------------------------------------------------------------
    # [5/8] OurBox DATA mount contract (by label).
    #       Written directly to /target/etc/fstab.
    # -----------------------------------------------------------------------
    - echo "==> [5/8] Writing OURBOX_DATA fstab entry"
    - 'mkdir -p /target/var/lib/ourbox && grep -qF "LABEL=OURBOX_DATA" /target/etc/fstab || echo "LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2" >> /target/etc/fstab'
    - echo "==>       fstab entry written"

    # -----------------------------------------------------------------------
    # [6/8] Rewrite netplan to match NIC by MAC address.
    # -----------------------------------------------------------------------
    - echo "==> [6/8] Rewriting netplan (MAC-based)"
    - 'iface=$(ip route show default 2>/dev/null | awk "{print \$5; exit}"); mac=$(cat /sys/class/net/"$iface"/address 2>/dev/null); echo "==>       iface=${iface} mac=${mac}"; [ -n "$mac" ] && printf "network:\n  version: 2\n  ethernets:\n    id0:\n      match:\n        macaddress: %s\n      dhcp4: true\n" "$mac" > /target/etc/netplan/00-installer-config.yaml'
    - echo "==>       netplan written"

    # -----------------------------------------------------------------------
    # [7/8] Verify DATA disk prepared by pre-installer after INSTALL confirmation.
    # -----------------------------------------------------------------------
    - 'echo "==> [7/8] Verifying DATA disk prepared in preinstall"'
    - 'test -n "$(blkid -L OURBOX_DATA 2>/dev/null)"'
    - 'echo "==>       OURBOX_DATA present on $(blkid -L OURBOX_DATA)"'
    - 'lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$(blkid -L OURBOX_DATA)" || true'

    # -----------------------------------------------------------------------
    # [8/8] Restore boot order. grub-install pushes itself to the front;
    #       put USB first so it's skipped cleanly when absent, falling
    #       through to the installed OS disk.
    # -----------------------------------------------------------------------
    - echo "==> [8/8] Adjusting EFI boot order"
    - efibootmgr
    - 'CURRENT=$(efibootmgr | awk "/^BootCurrent:/ {print \$2}"); OTHERS=$(efibootmgr | awk -v c="$CURRENT" "/^Boot[0-9A-F]+[*]/ {match(\$1, /Boot([0-9A-F]+)/, m); if(m[1] != c) printf m[1]\",\"}" | sed "s/,$//"); if [ -n "$CURRENT" ]; then ORDER="$CURRENT"; [ -n "$OTHERS" ] && ORDER="$CURRENT,$OTHERS"; efibootmgr --bootorder "$ORDER"; fi'
    - echo "==>       EFI boot order set (USB first, installed OS second)"

    # Clear static MOTD so only our dynamic status script runs
    - truncate -s 0 /target/etc/motd

    # Try to install NVIDIA drivers (requires internet); safe to fail.
    # If you are fully airgapped, remove this line.
    - echo "==> Attempting NVIDIA driver install (safe to fail if no internet)"
    - curtin in-target --target=/target -- /bin/bash -lc 'ubuntu-drivers install --gpgpu || true'

    - echo "==> =================================================================="
    - echo "==> OurBox late-commands complete. Machine powering off."
    - 'echo "==> When power is off: remove USB, then press power button to boot."'
    - echo "==> =================================================================="
