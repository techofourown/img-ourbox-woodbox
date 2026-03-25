# Installer — OurBox Woodbox

## Media roles

Woodbox now distinguishes two different objects:

### Installer substrate

- target-owned boot/install runtime
- no selected OS bytes
- no selected `ourbox-substrate` bytes
- not a supported standalone install path

### Mission media

- composed on a trusted host
- substrate plus selected OS payload, a synthesized application bundle derived
  from one or more selected application catalogs, selected-app metadata, and
  `mission-manifest.json`
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
selection policy, `ourbox-substrate` selection policy, ORAS versioning, or
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
- `/cdrom/ourbox/apt/Packages.gz`
- `/cdrom/ourbox/apt/target-packages.txt`
- `/cdrom/ourbox/mission/mission-manifest.json`
- `/cdrom/ourbox/mission/artifacts/os/...`
- `/cdrom/ourbox/mission/artifacts/substrate/...`

When the selected catalog advertises application-catalog metadata, the mission
also carries:

- `/cdrom/ourbox/mission/artifacts/substrate/catalog.json`
- `/cdrom/ourbox/mission/artifacts/substrate/selected-apps.json`

When the host-side composer stages installed-target SSH key auth, the mission
also carries:

- `/cdrom/ourbox/mission/artifacts/installed-target-ssh/authorized-key.pub`

The live installer reuses that same staged public key for `ourbox-installer`
SSH access when the media carries it.

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
4. Stages the selected `ourbox-substrate` bundle from mission media
   and stages the selected application catalog / selected app set metadata
5. Prompts for hostname, username, password, and installed-target SSH password posture
6. Prompts for final destructive confirmation (`INSTALL`)

Critical boundary:

- the target never browses catalogs
- the target never resolves refs
- the target never logs into registries
- the target never pulls OS or `ourbox-substrate` artifacts
- the target never fetches remote `install-defaults`

Step 3:

- stages `/cdrom/ourbox/payload/os-payload.tar.gz` into the installer cache
- verifies its SHA-256
- reads `payload.meta.env`
- reads `mission-manifest.json`
- loads selected OS provenance from the embedded mission manifest

Step 4:

- reads the selected `ourbox-substrate` identity from the embedded mission
  manifest
- reads the selected application catalog ids and selected app ids from the
  embedded mission manifest
- if the mission-selected substrate bundle matches the baked bundle already inside
  the OS payload, uses the baked bundle
- otherwise extracts the staged mission substrate bundle into the override cache
- validates the extracted bundle locally against:
  - expected `amd64` arch
  - required bundle shape and manifest fields
- requires baked/selected application metadata to already exist in-band as:
  - `platform/catalog.json`
  - `platform/selected-apps.json`
  - `platform/images.lock.json`
- stages `catalog.json` and `selected-apps.json` into the installer cache

There is no target-side fallback selection path.

Before Subiquity handoff, `ourbox-preinstall` also:

- renders the final target netplan from sysfs Ethernet inventory
- stages wrappers for late-commands to:
  - install required target packages from `/cdrom/ourbox/apt` only
  - optionally install and configure `openssh-server` from that same local repo
  - copy the prepared netplan into `/target/etc/netplan/00-installer-config.yaml`

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
- when mission media carries a staged installed-target SSH public key, the live
  installer also authorizes that same key for `ourbox-installer`
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
  application catalogs on the host
- `sw-ourbox-installer` merges those catalogs into one effective catalog on the host
- `sw-ourbox-installer` chooses the selected app set from that merged catalog on the host
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
- `tag`
- `created`
- `version`
- `variant`
- `target`
- `sku`
- `git_sha`
- `k3s_version`
- `payload_sha256`
- `artifact_digest`
- `pinned_ref`

The OS catalog is consumed on the host by `sw-ourbox-installer`. It is not a
target-side runtime input.

Older examples may still mention a legacy contract-metadata column. That is
legacy wording and not part of the current host-side selection contract.

## Autoinstall late-commands (payload extraction)

Late-commands in `autoinstall.tpl`:

1. Extract `os-payload.tar.gz` and copy the payload rootfs + baked substrate bytes into `/target/`
2. Install the remaining target packages from the substrate-local APT repo only
3. If the mission-selected substrate bundle differs from the baked bundle, overlay the validated mutable substrate subset from the override cache
4. Copy the selected application catalog metadata (`catalog.json` and `selected-apps.json`) into the target platform directory
5. Install the `k3s` binary from `substrate/k3s/k3s`
6. Append install-time provenance to `/target/etc/ourbox/release`
7. Configure installed-target SSH when a staged host key or target-side password SSH was requested
8. Enable required systemd services
9. Write DATA disk `fstab` entry
10. Copy the prepared netplan rendered from NIC hardware inventory
11. Verify the DATA disk prepared by `ourbox-preinstall`
12. Prefer the installed EFI entry for the next and future UEFI boots

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
- `OURBOX_SUBSTRATE_SOURCE`
- `OURBOX_SUBSTRATE_REVISION`
- `OURBOX_SUBSTRATE_VERSION`
- `OURBOX_SUBSTRATE_CREATED`
- `OURBOX_SUBSTRATE_ARCH`
- `OURBOX_SUBSTRATE_PROFILE`
- `OURBOX_SUBSTRATE_K3S_VERSION`
- `OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256`
- `OURBOX_SUBSTRATE_ARTIFACT_SOURCE`
- `OURBOX_SUBSTRATE_REF`
- `OURBOX_SUBSTRATE_DIGEST`
- `OURBOX_SUBSTRATE_SELECTION_SOURCE`
- `OURBOX_SUBSTRATE_RELEASE_CHANNEL`
- `OURBOX_APPLICATION_CATALOG_ID`
- `OURBOX_APPLICATION_CATALOG_NAME`
- `OURBOX_APPLICATION_SELECTION_MODE`
- `OURBOX_SELECTED_APPLICATION_IDS`
