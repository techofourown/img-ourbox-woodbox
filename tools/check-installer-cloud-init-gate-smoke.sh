#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="${ROOT}/tools/check-installer-boot-smoke.sh"

grep -Fq 'wait_for_cloud_init_ready() {' "${SMOKE}" \
  || { echo "boot smoke does not define wait_for_cloud_init_ready" >&2; exit 1; }

grep -Fq 'for unit in cloud-init-local.service cloud-init.service cloud-config.service; do' "${SMOKE}" \
  || { echo "boot smoke does not iterate over the required cloud-init one-shot units" >&2; exit 1; }

grep -Fq "systemctl show --property LoadState,SubState,Result" "${SMOKE}" \
  || { echo "boot smoke does not inspect cloud-init unit state via systemctl show" >&2; exit 1; }

grep -Fq "grep -q '^LoadState=loaded$'" "${SMOKE}" \
  || { echo "boot smoke does not require loaded cloud-init units" >&2; exit 1; }

grep -Fq "grep -q '^Result=success$'" "${SMOKE}" \
  || { echo "boot smoke does not require successful cloud-init unit results" >&2; exit 1; }

grep -Fq "grep -Eq '^SubState=(exited|dead)$'" "${SMOKE}" \
  || { echo "boot smoke does not accept completed one-shot cloud-init unit substates" >&2; exit 1; }

grep -Fq 'cloud-id 2>/dev/null || true' "${SMOKE}" \
  || { echo "boot smoke does not capture cloud-id datasource diagnostics" >&2; exit 1; }

grep -Fq "grep -q 'DataSourceNoCloud'" "${SMOKE}" \
  || { echo "boot smoke does not assert the NoCloud datasource" >&2; exit 1; }

if grep -Fq "grep -q '^status: done$'" "${SMOKE}"; then
  echo "boot smoke still requires cloud-init status: done" >&2
  exit 1
fi

if grep -Fq "grep -q '^extended_status:'" "${SMOKE}"; then
  echo "boot smoke still requires extended_status output" >&2
  exit 1
fi

if grep -Fq "grep -q '^extended_status: degraded'" "${SMOKE}"; then
  echo "boot smoke still rejects degraded extended_status explicitly" >&2
  exit 1
fi

echo "installer cloud-init gate smoke passed"
