# Platform Contract Consumption (Woodbox)

Woodbox is **only a consumer** of platform software. All manifests, static assets, and platform
images come from `sw-ourbox-os` via pinned OCI artifacts; nothing is authored or fetched ad-hoc in
this repo.

---

## Sources of truth

- `sw-ourbox-os` ADR-0009 (platform contract as OCI artifact)
- `sw-ourbox-os` artifact docs: https://github.com/techofourown/sw-ourbox-os/blob/main/docs/architecture/artifact-distribution-and-integration.md
- Approved upstream snapshot in `sw-ourbox-os/release/approved-upstream-inputs.json`
- Supported input sources in this repo:
  - `release/official-inputs.env` (generated digest-pinned lockfile for official builds)
  - explicit `OURBOX_PLATFORM_CONTRACT_REF` / `OURBOX_AIRGAP_PLATFORM_REF` overrides for local work

---

## Current state (OCI by digest)

Woodbox pulls two GHCR artifacts published by `sw-ourbox-os`:

1) **platform-contract** (arch-agnostic)
   - Contents: manifests, landing, todo-bloom assets, contract metadata
   - Pulled via `./tools/fetch-platform-contract.sh`
   - Synced into installer rootfs via `./tools/sync-platform-contract-into-installer.sh`

2) **airgap-platform** (arch-specific: amd64)
   - Contents: `k3s` binary, `k3s-airgap-images-amd64.tar`, platform image tars, `manifest.env`
   - Pulled via `./tools/fetch-airgap-platform.sh` (which also triggers the contract sync)
   - Staged in the OS payload tarball as `airgap/`

Runtime layout on the installed system:
- `/opt/ourbox/airgap/k3s/{k3s,k3s-airgap-images-amd64.tar}`
- `/opt/ourbox/airgap/images/*.tar`
- `/opt/ourbox/airgap/platform/manifests/**`
- `/opt/ourbox/airgap/platform/{landing,todo-bloom}/**`
- `/opt/ourbox/airgap/platform/contract.env` + `contract.digest`

---

## Provenance recording

During `build-os-payload.sh`, platform contract provenance is written to
`installer/ourbox/rootfs/etc/ourbox/release` and bundled into the OS payload tarball:
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`
- `OURBOX_PLATFORM_CONTRACT_VERSION`
- `OURBOX_PLATFORM_CONTRACT_CREATED`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`

These are read from the synced `contract.env` and `contract.digest` files in the installer rootfs.

---

## Updating pins

1. Approve the new upstream snapshot in `sw-ourbox-os/release/approved-upstream-inputs.json`.
2. Let the upstream sync workflow open the Woodbox lockfile PR updating `release/official-inputs.env`.
3. Run `./tools/fetch-airgap-platform.sh` to pull/sync into `installer/ourbox/rootfs/`.
4. Rebuild OS payload; update release notes/changelog with new digests.

If `release/official-inputs.env` is absent, the fetch scripts fail closed unless you provide
explicit `OURBOX_PLATFORM_CONTRACT_REF` / `OURBOX_AIRGAP_PLATFORM_REF` values.

---

## Relationship to OS artifact distribution

OCI distribution of the OS payload (`os-payload.tar.gz`) is transport only (see ADR-0003).
Platform contract identity is separate and governed by `sw-ourbox-os`.

---

## Related docs

- `docs/decisions/ADR-0004-consume-platform-contract-from-sw-ourbox-os.md`
- `docs/reference/contracts.md`
- `docs/OPS.md`
