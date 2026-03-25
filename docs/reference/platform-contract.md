# Platform Input Consumption (Woodbox)

Woodbox consumes two upstream platform inputs published by `sw-ourbox-os`:

1. `platform-contract`
2. `ourbox-substrate`

They serve different roles:

- `platform-contract` is the arch-agnostic runtime platform payload. It carries
  manifests, static assets, and the helper scripts Woodbox bootstrap executes on
  the installed system.
- `ourbox-substrate` is the arch-specific transport bundle. It carries the
  `k3s` binary, the normalized `k3s-images-amd64.tar` payload, platform image
  tars, and `manifest.env`.

Woodbox does not author platform content locally. It stages these upstream
artifacts into the OS payload and installer substrate, then runs the shipped
platform tooling at runtime.

## Sources of truth

- `sw-ourbox-os` artifact docs:
  `docs/architecture/artifact-distribution-and-integration.md`
- `sw-ourbox-os` downstream surface docs:
  `docs/reference/downstream-consumer-surfaces.md`
- approved upstream snapshot in
  `sw-ourbox-os/release/approved-upstream-inputs.json`
- repo-local pointer to that approved snapshot:
  `tools/approved-upstream-inputs.upstream.env`
- official candidate and revalidation workflows resolve exact upstream refs from
  that approved snapshot at workflow start

For local/manual runs, pass explicit `OURBOX_PLATFORM_CONTRACT_REF` and
`OURBOX_SUBSTRATE_REF` overrides only when you intentionally want non-default
upstream inputs.

## Current consumption model

Woodbox pulls two GHCR artifacts published by `sw-ourbox-os`:

1. `platform-contract` (arch-agnostic)
   - fetched by `./tools/fetch-platform-contract.sh`
   - validated by `./tools/validate-platform-contract-shape.sh`
   - synced into the installer rootfs by
     `./tools/sync-platform-contract-into-installer.sh`

2. `ourbox-substrate` (amd64-specific)
   - fetched by `./tools/fetch-ourbox-substrate.sh`
   - staged into the OS payload under `substrate/`
   - consumed later as mission-selected `selected_substrate` content during
     host-composed install flows

Runtime layout on the installed system:

- `/opt/ourbox/substrate/k3s/{k3s,k3s-images-amd64.tar}`
- `/opt/ourbox/substrate/platform/images/*.tar`
- `/opt/ourbox/substrate/platform/manifests/**`
- `/opt/ourbox/substrate/platform/{landing,todo-bloom}/**`
- `/opt/ourbox/substrate/platform/tools/{contract-identity.sh,render-contract.py,verify-runtime.sh}`

## Runtime rule

Woodbox installer and runtime behavior must be driven by:

- exact selected artifact identities
- local bundle-shape validation
- required runtime capabilities exposed by the shipped platform tooling

They must not be driven by duplicated platform-contract metadata such as copied
digest or version fields.

## Provenance rule

Primary build, payload, and install provenance now lives in the
`OURBOX_SUBSTRATE_*` fields recorded in payload metadata, publish metadata, and
installed-system release files.

## Updating approved inputs

1. Approve the new upstream snapshot in
   `sw-ourbox-os/release/approved-upstream-inputs.json`.
2. Update `tools/approved-upstream-inputs.upstream.env` to the upstream
   revision/path carrying that approved snapshot.
3. Let official workflows resolve exact upstream refs from that snapshot at
   workflow start.
4. For local/manual runs, export explicit `OURBOX_PLATFORM_CONTRACT_REF` and
   `OURBOX_SUBSTRATE_REF` overrides before fetch/build only when you want
   non-default upstream inputs.
5. Run `./tools/fetch-ourbox-substrate.sh` to pull and sync into
   `installer/ourbox/rootfs/`.
6. Rebuild the OS payload and installer substrate, then update release notes
   with the new artifact identities.

## Relationship to OS artifact distribution

OCI distribution of the OS payload (`os-payload.tar.gz`) is transport only. The
runtime platform payload is still sourced from `sw-ourbox-os`, but install and
runtime compatibility are anchored to exact selected artifacts and local
validation, not to copied platform-contract metadata.

## Related docs

- `docs/decisions/ADR-0004-consume-platform-contract-from-sw-ourbox-os.md`
- `docs/reference/contracts.md`
- `docs/OPS.md`
