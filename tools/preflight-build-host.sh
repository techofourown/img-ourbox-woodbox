#!/usr/bin/env bash
# Preflight check for the Woodbox build host.
# Verifies that host tools are present and the deploy directory is writable.
# Called by official CI workflows before the OS or installer build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd xorriso
need_cmd 7z
need_cmd rsync
need_cmd sha256sum
need_cmd envsubst
need_cmd oras
need_cmd curl
need_cmd sed
need_cmd awk
need_cmd git
need_cmd tar

mkdir -p "${ROOT}/deploy"
[[ -w "${ROOT}/deploy" ]] || die "deploy/ directory is not writable"

log "Preflight: build host tools OK"
