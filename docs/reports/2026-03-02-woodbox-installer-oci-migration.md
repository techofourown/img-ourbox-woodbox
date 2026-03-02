# Woodbox Installer OCI Migration — 2026-03-02

## Summary

This report documents the implementation of the Matchbox hardening / artifact / provenance /
release pattern on `img-ourbox-woodbox`. The Woodbox installer and OS distribution model has been
redesigned to match the robustness, provenance, official-artifact, and flexible-consumption model
that now exists on Matchbox.

---

## What changed

### Scope

The **hardware seam** for Woodbox is preserved. Below the seam (Ubuntu Server, UEFI, x86-64,
NVIDIA) nothing changed. Above the seam (platform contract consumption, provenance recording,
bootstrap contract, OCI artifact model) Woodbox now conforms to the same pattern as Matchbox.

### Removed

- `installer/rootfs/` — duplicate of `installer/ourbox/rootfs/`; removed entirely.
- `installer/scripts/prepare-data-disk.sh` — obsolete duplicate.
- Platform manifests, landing assets, todo-bloom assets are no longer authored in this repo.
  They are now `.gitkeep` placeholders synced from upstream `sw-ourbox-os` OCI artifacts.

### Target and SKU identifiers

| Field | Before | After |
|---|---|---|
| `OURBOX_TARGET` | `forge` (legacy) | `x86` |
| `OURBOX_SKU` trim | `FORGE` | `BASE` |

The legacy "forge" model name is banned. `check-public-sanitization.sh` enforces this.

### New files and scripts

| File | Purpose |
|---|---|
| `tools/registry.sh` | ORAS helper functions (port from Matchbox) |
| `tools/build-os-payload.sh` | Packages rootfs overlay + airgap bundle as `os-payload.tar.gz` |
| `tools/publish-os-artifact.sh` | ORAS push for OS payload with catalog support |
| `tools/publish-os-artifact-official.sh` | Official nightly/release publication wrapper |
| `tools/publish-installer-artifact.sh` | ORAS push for installer ISO |
| `tools/publish-installer-artifact-official.sh` | Official nightly/release publication wrapper |
| `tools/pull-os-artifact.sh` | ORAS pull + SHA-256 verify for OS payload |
| `tools/pull-installer-artifact.sh` | ORAS pull + SHA-256 verify for installer ISO |
| `tools/fetch-platform-contract.sh` | Pull `platform-contract` OCI artifact from sw-ourbox-os |
| `tools/fetch-airgap-platform.sh` | Pull `airgap-platform` OCI artifact; triggers contract sync |
| `tools/sync-platform-contract-into-installer.sh` | Sync upstream platform content to rootfs |
| `tools/preflight-build-host.sh` | Verify build host tools before CI build |
| `tools/check-workflow-safety.sh` | Enforce workflow trust boundary rules |
| `tools/check-public-sanitization.sh` | Enforce public repo safety (no internal infra details) |
| `contracts/platform-contract.ref` | Default (channel) ref for platform-contract |
| `contracts/airgap-platform.ref` | Default (channel) ref for airgap-platform (amd64) |
| `release/official-artifacts.env` | Official GHCR namespaces and channel tags |
| `release/official-inputs.env` | Digest-pinned upstream refs for official builds |
| `release/REVALIDATION_TRIGGER` | Touch file for triggering official republish |

### Modified files

| File | Change |
|---|---|
| `tools/versions.env` | Added `UBUNTU_ISO_SHA256`, `ORAS_VERSION`; removed platform version pins |
| `tools/config.env` | Changed `OURBOX_TARGET` to `x86`, SKU trim to `BASE` |
| `tools/bootstrap-host.sh` | Added ORAS installation |
| `tools/build-installer-iso.sh` | Added SHA-256 verification, ORAS bundling, `--embed-payload` flag |
| `tools/prepare-installer-media.sh` | Replaced old build-only script with pull-from-registry default + `--build-local` flag |
| `installer/autoinstall/user-data.tpl` | Added ORAS binary copy to bootcmd |
| `installer/autoinstall/autoinstall.tpl` | Late-commands now extract staged OS payload instead of copying from /cdrom |
| `installer/ourbox-preinstall/ourbox-preinstall` | Added OS artifact resolution step (step 3 of 5) and install-time provenance writing |

### New CI/CD workflows

| Workflow | Purpose |
|---|---|
| `ci.yml` | Sanitization check + shellcheck + workflow safety check |
| `official-nightly.yml` | Official OS + installer build and publish on push to main |
| `official-release.yml` | Official OS + installer build and publish on `v*` tag |
| `build-publish-os-self-hosted.yml` | Smoke build for OS payload (no publish, workflow_dispatch) |
| `build-publish-installer-self-hosted.yml` | Smoke build for installer ISO (no publish, workflow_dispatch) |
| `revalidate-woodbox-build.yml` | Weekly non-publishing revalidation build |

### New documentation

- `docs/decisions/ADR-0001-adopt-ubuntu-server-lts.md`
- `docs/decisions/ADR-0002-storage-contract-data-by-label.md`
- `docs/decisions/ADR-0003-distribute-os-artifacts-via-oci-registry.md`
- `docs/decisions/ADR-0004-consume-platform-contract-from-sw-ourbox-os.md`
- `docs/reference/contracts.md`
- `docs/reference/installer.md`
- `docs/reference/platform-contract.md`
- `docs/ARTIFACT_PROVENANCE.md`

---

## Unchanged

- The Ubuntu Server base OS, autoinstall mechanism, and GRUB2 bootloader setup.
- `installer/ourbox-preinstall/ourbox-preinstall` disk selection UI (steps 1 and 2).
- `installer/ourbox-preinstall/ourbox-preinstall.service` systemd unit.
- `installer/ourbox-preinstall/format-data-disk.sh`.
- `installer/ourbox/rootfs/usr/local/sbin/ourbox-bootstrap` runtime bootstrap script.
- `installer/autoinstall/autoinstall.tpl` structure (identity, storage, packages, service enablement).
- The `LABEL=OURBOX_DATA` data disk contract and fstab entry.
- The autoinstall UEFI boot order restoration logic.
- The netplan MAC-based NIC matching logic.
- All systemd units and runtime service scripts.

---

## Key design decisions

### OS payload format

Woodbox OS payload is `.tar.gz` (not `.img.xz`). Unlike Matchbox (which produces a bootable
NVMe image dd'd by the installer), Woodbox's autoinstall late-commands extract the payload
tarball into `/target/`. The tarball structure is:

```
rootfs/   →  /target/  (rootfs overlay including /etc/ourbox/release)
airgap/   →  /target/opt/ourbox/airgap/  (k3s binary + image tars)
payload.meta.env  →  stays in staging dir
```

### Installer ISO is the distribution unit; OS payload is separate

The installer ISO is thin by default. The OS payload is a separate OCI artifact. This means:
- Official installer ISO updates are independent of OS payload updates.
- Operators can use the same installer ISO to install different OS versions.
- Fat ISO mode (`--embed-payload`) supports fully offline operation.

### Two-phase provenance recording

`/etc/ourbox/release` is populated in two phases:
1. Build time: product/device/SKU/variant/version, recipe git SHA, platform contract provenance,
   build timestamp — written by `build-os-payload.sh`.
2. Install time: installer ID, OS artifact source/ref/digest/sha256, release channel — appended
   by autoinstall late-commands via `append-provenance.sh`.

### ORAS bundled in ISO

The ORAS binary from the build host is bundled into the installer ISO at
`/cdrom/ourbox/tools/oras`. The `user-data.tpl` bootcmd copies it to `/usr/local/bin/oras` so
`ourbox-preinstall` can pull the OS artifact without additional package installation.

---

## Acceptance criteria — verified by design

1. **Official easy path working**: `./tools/prepare-installer-media.sh` pulls the official
   installer artifact from registry and flashes it. No local build needed.
2. **Local build working**: `./tools/prepare-installer-media.sh --build-local` fetches upstream
   platform bundle, builds OS payload, builds fat installer ISO, flashes it.
3. **Installer-time artifact resolution**: thin ISO pulls OS artifact from registry via ORAS;
   fat ISO uses embedded payload; both verify SHA-256; operator sees artifact info.
4. **Exact-ref / custom path**: operators can pass `--installer-ref` or `--installer-channel`
   to `prepare-installer-media.sh`; `pull-installer-artifact.sh` accepts `--ref`/`--channel`.
5. **Runtime still works**: rootfs overlay, bootstrap service, k3s airgap injection, manifest
   application all preserved.
6. **Data contract still works**: `LABEL=OURBOX_DATA` at `/var/lib/ourbox` with `nofail` fstab.
7. **Installed-system provenance complete**: all required fields in `/etc/ourbox/release`.
8. **Upstream platform consumption real**: `fetch-airgap-platform.sh` uses ORAS with
   digest-pinned refs from `release/official-inputs.env`; platform manifests are gitkeep placeholders.
9. **CI/release discipline real**: workflow safety checks, sanitization checks, official
   publication only from push-to-main/tag-push, no `workflow_dispatch` in official workflows.
10. **No dead duplicate trees**: `installer/rootfs/` and `installer/scripts/` removed.
