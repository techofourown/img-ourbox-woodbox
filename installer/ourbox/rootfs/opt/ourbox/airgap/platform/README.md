# Platform contract files

The `manifests/`, `landing/`, and `todo-bloom/` directories here are
**populated at build time** by `tools/sync-platform-contract-into-installer.sh`.

They are NOT hand-authored in this repo. The authoritative source is
`sw-ourbox-os` (consumed via `contracts/platform-contract.ref` or
`release/official-inputs.env`).

Running `tools/fetch-airgap-platform.sh` will automatically fetch the
upstream platform contract and sync it into these directories.
