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

### Compose Woodbox mission media

Woodbox mission media is now composed by the unified host-side installer repo,
`sw-ourbox-installer`. This repo is no longer the operator front door for
artifact selection or USB composition.

Use the unified host-side composer, pointing it at this Woodbox repo as the
target adapter/substrate source:

```bash
cd sw-ourbox-installer
./tools/prepare-installer-media.sh --target woodbox --adapter-repo-root ../img-ourbox-woodbox
```

That flow resolves the selected OS payload and `airgap-platform` bundle on the
trusted host, stages the exact bytes onto mission media, and produces a USB
that installs fully offline on the target.

The helper at [tools/prepare-installer-media.sh](/techofourown/img-ourbox-woodbox/tools/prepare-installer-media.sh)
now delegates to `sw-ourbox-installer`; it does not maintain a separate
Woodbox-only operator flow.

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

- Official candidate: push to `main` via `.github/workflows/official-candidate.yml` → publishes `x86-beta` / `x86-installer-beta`
- Integration nightly: daily cron via `.github/workflows/integration-nightly.yml` → publishes `x86-nightly` / `x86-installer-nightly`
- Stable promotion: GitHub Release `published` via `.github/workflows/official-promote-stable.yml`
- Exp-labs promotion: GitHub Release `prereleased` via `.github/workflows/official-exp-labs.yml`
- Heavy-build runners: `[self-hosted, official-heavy, x86-image]` (organization-controlled)

Official Woodbox builds still publish the OS payload first and also publish a
bootable installer substrate artifact for host-side composition workflows.
Candidate builds consume the pinned refs in `release/official-inputs.env`;
scheduled nightly integration builds resolve the latest `sw-ourbox-os`
nightly/platform inputs at workflow time.

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
