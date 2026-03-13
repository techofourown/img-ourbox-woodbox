# img-ourbox-woodbox

Build repository for **OurBox Woodbox** — a local-first x86-64 appliance running the OurBox
software platform. This repo produces the Woodbox OS payload and the Woodbox installer
substrate consumed by the unified host-side installer.

**Hardware**: x86-64 desktop-class PC, UEFI, NVMe system disk, SATA data disk
**OS base**: Ubuntu Server LTS 24.04 (x86-64), autoinstall via cloud-init
**Runtime**: airgapped single-node k3s, deployed from OCI platform bundle

## Identifiers

- **Model ID**: `TOO-OBX-WBX` (Woodbox hardware class)
- **Default SKU**: `TOO-OBX-WBX-BASE-JU3XK8`
- **Build target**: `x86`

## If You Want To Install A Woodbox

Do not start from this repo.

Woodbox installation now goes through the unified host-side installer:

- repo: `https://github.com/techofourown/sw-ourbox-installer`
- normal operator command:

```bash
cd sw-ourbox-installer
./tools/prepare-installer-media.sh
```

That flow:

- chooses the Woodbox OS artifact on the trusted host
- chooses the `airgap-platform` bundle on the trusted host
- pulls the published Woodbox installer substrate artifact
- composes mission media
- flashes removable media
- installs fully offline on the target

This repo is not the operator front door for artifact selection or USB
composition anymore.

The helper at [tools/prepare-installer-media.sh](/techofourown/img-ourbox-woodbox/tools/prepare-installer-media.sh)
now delegates to `sw-ourbox-installer`; it does not maintain a separate
Woodbox-only operator flow.

## What This Repo Owns

This repo still owns the Woodbox-specific surfaces below the hardware seam:

- Woodbox OS payload build and publish
- Woodbox installer substrate build and publish
- Woodbox target runtime install behavior
- Woodbox storage, boot, and hardware-specific installation logic
- Woodbox host-side media adapter surface used by `sw-ourbox-installer`

## Operator runbook

See [`docs/OPS.md`](./docs/OPS.md) for the full operator runbook including:
- Individual build steps
- Registry operations (publish/pull)
- Post-boot verification
- Updating upstream platform inputs
- Troubleshooting

## Artifact model

Woodbox now has a two-layer model:

- this repo publishes target-owned artifacts
- `sw-ourbox-installer` composes final mission media from those artifacts

Published artifacts from this repo:

| Artifact | ORAS artifact type | Registry |
|---|---|---|
| OS payload (`.tar.gz`) | `application/vnd.techofourown.ourbox.woodbox.os-payload.v1` | `ghcr.io/techofourown/ourbox-woodbox-os` |
| Installer substrate ISO (`.iso`) | `application/vnd.techofourown.ourbox.woodbox.installer.v1` | `ghcr.io/techofourown/ourbox-woodbox-installer` |

Official channel tags: `x86-stable`, `x86-nightly`, `x86-installer-stable`, `x86-installer-nightly`

Important distinction:

- the published installer ISO is a substrate artifact, not the supported standalone install path
- the supported install path is host-composed mission media created by `sw-ourbox-installer`
- mission media embeds the selected OS payload, selected `airgap-platform` bundle, and mission manifest
- the target then installs from those local mission bytes only

See [`docs/ARTIFACT_PROVENANCE.md`](./docs/ARTIFACT_PROVENANCE.md) for the full provenance model
and official release policy.

## Official build posture

Official artifacts are produced by organization-controlled build infrastructure per
[ADR-0008](https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0008-adopt-organization-controlled-build-infrastructure-for-heavy-artifacts.md).

- Official candidate: push to `main` via `.github/workflows/official-candidate.yml` → publishes `x86-beta` / `x86-installer-beta`
- Integration nightly: daily cron via `.github/workflows/integration-nightly.yml` → publishes `x86-nightly` / `x86-installer-nightly`
- Stable promotion: GitHub Release `published` via `.github/workflows/official-promote-stable.yml`
- Exp-labs promotion: GitHub Release `prereleased` via `.github/workflows/official-exp-labs.yml`
- Heavy-build runners: `[self-hosted, official-heavy, x86-image]` (organization-controlled)

Official Woodbox builds publish:

- the OS payload artifact
- the Woodbox installer substrate artifact used by host-side mission composition

Candidate builds consume the pinned refs in `release/official-inputs.env`.
Scheduled nightly integration builds resolve the latest `sw-ourbox-os`
nightly/platform inputs at workflow time.

The offline-install contract now lives in the Woodbox substrate itself:

- target package installation comes from substrate-local media, not Ubuntu mirrors
- target netplan is rendered from hardware inventory, not the live installer's default route
- target-side OS and `airgap-platform` browsing/pulling are removed from the supported path

## Documentation

| Document | Contents |
|---|---|
| [`sw-ourbox-installer`](https://github.com/techofourown/sw-ourbox-installer) | Unified host-side installer and mission-media composer |
| [`sw-ourbox-os`](https://github.com/techofourown/sw-ourbox-os) | Upstream platform-contract and install-defaults producer |
| [`docs/OPS.md`](./docs/OPS.md) | Operator runbook |
| [`docs/ARTIFACT_PROVENANCE.md`](./docs/ARTIFACT_PROVENANCE.md) | Artifact provenance and release policy |
| [`docs/reference/contracts.md`](./docs/reference/contracts.md) | Host contracts (release metadata, storage, installer) |
| [`docs/reference/installer.md`](./docs/reference/installer.md) | Installer reference (defaults, UX flow, artifact contract) |
| [`docs/reference/platform-contract.md`](./docs/reference/platform-contract.md) | Platform contract consumption from sw-ourbox-os |
| [`docs/decisions/`](./docs/decisions/) | Architectural Decision Records |
