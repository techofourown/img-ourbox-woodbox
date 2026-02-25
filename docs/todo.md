# OurBox Woodbox — Installer TODO / Scratch

## TODO: Remove all references to "forge" from the codebase

The "forge" target name appears in filenames, variable names, and comments but
serves no purpose. Clean it up.

## TODO: Installer USB must require user interaction before touching any disk

A USB stick that silently erases a computer's data on boot — with no interaction
beyond powering on — is dangerous. Even if it requires plugging in a keyboard,
that is a worthwhile trade-off to prevent accidental data loss. The installer
must never destructively modify any disk without explicit operator confirmation.

(This is now implemented via the pre-installer UI. Keep this note as a reminder
not to regress toward silent/automated installs without confirmation gates.)

## TODO: Username and password should be prompted on the Woodbox, not on the build host

Currently `prepare-installer-media.sh` prompts for hostname, username, and
password before building the ISO. This bakes identity into the installer media,
which means a USB stick prepared for Bob can't safely be handed to Alice.

We want the USB to be identity-neutral: one stick, many users.

Desired behaviour:
- Remove the username/password prompt from the build step entirely.
- Identity (username, password) should only be collected when the installer
  actually runs on the Woodbox — i.e. as part of the autoinstall flow on the
  target machine, not on the build host.
- Reconsider whether a default username should be offered at all (it
  pre-fills an answer that the user on the Woodbox should own).
- Hostname might still be build-time if it's meant to be baked in, but
  username/password definitely should not be.

Not a blocker for first successful Woodbox install. Park until then.

### Trade-off analysis (expanded)

The core tension is between two UX models:

**Option A — Identity at USB build time (current behaviour)**
- User enters username/password on their build machine when running `prepare-installer-media.sh`
- Advantage: the Woodbox install can be fully non-interactive — plug in USB, boot, walk away
- Advantage: no keyboard or monitor required on the Woodbox (except possibly to set boot order in UEFI/firmware, but that's not our problem — it's a one-time UEFI thing, not an OS installer thing)
- Disadvantage: identity is baked into the USB stick; you can't hand the same stick to someone else or ship a product image that works for all customers

**Option B — Identity at install time (on the Woodbox)**
- Username/password are collected when the autoinstall runs on the target machine
- Advantage: USB stick is identity-neutral; same stick works for any user; shippable as a product
- Disadvantage: requires a keyboard and monitor plugged into the Woodbox at install time — the only moment in the whole workflow where that's needed, which feels like a heavy ask

**Preferred direction — offer a choice at build time**

Add a prompt to `prepare-installer-media.sh` that asks:

  "Set username/password now (fully hands-free install on Woodbox, but
   this USB is personalised to you), or defer identity to the Woodbox
   install (USB is shareable/shippable, but requires keyboard + monitor
   on the target)?"

If the user chooses now: behave as today (bake credentials into autoinstall).
If the user chooses defer: omit credentials from the autoinstall seed; the
installer must pause and prompt for identity interactively on the Woodbox.

Notes:
- "Might not need keyboard/monitor" caveat: even with Option A, the user may
  need to enter UEFI to change boot order the first time. That's firmware, not
  our installer — mention it, but don't overstate it.
- Hostname is a separate question. It could reasonably stay build-time (baked
  in) even when credentials are deferred, or it could also be deferred. Decide
  separately.
- For a shippable product (many customers, one image), Option B / defer is
  almost certainly the right default. Option A is a power-user convenience.

## TODO: USB stick mount lifecycle management

Currently the script does not think carefully about whether the USB stick is
mounted at the start or end of the workflow. This is polish, not a blocker.

### At the start (before flashing)

If the user inserts the USB stick and their OS auto-mounts it (common on
desktop Linux, macOS, etc.), and they are actively browsing its contents,
the flash will either fail or corrupt the filesystem. The script should:
- Detect whether the selected device has any mounted partitions before flashing
- If mounted: warn the user clearly, tell them to unmount it (with the exact
  command, e.g. `sudo umount /dev/sdX*`), and either abort or offer to
  unmount automatically before proceeding
- Don't silently proceed — a mount-then-dd scenario is a data hazard

### At the end (after flashing)

After `dd` completes, the OS may auto-mount the newly written ISO partitions.
The "Next steps" message tells the user to boot the Woodbox, but does not tell
them to safely eject/remove the USB stick from the build machine first. Risks:
- User pulls USB while it's still mounted → filesystem corruption on the stick
- User forgets to remove USB from Woodbox after install completes → Woodbox
  reboots back into installer instead of NVMe

The script should:
- After flashing, explicitly eject/sync and optionally unmount the device
- Print a clear "safe to remove" message before saying "plug into Woodbox"
- The "Next steps" list needs a step 0 — currently it jumps straight to
  "Boot the Woodbox from this USB" without telling the user to first remove
  the stick from their build machine. Add:

    0) Safely eject and remove this USB from your build machine
    1) Boot the Woodbox from this USB (UEFI boot menu)
    2) The installer will run unattended (watch console for progress)
    3) When it powers off, remove the USB and boot from NVMe

- Step 3 (remove USB from Woodbox) should also be prominent — forgetting it
  causes a confusing re-install loop on next boot

### General note

Most of this may just be better terminal output and a couple of guard checks —
not a major rework. But the user mental model needs coaching: the USB stick
has distinct physical states (in build machine / in Woodbox / on the shelf)
and the script should acknowledge and guide each transition explicitly.

## TODO: Warn when USB is not high in UEFI boot priority

If a partial or failed install has already written a bootloader to the NVMe,
the machine may prefer NVMe over USB on the next boot — meaning the USB
installer never runs, and the machine boots into a broken half-installed OS
with no easy recovery path.

The installer (or the pre-install media instructions) should warn the operator:

- Before starting the install, check (or remind the user to check) that the
  USB is first in the UEFI boot order.
- If the machine has already had a previous install attempt, NVMe may now be
  bootable and ranked above USB. A partial install can leave the machine in a
  state where USB booting requires a manual UEFI intervention to recover.
- Suggest using `efibootmgr --bootorder` to place the USB entry first, or
  entering the UEFI boot menu (typically F12 / F2) to select USB manually.
- The consequence of getting this wrong is that the machine silently boots
  into a broken NVMe install instead of the USB installer — with no obvious
  error message.

## TODO: Do not print cryptographic material to the screen

The installer currently echoes or logs information that may include
cryptographic keys, hashes, or tokens (e.g. sha512crypt password hashes
generated by `openssl passwd -6`).

These should never appear on screen:
- Password hashes must not be printed to the terminal at any point — not in
  summaries, not in debug output, not in the generated autoinstall.yaml
  display if we ever add a "show config" step.
- Any device keys, bootstrap tokens, or secrets written during late-commands
  should not be echoed to console.
- Review all `log`, `echo`, and `cat` calls in ourbox-preinstall,
  format-data-disk.sh, and any late-command scripts for accidental secret
  exposure.

## TODO: Support OS reinstall while preserving DATA disk contents

Currently, reinstalling the OS (wiping and re-flashing the NVMe) while
keeping the existing SATA DATA disk breaks the boot sequence:

- `bootstrap.done` on the DATA disk causes `ourbox-bootstrap` to exit early
- k3s starts at boot (now enabled via late-commands) before bootstrap has
  hydrated the airgap image tars into `/var/lib/ourbox/k3s/agent/images/`
- Result: k3s is running but app pods fail with `ErrImageNeverPull` because
  the image cache is empty; the user must manually restart k3s after bootstrap

The right solution is to decouple "first-time data setup" from "ensure
platform is running" so that reinstalling the OS triggers a re-hydration and
re-application of manifests without destroying user data (flatnotes content,
todo items, uploaded files, device_id, k3s_token, etc.).

Possible approaches:

- **Split the bootstrap marker**: use separate markers for data init
  (`data.done`) and platform deployment (`platform.done`). On reinstall,
  delete only `platform.done` (via an installer late-command) so bootstrap
  re-applies manifests and re-hydrates images, but skips data initialisation.

- **k3s depends on bootstrap**: add `After=ourbox-bootstrap.service` and
  `Requires=ourbox-bootstrap.service` to `k3s.service` so k3s never starts
  before bootstrap has finished — regardless of whether bootstrap did a full
  run or a fast-path re-hydration. This ensures correct ordering without
  needing to manually restart k3s after reinstall.

- **Bootstrap always re-hydrates images**: remove the early `exit 0` on
  `bootstrap.done` for the hydration step specifically — always copy tars and
  always apply manifests, only skip data-destructive operations (wipefs, mkfs,
  etc.). This is the simplest change and handles the reinstall case cleanly.

The third option (always re-hydrate + re-apply, skip only destructive ops) is
probably the right default. User data lives under `/var/lib/ourbox/` subdirs
that bootstrap never touches after creation; manifests are idempotent via
`kubectl apply`; image tar copies are idempotent via the `[[ -f dst ]]` check.
