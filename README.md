# img-ourbox-woodbox

OurBox Woodbox (TOO-OBX-WBX) — Ubuntu Server LTS installer media builder.

This repo produces a bootable USB installer that:

- Installs **Ubuntu Server LTS** onto a selected **SYSTEM** disk (NVMe)
- Enforces OurBox invariants:
  - `LABEL=OURBOX_DATA` mounted at `/var/lib/ourbox`
  - `/etc/ourbox/release`
  - first-boot bootstrap marker on DATA disk
  - airgap hydration (k3s + preloaded app images)
  - status reporter + MOTD
  - mDNS aliases (`files.<host>.local`, `notes.<host>.local`, `todo.<host>.local`)

The install flow is intentionally **interactive** at the console for safety.

## Quick start

```bash
git clone --recurse-submodules https://github.com/techofourown/img-ourbox-woodbox.git
cd img-ourbox-woodbox
./tools/prepare-installer-media.sh

# move media to Woodbox, boot, follow prompts, device powers off,
# remove media, boot from NVMe
```

## Retrying or starting over

The script writes a `.used` sentinel file the moment any real work begins.
If you run the script again in the same working tree, it will refuse and
tell you to reset first. This is intentional — we prioritise a known-good
state over saving a few minutes of download time.

**To reset and retry in place:**

```bash
git clean -fdx
./tools/prepare-installer-media.sh
```

`git clean -fdx` removes everything not tracked by git — downloaded
artifacts, built ISOs, the sentinel — and leaves you with a clean tree
identical to a fresh clone, but faster.

**To start from a completely fresh clone:**

```bash
cd ..
rm -rf img-ourbox-woodbox
git clone --recurse-submodules https://github.com/techofourown/img-ourbox-woodbox.git
cd img-ourbox-woodbox
./tools/prepare-installer-media.sh
```

## Requirements

- A Linux build host (Ubuntu/Debian recommended)
- `sudo`
- A USB drive (8GB+ recommended)
- Internet access during build (to fetch Ubuntu ISO + container images)

> Fully airgapped installs are possible, but you must pre-populate `artifacts/` yourself.

## Defaults you can override

All are optional environment variables:

- `OURBOX_SKU` (default: `TOO-OBX-WBX-FORGE-JU3XK8`)
- `OURBOX_VARIANT` (default: `prod`)
- `OURBOX_VERSION` (default: `dev`)
- `OURBOX_TARGET` (default: `forge`)
- `OURBOX_HOSTNAME` (default: `ourbox-woodbox`)
- `OURBOX_USERNAME` (default: `ourbox`)
- `OURBOX_PASSWORD_HASH` (default: a placeholder; installer prompts for identity)

Example:

```bash
OURBOX_VERSION=v0.1.0 OURBOX_VARIANT=dev ./tools/prepare-installer-media.sh
```

## NVIDIA driver note

The autoinstall runs `ubuntu-drivers install` during late-install.

- If the Woodbox has internet during install: drivers should install automatically.
- If you are **fully airgapped**, comment out the `ubuntu-drivers install ...` line in:
  - `installer/autoinstall/user-data.tpl`

Then install drivers later using your preferred offline method.

## Repo layout

- `installer/autoinstall/` — cloud-init autoinstall templates (NoCloud)
- `installer/ourbox/rootfs/` — files copied into the installed OS (`/target`) during late-commands
- `tools/` — build + flash scripts

