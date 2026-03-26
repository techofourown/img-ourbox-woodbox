#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

report_err() {
  local rc=$?
  log "ERROR: command failed at line ${1}: ${2} (exit ${rc})"
  exit "${rc}"
}
trap 'report_err "${LINENO}" "${BASH_COMMAND}"' ERR

need_cmd xorriso

DEPLOY_DIR="${DEPLOY_DIR:-${ROOT}/deploy}"
: "${OURBOX_TARGET:=x86}"

ISO_FILE="${1:-}"
if [[ -z "${ISO_FILE}" ]]; then
  # shellcheck disable=SC2012
  ISO_FILE="$(ls -1t "${DEPLOY_DIR}"/installer-ourbox-woodbox-"${OURBOX_TARGET,,}"-*.iso 2>/dev/null | head -n 1 || true)"
fi
[[ -n "${ISO_FILE}" && -f "${ISO_FILE}" ]] || die "installer ISO not found"

EXPECTED_INSTALLER_SSH_MODE="${EXPECTED_INSTALLER_SSH_MODE:-both}"
EXPECTED_INSTALLER_SSH_USER="${EXPECTED_INSTALLER_SSH_USER:-ourbox-installer}"
EXPECTED_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY="${EXPECTED_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY:-1}"
EXPECTED_INSTALLER_SSH_ALLOW_ROOT="${EXPECTED_INSTALLER_SSH_ALLOW_ROOT:-0}"
EXPECTED_INSTALLER_SSH_GRANT_SUDO="${EXPECTED_INSTALLER_SSH_GRANT_SUDO:-1}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
EXTRACTED_DEFAULTS="${TMP}/installer-defaults.env"

log "Extracting baked installer defaults from $(basename "${ISO_FILE}")"
xorriso -osirrox on -indev "${ISO_FILE}" \
  -extract /ourbox/installer/defaults.env "${EXTRACTED_DEFAULTS}" >/dev/null 2>&1 \
  || die "failed to extract /ourbox/installer/defaults.env from ${ISO_FILE}"

# shellcheck disable=SC1090
source "${EXTRACTED_DEFAULTS}" \
  || die "failed to source extracted installer defaults from ${EXTRACTED_DEFAULTS}"

[[ "${INSTALLER_ID:-}" == "woodbox" ]] || die \
  "installer defaults INSTALLER_ID mismatch: expected 'woodbox', found '${INSTALLER_ID:-}'"
[[ -n "${INSTALLER_VERSION:-}" ]] || die "installer defaults INSTALLER_VERSION must not be empty"
[[ -n "${INSTALLER_GIT_HASH:-}" ]] || die "installer defaults INSTALLER_GIT_HASH must not be empty"
[[ "${OURBOX_INSTALLER_SSH_MODE:-}" == "${EXPECTED_INSTALLER_SSH_MODE}" ]] || die \
  "installer defaults OURBOX_INSTALLER_SSH_MODE mismatch: expected '${EXPECTED_INSTALLER_SSH_MODE}', found '${OURBOX_INSTALLER_SSH_MODE:-}'"
[[ "${OURBOX_INSTALLER_SSH_USER:-}" == "${EXPECTED_INSTALLER_SSH_USER}" ]] || die \
  "installer defaults OURBOX_INSTALLER_SSH_USER mismatch: expected '${EXPECTED_INSTALLER_SSH_USER}', found '${OURBOX_INSTALLER_SSH_USER:-}'"
[[ "${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY:-}" == "${EXPECTED_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}" ]] || die \
  "installer defaults OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY mismatch: expected '${EXPECTED_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}', found '${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY:-}'"
[[ "${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-}" == "${EXPECTED_INSTALLER_SSH_ALLOW_ROOT}" ]] || die \
  "installer defaults OURBOX_INSTALLER_SSH_ALLOW_ROOT mismatch: expected '${EXPECTED_INSTALLER_SSH_ALLOW_ROOT}', found '${OURBOX_INSTALLER_SSH_ALLOW_ROOT:-}'"
[[ "${OURBOX_INSTALLER_SSH_GRANT_SUDO:-}" == "${EXPECTED_INSTALLER_SSH_GRANT_SUDO}" ]] || die \
  "installer defaults OURBOX_INSTALLER_SSH_GRANT_SUDO mismatch: expected '${EXPECTED_INSTALLER_SSH_GRANT_SUDO}', found '${OURBOX_INSTALLER_SSH_GRANT_SUDO:-}'"

for legacy_key in \
  OS_REPO \
  OS_TARGET \
  OS_CHANNEL \
  OS_DEFAULT_REF \
  OS_CATALOG_ENABLED \
  OS_CATALOG_TAG \
  INSTALL_DEFAULTS_REF \
  OS_ORAS_VERSION \
  AIRGAP_PLATFORM_REPO \
  AIRGAP_PLATFORM_ARCH \
  AIRGAP_PLATFORM_CHANNEL \
  AIRGAP_PLATFORM_REF \
  AIRGAP_PLATFORM_DEFAULT_REF \
  AIRGAP_PLATFORM_CATALOG_ENABLED \
  AIRGAP_PLATFORM_CATALOG_TAG \
  AIRGAP_PLATFORM_CHANNEL_STABLE_TAG \
  AIRGAP_PLATFORM_CHANNEL_BETA_TAG \
  AIRGAP_PLATFORM_CHANNEL_NIGHTLY_TAG \
  AIRGAP_PLATFORM_CHANNEL_EXP_LABS_TAG; do
  if grep -Eq "^${legacy_key}=" "${EXTRACTED_DEFAULTS}"; then
    die "installer defaults must not contain legacy target-side artifact selection key: ${legacy_key}"
  fi
done

cp "${EXTRACTED_DEFAULTS}" "${DEPLOY_DIR}/installer-defaults.extracted.env" \
  || die "failed to persist extracted installer defaults into deploy/"
cat > "${DEPLOY_DIR}/installer-defaults-smoke.txt" <<EOF
ARTIFACT=$(basename "${ISO_FILE}")
EXTRACTED_DEFAULTS=${DEPLOY_DIR}/installer-defaults.extracted.env
INSTALLER_ID=${INSTALLER_ID}
INSTALLER_VERSION=${INSTALLER_VERSION}
INSTALLER_GIT_HASH=${INSTALLER_GIT_HASH}
OURBOX_INSTALLER_SSH_MODE=${OURBOX_INSTALLER_SSH_MODE}
OURBOX_INSTALLER_SSH_USER=${OURBOX_INSTALLER_SSH_USER}
OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY=${OURBOX_INSTALLER_SSH_GENERATE_PASSWORD_IF_EMPTY}
OURBOX_INSTALLER_SSH_ALLOW_ROOT=${OURBOX_INSTALLER_SSH_ALLOW_ROOT}
OURBOX_INSTALLER_SSH_GRANT_SUDO=${OURBOX_INSTALLER_SSH_GRANT_SUDO}
LEGACY_SELECTION_KEYS_PRESENT=0
EOF

log "Installer defaults smoke passed for $(basename "${ISO_FILE}")"
