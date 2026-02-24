# Autoinstall seed

These files are injected into the Ubuntu Server ISO as a NoCloud datasource.

- `user-data` contains the full autoinstall config.
- `meta-data` is minimal.

The build tooling replaces identity + OurBox release metadata at ISO build time.
