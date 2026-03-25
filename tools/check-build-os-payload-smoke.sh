#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
INSTALLER_ROOTFS="${FIXTURE_ROOT}/installer/ourbox/rootfs"
ARTIFACTS_SUBSTRATE="${FIXTURE_ROOT}/artifacts/substrate"
DEPLOY_DIR="${FIXTURE_ROOT}/deploy"
mkdir -p "${TOOLS_DIR}" "${INSTALLER_ROOTFS}/opt/ourbox/substrate/platform" "${INSTALLER_ROOTFS}/etc/ourbox" "${ARTIFACTS_SUBSTRATE}/k3s" "${ARTIFACTS_SUBSTRATE}/platform/images" "${DEPLOY_DIR}"

cp "${ROOT}/tools/build-os-payload.sh" "${TOOLS_DIR}/build-os-payload.sh"
cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"

printf '#!/bin/sh\nexit 0\n' > "${ARTIFACTS_SUBSTRATE}/k3s/k3s"
chmod +x "${ARTIFACTS_SUBSTRATE}/k3s/k3s"
: > "${ARTIFACTS_SUBSTRATE}/k3s/k3s-images-amd64.tar"
: > "${ARTIFACTS_SUBSTRATE}/platform/images/app.tar"
printf '{}\n' > "${ARTIFACTS_SUBSTRATE}/platform/images.lock.json"
printf 'OURBOX_PLATFORM_PROFILE=demo-apps\n' > "${ARTIFACTS_SUBSTRATE}/platform/profile.env"

SUBSTRATE_DIGEST="sha256:5555555555555555555555555555555555555555555555555555555555555555"
LOCK_SHA="7777777777777777777777777777777777777777777777777777777777777777"

cat > "${ARTIFACTS_SUBSTRATE}/manifest.env" <<EOF
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-substrate-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-11T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=${LOCK_SHA}
EOF

cat > "${ARTIFACTS_SUBSTRATE}/selected-bundle.env" <<EOF
OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${SUBSTRATE_DIGEST}
OURBOX_SUBSTRATE_DIGEST=${SUBSTRATE_DIGEST}
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-substrate-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-11T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${LOCK_SHA}
EOF

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

grep -F "OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${SUBSTRATE_DIGEST}" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_DIGEST=${SUBSTRATE_DIGEST}" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_ARCH=amd64" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_PROFILE=demo-apps" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1" "${META_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${LOCK_SHA}" "${META_ENV}" >/dev/null
grep -F "OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1" "${META_ENV}" >/dev/null
grep -F "GIT_SHA=" "${META_ENV}" >/dev/null
tar -xOzf "${TARBALL}" ./payload.meta.env | grep -F "OURBOX_SUBSTRATE_DIGEST=${SUBSTRATE_DIGEST}" >/dev/null
tar -xOzf "${TARBALL}" ./payload.meta.env | grep -F "OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${LOCK_SHA}" >/dev/null
tar -xOzf "${TARBALL}" ./payload.meta.env | grep -F "OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1" >/dev/null
tar -xOzf "${TARBALL}" ./substrate/platform/images.lock.json | grep -F '{}' >/dev/null
if tar -tzf "${TARBALL}" | grep -Fx './substrate/platform/catalog.json' >/dev/null; then
  echo "OS payload must not bake application catalog metadata into the substrate bundle" >&2
  exit 1
fi
if tar -tzf "${TARBALL}" | grep -Fx './substrate/platform/selected-apps.json' >/dev/null; then
  echo "OS payload must not bake selected application metadata into the substrate bundle" >&2
  exit 1
fi
if tar -xOzf "${TARBALL}" ./rootfs/etc/ourbox/release | grep -q '^OURBOX_SUBSTRATE_'; then
  echo "payload rootfs release file must not preseed OURBOX_SUBSTRATE_* keys" >&2
  exit 1
fi

printf '[%s] Woodbox build-os-payload smoke passed\n' "$(date -Is)"
