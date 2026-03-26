# OPS — OurBox Woodbox

## Quick start: compose Woodbox mission media

Use the unified host-side installer repo as the operator front door:

```bash
cd sw-ourbox-installer
./tools/prepare-installer-media.sh
```

This will:

1. Resolve the selected OS payload on the trusted host
2. Resolve the selected `ourbox-substrate` bundle on the trusted host
3. Pull and verify those bytes locally
4. Pull the published Woodbox installer substrate artifact
5. Compose Woodbox mission media using the adapter in this repo
6. Optionally flash the resulting media to a USB device

The published installer substrate now also carries the tiny local APT repo the
installed target still needs, so official mission-media installs do not consult
Ubuntu package mirrors.

Then: plug the USB into the Woodbox, boot from USB (UEFI boot menu), follow the installer
prompts, wait for the machine to power off, remove USB, boot from the selected OS disk.
The installer also attempts to prefer the installed OS for the next UEFI boot when possible.

During live installation, official/public media exposes a dedicated installer SSH account:
- user: `ourbox-installer`
- readiness is shown truthfully in the TTY banner and installer monitor
- when SSH is password-capable and no hash was baked, a one-time password is generated at boot and shown only on the attached console
- when the mission media stages an installed-target SSH key, that same public key is also accepted by the live installer account

---

This repo still owns substrate/payload build steps and the Woodbox adapter.
Custom installer SSH posture can be set with environment overrides passed to
`build-installer-iso.sh`, for example:

```bash
OURBOX_INSTALLER_SSH_MODE=key \
OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)" \
./tools/build-installer-iso.sh
```

`tools/build-installer-iso.sh` validates the rendered NoCloud seed as YAML
before repacking the ISO.

## Boot + install on Woodbox

The installer is interactive. It will prompt for:

0. **Optional installer SSH password** — set a temporary password for `ourbox-installer`, or press Enter to keep the current media posture
1. **OS disk selection** — any non-removable non-USB disk to install onto (will be erased; SSD/NVMe recommended)
2. **DATA disk selection** — the disk to format as `OURBOX_DATA` (ext4)
3. **OS payload** — loaded from embedded mission media and displayed with SHA-256
4. **Apps bundle** — staged from embedded mission media; no target-side registry access
5. **Hostname, username, password** — for the installed system
6. **INSTALL confirmation** — type `INSTALL` to begin

If installer SSH is ready, the banner/monitor will show:
- `ssh ourbox-installer@<installer-ip>`

For official/public media, the live-installer password is generated at boot and shown only on the attached console. It is not broadcast over UDP, HTTP, or the shared installer log.
If you set a password in step 0, that operator-chosen password replaces the generated installer password for the rest of the live install session.

After confirmation, the installer runs unattended (~10–15 minutes). When the machine powers off:

- Remove the USB stick
- Boot from the selected OS disk
- Wait for first-boot bootstrap (several minutes)

The installer attempts to prefer the installed OS for the next and future UEFI boots, but USB
removal after poweroff is still recommended.

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

./tools/fetch-ourbox-substrate.sh      # Pull pinned ourbox-substrate bundle + platform contract via ORAS

./tools/build-os-payload.sh            # Build OS payload tarball (rootfs overlay + substrate)

./tools/build-installer-iso.sh         # Build installer substrate ISO (not a standalone install path)

./tools/validate-installer-seed.sh     # Render + parse the NoCloud seed as YAML

# Or: build mission media by embedding both payload and mission directory
./tools/build-installer-iso.sh \
  --embed-payload deploy/os-payload-ourbox-woodbox-x86-*.tar.gz \
  --embed-payload-meta deploy/os-payload-ourbox-woodbox-x86-*.meta.env \
  --embed-mission-dir /path/to/prepared-mission-dir
```

For an explicit boot-level check of the installer control plane on a development machine:

```bash
OURBOX_INSTALLER_SSH_PASSWORD='ourbox-smoke-pass' \
./tools/check-installer-boot-smoke.sh deploy/installer-ourbox-woodbox-x86-*.iso
```

---

## Registry operations

```bash
# Publish OS payload and installer substrate ISO after building
./tools/publish-os-artifact.sh deploy
./tools/publish-installer-artifact.sh deploy

# Pull OS payload or installer substrate ISO from registry
./tools/pull-os-artifact.sh ghcr.io/techofourown/ourbox-woodbox-os:x86-stable
# Channel arg is the short channel name (stable|nightly); the x86-installer- prefix is added automatically
./tools/pull-installer-artifact.sh --channel stable
```

The published installer artifact is substrate only. Supported operator installs
still require host-composed mission media from `sw-ourbox-installer`.

---

## Updating upstream platform inputs

When `sw-ourbox-os` publishes new `platform-contract` or `ourbox-substrate` bundles:

```bash
# 1. Approve the new upstream snapshot in sw-ourbox-os and take the generated lockfile PR

# 2. Pull and sync
./tools/fetch-ourbox-substrate.sh

# 3. Rebuild OS payload/substrate as needed; then compose mission media via sw-ourbox-installer
```

---

## Verify /etc/ourbox/release on an installed device

```bash
cat /etc/ourbox/release
```

Expected fields include: `OURBOX_PRODUCT`, `OURBOX_DEVICE`, `OURBOX_TARGET`, `OURBOX_SKU`,
`OURBOX_VARIANT`, `OURBOX_VERSION`, `OURBOX_RECIPE_GIT_HASH`, build timing
(`OURBOX_BUILD_TS`), and install-time provenance such as `OURBOX_INSTALLER_ID`,
`OURBOX_OS_ARTIFACT_REF`, `OURBOX_OS_IMAGE_SHA256`, `OURBOX_SUBSTRATE_REF`,
and `OURBOX_SELECTED_APPLICATION_IDS`.

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
- Source: `mission`
- Ref: the host-selected artifact ref staged onto the mission media
- SHA-256: the tarball SHA-256

After installation:
```bash
cat /etc/ourbox/release | grep OURBOX_OS_
```

---

## ADR-0008 revalidation

To trigger an official republish after infrastructure maintenance without a source change:
- Use GitHub Actions → `official-candidate.yml` → Run workflow (select `main`, enter a reason)

> **Deprecated**: the old `release/REVALIDATION_TRIGGER` PR path still works but creates
> unnecessary ceremony. Prefer the workflow_dispatch button.

To run a non-publishing revalidation build:
- Use GitHub Actions → `revalidate-woodbox-build.yml` → Run workflow

---

## Reference

- `docs/ARTIFACT_PROVENANCE.md` — official artifact types, channels, and provenance requirements
- `docs/reference/contracts.md` — host contracts (release metadata, storage, installer, k3s)
- `docs/reference/installer.md` — installer defaults, artifact contract, UX flow
- `docs/reference/platform-contract.md` — upstream platform contract consumption
- `release/official-artifacts.env` — official GHCR namespaces and channel tags
- `tools/approved-upstream-inputs.upstream.env` — repo-local pointer to the approved upstream snapshot
