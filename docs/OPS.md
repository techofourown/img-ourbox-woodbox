# OPS — OurBox Woodbox

## Quick start: prepare installer media

### Default path (recommended): pull official installer from registry

```bash
./tools/prepare-installer-media.sh
```

This will:

1. Prompt you to select a target USB disk (interactive)
2. Bootstrap host dependencies (ORAS, xorriso, etc.)
3. Pull the official installer ISO from GHCR (channel `stable`, tag `x86-installer-stable`, by default)
4. Flash the ISO to the selected USB disk

Then: plug the USB into the Woodbox, boot from USB (UEFI boot menu), follow the installer
prompts, wait for the machine to power off, remove USB, boot from the selected OS disk.

During live installation, official/public media exposes a dedicated installer SSH account:
- user: `ourbox-installer`
- readiness is shown truthfully in the TTY banner and installer monitor
- when SSH is password-capable and no hash was baked, a one-time password is generated at boot and shown only on the attached console

---

### Local source-build path

```bash
./tools/prepare-installer-media.sh --build-local
```

This will:

1. Prompt you to select a target USB disk
2. Bootstrap host dependencies
3. Fetch upstream platform bundle (k3s + images + platform contract) via ORAS
4. Build OS payload locally
5. Build a fat installer ISO with the OS payload embedded (no network pull at install time)
6. Flash the ISO

Custom installer SSH posture can be set with environment overrides passed to `build-installer-iso.sh`, for example:

```bash
OURBOX_INSTALLER_SSH_MODE=key \
OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)" \
./tools/build-installer-iso.sh
```

Both the default and `--build-local` paths converge on the same rendered NoCloud seed.
`tools/build-installer-iso.sh` now validates that rendered seed as YAML before repacking the ISO.

---

### Other installer options

```bash
# Pull a specific installer ref by digest or tag
./tools/prepare-installer-media.sh --installer-ref ghcr.io/techofourown/ourbox-woodbox-installer@sha256:...

# Pull from a specific channel (short name: stable or nightly)
./tools/prepare-installer-media.sh --installer-channel nightly
```

---

## Boot + install on Woodbox

The installer is interactive. It will prompt for:

1. **OS disk selection** — any non-removable non-USB disk to install onto (will be erased; SSD/NVMe recommended)
2. **DATA disk selection** — the disk to format as `OURBOX_DATA` (ext4)
3. **OS artifact** — pulled from registry or used from embedded payload; displayed with SHA-256
4. **Hostname, username, password** — for the installed system
5. **INSTALL confirmation** — type `INSTALL` to begin

If installer SSH is ready, the banner/monitor will show:
- `ssh ourbox-installer@<installer-ip>`

For official/public media, the live-installer password is generated at boot and shown only on the attached console. It is not broadcast over UDP, HTTP, or the shared installer log.

After confirmation, the installer runs unattended (~10–15 minutes). When the machine powers off:

- Remove the USB stick
- Boot from the selected OS disk
- Wait for first-boot bootstrap (several minutes)

---

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

## Individual build steps

```bash
sudo ./tools/bootstrap-host.sh         # Install host deps (ORAS, xorriso, etc.) — idempotent

./tools/fetch-airgap-platform.sh       # Pull pinned airgap bundle + platform contract via ORAS

./tools/build-os-payload.sh            # Build OS payload tarball (rootfs overlay + airgap)

./tools/build-installer-iso.sh         # Build thin installer ISO (no payload embedded)

./tools/validate-installer-seed.sh     # Render + parse the NoCloud seed as YAML

# Or: build fat ISO with embedded OS payload (for offline operation)
./tools/build-installer-iso.sh --embed-payload deploy/os-payload-ourbox-woodbox-x86-*.tar.gz
```

For an explicit boot-level check of the installer control plane on a development machine:

```bash
OURBOX_INSTALLER_SSH_PASSWORD='ourbox-smoke-pass' \
./tools/check-installer-boot-smoke.sh deploy/installer-ourbox-woodbox-x86-*.iso
```

---

## Registry operations

```bash
# Publish OS payload and installer ISO after building
./tools/publish-os-artifact.sh deploy
./tools/publish-installer-artifact.sh deploy

# Pull OS payload or installer ISO from registry
./tools/pull-os-artifact.sh ghcr.io/techofourown/ourbox-woodbox-os:x86-stable
# Channel arg is the short channel name (stable|nightly); the x86-installer- prefix is added automatically
./tools/pull-installer-artifact.sh --channel stable
```

---

## Updating upstream platform inputs

When `sw-ourbox-os` publishes new `platform-contract` or `airgap-platform` bundles:

```bash
# 1. Resolve new digests
oras resolve ghcr.io/techofourown/sw-ourbox-os/platform-contract:edge
oras resolve ghcr.io/techofourown/sw-ourbox-os/airgap-platform:edge-amd64

# 2. Update release/official-inputs.env with the new digest-pinned refs

# 3. Pull and sync
./tools/fetch-airgap-platform.sh

# 4. Rebuild OS payload + installer; verify; open a PR
```

---

## Verify /etc/ourbox/release on an installed device

```bash
cat /etc/ourbox/release
```

Expected fields include: `OURBOX_PRODUCT`, `OURBOX_DEVICE`, `OURBOX_TARGET`, `OURBOX_SKU`,
`OURBOX_VARIANT`, `OURBOX_VERSION`, `OURBOX_RECIPE_GIT_HASH`, platform contract provenance
(`OURBOX_PLATFORM_CONTRACT_DIGEST`, etc.), and install-time provenance (`OURBOX_INSTALLER_ID`,
`OURBOX_OS_ARTIFACT_REF`, `OURBOX_OS_IMAGE_SHA256`, etc.).

---

## Troubleshooting

### k3s fails to start — memory cgroup

If `/sys/fs/cgroup/cgroup.controllers` does not include `memory`, k3s will fail:

```
failed to find memory cgroup (v2)
```

This is a kernel cmdline issue. Ubuntu 24.04 LTS enables cgroup v2 by default on modern kernels;
if you see this, check that GRUB passes the correct cgroup flags. This should not occur on stock
Ubuntu 24.04 with the default kernel.

### DATA disk not mounted at /var/lib/ourbox

Check the label:
```bash
lsblk -o NAME,LABEL,FSTYPE,MOUNTPOINTS
```

If the data disk is not labeled `OURBOX_DATA`, relabel it (destructive to the filesystem):
```bash
sudo tune2fs -L OURBOX_DATA /dev/sdX1
```

If it needs to be reformatted:
```bash
sudo /cdrom/ourbox/tools/format-data-disk.sh /dev/sdX
```

### Verify artifact provenance at install time

During installation (`ourbox-preinstall` step 3 output):
- Source: `registry` or `embedded`
- Ref: the ORAS ref used
- SHA-256: the tarball SHA-256

After installation:
```bash
cat /etc/ourbox/release | grep OURBOX_OS_
```

---

## ADR-0008 revalidation

To trigger an official republish after infrastructure maintenance without a source change,
touch `release/REVALIDATION_TRIGGER` in a PR. See that file for the documented procedure.

To run a non-publishing revalidation build:
- Use GitHub Actions → `revalidate-woodbox-build.yml` → Run workflow

---

## Reference

- `docs/ARTIFACT_PROVENANCE.md` — official artifact types, channels, and provenance requirements
- `docs/reference/contracts.md` — host contracts (release metadata, storage, installer, k3s)
- `docs/reference/installer.md` — installer defaults, artifact contract, UX flow
- `docs/reference/platform-contract.md` — upstream platform contract consumption
- `release/official-artifacts.env` — official GHCR namespaces and channel tags
- `release/official-inputs.env` — digest-pinned upstream refs for official builds
