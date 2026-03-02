# ADR-0002: Adopt a label-based data mount contract for OurBox Woodbox


## Context

OurBox Woodbox hardware includes at minimum two storage devices:

- an **NVMe** drive that receives the OS image during installation
- a **DATA** drive (typically SATA SSD) intended for persistent application storage

Device enumeration order (`nvme0n1`, `sda`, etc.) is not guaranteed across boots, firmware
versions, driver updates, or hardware differences. Mounting storage by kernel path risks mounting
the wrong device.

We need a deterministic, low-risk contract that:

- survives device enumeration changes and hardware revisions
- supports safe automation
- avoids bricking the device when the data disk is missing or slow to appear

This contract must also survive OS reinstalls: when the OS NVMe is reflashed, the DATA disk
retains its contents and its label, so the new OS can mount it immediately on first boot.

## Decision

We will standardize on:

- DATA filesystem: **ext4**
- DATA identity: filesystem **LABEL = `OURBOX_DATA`**
- Mount point: `/var/lib/ourbox`
- fstab entry uses label + resilient options:

```fstab
LABEL=OURBOX_DATA /var/lib/ourbox ext4 defaults,noatime,nofail,x-systemd.device-timeout=10 0 2
```

The installer (`ourbox-preinstall` + autoinstall late-commands) formats the operator-selected DATA
disk as `OURBOX_DATA` and appends the fstab entry to the installed system.

## Rationale

- Label-based mounts are stable and human-auditable.
- Label approach works well for field recovery ("relabel disk, reboot").
- `nofail` ensures we can boot even if the data disk is absent.
- Short timeout prevents slow-boot failures due to SATA/NVMe timing.
- The same contract is used on Matchbox (`LABEL=OURBOX_DATA`, `/var/lib/ourbox`) — cross-platform
  consistency reduces cognitive overhead for operators managing multiple OurBox models.

## Consequences

### Positive

- Strong protection against wrong-disk mounts
- Simpler recovery story: relabeling a replacement disk is sufficient
- Works without additional discovery logic
- OS reinstalls preserve DATA disk contents; new OS immediately re-mounts at correct path

### Negative

- Requires the DATA disk to be formatted and labeled correctly at install time
- ext4 is Linux-native (not directly readable on Windows/macOS without third-party software)

### Mitigation

- The `format-data-disk.sh` script and installer late-commands handle formatting at install time
- Document the labeling and format steps in `docs/OPS.md`
- Keep the contract small and explicit; avoid hidden magic
