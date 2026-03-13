#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE="${ROOT}/tools/check-installer-boot-smoke.sh"

grep -Fq 'wait_for_cloud_init_ready() {' "${SMOKE}" \
  || { echo "boot smoke does not define wait_for_cloud_init_ready" >&2; exit 1; }

grep -Fq 'systemctl is-active --quiet cloud-init-local.service && exit 1' "${SMOKE}" \
  || { echo "boot smoke does not wait for cloud-init-local.service to finish" >&2; exit 1; }

grep -Fq 'systemctl is-active --quiet cloud-init.service && exit 1' "${SMOKE}" \
  || { echo "boot smoke does not wait for cloud-init.service to finish" >&2; exit 1; }

grep -Fq 'systemctl is-active --quiet cloud-config.service && exit 1' "${SMOKE}" \
  || { echo "boot smoke does not wait for cloud-config.service to finish" >&2; exit 1; }

grep -Fq 'systemctl is-failed --quiet cloud-init-local.service && exit 1' "${SMOKE}" \
  || { echo "boot smoke does not reject failed cloud-init-local.service" >&2; exit 1; }

grep -Fq 'systemctl is-failed --quiet cloud-init.service && exit 1' "${SMOKE}" \
  || { echo "boot smoke does not reject failed cloud-init.service" >&2; exit 1; }

grep -Fq 'systemctl is-failed --quiet cloud-config.service && exit 1' "${SMOKE}" \
  || { echo "boot smoke does not reject failed cloud-config.service" >&2; exit 1; }

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
