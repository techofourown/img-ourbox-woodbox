# ADR-0003: Distribute OS payload and installer artifacts as OCI artifacts via a container registry


## Context

Woodbox builds produce two large artifacts that must be transferred to other machines for
installation and recovery:

1. **OS payload** — a `.tar.gz` containing the rootfs overlay, airgap bundle (k3s + image tars),
   and platform contract content, staged at install time from the installer USB.
2. **Installer ISO** — a bootable Ubuntu autoinstall ISO that the operator flashes to a USB stick
   and boots on the Woodbox.

Ad-hoc file transfer (SCP/USB) works but is inconsistent and hard to standardize. We need a
distribution mechanism that is reproducible, content-addressed, and integrates with existing CI.

We already operate a container registry (GHCR) and have standard tooling (ORAS) for pushing and
pulling OCI artifacts efficiently.

## Decision

We will distribute OS payload and installer artifacts as **OCI artifacts (non-runnable)** pushed
with **ORAS**, not as container layers. Each artifact carries files directly:

**OS payload artifact:**
- `os-payload.tar.gz`
- `os-payload.tar.gz.sha256`
- `os.meta.env` (KEY=VALUE metadata)

**Installer artifact:**
- `installer.iso`
- `installer.iso.sha256`
- `installer.meta.env` (KEY=VALUE metadata)

Artifact types:
- OS payload: `application/vnd.techofourown.ourbox.woodbox.os-payload.v1`
- Installer: `application/vnd.techofourown.ourbox.woodbox.installer.v1`

Implemented by:

- `tools/publish-os-artifact.sh` (oras push, supports immutable + channel tags, updates catalog)
- `tools/pull-os-artifact.sh` (oras pull, sha verification)
- `tools/publish-installer-artifact.sh` (oras push, immutable + channel tags)
- `tools/pull-installer-artifact.sh` (oras pull, sha verification)

The installer USB operates in two modes:
- **Thin ISO** (default): the USB does not contain an OS payload; `ourbox-preinstall` pulls it
  from the registry at install time using the bundled ORAS binary.
- **Fat ISO** (`--embed-payload`): the OS payload is embedded in the ISO for offline operation;
  `ourbox-preinstall` detects and uses it without a network pull.

## Rationale

- Registries solve "large artifact distribution" well (storage + content addressing + caching).
- ORAS operates without a container runtime — suitable for the live Ubuntu installer environment.
- The artifact reference becomes a stable, digest-addressable identifier.
- Catalog artifacts (`x86-catalog`) let installers list available versions without downloading.

## Consequences

### Positive
- Standard transport path for OS payload and installer artifacts
- Easier repeatability ("pull this ref and install it")
- Digest-addressable — consumers can pin exactly what they use
- Works without a container runtime on the installer (ORAS only)
- Catalog tag enables version browsing at install time

### Negative
- Requires registry access for thin-ISO installs; fat ISO mitigates for offline scenarios
- Requires ORAS on build hosts and bundled in installer ISO (we bootstrap/bundle it)

### Mitigation
- Keep direct-download (SCP/USB) as a documented fallback path
- Maintain metadata alongside artifacts (`os.meta.env`, `installer.meta.env`)
- Use `--embed-payload` mode for fully offline/local-build operation
- Bundle ORAS binary into the installer ISO so it's available without network access

---

## Notes

This ADR covers **transporting OS payload bytes and installer ISOs** using OCI registry mechanics.
It is compatible with the org-wide OCI posture (org ADR-0007), but intentionally narrower:

- It does **not** decide how apps are distributed (org ADR-0007).
- It does **not** define the OurBox OS platform contract. Platform contract provenance and
  consumption are handled by ADR-0004 and the upstream `sw-ourbox-os` documentation.

---

## References

- Org ADR-0007 (OCI substrate for apps + platform components):
  https://github.com/techofourown/org-techofourown/blob/main/docs/decisions/ADR-0007-adopt-oci-artifacts-for-app-distribution.md
- `sw-ourbox-os` ADR-0009 (platform contract as OCI artifact):
  https://github.com/techofourown/sw-ourbox-os/blob/main/docs/decisions/ADR-0009-package-the-platform-contract-as-an-oci-artifact.md
- `sw-ourbox-os` integration reference:
  https://github.com/techofourown/sw-ourbox-os/blob/main/docs/architecture/artifact-distribution-and-integration.md
- ADR-0004 (this repo): Consume platform contract from `sw-ourbox-os`
