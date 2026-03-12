# Installer — OurBox Woodbox

## Media roles

Woodbox now distinguishes two different objects:

### Installer substrate

- target-owned boot/install runtime
- no selected OS bytes
- no selected `airgap-platform` bytes
- not a supported standalone install path

### Mission media

- composed on a trusted host
- substrate plus selected OS payload, selected `airgap-platform` bundle, and `mission-manifest.json`
- the only supported Woodbox install path
- installs fully offline on the target

The supported operator flow is mission composition in
`sw-ourbox-installer`, not target-side artifact selection.

## Media adapter surface

Woodbox exposes a narrow host-side media-adapter API at:

- `tools/media-adapter/adapter.json`
- `tools/media-adapter/validate-media.sh`
- `tools/media-adapter/compose-media.sh`

That surface is for host-side tooling such as `sw-ourbox-installer`.

Adapter contract:

- the host chooses exact artifact identities
- the host pulls and verifies exact bytes
- the adapter validates a prepared mission directory
- the adapter composes Woodbox media from those local bytes

The adapter does not own catalog browsing, ref resolution, registry pulls, or
target-side artifact discovery.

## Installer-local defaults

Baked into ISO at build time:

- `/cdrom/ourbox/installer/defaults.env`

This file now carries installer-local posture only. It does not carry OS
selection policy, `airgap-platform` selection policy, ORAS versioning, or
remote `install-defaults` state.

Current fields:

- `INSTALLER_ID`
- `INSTALLER_VERSION`
- `INSTALLER_GIT_HASH`
- `OURBOX_VARIANT`
- `OURBOX_INSTALLER_SSH_MODE`
- `OURBOX_INSTALLER_SSH_USER`
- `OURBOX_INSTALLER_SSH_PASSWORD_HASH`
- `OURBOX_INSTALLER_SSH_AUTHORIZED_KEYS`
- `OURBOX_INSTALLER_SSH_ALLOW_ROOT`
- `OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY`
- `OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR`
- `OURBOX_INSTALLER_MONITOR_BROADCAST_PORT`

Shared installer SSH policy is still sourced from the vendored helper at
`/cdrom/ourbox/tools/installer-ssh-helper.sh`, which realizes the upstream
installer SSH contract from `sw-ourbox-os`.

## Mission directory contract

Mission media embeds:

- `/cdrom/ourbox/payload/os-payload.tar.gz`
- `/cdrom/ourbox/payload/os-payload.tar.gz.sha256`
- `/cdrom/ourbox/payload/payload.meta.env`
- `/cdrom/ourbox/mission/mission-manifest.json`
- `/cdrom/ourbox/mission/artifacts/os/...`
- `/cdrom/ourbox/mission/artifacts/airgap/...`

`ourbox-preinstall` requires both:

- an embedded payload
- an embedded mission manifest

If either is missing, the install path is out of contract and the runtime fails
closed.

## Installer runtime UX (`ourbox-preinstall`)

The `ourbox-preinstall` service runs on TTY1 before Subiquity starts. It:

0. Optionally sets a temporary password for the live-installer SSH account
1. Prompts for the OS disk
2. Prompts for the DATA disk
3. Loads the staged OS payload from mission media
4. Stages the selected `airgap-platform` bundle from mission media
5. Prompts for hostname, username, and password
6. Prompts for final destructive confirmation (`INSTALL`)

Critical boundary:

- the target never browses catalogs
- the target never resolves refs
- the target never logs into registries
- the target never pulls OS or `airgap-platform` artifacts
- the target never fetches remote `install-defaults`

Step 3:

- stages `/cdrom/ourbox/payload/os-payload.tar.gz` into the installer cache
- verifies its SHA-256
- reads `payload.meta.env`
- reads `mission-manifest.json`
- loads selected OS provenance from the embedded mission manifest

Step 4:

- reads the selected `airgap-platform` identity from the embedded mission
  manifest
- if the mission-selected airgap bundle matches the baked bundle already inside
  the OS payload, uses the baked bundle
- otherwise extracts the staged mission airgap bundle into the override cache
- validates the extracted bundle locally against:
  - required `OURBOX_PLATFORM_CONTRACT_DIGEST`
  - expected `amd64` arch
  - required bundle shape and manifest fields

There is no target-side fallback selection path.

At the end of late-commands, the installer attempts to identify the installed
EFI entry on the target ESP, set `BootNext` to it for the immediate next boot,
and move that entry to the front of `BootOrder` while preserving the relative
order of the remaining entries. If EFI retargeting cannot be performed
confidently, the installer fails soft and still powers off.

## Live-installer SSH contract

The live installer keeps a dedicated diagnostics account:

- user: `ourbox-installer`
- config surface: `/etc/ssh/sshd_config.d/60-ourbox-installer.conf`
- status surface: `/run/ourbox-installer-ssh-status.env`
- bootstrap logic: `/cdrom/ourbox/tools/ourbox-installer-ssh-bootstrap.sh`

Behavior:

- `installer/autoinstall/user-data.tpl` stays a small cloud-config wrapper
- complex SSH bootstrap logic is staged into the ISO as a standalone script
- host keys are generated before `sshd -t`
- SSH is only advertised after validation and service startup succeed
- official/public media is password-capable by default
- when no password hash is baked, the installer generates a one-time password at
  boot and shows it only on the attached console
- step 0 on TTY1 can replace that generated password with an operator-chosen
  temporary password for the live installer only
- Woodbox keeps generated-password handling, the status file, and the HTTP/UDP
  monitor as repo-local behavior layered on top of the shared upstream SSH
  contract
- HTTP/UDP monitor output never includes password material

Validation:

- `tools/validate-installer-seed.sh` renders and parses the NoCloud seed as
  YAML, asserts `bootcmd` exists, and optionally runs `cloud-init schema` when
  available
- `tools/build-installer-iso.sh` runs the rendered-seed validator before
  repacking the ISO
- smoke workflows may still boot substrate media to validate the live installer
  environment itself

## Official build posture

Current Woodbox repo workflows still publish two artifact classes:

- OS payload artifact
- installer substrate ISO artifact

The supported operator install flow is not “flash the published substrate and
let the target resolve artifacts.” Instead:

- `sw-ourbox-installer` resolves the selected OS payload and selected
  `airgap-platform` bundle on the host
- `sw-ourbox-installer` composes mission media using the Woodbox adapter in this
  repo
- the target installs from those local mission bytes only

Candidate / nightly / stable / exp-labs publication in this repo still applies
to the OS payload and substrate artifacts that the host-side composer builds on
top of.

## Catalog TSV

Tag: `x86-catalog`

Columns:

- `channel`
- `created`
- `version`
- `variant`
- `target`
- `sku`
- `git_sha`
- `platform_contract_digest`
- `k3s_version`
- `payload_sha256`
- `artifact_digest`
- `pinned_ref`

The OS catalog is consumed on the host by `sw-ourbox-installer`. It is not a
target-side runtime input.

## Autoinstall late-commands (payload extraction)

Late-commands in `autoinstall.tpl`:

1. Extract `os-payload.tar.gz` from `/opt/ourbox/installer/cache/payload/`
2. Copy `rootfs/` overlay into `/target/`
3. Copy the baked airgap bundle into `/target/opt/ourbox/airgap/`
4. Install the `k3s` binary from `airgap/k3s/k3s`
5. If the mission-selected airgap bundle differs from the baked bundle, overlay
   the validated mutable airgap subset from the override cache
6. Append install-time provenance to `/target/etc/ourbox/release`
7. Enable required systemd services
8. Write DATA disk `fstab` entry
9. Configure netplan by MAC address
10. Format the DATA disk as `OURBOX_DATA`
11. Prefer the installed EFI entry for the next and future UEFI boots

## Provenance written at install time

`/etc/ourbox/release` is extended by late-commands with install-time fields:

- `OURBOX_INSTALLER_ID`
- `OURBOX_INSTALLER_VERSION`
- `OURBOX_INSTALLER_GIT_HASH`
- `OURBOX_OS_ARTIFACT_SOURCE`
- `OURBOX_OS_ARTIFACT_REF`
- `OURBOX_OS_ARTIFACT_DIGEST`
- `OURBOX_OS_IMAGE_SHA256`
- `OURBOX_INSTALL_SELECTION_SOURCE`
- `OURBOX_RELEASE_CHANNEL`
- `OURBOX_AIRGAP_PLATFORM_SOURCE`
- `OURBOX_AIRGAP_PLATFORM_REVISION`
- `OURBOX_AIRGAP_PLATFORM_VERSION`
- `OURBOX_AIRGAP_PLATFORM_CREATED`
- `OURBOX_AIRGAP_PLATFORM_ARCH`
- `OURBOX_AIRGAP_PLATFORM_PROFILE`
- `OURBOX_AIRGAP_PLATFORM_K3S_VERSION`
- `OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256`
- `OURBOX_AIRGAP_PLATFORM_ARTIFACT_SOURCE`
- `OURBOX_AIRGAP_PLATFORM_REF`
- `OURBOX_AIRGAP_PLATFORM_DIGEST`
- `OURBOX_AIRGAP_PLATFORM_SELECTION_SOURCE`
- `OURBOX_AIRGAP_PLATFORM_RELEASE_CHANNEL`
