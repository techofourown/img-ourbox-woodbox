## [0.12.3](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.12.2...v0.12.3) (2026-03-16)


### Bug Fixes

* **bootstrap:** reject legacy profile keys ([c17d1e4](https://github.com/techofourown/img-ourbox-woodbox/commit/c17d1e4f05c1ea538ef8341136442691902109f7))
* **ci:** satisfy bootstrap smoke shellcheck ([3c0f206](https://github.com/techofourown/img-ourbox-woodbox/commit/3c0f2066031e6df71320ababc91cbf00fde3b8db))
* fail closed on missing airgap application intent ([1a8d94d](https://github.com/techofourown/img-ourbox-woodbox/commit/1a8d94d71c774f1c77fc84b4a6ccd9bf4515b271))

## [0.12.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.12.1...v0.12.2) (2026-03-14)


### Bug Fixes

* honor staged mission ssh key in live installer ([fbab273](https://github.com/techofourown/img-ourbox-woodbox/commit/fbab273322c9c67f0f8f45c5b57a9d31f0649cbd))
* merge staged installer mission SSH keys ([7acbc0a](https://github.com/techofourown/img-ourbox-woodbox/commit/7acbc0a936c216581eed2a572686addff22b0fed))

## [0.12.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.12.0...v0.12.1) (2026-03-14)


### Bug Fixes

* accept current platform contract manifest naming ([89182d1](https://github.com/techofourown/img-ourbox-woodbox/commit/89182d13d24789590ccee57bf9cc64876ae9cd28))

# [0.12.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.11.0...v0.12.0) (2026-03-14)


### Bug Fixes

* fail closed on malformed mission and contract metadata ([d976f7e](https://github.com/techofourown/img-ourbox-woodbox/commit/d976f7eedcfc365cef6b022e0851fee18a08dd99))
* sync woodbox inputs and self-contain shape smoke ([56041f5](https://github.com/techofourown/img-ourbox-woodbox/commit/56041f5346c5037c647a383054da0a4e6bb1b48e))


### Features

* harden woodbox install bootstrap ([25d5396](https://github.com/techofourown/img-ourbox-woodbox/commit/25d5396a6cb743f870f4cfbba9cf2a270bec4bff))

# [0.11.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.7...v0.11.0) (2026-03-14)


### Bug Fixes

* **adapter:** accept contract created metadata ([2e889cf](https://github.com/techofourown/img-ourbox-woodbox/commit/2e889cf5ded35ba71848a52ad7178797548b734e))
* **build:** backfill demo catalog metadata compat ([8a58adc](https://github.com/techofourown/img-ourbox-woodbox/commit/8a58adce4560ca40a0eb628b6a8ac27e1b23811d))
* **build:** invoke metadata helper via bash ([6a0a6b5](https://github.com/techofourown/img-ourbox-woodbox/commit/6a0a6b5c7e946b8075fc9f5b20a8fc04d5aa56c8))
* **ci:** export bootstrap smoke contract vars ([278db70](https://github.com/techofourown/img-ourbox-woodbox/commit/278db70fcf54d7ccd96020d865258eec9744d8c6))
* **ci:** pin commitlint dependency ([be817d2](https://github.com/techofourown/img-ourbox-woodbox/commit/be817d289dc61ea15fefe63ae7590a099c594914))
* **ci:** repair Woodbox PR checks ([4107136](https://github.com/techofourown/img-ourbox-woodbox/commit/41071366290d6dd81856c24f7414273212114318))
* **ci:** silence timeout smoke shellcheck ([d7f51fa](https://github.com/techofourown/img-ourbox-woodbox/commit/d7f51fa377ca5e11b96baac07961836188c1ac64))
* **payload:** emit full mission metadata contract ([01e1195](https://github.com/techofourown/img-ourbox-woodbox/commit/01e119567d46b8cbc425f1c6105326f281ba6b1c))
* **smoke:** accept completed cloud-init units ([5b011ed](https://github.com/techofourown/img-ourbox-woodbox/commit/5b011ed3361a0bb0e442153ac28019268a70fbfb))
* **smoke:** align cloud-init readiness gate ([883e376](https://github.com/techofourown/img-ourbox-woodbox/commit/883e376ee80cc0f87b28915e00b4c82bb33a6b4b))
* **smoke:** align mission metadata allowlist ([cd569ef](https://github.com/techofourown/img-ourbox-woodbox/commit/cd569ef3d5528f1ddceb9a949ddd6860afc5a480))
* **smoke:** align mission monitor port contract ([36e9be1](https://github.com/techofourown/img-ourbox-woodbox/commit/36e9be1823e4adc3575420570ff3d77a5555a8b3))
* **smoke:** backfill baked app metadata ([9689182](https://github.com/techofourown/img-ourbox-woodbox/commit/96891824ffe0c76059870e5c9f6d3ba1f50a69b3))
* **smoke:** bound installer ssh bootstrap restart ([2862845](https://github.com/techofourown/img-ourbox-woodbox/commit/2862845660f17035888255efb597bbfb8313989c))
* **smoke:** expose installer ssh status contract ([2ca67e1](https://github.com/techofourown/img-ourbox-woodbox/commit/2ca67e1b2b57925e5e58580b7212cc32d431b1e5))
* **smoke:** make installer ssh readiness async ([a271112](https://github.com/techofourown/img-ourbox-woodbox/commit/a271112d8d2c94d9522f63f66a4641e7613be84d))
* **smoke:** match payload metadata contract ([aed4243](https://github.com/techofourown/img-ourbox-woodbox/commit/aed42432399e7e9499f0e32b387254f591c9b60b))
* **smoke:** tighten installer ssh leak checks ([8b7e5ea](https://github.com/techofourown/img-ourbox-woodbox/commit/8b7e5ea8ff90f57a2a88e787d8583077f8b1ccbc))
* **smoke:** widen installer ssh readiness window ([88b7252](https://github.com/techofourown/img-ourbox-woodbox/commit/88b725253efc52146cd912660e9224c068b6438e))
* **test:** isolate bootstrap smoke traps ([a66ecd9](https://github.com/techofourown/img-ourbox-woodbox/commit/a66ecd950e9cbe5d625bca961cdc2fc08fbc54ad))
* **woodbox:** harden selected application metadata ([f44f857](https://github.com/techofourown/img-ourbox-woodbox/commit/f44f85780c65693f2a94673673a0ab8aa042caef))
* **woodbox:** refresh legacy fallback refs ([e360938](https://github.com/techofourown/img-ourbox-woodbox/commit/e3609384b9e5a4af23c33d508c6bcc82a07389bb))


### Features

* **installer:** honor mission-selected applications ([38f0461](https://github.com/techofourown/img-ourbox-woodbox/commit/38f04614b1b45e134679c89a422c41f53541435e))
* **woodbox:** consume merged application catalogs ([bdf0683](https://github.com/techofourown/img-ourbox-woodbox/commit/bdf0683d92d8883ea7d8e1f7debab87c530cae8f))

## [0.10.7](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.6...v0.10.7) (2026-03-13)


### Bug Fixes

* **ci:** derive platform contract ref from airgap bundle manifest ([af79a54](https://github.com/techofourown/img-ourbox-woodbox/commit/af79a54dd76942710969f422c5ee63cb79bc8040))

## [0.10.6](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.5...v0.10.6) (2026-03-13)


### Bug Fixes

* **installer:** align apt repo helper execution path ([2dffcff](https://github.com/techofourown/img-ourbox-woodbox/commit/2dffcff35d2187ae2b46592364cd1bc84e12b23e))

## [0.10.5](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.4...v0.10.5) (2026-03-13)


### Bug Fixes

* **installer:** make woodbox install path fully offline ([b050a91](https://github.com/techofourown/img-ourbox-woodbox/commit/b050a91f47433573edbc38430986a2951022d336))

## [0.10.4](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.3...v0.10.4) (2026-03-13)


### Bug Fixes

* **installer:** support vendored flash helper ([5f735a2](https://github.com/techofourown/img-ourbox-woodbox/commit/5f735a257abebea802d0702b1c5d7bb786e269b2))

## [0.10.3](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.2...v0.10.3) (2026-03-13)


### Bug Fixes

* **adapter:** parse substrate iso volume id robustly ([74cb5f1](https://github.com/techofourown/img-ourbox-woodbox/commit/74cb5f19bf480ebac0fcda907e3c0e66abe75159))
* **installer:** consume published woodbox substrate ([5cc0cf4](https://github.com/techofourown/img-ourbox-woodbox/commit/5cc0cf4bdb015f35e6cbf47c2a2f57fa68e5dcc3))
* **installer:** reduce flash-path disk churn ([f0e5414](https://github.com/techofourown/img-ourbox-woodbox/commit/f0e5414afe8914342becfbb387372369004b66c7))

## [0.10.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.1...v0.10.2) (2026-03-12)


### Bug Fixes

* **adapter:** avoid redundant airgap extraction ([8ef5d8a](https://github.com/techofourown/img-ourbox-woodbox/commit/8ef5d8a75be9fb42de06402253a866806c4c4f3c))

## [0.10.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.10.0...v0.10.1) (2026-03-12)


### Bug Fixes

* **installer:** tighten mission adapter validation ([4a02fa7](https://github.com/techofourown/img-ourbox-woodbox/commit/4a02fa7cc87cb7b4df5850c686beff07a055977f))
* **publish:** keep strict metadata parseable ([27b1c2a](https://github.com/techofourown/img-ourbox-woodbox/commit/27b1c2ab866689c6cc58113b046d0cb03741e8bd))

# [0.10.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.9.2...v0.10.0) (2026-03-12)


### Bug Fixes

* **adapter:** validate mission airgap contract ([2148aca](https://github.com/techofourown/img-ourbox-woodbox/commit/2148aca040ab8081e4af2cf226af5c26aecc448d))
* **installer:** align mission metadata contract ([20f1930](https://github.com/techofourown/img-ourbox-woodbox/commit/20f19302659fa8c204b1db926832370a1c96c06b))
* **installer:** harden woodbox mission metadata contract ([1f7317b](https://github.com/techofourown/img-ourbox-woodbox/commit/1f7317b0ae79f15d57b258ab83b5f3b1aeee7069))


### Features

* **installer:** make woodbox mission-media-only ([fa479c0](https://github.com/techofourown/img-ourbox-woodbox/commit/fa479c0c4c4c34ba83c4842b56ef20fcbed65b32))

## [0.9.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.9.1...v0.9.2) (2026-03-12)


### Bug Fixes

* refresh approved upstream pins to v0.16.2 ([dccdf75](https://github.com/techofourown/img-ourbox-woodbox/commit/dccdf75ee939ef88fe60285151b134dc4579cba9))

## [0.9.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.9.0...v0.9.1) (2026-03-11)


### Bug Fixes

* refresh approved upstream pins to v0.16.0 ([69373de](https://github.com/techofourown/img-ourbox-woodbox/commit/69373de342af5d6805eacd212b6b7c739b60d807))

# [0.9.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.8.0...v0.9.0) (2026-03-11)


### Bug Fixes

* address airgap review findings ([7859872](https://github.com/techofourown/img-ourbox-woodbox/commit/7859872147a8acd287d1b3f4477c667d8664f005))
* clear lint and resolver sync failures ([705c99b](https://github.com/techofourown/img-ourbox-woodbox/commit/705c99b1cd6cf167fba15d4be6174c3fe93fff6a))


### Features

* add contract-bound airgap bundle selection ([1e03827](https://github.com/techofourown/img-ourbox-woodbox/commit/1e038276abfbb3a598da350f7d5c83e93bbcb658))

# [0.8.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.7.2...v0.8.0) (2026-03-11)


### Bug Fixes

* confirm pinned browse selections before install ([9a2012c](https://github.com/techofourown/img-ourbox-woodbox/commit/9a2012cfc00ad81dae6cd034a7c247936ebaf958))


### Features

* adopt shared installer selection browsing ([1c5c3d4](https://github.com/techofourown/img-ourbox-woodbox/commit/1c5c3d4e85161cef7da5a1eeaeda66be9cafcb3e))

## [0.7.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.7.1...v0.7.2) (2026-03-10)


### Bug Fixes

* resolve pr batch diffs from pr refs ([106d4aa](https://github.com/techofourown/img-ourbox-woodbox/commit/106d4aafafe09f9de92fee6d5333fe6339943823))

## [0.7.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.7.0...v0.7.1) (2026-03-09)


### Bug Fixes

* **installer:** keep shared ssh helper exit semantics ([becf323](https://github.com/techofourown/img-ourbox-woodbox/commit/becf323d5ba01dd3ef06fb4117a536946cd22c4e))

# [0.7.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.6.2...v0.7.0) (2026-03-09)


### Bug Fixes

* align platform contract digest publish metadata ([7079aab](https://github.com/techofourown/img-ourbox-woodbox/commit/7079aab2ba9a89d0f25c56e12cd13d2f20988f54))


### Features

* vendor shared release-control plane ([6d82071](https://github.com/techofourown/img-ourbox-woodbox/commit/6d820714c775b7e6b091e5645c8ad9e35906a0ce))

## [0.6.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.6.1...v0.6.2) (2026-03-09)


### Bug Fixes

* **release:** consume approved upstream inputs ([67f065a](https://github.com/techofourown/img-ourbox-woodbox/commit/67f065a12c1ec7180a480550247dc913ae468c4c))

## [0.6.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.6.0...v0.6.1) (2026-03-08)


### Bug Fixes

* **ci:** add release-side promotion wake-up ([94fa55c](https://github.com/techofourown/img-ourbox-woodbox/commit/94fa55c6d2182a16e82783cc8b1fb7605af749d2))
* **ci:** gate promotion on candidate provenance ([eb54bbf](https://github.com/techofourown/img-ourbox-woodbox/commit/eb54bbf2e6f09c542540ecce893ec94414f852ae))

# [0.6.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.5.4...v0.6.0) (2026-03-08)


### Bug Fixes

* **release:** preserve nightly and pinned-input provenance ([e77a492](https://github.com/techofourown/img-ourbox-woodbox/commit/e77a492fc254205ebaa0a562527345ec7e1d358d))
* **release:** restore short catalog channel keys ([a6b6c23](https://github.com/techofourown/img-ourbox-woodbox/commit/a6b6c2339fcb3d6106f9f92c5ce61d6e97fdffc2))


### Features

* **release:** adopt promote-first official channels ([6888084](https://github.com/techofourown/img-ourbox-woodbox/commit/6888084a7b9e47ecd932a5c51eebe964bc918703))

## [0.5.4](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.5.3...v0.5.4) (2026-03-08)


### Bug Fixes

* **installer:** sync resolver stderr hardening ([c43310c](https://github.com/techofourown/img-ourbox-woodbox/commit/c43310c27de2e98bc51ab131ae52b2d039da5e9a))
* **installer:** sync shared selection resolver fixes ([cdadff1](https://github.com/techofourown/img-ourbox-woodbox/commit/cdadff141d938c3d7967406258ea26f298e27f86))

## [0.5.3](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.5.2...v0.5.3) (2026-03-07)


### Bug Fixes

* **ci:** pin official Woodbox installer defaults ([335d7e2](https://github.com/techofourown/img-ourbox-woodbox/commit/335d7e23b1a89873dbd8b1cf0bc0012b1189a485))
* **installer:** honor official build defaults inputs ([25a7af9](https://github.com/techofourown/img-ourbox-woodbox/commit/25a7af98ddb027213bdf6367f438515b29df4ead))

## [0.5.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.5.1...v0.5.2) (2026-03-07)


### Bug Fixes

* **platform:** pin full-shape contract and guard extracted shape ([e3771d9](https://github.com/techofourown/img-ourbox-woodbox/commit/e3771d95f15a7165ba0c757c85f74c9bc76c7db5))

## [0.5.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.5.0...v0.5.1) (2026-03-07)


### Bug Fixes

* **installer:** prefer installed OS after USB install ([d09e6ed](https://github.com/techofourown/img-ourbox-woodbox/commit/d09e6ed454bab5db0a4ebbebbd30cfb5a345c2f3))

# [0.5.0](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.6...v0.5.0) (2026-03-07)


### Bug Fixes

* **installer:** wait for sshd restart before ready ([0ac1dc4](https://github.com/techofourown/img-ourbox-woodbox/commit/0ac1dc467193ec17f1e34dd6739d4935495c6b67))


### Features

* **installer:** add step 0 installer ssh password ([1c5e559](https://github.com/techofourown/img-ourbox-woodbox/commit/1c5e55975911d9c65c1b3c17a63029fadc9b06fd))

## [0.4.6](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.5...v0.4.6) (2026-03-07)


### Bug Fixes

* **ci:** propagate installer SSH probe failures ([5cfcdb2](https://github.com/techofourown/img-ourbox-woodbox/commit/5cfcdb23b65ca5e3a31d64697f0300e66bc7ed32))
* **ci:** recover woodbox installer smoke gating ([dd69319](https://github.com/techofourown/img-ourbox-woodbox/commit/dd69319368d634e6c32956b35cf9166ace65eb03))
* **smoke:** capture installer ssh failure diagnostics ([46cc987](https://github.com/techofourown/img-ourbox-woodbox/commit/46cc987bb3aadec104f9bb3eb0cad5ca679fa49e))

## [0.4.5](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.4...v0.4.5) (2026-03-06)


### Bug Fixes

* **ci:** wait for real installer readiness in smoke test ([a4fd2e4](https://github.com/techofourown/img-ourbox-woodbox/commit/a4fd2e46b60666987a6c75f81e6ae7eae72650c5))

## [0.4.4](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.3...v0.4.4) (2026-03-06)


### Bug Fixes

* **bootstrap:** reapply the platform contract when the shipped state changes ([2ba4370](https://github.com/techofourown/img-ourbox-woodbox/commit/2ba4370de41a43cd74a72b6d4a5d31aa7c5f8687))
* **ci:** run installer smoke checks through bash ([ba5998c](https://github.com/techofourown/img-ourbox-woodbox/commit/ba5998c4e2bd91a4a1a35f47d04ea3ed897efcb1))
* harden installer seed and smoke validation ([d5e3408](https://github.com/techofourown/img-ourbox-woodbox/commit/d5e3408b53cb1849149cdfac39aaee09b2ab1c06))

## [0.4.3](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.2...v0.4.3) (2026-03-06)


### Bug Fixes

* **installer:** run EFI reorder in target context ([916fb69](https://github.com/techofourown/img-ourbox-woodbox/commit/916fb694fd95802bc781a709f569ab6c26296828))

## [0.4.2](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.1...v0.4.2) (2026-03-06)


### Bug Fixes

* **installer:** repair cloud-init SSH status seed ([0ba06e8](https://github.com/techofourown/img-ourbox-woodbox/commit/0ba06e8d6b24a6d526f7090e27067a76878a6aef))

## [0.4.1](https://github.com/techofourown/img-ourbox-woodbox/compare/v0.4.0...v0.4.1) (2026-03-06)


### Bug Fixes

* **installer:** remove unused SSH status field in TTY script ([b5b4f36](https://github.com/techofourown/img-ourbox-woodbox/commit/b5b4f36f9347234899eb573f4f9d3ec7b23bb791)), closes [#27](https://github.com/techofourown/img-ourbox-woodbox/issues/27)
* **installer:** restore truthful public installer SSH readiness ([d37f363](https://github.com/techofourown/img-ourbox-woodbox/commit/d37f3637c01ce427344b3c7cbcdf8306cfec016c))

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
