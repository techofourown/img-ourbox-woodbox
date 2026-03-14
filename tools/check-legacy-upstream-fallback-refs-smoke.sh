#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform_ref="$(tr -d '\n' < "${ROOT}/contracts/platform-contract.ref")"
airgap_ref="$(tr -d '\n' < "${ROOT}/contracts/airgap-platform.ref")"

[[ "${platform_ref}" == "ghcr.io/techofourown/sw-ourbox-os/platform-contract:nightly" ]] || {
  echo "unexpected legacy platform-contract fallback ref: ${platform_ref}" >&2
  exit 1
}

[[ "${airgap_ref}" == "ghcr.io/techofourown/sw-ourbox-os/airgap-platform:nightly-amd64" ]] || {
  echo "unexpected legacy airgap-platform fallback ref: ${airgap_ref}" >&2
  exit 1
}

[[ "${platform_ref}" != *":edge" ]] || {
  echo "legacy platform-contract fallback ref must not use removed edge lane" >&2
  exit 1
}

[[ "${airgap_ref}" != *":edge-amd64" ]] || {
  echo "legacy airgap-platform fallback ref must not use removed edge-amd64 lane" >&2
  exit 1
}

printf '[%s] Woodbox legacy upstream fallback ref smoke passed\n' "$(date -Is)"
