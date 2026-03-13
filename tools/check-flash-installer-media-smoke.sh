#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

output="$(OURBOX_FLASH_HELPER_SELFTEST=1 bash "${ROOT}/tools/flash-installer-media.sh")"
grep -q "flash helper self-test passed" <<<"${output}" || {
  echo "flash helper self-test did not report success" >&2
  exit 1
}

echo "Woodbox flash helper smoke passed"
