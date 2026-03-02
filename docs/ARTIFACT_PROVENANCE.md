# Artifact Provenance — OurBox Woodbox

This document is the required audit record for `img-ourbox-woodbox` per the
[Official Artifact Build and Provenance Policy](https://github.com/techofourown/org-techofourown/blob/main/docs/policies/OFFICIAL_ARTIFACT_BUILD_AND_PROVENANCE_POLICY.md)
and
[ADR-0008](https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0008-adopt-organization-controlled-build-infrastructure-for-heavy-artifacts.md).

---

## Artifact types produced

| Artifact | Description |
|---|---|
| OS payload | Rootfs overlay + airgap bundle for Woodbox x86-64 (`.tar.gz` + SHA-256 checksum + metadata) |
| Installer media | Bootable Ubuntu autoinstall ISO that stages and installs the OS payload (`.iso` + SHA-256 checksum + metadata) |

Both are published as ORAS OCI artifacts (non-runnable) to GHCR.

---

## Official release channels

| Channel tag | Artifact | Trigger |
|---|---|---|
| `x86-nightly` | OS payload | Push to `main` |
| `x86-installer-nightly` | Installer | Push to `main` |
| `x86-stable` | OS payload | `v*` tag push |
| `x86-installer-stable` | Installer | `v*` tag push |

Registry namespaces (from `release/official-artifacts.env`):
- OS payload: `ghcr.io/techofourown/ourbox-woodbox-os`
- Installer: `ghcr.io/techofourown/ourbox-woodbox-installer`

Each immutable tag is named after the build basename (e.g., `nightly-<sha12>-x86`).
Moving channel tags (`x86-nightly`, `x86-stable`) always point to the latest build in that channel.
A catalog tag (`x86-catalog`) accumulates one TSV row per published OS payload build.

---

## Trusted release contexts

- Push to `main` branch (nightly)
- Signed `v*` tag push (stable release)

These are the only authorized triggers for the official publication lane.
`workflow_dispatch` is intentionally absent from all official publish workflows.

---

## Public build entrypoints

| Operation | Entrypoint |
|---|---|
| Prepare + flash installer media (default: pull from registry) | `./tools/prepare-installer-media.sh` |
| Prepare + flash installer media (local build) | `./tools/prepare-installer-media.sh --build-local` |
| Fetch upstream platform inputs | `./tools/fetch-airgap-platform.sh` |
| Build OS payload only | `./tools/build-os-payload.sh` |
| Build installer ISO only | `./tools/build-installer-iso.sh` |
| Publish OS artifact | `./tools/publish-os-artifact.sh deploy` |
| Publish installer artifact | `./tools/publish-installer-artifact.sh deploy` |
| Pull OS artifact from registry | `./tools/pull-os-artifact.sh IMAGE_REF` |
| Pull installer artifact from registry | `./tools/pull-installer-artifact.sh --channel stable` |

All build logic lives in this repository. Official and compatible builds use the same entrypoints.
Official status derives from the publication identity (TOOO-controlled GHCR namespace), not from
hidden build logic.

---

## Official release workflows

| Workflow | File | Runner | Trigger |
|---|---|---|---|
| Official nightly | `.github/workflows/official-nightly.yml` | `[self-hosted, official-heavy, x86-image]` | Push to `main` (source-filtered) |
| Official release | `.github/workflows/official-release.yml` | `[self-hosted, official-heavy, x86-image]` | `v*` tag push |

Both run on organization-controlled build infrastructure in the `official-heavy-artifacts`
runner group. Third-party hosted runners are not used for artifact publication.

### Trigger filtering

`official-nightly.yml` uses `paths-ignore` to skip publication for documentation-only changes.
The following paths do not trigger a nightly build when changed:

```
docs/**
README.md
CLAUDE.md
```

All other paths are treated as potentially artifact-affecting and do trigger the nightly build.

`official-release.yml` is not filtered — it triggers on explicit `v*` tag push, which is always
an intentional release act.

### Forcing an official republish without source changes

Touch `release/REVALIDATION_TRIGGER` in a PR. That file is not in the `paths-ignore` list,
so merging a change to it will trigger `official-nightly.yml`. Use this when you need an
official artifact after infrastructure maintenance or runner migration, without making a
substantive code change. See `release/REVALIDATION_TRIGGER` for the documented procedure.

### Non-publishing revalidation

`.github/workflows/revalidate-woodbox-build.yml` runs the full build pipeline on the official
builder weekly (Sunday 04:00 UTC) and on `workflow_dispatch`. It does NOT publish official
artifacts. Use it to confirm the release-capable path works after infrastructure changes, per
the ADR-0008 revalidation requirement.

---

## Provenance metadata

Every published artifact carries the following provenance in its OCI annotations:

| Field | Value source |
|---|---|
| `org.opencontainers.image.source` | `https://github.com/techofourown/img-ourbox-woodbox` |
| `org.opencontainers.image.revision` | Git commit SHA (short, 12 chars) |
| `org.opencontainers.image.version` | `OURBOX_VERSION` env (semver or `dev`) |
| `org.opencontainers.image.created` | Build timestamp (UTC, ISO 8601) |
| `techofourown.artifact.kind` | `os-payload` or `installer` |
| `techofourown.target` | `x86` |
| `techofourown.variant` | `prod` |
| `techofourown.sku` | `TOO-OBX-WBX-BASE-JU3XK8` |
| `techofourown.platform-contract.digest` | Digest of platform-contract bundle baked in |
| `techofourown.build.workflow` | GitHub workflow name |
| `techofourown.build.run-id` | GitHub run ID |
| `techofourown.build.run-attempt` | GitHub run attempt |

Additional metadata is published as artifact files:

- `os.meta.env` / `installer.meta.env` — full provenance record including K3S version, upstream
  contract source/revision/version/digest, SHA-256, and size
- `os-payload.tar.gz.sha256` / `installer.iso.sha256` — SHA-256 checksum for offline verification

Canonical artifact identity for consumption is **by digest**
(e.g., `ghcr.io/techofourown/ourbox-woodbox-os@sha256:...`).

---

## Installed-system provenance

Every installed Woodbox system records provenance in `/etc/ourbox/release`. Full field list:

**Build-time fields** (from `build-os-payload.sh`):
- `OURBOX_PRODUCT`, `OURBOX_DEVICE`, `OURBOX_TARGET`, `OURBOX_SKU`
- `OURBOX_VARIANT`, `OURBOX_VERSION`, `OURBOX_RECIPE_GIT_HASH`
- `OURBOX_PLATFORM_CONTRACT_SOURCE`, `OURBOX_PLATFORM_CONTRACT_REVISION`
- `OURBOX_PLATFORM_CONTRACT_VERSION`, `OURBOX_PLATFORM_CONTRACT_CREATED`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`, `OURBOX_BUILD_TS`

**Install-time fields** (appended by autoinstall late-commands):
- `OURBOX_INSTALLER_ID`, `OURBOX_OS_ARTIFACT_SOURCE`, `OURBOX_OS_ARTIFACT_REF`
- `OURBOX_OS_ARTIFACT_DIGEST`, `OURBOX_OS_IMAGE_SHA256`, `OURBOX_RELEASE_CHANNEL`

---

## Upstream input pinning

The official build consumes pinned OCI artifacts from `sw-ourbox-os` (defined in
`release/official-inputs.env`):

```
PLATFORM_CONTRACT_REF=ghcr.io/techofourown/sw-ourbox-os/platform-contract@sha256:<digest>
AIRGAP_PLATFORM_REF=ghcr.io/techofourown/sw-ourbox-os/airgap-platform@sha256:<digest>
```

These MUST be digest-pinned refs (never floating tags) in official builds.

To update when `sw-ourbox-os` ships a new bundle:

```bash
oras resolve ghcr.io/techofourown/sw-ourbox-os/platform-contract:edge
oras resolve ghcr.io/techofourown/sw-ourbox-os/airgap-platform:edge-amd64

# Update release/official-inputs.env with new digests, open a PR
```

---

## Cryptographic signatures and attestations

**No cryptographic signatures or attestations are currently used.**

Provenance is established via OCI annotations, digest-pinned upstream refs, and the
`os.meta.env`/`installer.meta.env` files accompanying each artifact. Consumers should use
artifacts by digest to ensure they receive exactly what was published.

---

## Compatible artifacts

Third parties may build compatible artifacts from this public source using the same documented
entrypoints, subject to their own environment configuration. Compatible artifacts built outside
TOOO-controlled publication are not official TOOO artifacts.

---

## References

- [OFFICIAL_ARTIFACT_BUILD_AND_PROVENANCE_POLICY](https://github.com/techofourown/org-techofourown/blob/main/docs/policies/OFFICIAL_ARTIFACT_BUILD_AND_PROVENANCE_POLICY.md)
- [ADR-0008: Organization-Controlled Build Infrastructure](https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0008-adopt-organization-controlled-build-infrastructure-for-heavy-artifacts.md)
- [ADR-0003: Distribute OS Artifacts via OCI Registry](./decisions/ADR-0003-distribute-os-artifacts-via-oci-registry.md)
- [ADR-0004: Consume Platform Contract from sw-ourbox-os](./decisions/ADR-0004-consume-platform-contract-from-sw-ourbox-os.md)
- [OPS.md — Operator Runbook](./OPS.md)
- `release/official-artifacts.env` — official publication targets
- `release/official-inputs.env` — digest-pinned upstream refs
