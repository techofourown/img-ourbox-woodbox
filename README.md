# img-ourbox-woodbox

Build repository for **OurBox Woodbox** — a local-first x86-64 appliance running the OurBox
software platform. This repo produces a bootable USB installer and distributable OS payload
artifacts for Woodbox hardware.

**Hardware**: x86-64 desktop-class PC, UEFI, NVMe system disk, SATA data disk
**OS base**: Ubuntu Server LTS 24.04 (x86-64), autoinstall via cloud-init
**Runtime**: airgapped single-node k3s, deployed from OCI platform bundle

## Identifiers

- **Model ID**: `TOO-OBX-WBX` (Woodbox hardware class)
- **Default SKU**: `TOO-OBX-WBX-BASE-JU3XK8`
- **Build target**: `x86`

## Quick start

### Prepare and flash an installer USB (default: pull from registry)

```bash
git clone https://github.com/techofourown/img-ourbox-woodbox.git
cd img-ourbox-woodbox
./tools/prepare-installer-media.sh
```

This pulls the official installer artifact from GHCR, flashes it to a USB disk you select, then:

1. Plug USB into Woodbox, boot from USB (UEFI boot menu)
2. Installer prompts: OS disk, DATA disk, OS artifact (auto-resolved), hostname/username/password
3. Type `INSTALL` to begin — runs unattended (~10–15 minutes)
4. Machine powers off — remove USB, boot from NVMe

The installer also attempts to prefer the installed OS for the next UEFI boot when possible, but
removing the USB after poweroff is still the recommended operator flow.

### Prepare a fully offline USB (local source build)

```bash
./tools/prepare-installer-media.sh --build-local
```

Builds the OS payload and installer ISO locally from source, then flashes. No network access
required at install time.

## Operator runbook

See [`docs/OPS.md`](./docs/OPS.md) for the full operator runbook including:
- Individual build steps
- Registry operations (publish/pull)
- Post-boot verification
- Updating upstream platform inputs
- Troubleshooting

## Artifact model

Woodbox produces two distributable artifacts:

| Artifact | ORAS artifact type | Registry |
|---|---|---|
| OS payload (`.tar.gz`) | `application/vnd.techofourown.ourbox.woodbox.os-payload.v1` | `ghcr.io/techofourown/ourbox-woodbox-os` |
| Installer ISO (`.iso`) | `application/vnd.techofourown.ourbox.woodbox.installer.v1` | `ghcr.io/techofourown/ourbox-woodbox-installer` |

Official channel tags: `x86-stable`, `x86-nightly`, `x86-installer-stable`, `x86-installer-nightly`

See [`docs/ARTIFACT_PROVENANCE.md`](./docs/ARTIFACT_PROVENANCE.md) for the full provenance model
and official release policy.

## Official build posture

Official artifacts are produced by organization-controlled build infrastructure per
[ADR-0008](https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0008-adopt-organization-controlled-build-infrastructure-for-heavy-artifacts.md).

- Official nightly: triggered by push to `main` via `.github/workflows/official-nightly.yml`
- Official release: triggered by `v*` tag push via `.github/workflows/official-release.yml`
- Runners: `[self-hosted, official-heavy, x86-image]` (organization-controlled)

## Documentation

| Document | Contents |
|---|---|
| [`sw-ourbox-os`](https://github.com/techofourown/sw-ourbox-os) | Upstream platform-contract and install-defaults producer |
| [`docs/OPS.md`](./docs/OPS.md) | Operator runbook |
| [`docs/ARTIFACT_PROVENANCE.md`](./docs/ARTIFACT_PROVENANCE.md) | Artifact provenance and release policy |
| [`docs/reference/contracts.md`](./docs/reference/contracts.md) | Host contracts (release metadata, storage, installer) |
| [`docs/reference/installer.md`](./docs/reference/installer.md) | Installer reference (defaults, UX flow, artifact contract) |
| [`docs/reference/platform-contract.md`](./docs/reference/platform-contract.md) | Platform contract consumption from sw-ourbox-os |
| [`docs/decisions/`](./docs/decisions/) | Architectural Decision Records |
