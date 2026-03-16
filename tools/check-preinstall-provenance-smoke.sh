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
export OURBOX_APPLICATION_SELECTION_MODE="catalog-defaults"
export OURBOX_SELECTED_APPLICATION_IDS="landing,dufs"

write_install_provenance

TARGET_DIR="${TMP}/target"
OVERRIDE_DIR="${TMP}/airgap-platform-override"
APPLICATION_SELECTION_DIR="${TMP}/application-selection"
mkdir -p "${TARGET_DIR}/etc/ourbox"
mkdir -p "${TARGET_DIR}/opt/ourbox/airgap/platform" \
  "${OVERRIDE_DIR}/k3s" \
  "${OVERRIDE_DIR}/platform/images" \
  "${APPLICATION_SELECTION_DIR}"
printf 'EXISTING_KEY="existing-value"\n' > "${TARGET_DIR}/etc/ourbox/release"
OURBOX_INSTALLER_PROVENANCE_FILE="${CACHE_DIR}/install-provenance.env" \
  "${CACHE_DIR}/append-provenance.sh" "${TARGET_DIR}"

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

grep -F 'AIRGAP_PLATFORM_ARTIFACT_SOURCE="registry"' "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F 'APPLICATION_CATALOG_ID="demo-apps"' "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F 'APPLICATION_CATALOG_NAME="Demo Apps"' "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F 'SELECTED_APPLICATION_IDS="landing,dufs"' "${CACHE_DIR}/install-provenance.env" >/dev/null
grep -F 'OURBOX_INSTALLER_PROVENANCE_FILE:-/opt/ourbox/installer/cache/install-provenance.env' "${CACHE_DIR}/apply-airgap-platform-override.sh" >/dev/null
grep -F 'OURBOX_INSTALLER_AIRGAP_OVERRIDE_DIR:-/opt/ourbox/installer/cache/airgap-platform-override' "${CACHE_DIR}/apply-airgap-platform-override.sh" >/dev/null
grep -F 'OURBOX_INSTALLER_APPLICATION_CATALOG_FILE:-/opt/ourbox/installer/cache/catalog.json' "${CACHE_DIR}/apply-application-selection.sh" >/dev/null
grep -F 'OURBOX_INSTALLER_SELECTED_APPLICATIONS_FILE:-/opt/ourbox/installer/cache/selected-apps.json' "${CACHE_DIR}/apply-application-selection.sh" >/dev/null
grep -F 'OURBOX_AIRGAP_PLATFORM_ARTIFACT_SOURCE="registry"' "${TARGET_DIR}/etc/ourbox/release" >/dev/null
grep -F 'OURBOX_APPLICATION_CATALOG_ID="demo-apps"' "${TARGET_DIR}/etc/ourbox/release" >/dev/null
grep -F 'OURBOX_APPLICATION_CATALOG_NAME="Demo Apps"' "${TARGET_DIR}/etc/ourbox/release" >/dev/null
grep -F 'OURBOX_SELECTED_APPLICATION_IDS="landing,dufs"' "${TARGET_DIR}/etc/ourbox/release" >/dev/null
grep -F 'EXISTING_KEY="existing-value"' "${TARGET_DIR}/etc/ourbox/release" >/dev/null
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

printf 'fixture-k3s\n' > "${OVERRIDE_DIR}/k3s/README"
printf 'fixture-image\n' > "${OVERRIDE_DIR}/platform/images/example.txt"
printf '{"images":[]}\n' > "${OVERRIDE_DIR}/platform/images.lock.json"
printf 'OURBOX_PLATFORM_PROFILE=demo-apps\n' > "${OVERRIDE_DIR}/platform/profile.env"
printf 'K3S_VERSION=v1.35.0+k3s1\n' > "${OVERRIDE_DIR}/manifest.env"
printf 'keep-me\n' > "${TARGET_DIR}/opt/ourbox/airgap/platform/contract.digest"

OURBOX_INSTALLER_PROVENANCE_FILE="${CACHE_DIR}/install-provenance.env" \
OURBOX_INSTALLER_AIRGAP_OVERRIDE_DIR="${OVERRIDE_DIR}" \
  "${CACHE_DIR}/apply-airgap-platform-override.sh" "${TARGET_DIR}"

[[ -f "${TARGET_DIR}/opt/ourbox/airgap/k3s/README" ]] || {
  echo "override helper did not stage k3s payload into target" >&2
  exit 1
}
[[ -f "${TARGET_DIR}/opt/ourbox/airgap/platform/images/example.txt" ]] || {
  echo "override helper did not stage platform images into target" >&2
  exit 1
}
[[ -f "${TARGET_DIR}/opt/ourbox/airgap/platform/images.lock.json" ]] || {
  echo "override helper did not stage images.lock.json into target" >&2
  exit 1
}
[[ -f "${TARGET_DIR}/opt/ourbox/airgap/platform/profile.env" ]] || {
  echo "override helper did not stage profile.env into target" >&2
  exit 1
}
[[ -f "${TARGET_DIR}/opt/ourbox/airgap/manifest.env" ]] || {
  echo "override helper did not stage manifest.env into target" >&2
  exit 1
}
grep -F 'keep-me' "${TARGET_DIR}/opt/ourbox/airgap/platform/contract.digest" >/dev/null || {
  echo "override helper unexpectedly replaced platform contract digest" >&2
  exit 1
}

printf '{"catalog_id":"demo-apps"}\n' > "${APPLICATION_SELECTION_DIR}/catalog.json"
printf '{"selected_app_ids":["landing","dufs"]}\n' > "${APPLICATION_SELECTION_DIR}/selected-apps.json"

OURBOX_INSTALLER_APPLICATION_CATALOG_FILE="${APPLICATION_SELECTION_DIR}/catalog.json" \
OURBOX_INSTALLER_SELECTED_APPLICATIONS_FILE="${APPLICATION_SELECTION_DIR}/selected-apps.json" \
  "${CACHE_DIR}/apply-application-selection.sh" "${TARGET_DIR}"

cmp -s "${APPLICATION_SELECTION_DIR}/catalog.json" "${TARGET_DIR}/opt/ourbox/airgap/platform/catalog.json" || {
  echo "application selection helper did not copy catalog.json into target" >&2
  exit 1
}
cmp -s "${APPLICATION_SELECTION_DIR}/selected-apps.json" "${TARGET_DIR}/opt/ourbox/airgap/platform/selected-apps.json" || {
  echo "application selection helper did not copy selected-apps.json into target" >&2
  exit 1
}

rm -f "${APPLICATION_SELECTION_DIR}/selected-apps.json"
OURBOX_INSTALLER_APPLICATION_CATALOG_FILE="${APPLICATION_SELECTION_DIR}/catalog.json" \
OURBOX_INSTALLER_SELECTED_APPLICATIONS_FILE="${APPLICATION_SELECTION_DIR}/selected-apps.json" \
  "${CACHE_DIR}/apply-application-selection.sh" "${TARGET_DIR}"

[[ -f "${TARGET_DIR}/opt/ourbox/airgap/platform/catalog.json" ]] || {
  echo "application selection helper unexpectedly removed catalog.json from target" >&2
  exit 1
}
[[ ! -f "${TARGET_DIR}/opt/ourbox/airgap/platform/selected-apps.json" ]] || {
  echo "application selection helper did not remove selected-apps.json when no selection file was staged" >&2
  exit 1
}

printf '[%s] Woodbox preinstall provenance smoke passed\n' "$(date -Is)"
