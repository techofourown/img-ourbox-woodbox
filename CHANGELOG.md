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
