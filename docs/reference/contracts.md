# OurBox Woodbox host contracts

This repo produces a Woodbox OS payload and installer substrate that guarantee a
small set of host/runtime contracts. These contracts are the interface between
build-time artifact production, host-composed mission media, and the installed
runtime.

## Contract: Release metadata

### File

- `/etc/ourbox/release`

### Format

Line-oriented `KEY=VALUE` pairs (shell-friendly). Fields written at build time:

- `OURBOX_PRODUCT`
- `OURBOX_DEVICE`
- `OURBOX_TARGET`
- `OURBOX_SKU`
- `OURBOX_VARIANT`
- `OURBOX_VERSION`
- `OURBOX_RECIPE_GIT_HASH`
- `OURBOX_SUBSTRATE_REF`
- `OURBOX_SUBSTRATE_DIGEST`
- `OURBOX_SUBSTRATE_SOURCE`
- `OURBOX_SUBSTRATE_REVISION`
- `OURBOX_SUBSTRATE_VERSION`
- `OURBOX_SUBSTRATE_CREATED`
- `OURBOX_SUBSTRATE_ARCH`
- `OURBOX_SUBSTRATE_PROFILE`
- `OURBOX_SUBSTRATE_K3S_VERSION`
- `OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256`
- `OURBOX_BUILD_TS`

Fields appended at install time by autoinstall late-commands:

- `OURBOX_INSTALLER_ID`
- `OURBOX_INSTALLER_VERSION`
- `OURBOX_INSTALLER_GIT_HASH`
- `OURBOX_OS_ARTIFACT_SOURCE`
- `OURBOX_OS_ARTIFACT_REF`
- `OURBOX_OS_ARTIFACT_DIGEST`
- `OURBOX_OS_IMAGE_SHA256`
- `OURBOX_INSTALL_SELECTION_SOURCE`
- `OURBOX_RELEASE_CHANNEL`

Legacy `OURBOX_PLATFORM_CONTRACT_*` fields may still appear on transitional
payloads or installed systems, but they are informational only and not the
normative compatibility surface.

### Why it exists

- debugging ("what build is on this device?")
- fleet management ("what should this be running?")
- predictable support ("we can reproduce your image")

See `docs/reference/platform-contract.md` for the full platform-input model.

## Contract: Storage (DATA disk)

### Rule

- The DATA drive is ext4 with filesystem label `OURBOX_DATA`
- It mounts at `/var/lib/ourbox`

### Implementation

`/etc/fstab` includes a label-based mount:

```fstab
LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2
```

Key properties:

- uses LABEL rather than a fixed device path, so device enumeration changes do
  not break the mount
- uses `nofail` so the system can boot without the data disk
- uses a short systemd timeout to avoid slow boots

### Intended contents of `/var/lib/ourbox`

This is where higher-level stacks store persistent state:

- k3s storage and persistent volumes
- application state
- logs, if desired

Exact directory layout is owned by the platform layer.

## Contract: Installer flow

Mission media is the only supported Woodbox install path.

Mission media contains:

- installer substrate
- embedded OS payload
- substrate-local target package repo
- embedded mission manifest
- embedded selected `ourbox-substrate` bundle

Install flow:

1. Operator boots Woodbox mission media
2. `ourbox-preinstall` loads installer-local defaults from
   `/cdrom/ourbox/installer/defaults.env`
3. Operator may set a temporary password for the live-installer SSH account, or
   press Enter to keep the current installer SSH posture
4. `ourbox-preinstall` stages the embedded OS payload into
   `/opt/ourbox/installer/cache/payload/`
5. `ourbox-preinstall` reads mission-selected OS and `ourbox-substrate`
   provenance from the embedded mission manifest
6. `ourbox-preinstall` prepares offline target helpers, including local package
   installation and netplan rendering from hardware inventory
7. Operator confirms disk selection, identity, and `INSTALL`
8. Autoinstall late-commands extract the staged OS payload to `/target/`

The target does not browse catalogs, resolve refs, or pull artifacts during
install. The target also does not consult remote package mirrors during
install; required Ubuntu packages come only from the substrate-local APT repo.

Compatibility is enforced by exact selected artifact identities plus local
bundle-shape and runtime-capability checks. It is not enforced by duplicated
platform-contract metadata.

Installer substrate artifacts may still exist as host-composition inputs, but
they are not a supported standalone install path.

### Payload cache path

- `/opt/ourbox/installer/cache/payload/os-payload.tar.gz`
- `/opt/ourbox/installer/cache/payload/os-payload.tar.gz.sha256`
- `/opt/ourbox/installer/cache/payload/payload.meta.env`

### Installer defaults file (baked into ISO)

- `/cdrom/ourbox/installer/defaults.env`

Key variables:

- `INSTALLER_ID` (`woodbox`)
- `INSTALLER_VERSION`
- `INSTALLER_GIT_HASH`
- `OURBOX_INSTALLER_SSH_MODE`
- `OURBOX_INSTALLER_SSH_USER`
- `OURBOX_INSTALLER_SSH_PASSWORD_HASH`
- `OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS`
- `OURBOX_INSTALLER_SSH_ALLOW_ROOT`
- `OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY`

Woodbox keeps live-installer password generation,
`/run/ourbox-installer-ssh-status.env`,
`/run/ourbox-installer-ssh-password.txt`, and monitor output as repo-local
behavior layered on top of the shared upstream SSH helper contract.

### OS payload artifact files

- Type: `application/vnd.techofourown.ourbox.woodbox.os-payload.v1`
- Required files:
  - `os-payload.tar.gz`
  - `os-payload.tar.gz.sha256` (must match content)
  - `os.meta.env` (KEY=VALUE metadata)

## Contract: Platform runtime (`k3s`)

- `k3s` binary at `/usr/local/bin/k3s`
- `k3s.service` exists and is enabled by bootstrap, or enabled directly
- `ourbox-bootstrap.service` exists and runs on first boot
- success marker: `/var/lib/ourbox/state/bootstrap.done`
- `k3s` data lives under `/var/lib/ourbox/k3s`

## Related ADRs

- ADR-0001: Adopt Ubuntu Server LTS
- ADR-0002: Storage contract (mount data by label)
- ADR-0003: OS artifact distribution via OCI registry
- ADR-0004: Consume platform inputs from `sw-ourbox-os`
