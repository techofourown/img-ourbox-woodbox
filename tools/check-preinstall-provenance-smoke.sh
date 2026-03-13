#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
PREINSTALL_DIR="${FIXTURE_ROOT}/installer/ourbox-preinstall"
CACHE_DIR="${TMP}/cache"
mkdir -p "${TOOLS_DIR}" "${PREINSTALL_DIR}" "${CACHE_DIR}"

cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" "${PREINSTALL_DIR}/ourbox-preinstall"

# shellcheck disable=SC1091
OURBOX_PREINSTALL_LIBRARY_ONLY=1 \
OURBOX_PREINSTALL_TOOLS_ROOT="${TOOLS_DIR}" \
  source "${PREINSTALL_DIR}/ourbox-preinstall"

export INSTALLER_CACHE_DIR="${CACHE_DIR}"
export INSTALLER_ID="woodbox"
export INSTALLER_VERSION="v0.0.0-fixture"
export INSTALLER_GIT_HASH="fixture-git-hash"
export OS_ARTIFACT_SOURCE="registry"
export OS_ARTIFACT_REF="ghcr.io/techofourown/ourbox-woodbox-os@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export OS_ARTIFACT_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
export OS_IMAGE_SHA256="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
export RELEASE_CHANNEL="stable"
export INSTALL_SELECTION_SOURCE="os-default-ref"
export OURBOX_AIRGAP_PLATFORM_SOURCE="https://github.com/techofourown/sw-ourbox-os"
export OURBOX_AIRGAP_PLATFORM_REVISION="fixture-airgap-revision"
export OURBOX_AIRGAP_PLATFORM_VERSION="v0.0.0-fixture"
export OURBOX_AIRGAP_PLATFORM_CREATED="2026-03-11T00:00:00Z"
export OURBOX_AIRGAP_PLATFORM_ARCH="amd64"
export OURBOX_AIRGAP_PLATFORM_PROFILE="demo-apps"
export OURBOX_AIRGAP_PLATFORM_K3S_VERSION="v1.35.0+k3s1"
export OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
export OURBOX_AIRGAP_PLATFORM_ARTIFACT_SOURCE="registry"
export OURBOX_AIRGAP_PLATFORM_REF="ghcr.io/techofourown/sw-ourbox-os/airgap-platform@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
export OURBOX_AIRGAP_PLATFORM_DIGEST="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
export OURBOX_AIRGAP_PLATFORM_SELECTION_SOURCE="catalog"
export OURBOX_AIRGAP_PLATFORM_RELEASE_CHANNEL="stable"
export OURBOX_APPLICATION_CATALOG_ID="demo-apps"
export OURBOX_APPLICATION_CATALOG_NAME="Demo Apps"
export OURBOX_APPLICATION_SELECTION_MODE="defaults"
export OURBOX_SELECTED_APPLICATION_IDS="landing,dufs"

write_install_provenance

[[ -f "${CACHE_DIR}/install-provenance.env" ]] || {
  echo "install-provenance.env was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/append-provenance.sh" ]] || {
  echo "append-provenance.sh was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/apply-airgap-platform-override.sh" ]] || {
  echo "apply-airgap-platform-override.sh was not generated" >&2
  exit 1
}
[[ -f "${CACHE_DIR}/apply-application-selection.sh" ]] || {
  echo "apply-application-selection.sh was not generated" >&2
  exit 1
}

grep -F "AIRGAP_PLATFORM_ARTIFACT_SOURCE=registry" "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F "APPLICATION_CATALOG_ID=demo-apps" "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F "SELECTED_APPLICATION_IDS=landing,dufs" "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F "OURBOX_AIRGAP_PLATFORM_ARTIFACT_SOURCE=\${AIRGAP_PLATFORM_ARTIFACT_SOURCE:-unknown}" "${CACHE_DIR}/append-provenance.sh" >/dev/null
grep -F "OURBOX_APPLICATION_CATALOG_ID=\${APPLICATION_CATALOG_ID:-}" "${CACHE_DIR}/append-provenance.sh" >/dev/null
grep -F "OURBOX_SELECTED_APPLICATION_IDS=\${SELECTED_APPLICATION_IDS:-}" "${CACHE_DIR}/append-provenance.sh" >/dev/null
# shellcheck disable=SC2016
grep -F 'if [ "${AIRGAP_PLATFORM_ARTIFACT_SOURCE:-baked}" = "baked" ]; then' "${CACHE_DIR}/apply-airgap-platform-override.sh" >/dev/null
# shellcheck disable=SC2016
grep -F 'cp -f "${SOURCE_SELECTION}" "${PLATFORM_DIR}/selected-apps.json"' "${CACHE_DIR}/apply-application-selection.sh" >/dev/null
if grep -Fq "INSTALL_DEFAULTS_" "${CACHE_DIR}/install-provenance.env"; then
  echo "legacy install-defaults provenance fields must not be written" >&2
  exit 1
fi
if grep -Fq "OURBOX_INSTALL_DEFAULTS_" "${CACHE_DIR}/append-provenance.sh"; then
  echo "legacy install-defaults release fields must not be appended" >&2
  exit 1
fi
if grep -F 'contract.digest' "${CACHE_DIR}/apply-airgap-platform-override.sh" >/dev/null; then
  echo "override helper must not replace platform contract files" >&2
  exit 1
fi

printf '[%s] Woodbox preinstall provenance smoke passed\n' "$(date -Is)"
