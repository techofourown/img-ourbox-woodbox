# Platform contract files

This tree is **populated at build time** by `tools/sync-platform-contract-into-installer.sh`.

It includes:
- upstream profile inputs and image locks under `profiles/`
- the upstream render tool under `tools/`
- a pre-rendered default bundle under `rendered/defaults/`

They are NOT hand-authored in this repo. The authoritative source is
`sw-ourbox-os` (consumed via `contracts/platform-contract.ref` or
`release/official-inputs.env`).

Running `tools/fetch-airgap-platform.sh` will automatically fetch the
upstream platform contract and sync the full tree into this directory.
