#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="${ROOT}/installer/ourbox/rootfs/usr/local/sbin/ourbox-bootstrap"

fragment="$(
  awk '
    /^require_application_intent_files\(\)/ { exit }
    { print }
  ' "${BOOTSTRAP}"
)"

run_case() {
  local label="$1"
  local shell_body="$2"

  bash -c "${fragment}
${shell_body}
" || {
    echo \"bootstrap platform profile smoke failed: ${label}\" >&2
    exit 1
  }
}

run_failure_case() {
  local label="$1"
  local shell_body="$2"
  local log_file=""

  log_file="$(mktemp)"
  trap 'rm -f "${log_file}"' RETURN

  if bash -c "${fragment}
${shell_body}
" > "${log_file}" 2>&1; then
    echo "bootstrap platform profile smoke failed: ${label} unexpectedly succeeded" >&2
    cat "${log_file}" >&2
    exit 1
  fi

  grep -F "OURBOX_PLATFORM_PROFILE" "${log_file}" >/dev/null || {
    echo "bootstrap platform profile smoke failed: ${label} missing failure text" >&2
    cat "${log_file}" >&2
    exit 1
  }
}

run_case \
  "current-env" \
  'tmpdir="$(mktemp -d)"
trap '\''rm -rf "${tmpdir}"'\'' EXIT
PLATFORM_CONTRACT_DIR="${tmpdir}/platform"
mkdir -p "${PLATFORM_CONTRACT_DIR}"
PLATFORM_PROFILE_INPUT=""
OURBOX_PLATFORM_PROFILE="demo-apps"
load_platform_profile_input
[[ "${PLATFORM_PROFILE_INPUT}" == "demo-apps" ]]'

run_case \
  "current-profile-env-file" \
  'tmpdir="$(mktemp -d)"
trap '\''rm -rf "${tmpdir}"'\'' EXIT
PLATFORM_CONTRACT_DIR="${tmpdir}/platform"
mkdir -p "${PLATFORM_CONTRACT_DIR}"
printf '\''OURBOX_PLATFORM_PROFILE=demo-apps\n'\'' > "${PLATFORM_CONTRACT_DIR}/profile.env"
PLATFORM_PROFILE_INPUT=""
load_platform_profile_input
[[ "${PLATFORM_PROFILE_INPUT}" == "demo-apps" ]]'

run_failure_case \
  "reject-legacy-env" \
  'tmpdir="$(mktemp -d)"
trap '\''rm -rf "${tmpdir}"'\'' EXIT
PLATFORM_CONTRACT_DIR="${tmpdir}/platform"
mkdir -p "${PLATFORM_CONTRACT_DIR}"
PLATFORM_PROFILE_INPUT=""
OURBOX_PROFILE="demo-apps"
load_platform_profile_input'

run_failure_case \
  "reject-legacy-profile-env-file" \
  'tmpdir="$(mktemp -d)"
trap '\''rm -rf "${tmpdir}"'\'' EXIT
PLATFORM_CONTRACT_DIR="${tmpdir}/platform"
mkdir -p "${PLATFORM_CONTRACT_DIR}"
printf '\''OURBOX_PROFILE=demo-apps\n'\'' > "${PLATFORM_CONTRACT_DIR}/profile.env"
PLATFORM_PROFILE_INPUT=""
load_platform_profile_input'

run_failure_case \
  "reject-legacy-profile-file" \
  'tmpdir="$(mktemp -d)"
trap '\''rm -rf "${tmpdir}"'\'' EXIT
PLATFORM_CONTRACT_DIR="${tmpdir}/platform"
mkdir -p "${PLATFORM_CONTRACT_DIR}"
printf '\''PROFILE=demo-apps\n'\'' > "${PLATFORM_CONTRACT_DIR}/profile.env"
PLATFORM_PROFILE_INPUT=""
load_platform_profile_input'

printf '[%s] bootstrap platform profile smoke passed\n' "$(date -Is)"
