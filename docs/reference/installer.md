# Installer — OurBox Woodbox

## Installer media modes

### Thin ISO (default, recommended)

The installer USB does not contain an OS payload. At install time, `ourbox-preinstall` pulls the
OS artifact from the registry using the bundled ORAS binary. Requires internet access.

### Fat ISO (offline/local-build)

The OS payload is embedded in the ISO at build time (`build-installer-iso.sh --embed-payload`).
No network access is required at install time. `ourbox-preinstall` detects the embedded payload
and uses it directly. Produced by `./tools/prepare-installer-media.sh --build-local`.

---

## Installer defaults

Baked into ISO at build time: `/cdrom/ourbox/installer/defaults.env`

Shared selection policy is sourced from `/cdrom/ourbox/tools/installer-selection-resolver.sh`, the
upstream reference resolver defined in `sw-ourbox-os`.

The vendored resolver copy is checked in CI against the upstream revision recorded in
`tools/installer-selection-resolver.upstream.env`.

Shared installer SSH policy is sourced from `/cdrom/ourbox/tools/installer-ssh-helper.sh`, the
vendored helper that realizes the upstream installer SSH contract in
`sw-ourbox-os/docs/reference/installer-ssh-contract.md`.

Key variables:
- `INSTALLER_ID` — installer identity (`woodbox`)
- `OS_REPO` — OS payload registry namespace (`ghcr.io/techofourown/ourbox-woodbox-os`)
- `OS_TARGET` — build target (`x86`)
- `OS_CHANNEL` — default channel (`stable`)
- `OS_DEFAULT_REF` — optional digest/tag ref for the default "press Enter" install target
- `OS_CATALOG_ENABLED` — enable catalog-based version selection (`1`)
- `OS_CATALOG_TAG` — catalog tag (`x86-catalog`)
- `OS_ORAS_VERSION` — ORAS binary version bundled in the ISO
- `INSTALLER_VERSION` — version label baked at ISO build time
- `INSTALLER_GIT_HASH` — git SHA of this repo at ISO build time
- `INSTALL_DEFAULTS_REF` — optional remote install-defaults OCI ref; official installers bake this empty when `OS_DEFAULT_REF` is pinned
- `OURBOX_INSTALLER_SSH_MODE` — live-installer SSH mode (`off|key|password|both`)
- `OURBOX_INSTALLER_SSH_USER` — dedicated live-installer SSH user (`ourbox-installer`)
- `OURBOX_INSTALLER_SSH_PASSWORD_HASH` — optional pre-baked password hash; blank means generate a one-time password at boot
- `OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS` — optional authorized key material for key-capable modes
- `OURBOX_INSTALLER_SSH_ALLOW_ROOT` — root-login override (`0` by default)
- `OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY` — allow the Woodbox live installer to generate a one-time password locally when no hash is baked (`1` for official/public media)
- `OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR` — optional monitor UDP destination override (defaults to `255.255.255.255`)
- `OURBOX_INSTALLER_MONITOR_BROADCAST_PORT` — optional monitor UDP destination port override (defaults to `9999`)

Official/public Woodbox media currently builds with:
- `OURBOX_INSTALLER_SSH_MODE=both`
- `OURBOX_INSTALLER_SSH_USER=ourbox-installer`
- `OURBOX_INSTALLER_SSH_PASSWORD_HASH=''` (generated at boot; shown only on the attached console)
- `OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY=1`
- `OURBOX_INSTALLER_SSH_ALLOW_ROOT=0`

At install time, before disk selection, the operator may set a temporary live-installer SSH
password on TTY1. Pressing Enter keeps the current media posture unchanged.

When `INSTALL_DEFAULTS_REF` is used, the installer expects the upstream bundle shape published by
`sw-ourbox-os`:

- OCI pull output contains `dist/install-defaults.tar.gz`
- that tarball expands to:
  - `install-defaults/schema.env`
  - `install-defaults/manifest.env`
  - `install-defaults/defaults/<installer-id>.env`

A baked non-empty `OS_DEFAULT_REF` remains authoritative unless the remote profile explicitly
replaces it with another non-empty `OS_DEFAULT_REF`.

After a successful install, the installer attempts to prefer the installed OS for the next and
future UEFI boots. Removing the USB after poweroff is still recommended.

---

## Artifact contract (oras pull)

- Type: `application/vnd.techofourown.ourbox.woodbox.os-payload.v1`
- Required files:
  - `os-payload.tar.gz` — rootfs overlay + airgap bundle
  - `os-payload.tar.gz.sha256` — first field is SHA-256 hex digest; required
  - `os.meta.env` — KEY=VALUE metadata (version/target/sku/git sha/platform contract digest/k3s)
- Optional:
  - `os.meta.json` — JSON form of the same flat metadata map

---

## Installer runtime UX (ourbox-preinstall)

The `ourbox-preinstall` service runs on TTY1 before Subiquity starts. It:

0. **Step 0**: Optionally set a temporary password for the live-installer SSH account
1. **Step 1**: Operator selects the OS disk (any non-removable non-USB disk)
2. **Step 2**: Operator selects the DATA disk (all non-removable non-OS disks)
3. **Step 3**: Resolves OS artifact
   - Checks for embedded payload at `/cdrom/ourbox/payload/os-payload.tar.gz` (fat ISO)
   - Otherwise applies the shared precedence:
     1. `OS_REF`
     2. `OS_DEFAULT_REF`
     3. newest valid digest-pinned catalog row for `OS_CHANNEL`
     4. `${OS_REPO}:${OS_TARGET}-${OS_CHANNEL}` fallback
   - Interactive options mirror the shared resolver menu:
     - `c` choose channel (stable/beta/nightly/exp-labs/custom); named lanes prefer the newest
       digest-pinned catalog row and fall back to the lane tag only when catalog resolution is not
       available
     - `l` list digest-pinned catalog entries (newest first by `created`)
     - `r` enter a custom OCI ref
   - `o` override the OS repo/catalog defaults interactively
   - Catalog resolution is row-order independent and chooses the newest valid row by `created`
   - The resolver also accepts legacy target-qualified catalog rows during the migration window,
     but install-time provenance and summaries normalize those back to the short release-channel
     vocabulary (`stable`, `beta`, `nightly`, `exp-labs`)
   - Floating refs are resolved to digests with `oras resolve` and pulled immutably by digest unless
     `OURBOX_ALLOW_UNRESOLVED_PULL=1` is set for development/testing
   - Verifies SHA-256
   - Displays artifact info (version, variant, sha256, source ref, selection source)
4. **Step 4**: Operator sets hostname, username, and password
5. **Step 5**: Summary and final confirmation (`INSTALL`)

After operator confirmation, `ourbox-preinstall` writes `/autoinstall.yaml` (filled from
`/cdrom/ourbox/autoinstall.tpl`) and exits. Subiquity then runs fully automated.

At the end of late-commands, the installer attempts to identify the installed EFI entry on the
target ESP, set `BootNext` to it for the immediate next boot, and move that entry to the front of
`BootOrder` while preserving the relative order of the remaining entries. If EFI retargeting
cannot be performed confidently, the installer fails soft and still powers off.

---

## Live-installer SSH contract

The live installer keeps a dedicated diagnostics account:
- user: `ourbox-installer`
- config surface: `/etc/ssh/sshd_config.d/60-ourbox-installer.conf`
- status surface: `/run/ourbox-installer-ssh-status.env`
- bootstrap logic: `/cdrom/ourbox/tools/ourbox-installer-ssh-bootstrap.sh`

Shared mode/user/root/auth semantics come from the upstream installer SSH contract in
`sw-ourbox-os/docs/reference/installer-ssh-contract.md`. Woodbox vendors the corresponding helper
at `/cdrom/ourbox/tools/installer-ssh-helper.sh`, and CI checks that copy against the pinned
upstream revision in `tools/installer-ssh-helper.upstream.env`.

Behavior:
- `installer/autoinstall/user-data.tpl` stays a small cloud-config wrapper; the complex SSH bootstrap logic is staged into the ISO as a standalone shell script
- host keys are generated before `sshd -t`
- SSH is only advertised after validation and service startup succeed
- official/public media is password-capable again by default
- when no password hash is baked, the installer generates a one-time password at boot and shows it only on the attached console
- step 0 on TTY1 can replace that generated password with an operator-chosen temporary password for the live installer only
- generated-password handling, the status file, and the HTTP/UDP monitor surfaces are Woodbox-local layers on top of the upstream SSH contract
- HTTP/UDP monitor output never includes password material

Validation:
- `tools/validate-installer-seed.sh` renders and parses the NoCloud seed as YAML, asserts `bootcmd` exists, and optionally runs `cloud-init schema` when available
- `tools/build-installer-iso.sh` runs the rendered-seed validator before repacking the ISO
- official candidate / integration nightly / revalidation workflows boot a smoke ISO in QEMU before publishing or signing off on installer health

## Official builds

- Official Woodbox workflows now publish the OS payload first, then build the installer with that exact digest-pinned OS ref baked into `OS_DEFAULT_REF`.
- Official installers bake `INSTALL_DEFAULTS_REF=''` for deterministic default installs; operators can still override the defaults at install time.
- Push-to-`main` official candidate builds consume the generated pinned refs in `release/official-inputs.env` and publish the `beta` lane.
- Stable builds are a promotion of that already-published candidate digest once both candidate success and a matching published GitHub Release are present; they are not rebuilt on release.
- Scheduled nightly integration builds resolve the latest `sw-ourbox-os` `edge` platform bundle digests at workflow time and publish the `nightly` lane.
- GitHub prereleases authorize promotion of the same candidate digest into `exp-labs`, and either the candidate or the prerelease event may wake that promotion after the other condition already exists.
- Promotion is driven by `candidate-provenance.json`; it does not use artifact-carried `.env` sidecars as promotion control-plane inputs.

---

## Catalog TSV

Tag: `x86-catalog`

Columns: `channel tab created version variant target sku git_sha platform_contract_digest k3s_version payload_sha256 artifact_digest pinned_ref`

Updated automatically by `tools/publish-os-artifact.sh` when channel tags are pushed.
`channel` stores the short release channel name (`stable`, `beta`, `nightly`, `exp-labs`).
The resolver still accepts legacy target-qualified rows during the migration window, but
`OURBOX_RELEASE_CHANNEL` remains normalized to the short names above.

Resolver behavior does not depend on append order; `created` is authoritative.

---

## Autoinstall late-commands (payload extraction)

Late-commands in `autoinstall.tpl`:

1. Extract `os-payload.tar.gz` from `/opt/ourbox/installer/cache/payload/` to staging dir
2. Copy `rootfs/` overlay into `/target/`
3. Copy `airgap/` bundle into `/target/opt/ourbox/airgap/`
4. Install `k3s` binary from `airgap/k3s/k3s`
5. Append install-time provenance to `/target/etc/ourbox/release`
6. Enable required systemd services
7. Write DATA disk fstab entry
8. Configure netplan by MAC address
9. Format DATA disk as `OURBOX_DATA`
10. Prefer the installed EFI entry for the next and future UEFI boots

---

## Provenance written at install time

`/etc/ourbox/release` is extended by late-commands with install-time fields:
- `OURBOX_INSTALLER_ID`
- `OURBOX_INSTALLER_VERSION`
- `OURBOX_INSTALLER_GIT_HASH`
- `OURBOX_OS_ARTIFACT_SOURCE` (`registry` or `embedded`)
- `OURBOX_OS_ARTIFACT_REF`
- `OURBOX_OS_ARTIFACT_DIGEST`
- `OURBOX_OS_IMAGE_SHA256`
- `OURBOX_INSTALL_DEFAULTS_SOURCE`
- `OURBOX_INSTALL_DEFAULTS_REF`
- `OURBOX_INSTALL_SELECTION_SOURCE`
- `OURBOX_RELEASE_CHANNEL`
