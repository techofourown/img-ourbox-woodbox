#cloud-config

# OurBox Woodbox autoinstall config — RUNTIME template
# Two-pass substitution:
#   Pass 1 (build time, build-installer-iso.sh):
#     Substitutes: OURBOX_PRODUCT OURBOX_DEVICE OURBOX_TARGET OURBOX_SKU
#                  OURBOX_VARIANT OURBOX_VERSION
#   Pass 2 (install time, ourbox-preinstall):
#     Substitutes: OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH
#                  OURBOX_STORAGE_MATCH OURBOX_DATA_DISK OURBOX_TARGET_DISK

autoinstall:
  version: 1

  # Power off after installation so the operator has a clear media-removal seam.
  # The late-commands also try to prefer the installed OS for subsequent UEFI
  # boots, but poweroff remains the simplest and least surprising operator flow.
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
    # [8/8] Prefer the installed EFI entry on the selected target disk.
    #       Do not use BootCurrent here: during external-media installs it
    #       identifies the installer transport, not the desired post-install
    #       default. Instead, resolve the target ESP mounted at /target/boot/efi,
    #       identify the Ubuntu loader on that ESP, set BootNext for the
    #       immediate next boot, and move that entry to the front of BootOrder
    #       while preserving the relative order of everything else.
    # -----------------------------------------------------------------------
    - echo "==> [8/8] Preferring installed EFI boot entry"
    - |
        set -e
        EFI_STATUS_FILE="/run/ourbox-efi-boot-preference.env"
        write_efi_status() {
          printf 'OURBOX_EFI_BOOT_STATUS=%s\n' "$1" > "${EFI_STATUS_FILE}"
        }
        rm -f "${EFI_STATUS_FILE}"
        TARGET_DISK_REAL="$(readlink -f "${OURBOX_TARGET_DISK}" 2>/dev/null || true)"
        TARGET_DISK_NAME="$(basename "${TARGET_DISK_REAL}" 2>/dev/null || true)"
        ESP_SRC="$(findmnt -nr -o SOURCE /target/boot/efi 2>/dev/null || true)"
        if [ -z "${ESP_SRC}" ]; then
          echo "==>       WARNING: /target/boot/efi is not mounted; skipping EFI boot preference update"
          echo "==>       WARNING: remove the USB before the next power-on or the installer may boot again"
          write_efi_status warning
          exit 0
        fi
        ESP_REAL="$(readlink -f "${ESP_SRC}" 2>/dev/null || true)"
        if [ -z "${ESP_REAL}" ]; then
          echo "==>       WARNING: could not resolve target ESP device from ${ESP_SRC}; skipping EFI boot preference update"
          echo "==>       WARNING: remove the USB before the next power-on or the installer may boot again"
          write_efi_status warning
          exit 0
        fi
        ESP_PARTUUID="$(blkid -s PARTUUID -o value "${ESP_REAL}" 2>/dev/null | tr "[:upper:]" "[:lower:]")"
        if [ -z "${ESP_PARTUUID}" ]; then
          echo "==>       WARNING: target ESP PARTUUID unavailable for ${ESP_REAL}; skipping EFI boot preference update"
          echo "==>       WARNING: remove the USB before the next power-on or the installer may boot again"
          write_efi_status warning
          exit 0
        fi
        if [ -n "${TARGET_DISK_NAME}" ]; then
          ESP_PARENT="$(lsblk -no PKNAME "${ESP_REAL}" 2>/dev/null | head -n1)"
          if [ -n "${ESP_PARENT}" ] && [ "${ESP_PARENT}" != "${TARGET_DISK_NAME}" ]; then
            echo "==>       WARNING: target ESP ${ESP_REAL} belongs to ${ESP_PARENT}, expected ${TARGET_DISK_NAME}; skipping EFI boot preference update"
            echo "==>       WARNING: remove the USB before the next power-on or the installer may boot again"
            write_efi_status warning
            exit 0
          fi
        fi
        echo "==>       target disk: ${TARGET_DISK_REAL:-unknown}"
        echo "==>       target ESP : ${ESP_REAL}"
        echo "==>       PARTUUID   : ${ESP_PARTUUID}"
        cat > /target/tmp/ourbox-adjust-efi-order.sh <<'SCRIPT'
        #!/bin/bash
        set -euo pipefail

        esp_partuuid="${1:-}"
        target_disk="${2:-unknown}"
        soft_skip() {
          echo "$1"
          exit 10
        }

        if ! command -v efibootmgr >/dev/null 2>&1; then
          soft_skip "==>       efibootmgr not installed in target; skipping EFI boot preference update"
        fi
        if [[ -z "${esp_partuuid}" ]]; then
          soft_skip "==>       target ESP PARTUUID unavailable; skipping EFI boot preference update"
        fi

        efi_before="$(efibootmgr -v || true)"
        printf '%s\n' "${efi_before}"

        order="$(printf '%s\n' "${efi_before}" | awk -F': ' '/^BootOrder:/ {print $2; exit}')"
        if [[ -z "${order}" ]]; then
          soft_skip "==>       WARNING: BootOrder unavailable; skipping EFI boot preference update"
        fi

        install_entry="$(
          printf '%s\n' "${efi_before}" | awk -v esp="${esp_partuuid}" '
            {
              line = tolower($0)
              if (index(line, "gpt," tolower(esp)) &&
                  (index(line, "file(\\efi\\ubuntu\\shimx64.efi)") ||
                   index(line, "file(\\efi\\ubuntu\\grubx64.efi)"))) {
                entry = $1
                sub(/^Boot/, "", entry)
                sub(/\*.*/, "", entry)
                print toupper(entry)
                exit
              }
            }'
        )"
        if [[ -z "${install_entry}" ]]; then
          install_entry="$(
            printf '%s\n' "${efi_before}" | awk -v esp="${esp_partuuid}" '
              {
                line = tolower($0)
                if (index(line, "gpt," tolower(esp)) &&
                    index(line, "file(\\efi\\ubuntu\\")) {
                  entry = $1
                  sub(/^Boot/, "", entry)
                  sub(/\*.*/, "", entry)
                  print toupper(entry)
                  exit
                }
              }'
          )"
        fi
        if [[ -z "${install_entry}" ]]; then
          soft_skip "==>       WARNING: could not identify installed EFI entry for target disk ${target_disk} (ESP ${esp_partuuid})"
        fi

        new_order="${install_entry}"
        IFS=',' read -r -a order_entries <<< "${order}"
        for entry in "${order_entries[@]}"; do
          entry="${entry^^}"
          [[ -n "${entry}" ]] || continue
          [[ "${entry}" == "${install_entry}" ]] && continue
          new_order="${new_order},${entry}"
        done

        bootnext_failed=0
        bootorder_failed=0
        echo "==>       installed EFI entry: ${install_entry}"
        echo "==>       BootNext -> ${install_entry}"
        echo "==>       BootOrder -> ${new_order}"
        if ! efibootmgr --bootnext "${install_entry}"; then
          bootnext_failed=1
          echo "==>       WARNING: failed to set BootNext to ${install_entry}"
        fi
        if ! efibootmgr --bootorder "${new_order}"; then
          bootorder_failed=1
          echo "==>       WARNING: failed to set BootOrder to ${new_order}"
        fi
        efibootmgr -v || true
        if [[ "${bootnext_failed}" -eq 1 && "${bootorder_failed}" -eq 1 ]]; then
          exit 1
        fi
        SCRIPT
        chmod 0755 /target/tmp/ourbox-adjust-efi-order.sh
        if curtin in-target --target=/target -- /tmp/ourbox-adjust-efi-order.sh "${ESP_PARTUUID}" "${TARGET_DISK_REAL:-unknown}"; then
          rm -f /target/tmp/ourbox-adjust-efi-order.sh
          write_efi_status preferred
        else
          status=$?
          rm -f /target/tmp/ourbox-adjust-efi-order.sh
          case "${status}" in
            10)
              echo "==>       WARNING: EFI boot preference was not updated confidently"
              ;;
            *)
              echo "==>       WARNING: EFI boot preference update failed with exit ${status}"
              ;;
          esac
          echo "==>       WARNING: remove the USB before the next power-on or the installer may boot again"
          write_efi_status warning
          exit 0
        fi
    - echo "==>       Installed EFI boot entry preferred when possible"

    # Clear static MOTD so only our dynamic status script runs
    - truncate -s 0 /target/etc/motd

    # Try to install NVIDIA drivers (requires internet); safe to fail.
    # If you are fully airgapped, remove this line.
    - echo "==> Attempting NVIDIA driver install (safe to fail if no internet)"
    - curtin in-target --target=/target -- /bin/bash -lc 'ubuntu-drivers install --gpgpu || true'

    - echo "==> =================================================================="
    - echo "==> OurBox late-commands complete. Machine powering off."
    - |
        EFI_STATUS_FILE="/run/ourbox-efi-boot-preference.env"
        OURBOX_EFI_BOOT_STATUS="warning"
        if [ -f "${EFI_STATUS_FILE}" ]; then
          # shellcheck disable=SC1090
          . "${EFI_STATUS_FILE}"
        fi
        if [ "${OURBOX_EFI_BOOT_STATUS}" = "preferred" ]; then
          echo "==> Installer preferred the installed OS for the next UEFI boot when possible."
          echo "==> When power is off: remove USB, then press power button to boot."
        else
          echo "==> WARNING: EFI boot preference was not updated confidently."
          echo "==> WARNING: remove the USB before the next power-on or the installer may boot again."
          echo "==> When power is off: remove USB, then press power button to boot."
        fi
    - echo "==> =================================================================="
