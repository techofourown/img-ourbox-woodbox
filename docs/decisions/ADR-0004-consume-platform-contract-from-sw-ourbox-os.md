# ADR-0004: Consume the OurBox OS Platform Contract from `sw-ourbox-os`

> Status note (2026-03): Woodbox now consumes both `platform-contract` and
> `ourbox-substrate` as pinned OCI inputs from `sw-ourbox-os`. Legacy
> platform-contract metadata may still appear in provenance, but compatibility
> is enforced by exact selected artifact identities plus local bundle and
> capability checks, not by contract-digest matching.


## Context

This repository (`img-ourbox-woodbox`) produces a **bootable installer and installable OS payload**
for Woodbox hardware. It is responsible for:

- bootability + base OS configuration (Ubuntu Server LTS, UEFI, GRUB2)
- disk/storage contract enforcement (`LABEL=OURBOX_DATA`)
- installer-time artifact selection and OS staging
- first-boot bootstrap services (k3s bring-up, applying baseline manifests, etc.)
- offline operation

Historically, image repos become the accidental "home" of the platform baseline (manifests, images,
components that make the box feel like an appliance). That creates drift and makes it easy for the
platform baseline to change without a clear upstream provenance boundary.

At the org level, TOOO adopted OCI artifacts + digests as the canonical distribution substrate for
apps and platform components (org ADR-0007). In `sw-ourbox-os`, this is realized as an explicit
**platform contract artifact** (ADR-0009 + integration doc).

This image repo must align with that model:

> `sw-ourbox-os` defines the platform contract. Image repos consume it.

This preserves "one lane, explicit trust" while keeping the official baseline legible and hard to
quietly alter.

## Decision

### 1) Source of truth

The OurBox OS **platform contract** consumed by Woodbox OS images SHALL be sourced from
`sw-ourbox-os`, not defined ad-hoc in this repo.

Canonical upstream docs:
- `sw-ourbox-os` ADR-0009 (platform contract as OCI artifact)
- `sw-ourbox-os` artifact distribution + integration reference

### 2) OCI by digest

This repo consumes the platform contract via ORAS pull. Official candidate builds resolve exact
digest-pinned refs at workflow start from the approved upstream snapshot in
`sw-ourbox-os/release/approved-upstream-inputs.json`, pinned here by
`tools/approved-upstream-inputs.upstream.env`. The following upstream artifacts are consumed:

1. **platform-contract** (arch-agnostic): manifests, landing, todo-bloom assets, contract metadata
2. **ourbox-substrate** (amd64-specific): `k3s` binary, `k3s-images-amd64.tar`, platform
   image tars, `manifest.env`

Both are pulled by `./tools/fetch-ourbox-substrate.sh` and synced into the installer rootfs by
`./tools/sync-platform-contract-into-installer.sh`.

The platform contract content is staged under `installer/ourbox/rootfs/opt/ourbox/substrate/platform/`
as part of the OS payload — it is baked into the installed system when the payload is extracted.

### 3) Provenance is mandatory

The installed system MUST record build-time and install-time provenance in `/etc/ourbox/release`
so operators can answer which OS payload, selected substrate bundle, and application selection are
running locally.

### 4) Platform manifests are gitkeep placeholders

`installer/ourbox/rootfs/opt/ourbox/substrate/platform/{manifests,landing,todo-bloom}/` are kept as
`.gitkeep` placeholders in version control. They are populated by `fetch-ourbox-substrate.sh` from
the upstream OCI artifact, not authored in this repo. This makes the dependency explicit.

## Rationale

- Keeps the platform baseline "officialness" anchored in one producer repo.
- Prevents silent baseline drift across multiple image repos.
- Makes support and debugging possible: "show me the exact upstream platform
  inputs and selected artifact identities."
- Preserves hackability: users can replace the contract, but the provenance boundary stays legible.

## Consequences

### Positive
- Clear producer/consumer boundary: `sw-ourbox-os` produces the contract, image repos consume it.
- Image repos become more mechanical: hardware enablement + bootstrap, not "platform policy."
- Helps later trust hardening (signatures / release manifests) land cleanly.

### Negative
- Requires a network pull (or pre-fetched artifact) to build a complete OS payload.
- Adds additional release metadata fields to maintain.

### Mitigation
- Local/manual development builds may pass explicit `OURBOX_PLATFORM_CONTRACT_REF` and
  `OURBOX_SUBSTRATE_REF` overrides when they need a non-default upstream input.
- Official builds resolve approved upstream intent into digest-pinned refs at workflow start rather
  than approving mirrored TOOO digests in this repo's source control.
- See `docs/reference/platform-contract.md` for the consumption workflow.

## References

- Org ADR-0007:
  https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0007-adopt-oci-artifacts-for-app-distribution.md
- `sw-ourbox-os` ADR-0009:
  https://github.com/techofourown/sw-ourbox-os/blob/main/docs/decisions/ADR-0009-package-the-platform-contract-as-an-oci-artifact.md
- `sw-ourbox-os` integration reference:
  https://github.com/techofourown/sw-ourbox-os/blob/main/docs/architecture/artifact-distribution-and-integration.md
- Reference: `docs/reference/platform-contract.md` (this repo)
