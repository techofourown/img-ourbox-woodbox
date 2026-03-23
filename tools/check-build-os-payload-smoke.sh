#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
INSTALLER_ROOTFS="${FIXTURE_ROOT}/installer/ourbox/rootfs"
ARTIFACTS_AIRGAP="${FIXTURE_ROOT}/artifacts/airgap"
DEPLOY_DIR="${FIXTURE_ROOT}/deploy"
mkdir -p "${TOOLS_DIR}" "${INSTALLER_ROOTFS}/opt/ourbox/airgap/platform" "${INSTALLER_ROOTFS}/etc/ourbox" "${ARTIFACTS_AIRGAP}/k3s" "${ARTIFACTS_AIRGAP}/platform/images" "${DEPLOY_DIR}"

cp "${ROOT}/tools/build-os-payload.sh" "${TOOLS_DIR}/build-os-payload.sh"
cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"

printf '#!/bin/sh\nexit 0\n' > "${ARTIFACTS_AIRGAP}/k3s/k3s"
chmod +x "${ARTIFACTS_AIRGAP}/k3s/k3s"
: > "${ARTIFACTS_AIRGAP}/k3s/k3s-airgap-images-amd64.tar"
: > "${ARTIFACTS_AIRGAP}/platform/images/app.tar"
printf '{}\n' > "${ARTIFACTS_AIRGAP}/platform/images.lock.json"
printf 'PROFILE=demo-apps\n' > "${ARTIFACTS_AIRGAP}/platform/profile.env"
cat > "${ARTIFACTS_AIRGAP}/platform/catalog.json" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-application-catalog",
  "catalog_id": "demo-apps",
  "catalog_name": "Demo Apps",
  "default_app_ids": [
    "landing"
  ],
  "apps": [
    {
      "id": "landing",
      "display_name": "Landing",
      "image_names": [
        "landing"
      ]
    }
  ]
}
EOF
cat > "${ARTIFACTS_AIRGAP}/platform/selected-apps.json" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-selected-applications",
  "catalog_id": "demo-apps",
  "selection_mode": "catalog-defaults",
  "selected_app_ids": [
    "landing"
  ]
}
EOF

AIRGAP_DIGEST="sha256:5555555555555555555555555555555555555555555555555555555555555555"
CONTRACT_DIGEST="sha256:6666666666666666666666666666666666666666666666666666666666666666"
LOCK_SHA="7777777777777777777777777777777777777777777777777777777777777777"

cat > "${ARTIFACTS_AIRGAP}/manifest.env" <<EOF
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-airgap-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-11T00:00:00Z
OURBOX_PLATFORM_CONTRACT_REF=ghcr.io/techofourown/sw-ourbox-os/platform-contract@${CONTRACT_DIGEST}
OURBOX_PLATFORM_CONTRACT_DIGEST=${CONTRACT_DIGEST}
OURBOX_SUBSTRATE_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=${LOCK_SHA}
EOF

cat > "${ARTIFACTS_AIRGAP}/selected-bundle.env" <<EOF
OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${AIRGAP_DIGEST}
OURBOX_SUBSTRATE_DIGEST=${AIRGAP_DIGEST}
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-airgap-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-11T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${LOCK_SHA}
OURBOX_PLATFORM_CONTRACT_REF=ghcr.io/techofourown/sw-ourbox-os/platform-contract@${CONTRACT_DIGEST}
OURBOX_PLATFORM_CONTRACT_DIGEST=${CONTRACT_DIGEST}
EOF

cat > "${INSTALLER_ROOTFS}/opt/ourbox/airgap/platform/contract.env" <<EOF
OURBOX_PLATFORM_CONTRACT_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_PLATFORM_CONTRACT_REVISION=fixture-platform-revision
OURBOX_PLATFORM_CONTRACT_VERSION=v0.0.0-fixture
OURBOX_PLATFORM_CONTRACT_CREATED=2026-03-11T00:00:00Z
EOF
printf '%s\n' "${CONTRACT_DIGEST}" > "${INSTALLER_ROOTFS}/opt/ourbox/airgap/platform/contract.digest"

OURBOX_VERSION="payload-smoke" \
OURBOX_TARGET="x86" \
OURBOX_SKU="TOO-OBX-WBX-FIXTURE" \
OURBOX_VARIANT="prod" \
bash "${TOOLS_DIR}/build-os-payload.sh"

META_ENV="$(find "${DEPLOY_DIR}" -maxdepth 1 -type f -name '*.meta.env' | head -n1)"
TARBALL="$(find "${DEPLOY_DIR}" -maxdepth 1 -type f -name '*.tar.gz' | head -n1)"
[[ -f "${META_ENV}" ]] || {
  echo "deploy metadata sidecar not found" >&2
  exit 1
}
[[ -f "${TARBALL}" ]] || {
  echo "payload tarball not found" >&2
  exit 1
}

grep -F "OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${AIRGAP_DIGEST}" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_DIGEST=${AIRGAP_DIGEST}" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_ARCH=amd64" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_PROFILE=demo-apps" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${LOCK_SHA}" "${META_ENV}" >/dev/null
grep -F "OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1" "${META_ENV}" >/dev/null
grep -F "GIT_SHA=" "${META_ENV}" >/dev/null
grep -F "OURBOX_PLATFORM_CONTRACT_CREATED=2026-03-11T00:00:00Z" "${META_ENV}" >/dev/null

tar -xOzf "${TARBALL}" ./payload.meta.env | grep -F "OURBOX_SUBSTRATE_DIGEST=${AIRGAP_DIGEST}" >/dev/null
tar -xOzf "${TARBALL}" ./payload.meta.env | grep -F "OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${LOCK_SHA}" >/dev/null
tar -xOzf "${TARBALL}" ./payload.meta.env | grep -F "OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1" >/dev/null
tar -xOzf "${TARBALL}" ./airgap/platform/catalog.json | grep -F '"catalog_id": "demo-apps"' >/dev/null
tar -xOzf "${TARBALL}" ./airgap/platform/selected-apps.json | grep -F '"selection_mode": "catalog-defaults"' >/dev/null
if tar -xOzf "${TARBALL}" ./rootfs/etc/ourbox/release | grep -q '^OURBOX_SUBSTRATE_'; then
  echo "payload rootfs release file must not preseed OURBOX_SUBSTRATE_* keys" >&2
  exit 1
fi

printf '[%s] Woodbox build-os-payload smoke passed\n' "$(date -Is)"
