# OPS — OurBox Woodbox

## Build + flash installer media (interactive)

```bash
./tools/prepare-installer-media.sh
```

What it does:

1. Installs host dependencies (podman/docker + xorriso + basics)
2. Downloads Ubuntu Server ISO (pinned in `tools/versions.env`)
3. Fetches airgap payloads (k3s + image tars)
4. Builds a custom installer ISO that contains:
   - NoCloud autoinstall config
   - OurBox rootfs overlay
   - Airgap artifacts
5. Flashes the ISO to a selected USB disk (destructive)

## Boot + install on Woodbox

- Boot from the USB installer
- The installer will prompt you to:
  - choose hostname/username/password
  - choose the **SYSTEM** disk (NVMe)
  - choose/format the **DATA** disk and ensure it is `ext4` labeled `OURBOX_DATA`

After installation completes:

- Remove USB media
- Boot from NVMe
- Wait for first-boot bootstrap (several minutes)

## Post-boot checks

```bash
findmnt /var/lib/ourbox
systemctl status ourbox-bootstrap --no-pager || true
systemctl status k3s --no-pager || true
woodbox status
```

If ready, you should be able to reach:

- `http://<hostname>.local`
- `http://files.<hostname>.local`
- `http://notes.<hostname>.local`
- `http://todo.<hostname>.local`

