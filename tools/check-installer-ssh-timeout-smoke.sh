#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="${ROOT}/installer/ourbox-preinstall/ourbox-installer-ssh-bootstrap.sh"
USER_DATA="${ROOT}/installer/autoinstall/user-data.tpl"

grep -Fq ': "${OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS:=180}"' "${BOOTSTRAP}" \
  || { echo "bootstrap does not default OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS to 180" >&2; exit 1; }

grep -Fq 'local deadline=$((SECONDS + OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS))' "${BOOTSTRAP}" \
  || { echo "bootstrap does not use OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS in wait_for_local_ssh_banner" >&2; exit 1; }

grep -Fq 'OURBOX_INSTALLER_SSH_READY_TIMEOUT_SECS=180 timeout 240 /bin/bash /run/ourbox-installer-ssh-bootstrap.sh' "${USER_DATA}" \
  || { echo "user-data.tpl does not provide the widened installer SSH bootstrap timeout envelope" >&2; exit 1; }

echo "installer SSH timeout smoke passed"
