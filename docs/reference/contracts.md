# OurBox Woodbox host contracts

This repo produces an OS payload and installer that guarantee a small set of contracts. These
contracts are the interface between "image build" and "k8s/apps".

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
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`
- `OURBOX_PLATFORM_CONTRACT_VERSION`
- `OURBOX_PLATFORM_CONTRACT_CREATED`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`
- `OURBOX_BUILD_TS`

Fields appended at install time (by autoinstall late-commands):

- `OURBOX_INSTALLER_ID`
- `OURBOX_OS_ARTIFACT_SOURCE` (`registry` or `embedded`)
- `OURBOX_OS_ARTIFACT_REF`
- `OURBOX_OS_ARTIFACT_DIGEST`
- `OURBOX_OS_IMAGE_SHA256`
- `OURBOX_RELEASE_CHANNEL`

### Why it exists

- debugging ("what build is on this device?")
- fleet management ("what should this be running?")
- predictable support ("we can reproduce your image")

See `docs/reference/platform-contract.md` for the full provenance model.

## Contract: Storage (DATA disk)

### Rule

- The DATA drive is **ext4** with filesystem label: `OURBOX_DATA`
- It mounts at: `/var/lib/ourbox`

### Implementation

`/etc/fstab` includes a label-based mount:

```fstab
LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2
```

Key properties:

- uses **LABEL** (not `/dev/sda1`) to survive device enumeration changes
- uses `nofail` so the system can boot without the data disk
- uses a short systemd timeout to avoid slow boots

### Intended contents of `/var/lib/ourbox`

This is where higher-level stacks store persistent state:

- k3s storage / persistent volumes
- application state
- logs (if desired)

(Exact directory layout is owned by the k8s/apps layer.)

## Contract: Installer flow

### Thin ISO (default)

1. Operator boots USB installer on Woodbox
2. `ourbox-preinstall` loads baked defaults (`/cdrom/ourbox/installer/defaults.env`)
3. Operator may set a temporary password for the live-installer SSH account, or press Enter to keep the current installer SSH posture
4. `ourbox-preinstall` pulls OS payload from registry via ORAS to `/opt/ourbox/installer/cache/payload/`
5. Operator confirms disk selection, identity, and INSTALL
6. Autoinstall late-commands extract the OS payload to `/target/`

After a successful install, the late-commands attempt to prefer the installed OS for the next and
future UEFI boots. The operator should still remove the USB after poweroff, but first boot should
not depend solely on that manual step.

### Fat ISO (`--embed-payload`)

Same flow, except step 3 uses an embedded `os-payload.tar.gz` from `/cdrom/ourbox/payload/`
instead of a registry pull. No network access required.

### Payload cache path

- `/opt/ourbox/installer/cache/payload/os-payload.tar.gz`
- `/opt/ourbox/installer/cache/payload/os-payload.tar.gz.sha256`
- `/opt/ourbox/installer/cache/payload/payload.meta.env`

### Installer defaults file (baked into ISO)

- `/cdrom/ourbox/installer/defaults.env`

Key variables:
- `INSTALLER_ID` (woodbox)
- `OS_REPO` (`ghcr.io/techofourown/ourbox-woodbox-os`)
- `OS_TARGET` (`x86`)
- `OS_CHANNEL` (`stable`)
- `OS_CATALOG_ENABLED` (`1`)
- `OS_CATALOG_TAG` (`x86-catalog`)
- `OS_ORAS_VERSION`
- `INSTALLER_VERSION`
- `INSTALLER_GIT_HASH`

### OS payload artifact files (oras pull)

- Type: `application/vnd.techofourown.ourbox.woodbox.os-payload.v1`
- Required files:
  - `os-payload.tar.gz`
  - `os-payload.tar.gz.sha256` (must match content)
  - `os.meta.env` (KEY=VALUE metadata)

## Contract: Platform runtime (k3s)

- `k3s` binary at `/usr/local/bin/k3s`
- `k3s.service` exists and is enabled by bootstrap (or enabled directly)
- `ourbox-bootstrap.service` exists and runs on first boot
- Success marker: `/var/lib/ourbox/state/bootstrap.done`
- k3s data lives under `/var/lib/ourbox/k3s`

## Related ADRs

- ADR-0001: Adopt Ubuntu Server LTS
- ADR-0002: Storage contract (mount data by label)
- ADR-0003: OS artifact distribution via OCI registry
- ADR-0004: Consume platform contract from `sw-ourbox-os`
