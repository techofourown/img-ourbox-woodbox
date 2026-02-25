# img-ourbox-woodbox

Build repository for **OurBox Woodbox** OS installer media targeting **Woodbox hardware** (x86-64, NVMe system disk + SATA data disk).

This repo produces a bootable USB installer that installs Ubuntu Server LTS, mounts `/var/lib/ourbox` on the SATA data disk, and boots into an airgapped single-node k3s runtime via `ourbox-bootstrap`.

## Identifiers used by this repo

- **Model ID**: `TOO-OBX-WBX` (physical device class)
- **Default SKU (part number)**: `TOO-OBX-WBX-BASE-001` (exact BOM/software build)

Model identifies the physical hardware class; SKU identifies the exact bill-of-materials and software configuration.

## Docs

- Operator runbook: [`docs/OPS.md`](./docs/OPS.md)

## Happy path (build host → USB installer → Woodbox install)

```bash
cd ~
git clone --recurse-submodules https://github.com/techofourown/img-ourbox-woodbox.git
cd img-ourbox-woodbox
./tools/prepare-installer-media.sh
# plug USB into Woodbox, boot, follow prompts, device powers off, remove USB, boot from NVMe
```

The installer requires a keyboard and monitor on the Woodbox at install time. It will prompt for OS disk selection, DATA disk selection, hostname, username, and password before writing anything to disk.
