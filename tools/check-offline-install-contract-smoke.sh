#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

runtime_tpl="${ROOT}/installer/autoinstall/autoinstall.tpl"
seed_tpl="${ROOT}/installer/autoinstall/user-data.tpl"
iso_builder="${ROOT}/tools/build-installer-iso.sh"

grep -q '/opt/ourbox/installer/cache/install-target-packages.sh' "${runtime_tpl}" \
  || die "runtime autoinstall must install required target packages from the local substrate repo"
grep -q '/opt/ourbox/installer/cache/apply-target-netplan.sh' "${runtime_tpl}" \
  || die "runtime autoinstall must apply the prepared target netplan helper"
grep -q 'prepare-installer-target-apt-repo.sh' "${iso_builder}" \
  || die "installer substrate build must stage a local target APT repo"

for forbidden in \
  'packages:' \
  'ubuntu-drivers install' \
  'ip route show default' \
  'install-server: true'
do
  if grep -q "${forbidden}" "${runtime_tpl}" "${seed_tpl}"; then
    die "offline install contract regression: found forbidden pattern '${forbidden}'"
  fi
done

printf '[%s] Woodbox offline-install contract smoke passed\n' "$(date -Is)"
