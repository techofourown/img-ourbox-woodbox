#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd xorriso

DEPLOY_DIR="${DEPLOY_DIR:-${ROOT}/deploy}"
: "${OURBOX_TARGET:=x86}"

ISO_FILE="${1:-}"
if [[ -z "${ISO_FILE}" ]]; then
  # shellcheck disable=SC2012
  ISO_FILE="$(ls -1t "${DEPLOY_DIR}"/installer-ourbox-woodbox-"${OURBOX_TARGET,,}"-*.iso 2>/dev/null | head -n 1 || true)"
fi
[[ -n "${ISO_FILE}" && -f "${ISO_FILE}" ]] || die "installer ISO not found"

EXPECTED_OS_DEFAULT_REF="${EXPECTED_OS_DEFAULT_REF:-}"
if [[ -z "${EXPECTED_OS_DEFAULT_REF}" && -f "${DEPLOY_DIR}/os-artifact.pinned.ref" ]]; then
  EXPECTED_OS_DEFAULT_REF="$(cat "${DEPLOY_DIR}/os-artifact.pinned.ref")"
fi
[[ -n "${EXPECTED_OS_DEFAULT_REF}" ]] || die "EXPECTED_OS_DEFAULT_REF not set and ${DEPLOY_DIR}/os-artifact.pinned.ref missing"

EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF="${EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF:-}"
if [[ -z "${EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF}" && -f "${ROOT}/release/official-inputs.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/release/official-inputs.env"
  EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF="${AIRGAP_PLATFORM_REF:-}"
fi
[[ -n "${EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF}" ]] || die "EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF not set and release/official-inputs.env did not provide AIRGAP_PLATFORM_REF"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
EXTRACTED_DEFAULTS="${TMP}/installer-defaults.env"

log "Extracting baked installer defaults from $(basename "${ISO_FILE}")"
xorriso -osirrox on -indev "${ISO_FILE}" \
  -extract /ourbox/installer/defaults.env "${EXTRACTED_DEFAULTS}" >/dev/null 2>&1 \
  || die "failed to extract /ourbox/installer/defaults.env from ${ISO_FILE}"

# shellcheck disable=SC1090
source "${EXTRACTED_DEFAULTS}"

[[ "${OS_DEFAULT_REF:-}" == "${EXPECTED_OS_DEFAULT_REF}" ]] || die \
  "installer defaults OS_DEFAULT_REF mismatch: expected '${EXPECTED_OS_DEFAULT_REF}', found '${OS_DEFAULT_REF:-}'"
[[ -z "${AIRGAP_PLATFORM_REF:-}" ]] || die \
  "installer defaults AIRGAP_PLATFORM_REF must be empty on official media, found '${AIRGAP_PLATFORM_REF:-}'"
[[ "${AIRGAP_PLATFORM_DEFAULT_REF:-}" == "${EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF}" ]] || die \
  "installer defaults AIRGAP_PLATFORM_DEFAULT_REF mismatch: expected '${EXPECTED_AIRGAP_PLATFORM_DEFAULT_REF}', found '${AIRGAP_PLATFORM_DEFAULT_REF:-}'"
[[ "${AIRGAP_PLATFORM_ARCH:-}" == "amd64" ]] || die \
  "installer defaults AIRGAP_PLATFORM_ARCH mismatch: expected 'amd64', found '${AIRGAP_PLATFORM_ARCH:-}'"
[[ "${AIRGAP_PLATFORM_CATALOG_TAG:-}" == "catalog-amd64" ]] || die \
  "installer defaults AIRGAP_PLATFORM_CATALOG_TAG mismatch: expected 'catalog-amd64', found '${AIRGAP_PLATFORM_CATALOG_TAG:-}'"
[[ -z "${INSTALL_DEFAULTS_REF:-}" ]] || die \
  "installer defaults INSTALL_DEFAULTS_REF must be empty for official installer, found '${INSTALL_DEFAULTS_REF}'"

cp "${EXTRACTED_DEFAULTS}" "${DEPLOY_DIR}/installer-defaults.extracted.env"
cat > "${DEPLOY_DIR}/installer-defaults-smoke.txt" <<EOF
ARTIFACT=$(basename "${ISO_FILE}")
EXTRACTED_DEFAULTS=${DEPLOY_DIR}/installer-defaults.extracted.env
OS_DEFAULT_REF=${OS_DEFAULT_REF}
AIRGAP_PLATFORM_REF=${AIRGAP_PLATFORM_REF-}
AIRGAP_PLATFORM_DEFAULT_REF=${AIRGAP_PLATFORM_DEFAULT_REF}
AIRGAP_PLATFORM_ARCH=${AIRGAP_PLATFORM_ARCH}
AIRGAP_PLATFORM_CATALOG_TAG=${AIRGAP_PLATFORM_CATALOG_TAG}
INSTALL_DEFAULTS_REF=${INSTALL_DEFAULTS_REF-}
EOF

log "Installer defaults smoke passed for $(basename "${ISO_FILE}")"
