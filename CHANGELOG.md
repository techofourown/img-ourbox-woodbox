# [0.4.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.3.3...v0.4.0) (2026-03-06)


### Bug Fixes

* **build:** silence shellcheck on crypt hash literal ([d75e523](https://github.com/techofourown/img-ourbox-woodbox/commit/d75e523ad0fdeaa27024a3efc317ecc01bcb023a))
* **installer-ssh:** avoid Match blocks and validate sshd config ([ec4b839](https://github.com/techofourown/img-ourbox-woodbox/commit/ec4b8397b343b8fdfe09c56127eeee05b772fafc))
* **installer-ssh:** honor passwd home for authorized_keys path ([a820ed4](https://github.com/techofourown/img-ourbox-woodbox/commit/a820ed430c891fe10fc20d90f57579879bf4b820))


### Features

* **installer:** standardize installer SSH diagnostics contract ([e78de27](https://github.com/techofourown/img-ourbox-woodbox/commit/e78de2701ccb733f437f5e0df0089861b93875dc))

## [0.3.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.3.1...v0.3.2) (2026-03-05)


### Bug Fixes

* **installer:** keep resolver output machine-readable and reject contaminated refs ([991aa75](https://github.com/techofourown/img-ourbox-woodbox/commit/991aa750ab03669f7ec26c0e137cd9150507ca33))

## [0.3.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.3.0...v0.3.1) (2026-03-04)


### Bug Fixes

* **installer:** avoid bootcmd blocking service starts ([cab91ee](https://github.com/techofourown/img-ourbox-woodbox/commit/cab91eedd4fddb3caedcde853eb04a1562f5f04d))

# [0.3.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.8...v0.3.0) (2026-03-04)


### Features

* broadcast installer events over network for zero-config monitoring ([5d849fa](https://github.com/techofourown/img-ourbox-woodbox/commit/5d849fa4b40eec5faeaa5fbe21bb88c3d487d02a))

## [0.2.8](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.7...v0.2.8) (2026-03-04)


### Bug Fixes

* power off after install and add installer observability ([4c30a3b](https://github.com/techofourown/img-ourbox-woodbox/commit/4c30a3b80fd5f2e7b49c83727a195fff21733c78))
* quote late-commands containing colon-space to prevent YAML parse error ([4a0fc3e](https://github.com/techofourown/img-ourbox-woodbox/commit/4a0fc3e909ae521a36e6fb6d6b76cce5b241e4be)), closes [#15](https://github.com/techofourown/img-ourbox-woodbox/issues/15)

## [0.2.7](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.6...v0.2.7) (2026-03-04)


### Bug Fixes

* update storage match comment to show non-NVMe device path example ([42cb0bd](https://github.com/techofourown/img-ourbox-woodbox/commit/42cb0bd0cf9e6c7e407a0396be573415d77eea96))

## [0.2.6](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.5...v0.2.6) (2026-03-03)


### Bug Fixes

* pin airgap-platform to digest for release builds ([9e5f8c0](https://github.com/techofourown/img-ourbox-woodbox/commit/9e5f8c0ae3aa0328e53605f94a327fcfdf9a50b5))

## [0.2.5](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.4...v0.2.5) (2026-03-03)


### Bug Fixes

* correct xargs split exit code in sanitization scan ([6e04d45](https://github.com/techofourown/img-ourbox-woodbox/commit/6e04d451d95c646a621abb0962193122fbe71834))

## [0.2.4](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.3...v0.2.4) (2026-03-03)


### Bug Fixes

* switch official-release trigger to release:published ([8c72e90](https://github.com/techofourown/img-ourbox-woodbox/commit/8c72e90e3d348cb9581f48172790fb0baea0e999))
* tighten rule 4 — require exactly types:[published], nothing else ([d37b27b](https://github.com/techofourown/img-ourbox-woodbox/commit/d37b27b75a4d9ab8d8bf615bff09b9e34603b612))

## [0.2.3](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.2...v0.2.3) (2026-03-03)


### Bug Fixes

* quote GITHUB_WORKFLOW in meta.env writes to survive spaces ([c806a42](https://github.com/techofourown/img-ourbox-woodbox/commit/c806a427399bfe7241c64c04b9607001625cd6e1))

## [0.2.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.1...v0.2.2) (2026-03-03)


### Bug Fixes

* correct Ubuntu 24.04.3 ISO SHA256 ([f3d1ad5](https://github.com/techofourown/img-ourbox-woodbox/commit/f3d1ad518369b675c9fd71ff91d6b782bf4d2873))
* sanitize CHANGELOG entry containing banned term ([c783827](https://github.com/techofourown/img-ourbox-woodbox/commit/c78382765893563e92f5a6ec638dc3dace21440e))

## [0.2.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.2.0...v0.2.1) (2026-03-02)


### Bug Fixes

* align sanitization checks with Matchbox — expand banned terms ([e820820](https://github.com/techofourown/img-ourbox-woodbox/commit/e8208202463a0e0b8533c176f80f06e1c0f4a9a7))
* reclaim workspace ownership before checkout in official workflows ([fc980bd](https://github.com/techofourown/img-ourbox-woodbox/commit/fc980bd04626368e26c42298a69c8e3adcac75cc))

# [0.2.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.1.0...v0.2.0) (2026-03-02)


### Bug Fixes

* address PR review blockers — channel semantics, catalog lane, provenance ([be692f2](https://github.com/techofourown/img-ourbox-woodbox/commit/be692f2f1fa547ae36200b6c1ce839d8c875de50))
* config.env must not clobber CI-provided environment variables ([4fe6e9b](https://github.com/techofourown/img-ourbox-woodbox/commit/4fe6e9b7fd13d78c8e7cc179d13e2416652b9f05))
* deploy sidecar, official-inputs wiring, catalog short-names, ORAS arch ([5b4e245](https://github.com/techofourown/img-ourbox-woodbox/commit/5b4e2455ee6171aba078334d76637402c287b76c))
* digest ref parsing for port registries; idempotent payload staging ([5392c83](https://github.com/techofourown/img-ourbox-woodbox/commit/5392c834c86e850adbc1cdae4e87a31525830987))
* disable SC2016 for intentional single-quoted envsubst vars in preinstall ([7040e48](https://github.com/techofourown/img-ourbox-woodbox/commit/7040e48779103ed3484b4edace02b5e24a1175aa))
* remote install-defaults lane, OS_DEFAULT_REF, interactive override ([af57f55](https://github.com/techofourown/img-ourbox-woodbox/commit/af57f5553abb332c1cf57f156593b88a00d3feb7))
* resolve CI sanitization and shellcheck failures ([43ff9a1](https://github.com/techofourown/img-ourbox-woodbox/commit/43ff9a1154224557dee102dff928db42e8369f01))
* runnable official workflows — bootstrap order, CI mode, workspace cleanup ([3b102e3](https://github.com/techofourown/img-ourbox-woodbox/commit/3b102e392b48d4f4776ed47923309e1793dafd1e))
* set executable bit on 7 scripts invoked as executables in workflows ([52f2b76](https://github.com/techofourown/img-ourbox-woodbox/commit/52f2b7613c074f62b919ad1965bcb8837b7f3fc1))
* strict artifact identity, installer provenance, ORAS checksum ([24b3813](https://github.com/techofourown/img-ourbox-woodbox/commit/24b3813f6cf936b3efd17b396665ca00dc661136))


### Features

* adopt OCI artifact model for Woodbox OS payload and installer ([3fe4f45](https://github.com/techofourown/img-ourbox-woodbox/commit/3fe4f45cc2cbd160749ce5ce5110bb7cc055a139))

# [0.1.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.0.0...v0.1.0) (2026-02-27)


### Bug Fixes

* always format DATA disk — remove blkid idempotency skip ([8db1ca7](https://github.com/techofourown/img-ourbox-woodbox/commit/8db1ca7b4a60e9e7cca2e122e3ab9aa4c96ac549))
* bump Ubuntu ISO to 24.04.3 (24.04.1 returns 404) ([aa9c3ef](https://github.com/techofourown/img-ourbox-woodbox/commit/aa9c3ef18ab70932a89d5334605388f0e04014c6))
* ensure k3s starts on reinstall when bootstrap.done already exists ([375ec14](https://github.com/techofourown/img-ourbox-woodbox/commit/375ec1415c11b582014b36eca1b27d79cad97bef))
* escape sha512crypt placeholder hash to avoid unbound variable ([7c43bd3](https://github.com/techofourown/img-ourbox-woodbox/commit/7c43bd36102e48378a0248cb41355db4654d90e4))
* match netplan NIC by MAC address instead of interface name wildcard ([1238f4f](https://github.com/techofourown/img-ourbox-woodbox/commit/1238f4fef67f6defb94b3447a0bdbae53e8963cc))
* match target disk by path instead of serial to avoid sysfs whitespace mismatch ([7e8a2b2](https://github.com/techofourown/img-ourbox-woodbox/commit/7e8a2b2f628b01ce30ad0268e642179add2ada0f))
* netplan wildcard match + auto-format SATA data disk in late-commands ([86664f5](https://github.com/techofourown/img-ourbox-woodbox/commit/86664f54a0b1ac4ceff4d477226ee26eb152fc79))
* pre-select ssd/nvme as default storage target ([20c7a6d](https://github.com/techofourown/img-ourbox-woodbox/commit/20c7a6dbdb55bc564985343b75255c0e837b6115))
* rebuild ISO with hybrid GPT/EFI boot structure for Ubuntu 24.04 ([a00edd6](https://github.com/techofourown/img-ourbox-woodbox/commit/a00edd6a895fd0d956ce3297965765af7f38eb76))
* redirect password-echo newlines to stderr to avoid polluting hash capture ([818ac1f](https://github.com/techofourown/img-ourbox-woodbox/commit/818ac1f051243e22ff0cee670af971f38e408fd6))
* rewrite fstab late-command as single line to avoid YAML scalar folding ([479486f](https://github.com/techofourown/img-ourbox-woodbox/commit/479486fe4b0ebf2379ff2a80f2f8cb35d4c38ec2))
* show xorriso stderr and drop -compliance no_emul_toc ([2304b58](https://github.com/techofourown/img-ourbox-woodbox/commit/2304b584d8fc472b3a37d9e1d22c5bc0e713eb21))
* use | delimiter in sed to avoid clash with /cdrom/nocloud/ path ([686190b](https://github.com/techofourown/img-ourbox-woodbox/commit/686190b7d2bb4a072baa8619f3e7541194a8e664))
* yaml syntax error crashing autoinstall on boot ([e536028](https://github.com/techofourown/img-ourbox-woodbox/commit/e536028bb7d556bb6e669b7716cb339c3d6080db))


### Features

* explicit operator disk selection for both OS and DATA disks ([bd5a864](https://github.com/techofourown/img-ourbox-woodbox/commit/bd5a86439d593cfd91f3aec34d3af90f70d0753a))
* replace Subiquity TUI with OurBox-branded pre-installer ([324332f](https://github.com/techofourown/img-ourbox-woodbox/commit/324332f7566df2d13daf48c6d8a9fa94a09efcf5))
* sentinel file enforces fresh working tree on every run ([af634b3](https://github.com/techofourown/img-ourbox-woodbox/commit/af634b36c97b0307d4bb27573d7ee8b125b34dbc))
