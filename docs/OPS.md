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

---

## Platform contract provenance (what baseline did this image ship?)

This image repo is responsible for "boot + bootstrap," but the *platform contract* (baseline
manifests / platform components contract) is sourced from `sw-ourbox-os`.

When debugging a device, the first question is:

> "What platform contract revision/digest am I running?"

Check:

```bash
sudo cat /etc/ourbox/release
```

Look for the `OURBOX_PLATFORM_CONTRACT_*` keys:
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`
- (when available) `OURBOX_PLATFORM_CONTRACT_VERSION`
- (when available) `OURBOX_PLATFORM_CONTRACT_DIGEST`

This is the provenance boundary that keeps "official baseline" legible even before we enforce
signatures.

