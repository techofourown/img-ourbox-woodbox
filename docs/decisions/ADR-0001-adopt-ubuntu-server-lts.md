# ADR-0001: Adopt Ubuntu Server LTS as the Base Operating System for OurBox Woodbox


## Context

OurBox Woodbox (TOO-OBX-WBX) is a physical appliance built around a **desktop-class x86-64 machine**
with NVMe storage, designed to run the OurBox software stack (delivered primarily via containers,
orchestrated by k3s). The product's trust promise depends not only on open-source code, but also
on the long-term ability to keep devices secure, stable, and supportable as a shipped product.

We must choose a **single supported/validated base OS** for Woodbox that minimizes hardware
enablement surprises (UEFI, NVMe, networking), reduces support burden, and provides a stable
baseline for years of updates. The OS choice should align with TOOO's principles of user autonomy
and avoid unnecessary ecosystem lock-in.

Candidates considered for Woodbox x86-64 hardware: **Ubuntu Server LTS**, **Debian Stable**, and
**Fedora Server**. The decision is specific to Woodbox's x86-64 hardware; other OurBox SKUs may
choose different baselines (e.g., Matchbox uses Raspberry Pi OS Lite for Pi-specific reasons).

Ubuntu Server LTS provides the `subiquity` autoinstall framework (cloud-init + YAML configuration)
which enables a fully automated, unattended OS installation from a bootable ISO — essential for the
Woodbox "USB installer" product experience.

## Decision

For **OurBox Woodbox (TOO-OBX-WBX)**, we will adopt **Ubuntu Server LTS (24.04 LTS, x86-64)** as
the supported/validated base operating system.

OurBox's application stack is **container-first** (k3s + workloads), so the base OS is responsible
for **hardware enablement, UEFI boot, networking, storage, and first-boot automation**. The OS is
treated as "firmware + host," not as an application platform.

## Rationale

Ubuntu Server LTS is selected because it provides the best combination of autoinstall capability,
x86-64 hardware compatibility, and long-term supportability:

- **Subiquity autoinstall is purpose-built for Woodbox's install flow.** Ubuntu's cloud-init-based
  autoinstall (`subiquity`) allows declarative, fully automated OS installation from a bootable
  ISO — including custom disk layouts, identity configuration, and late-command scripting. This
  is how the Woodbox installer works: `ourbox-preinstall` captures operator choices at boot time
  and writes the final `autoinstall.yaml` before `subiquity` runs.
- **Best-fit for x86-64 hardware.** Ubuntu Server LTS provides excellent x86-64 support including
  UEFI, NVIDIA drivers (`ubuntu-drivers`), NVMe, and standard PCIe peripherals with no special
  configuration needed.
- **Long-term stability and security.** LTS releases are supported for 5 years (with ESM for 10).
  This aligns with Woodbox's aim to ship stable, long-running appliances.
- **Aligns with TOOO autonomy goals.** Ubuntu Server LTS is a widely understood, inspectable Linux
  base. Users can rebuild, inspect, and maintain their device without platform lock-in.

Debian Stable is equally principled but lacks the `subiquity` autoinstall framework, requiring
additional tooling to achieve the same unattended installation UX. Fedora has a shorter support
lifecycle and slower adoption in appliance contexts.

## Consequences

### Positive
- **Automated installer with declarative configuration** via subiquity and cloud-init NoCloud.
- **Standard package ecosystem** with apt/dpkg and excellent hardware driver support.
- **UEFI-native** boot with standard GRUB2, compatible with all modern x86-64 hardware.
- **NVIDIA driver support** available via `ubuntu-drivers` for GPU-equipped Woodbox variants.
- **Long LTS support cycle** suitable for appliance lifetimes.

### Negative
- **Large ISO** (approximately 2 GB base Ubuntu Server ISO) required as the installer media base.
- **Snap packages** included in base Ubuntu Server; we do not use them but accept their presence.
- **Non-transactional OS updates** by default; we must be intentional about OS update practices.

## Mitigation
- Keep the installed OS minimal: the base OS is firmware + host. All features run in containers.
- Accept the large ISO size; the OS payload artifact separates OS identity from installer media.
- Document the OS update / reinstall path in `docs/OPS.md`.
- Re-evaluate the base OS per future LTS releases or if hardware requirements change significantly.

## References

- Ubuntu Server autoinstall reference: https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html
- Matchbox ADR-0001 (Raspberry Pi OS Lite for Pi hardware): comparison reference
- ADR-0002: Storage contract (`LABEL=OURBOX_DATA`)
- ADR-0003: Distribute OS artifacts via OCI registry
