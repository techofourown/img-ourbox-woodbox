# ADR-0004: Consume the OurBox OS Platform Contract from `sw-ourbox-os`


## Context

This repository (`img-ourbox-woodbox`) produces a **bootable installer and installable OS payload**
for Woodbox hardware. It is responsible for:

- bootability + base OS configuration (Ubuntu Server LTS, UEFI, GRUB2)
- disk/storage contract enforcement (`LABEL=OURBOX_DATA`)
- installer-time artifact selection and OS staging
- first-boot bootstrap services (k3s bring-up, applying baseline manifests, etc.)
- airgap/offline operation

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

This repo consumes the platform contract via ORAS pull, using digest-pinned refs defined in
`release/official-inputs.env`. The following upstream artifacts are consumed:

1. **platform-contract** (arch-agnostic): manifests, landing, todo-bloom assets, contract metadata
2. **airgap-platform** (amd64-specific): `k3s` binary, `k3s-airgap-images-amd64.tar`, platform
   image tars, `manifest.env`

Both are pulled by `./tools/fetch-airgap-platform.sh` and synced into the installer rootfs by
`./tools/sync-platform-contract-into-installer.sh`.

The platform contract content is staged under `installer/ourbox/rootfs/opt/ourbox/airgap/platform/`
as part of the OS payload — it is baked into the installed system when the payload is extracted.

### 3) Provenance is mandatory

The installed system MUST record platform contract provenance in `/etc/ourbox/release` so operators
can answer "what platform baseline is running?" locally.

Required keys:
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`
- `OURBOX_PLATFORM_CONTRACT_VERSION`
- `OURBOX_PLATFORM_CONTRACT_CREATED`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`

These are written to the OS payload during `build-os-payload.sh` from the synced `contract.env`
and `contract.digest` files.

### 4) Platform manifests are gitkeep placeholders

`installer/ourbox/rootfs/opt/ourbox/airgap/platform/{manifests,landing,todo-bloom}/` are kept as
`.gitkeep` placeholders in version control. They are populated by `fetch-airgap-platform.sh` from
the upstream OCI artifact, not authored in this repo. This makes the dependency explicit.

## Rationale

- Keeps the platform baseline "officialness" anchored in one producer repo.
- Prevents silent baseline drift across multiple image repos.
- Makes support and debugging possible: "show me the platform contract revision/digest."
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
- `contracts/platform-contract.ref` and `contracts/airgap-platform.ref` provide the canonical
  channel ref as a fallback for development builds.
- `release/official-inputs.env` carries the digest-pinned refs for official builds.
- See `docs/reference/platform-contract.md` for the consumption workflow.

## References

- Org ADR-0007:
  https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0007-adopt-oci-artifacts-for-app-distribution.md
- `sw-ourbox-os` ADR-0009:
  https://github.com/techofourown/sw-ourbox-os/blob/main/docs/decisions/ADR-0009-package-the-platform-contract-as-an-oci-artifact.md
- `sw-ourbox-os` integration reference:
  https://github.com/techofourown/sw-ourbox-os/blob/main/docs/architecture/artifact-distribution-and-integration.md
- Reference: `docs/reference/platform-contract.md` (this repo)
