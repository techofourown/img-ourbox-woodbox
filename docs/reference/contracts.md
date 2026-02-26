# OurBox Woodbox host contracts

This repo produces a custom Ubuntu Server installer ISO for x86-64 hardware (NVMe OS disk +
any-transport DATA disk) that guarantees a small set of contracts. These contracts are the
interface between "image build" and "k8s/apps".

## Contract: Release metadata

### File

- `/etc/ourbox/release`

### Format

Line-oriented `KEY=VALUE` pairs (shell-friendly). Keys:

- `OURBOX_PRODUCT`
- `OURBOX_DEVICE`
- `OURBOX_TARGET`
- `OURBOX_SKU`
- `OURBOX_VARIANT`
- `OURBOX_VERSION`
- `OURBOX_RECIPE_GIT_HASH` (recommended)
- `OURBOX_PLATFORM_CONTRACT_SOURCE` (required — see below)
- `OURBOX_PLATFORM_CONTRACT_REVISION` (required — see below)
- `OURBOX_PLATFORM_CONTRACT_VERSION` (optional, when known)
- `OURBOX_PLATFORM_CONTRACT_DIGEST` (optional, when OCI packaging exists)

### Platform contract provenance (normative)

Woodbox images MUST record the upstream OurBox OS platform contract provenance so operators can
answer:

- "Which platform baseline did this image ship?"
- "What upstream revision/digest does it correspond to?"

Minimum requirement (Phase 0+):
- `OURBOX_PLATFORM_CONTRACT_SOURCE`
- `OURBOX_PLATFORM_CONTRACT_REVISION`

When available, prefer also recording:
- `OURBOX_PLATFORM_CONTRACT_VERSION`
- `OURBOX_PLATFORM_CONTRACT_DIGEST`

See `docs/reference/platform-contract.md` for the full provenance model and vendoring workflow.

### Why it exists

- debugging ("what build is on this device?")
- fleet management ("what should this be running?")
- predictable support ("we can reproduce your image")

## Contract: Storage (DATA disk)

### Rule

- The DATA drive is **ext4** with filesystem label: `OURBOX_DATA`
- It mounts at: `/var/lib/ourbox`

### Implementation

The DATA disk is operator-selected during install (via `ourbox-preinstall` on TTY1). It can be any
non-removable, non-OS block device — SATA, SAS, NVMe, or other transports. The installer formats
it as GPT + single ext4 partition labeled `OURBOX_DATA` (via `format-data-disk.sh`).

The installed system mounts via `/etc/fstab`:

```fstab
LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2
```

Key properties:

- Uses **LABEL** (not `/dev/sda1`) to survive device enumeration changes
- Uses `nofail` so the system can boot without the data disk
- Uses a short systemd timeout to avoid slow boots
- DATA disk transport is not restricted — operator chooses from all eligible disks

### Intended contents of `/var/lib/ourbox`

This is where higher-level stacks should store persistent state:

- k3s storage / persistent volumes (`k3s/`)
- application state (`share/`, `flatnotes/`, `todo-bloom/`, `landing/`)
- device identity + secrets (`device/`, `secrets/`)
- bootstrap state markers (`state/`)
- logs (if desired)

(Exact directory layout is owned by the k8s/apps layer via `ourbox-bootstrap`.)

## Contract: Platform runtime (k3s)

- `k3s` binary exists at `/usr/local/bin/k3s`
- `k3s.service` exists and is enabled by bootstrap
- `ourbox-bootstrap.service` exists and runs on first boot
- Success marker: `/var/lib/ourbox/state/bootstrap.done`
- k3s data lives under `/var/lib/ourbox/k3s`
- Traefik ingress listens on hostPort 80/443
- mDNS aliases published for `{hostname}.local` + service subdomains

## Non-contracts (explicitly not guaranteed)

- No guarantee that the DATA disk is mounted if `ourbox-bootstrap` hasn't run
- Not trying to support non-x86-64 architectures
- Not trying to support running without a dedicated DATA disk
- mDNS alias publishing is best-effort (requires `avahi-daemon`)
- Application manifests are part of the airgap platform payload, not independently versioned (yet)

## Related ADRs

- ADR-0001: Consume platform contract from `sw-ourbox-os` (provenance + allocation)
