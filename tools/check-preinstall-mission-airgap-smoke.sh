#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
PREINSTALL_DIR="${FIXTURE_ROOT}/installer/ourbox-preinstall"
MISSION_ROOT="${TMP}/cdrom/ourbox/mission"
PAYLOAD_DIR="${TMP}/cache/payload"
OVERRIDE_DIR="${TMP}/cache/airgap-platform-override"
MISSION_AIRGAP_DIR="${MISSION_ROOT}/artifacts/airgap"
MISSION_OS_DIR="${MISSION_ROOT}/artifacts/os"
MISSION_SSH_DIR="${MISSION_ROOT}/artifacts/installed-target-ssh"
SOURCE_BUNDLE_DIR="${TMP}/source-airgap"
INSTALLER_CACHE_DIR="${TMP}/cache"

mkdir -p "${TOOLS_DIR}" "${PREINSTALL_DIR}" "${MISSION_AIRGAP_DIR}" "${MISSION_OS_DIR}" "${MISSION_SSH_DIR}" "${PAYLOAD_DIR}" "${INSTALLER_CACHE_DIR}" "${SOURCE_BUNDLE_DIR}/k3s" "${SOURCE_BUNDLE_DIR}/platform/images"

cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/tools/strict-kv-metadata.py" "${TOOLS_DIR}/strict-kv-metadata.py"
cp "${ROOT}/installer/ourbox-preinstall/ourbox-preinstall" "${PREINSTALL_DIR}/ourbox-preinstall"

# shellcheck disable=SC1091
OURBOX_PREINSTALL_LIBRARY_ONLY=1 \
OURBOX_PREINSTALL_TOOLS_ROOT="${TOOLS_DIR}" \
  source "${PREINSTALL_DIR}/ourbox-preinstall"

MISSION_DIR="${MISSION_ROOT}"
MISSION_MANIFEST="${MISSION_DIR}/mission-manifest.json"
PAYLOAD_CACHE_DIR="${PAYLOAD_DIR}"
AIRGAP_PLATFORM_OVERRIDE_DIR="${OVERRIDE_DIR}"

PLATFORM_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
BAKED_AIRGAP_DIGEST="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
MISSION_AIRGAP_DIGEST="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

cat > "${PAYLOAD_CACHE_DIR}/payload.meta.env" <<EOF
OURBOX_PLATFORM_CONTRACT_DIGEST=${PLATFORM_DIGEST}
OURBOX_AIRGAP_PLATFORM_REF=ghcr.io/example/airgap-platform@${BAKED_AIRGAP_DIGEST}
OURBOX_AIRGAP_PLATFORM_DIGEST=${BAKED_AIRGAP_DIGEST}
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/example/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=baked-revision
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.0-baked
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-12T00:00:00Z
OURBOX_AIRGAP_PLATFORM_ARCH=amd64
OURBOX_AIRGAP_PLATFORM_PROFILE=demo-apps
OURBOX_AIRGAP_PLATFORM_K3S_VERSION=v1.35.0+k3s1
OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF

cat > "${SOURCE_BUNDLE_DIR}/manifest.env" <<EOF
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/example/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=mission-revision
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.0-mission
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-12T00:10:00Z
OURBOX_PLATFORM_CONTRACT_DIGEST=${PLATFORM_DIGEST}
AIRGAP_PLATFORM_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
EOF

printf '#!/bin/sh\nexit 0\n' > "${SOURCE_BUNDLE_DIR}/k3s/k3s"
chmod +x "${SOURCE_BUNDLE_DIR}/k3s/k3s"
printf 'fixture\n' > "${SOURCE_BUNDLE_DIR}/k3s/k3s-airgap-images-amd64.tar"
printf '{"images":[]}\n' > "${SOURCE_BUNDLE_DIR}/platform/images.lock.json"
printf 'PROFILE=demo-apps\n' > "${SOURCE_BUNDLE_DIR}/platform/profile.env"
printf 'fixture image tar\n' > "${SOURCE_BUNDLE_DIR}/platform/images/platform-demo.tar"
cat > "${MISSION_AIRGAP_DIR}/catalog.json" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-application-catalog",
  "catalog_id": "demo-apps",
  "catalog_name": "Demo Apps",
  "default_app_ids": [
    "landing",
    "dufs"
  ],
  "apps": [
    {
      "id": "landing",
      "display_name": "Landing"
    },
    {
      "id": "dufs",
      "display_name": "Dufs"
    }
  ]
}
EOF
cat > "${MISSION_AIRGAP_DIR}/selected-apps.json" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-selected-applications",
  "catalog_id": "demo-apps",
  "selection_mode": "defaults",
  "selected_app_ids": [
    "landing",
    "dufs"
  ]
}
EOF

tar -C "${SOURCE_BUNDLE_DIR}" -czf "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz" k3s platform manifest.env
sha256sum "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz" | awk '{print $1"  airgap-platform.tar.gz"}' > "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz.sha256"
cp "${SOURCE_BUNDLE_DIR}/manifest.env" "${MISSION_AIRGAP_DIR}/manifest.env"

printf 'fixture os payload\n' > "${MISSION_OS_DIR}/os-payload.tar.gz"
printf 'OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1\n' > "${MISSION_OS_DIR}/os.meta.env"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBF4tZb5mB7mN7kI8dAcLhY3CS4n4L35YVjgx1qX7QvZ fixture@host\n' > "${MISSION_SSH_DIR}/authorized-key.pub"

cat > "${MISSION_MANIFEST}" <<EOF
{
  "schema": 1,
  "kind": "ourbox-mission",
  "target": {
    "id": "woodbox",
    "media_kind": "installer-usb"
  },
  "operator_mode": {
    "mode": "install",
    "prompt_hostname_on_target": true,
    "prompt_identity_on_target": true
  },
  "selected_os": {
    "artifact_ref": "ghcr.io/example/ourbox-woodbox-os@${MISSION_AIRGAP_DIGEST}",
    "artifact_digest": "${MISSION_AIRGAP_DIGEST}",
    "selection_source": "catalog",
    "release_channel": "stable",
    "platform_contract_digest": "${PLATFORM_DIGEST}",
    "payload": {
      "relpath": "artifacts/os/os-payload.tar.gz",
      "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "size_bytes": 18
    },
    "metadata_relpath": "artifacts/os/os.meta.env"
  },
  "selected_airgap": {
    "artifact_ref": "ghcr.io/example/airgap-platform@${MISSION_AIRGAP_DIGEST}",
    "artifact_digest": "${MISSION_AIRGAP_DIGEST}",
    "selection_source": "catalog",
    "release_channel": "stable",
    "platform_contract_digest": "${PLATFORM_DIGEST}",
    "arch": "amd64",
    "payload_relpath": "artifacts/airgap/airgap-platform.tar.gz",
    "manifest_relpath": "artifacts/airgap/manifest.env",
    "present_in_selected_os_payload": false
  },
  "selected_applications": {
    "catalog_id": "demo-apps",
    "catalog_name": "Demo Apps",
    "selection_mode": "defaults",
    "selected_app_ids": [
      "landing",
      "dufs"
    ],
    "catalog_relpath": "artifacts/airgap/catalog.json",
    "selection_relpath": "artifacts/airgap/selected-apps.json"
  },
  "installed_target_ssh": {
    "mode": "host-generated-authorized-key",
    "key_name": "fixture-shared-dev",
    "authorized_key_relpath": "artifacts/installed-target-ssh/authorized-key.pub",
    "key_type": "ssh-ed25519",
    "public_key_fingerprint": "SHA256:fixtureFingerprint0123456789abcdef=="
  }
}
EOF

load_selected_payload_airgap_metadata
[[ "${MISSION_PRESENT}" == "1" ]] || {
  echo "expected embedded mission metadata to be loaded" >&2
  exit 1
}
[[ "${OS_ARTIFACT_SOURCE}" == "mission" ]] || {
  echo "expected OS artifact source to switch to mission provenance" >&2
  exit 1
}
[[ "${OS_ARTIFACT_REF}" == "ghcr.io/example/ourbox-woodbox-os@${MISSION_AIRGAP_DIGEST}" ]] || {
  echo "unexpected mission OS artifact ref: ${OS_ARTIFACT_REF}" >&2
  exit 1
}
[[ "${OURBOX_APPLICATION_CATALOG_ID}" == "demo-apps" ]] || {
  echo "unexpected application catalog id: ${OURBOX_APPLICATION_CATALOG_ID}" >&2
  exit 1
}
[[ "${OURBOX_SELECTED_APPLICATION_IDS}" == "landing,dufs" ]] || {
  echo "unexpected selected applications: ${OURBOX_SELECTED_APPLICATION_IDS}" >&2
  exit 1
}
[[ "${MISSION_INSTALLED_TARGET_SSH_PRESENT}" == "1" ]] || {
  echo "expected embedded mission installed_target_ssh metadata to be loaded" >&2
  exit 1
}
[[ "${MISSION_INSTALLED_TARGET_SSH_KEY_NAME}" == "fixture-shared-dev" ]] || {
  echo "unexpected installed-target SSH key name: ${MISSION_INSTALLED_TARGET_SSH_KEY_NAME}" >&2
  exit 1
}
[[ -f "${MISSION_INSTALLED_TARGET_SSH_AUTHORIZED_KEY_PATH}" ]] || {
  echo "expected installed-target SSH public key path to resolve inside mission media" >&2
  exit 1
}

prepare_selected_airgap_platform_bundle
stage_selected_application_metadata
[[ "${OURBOX_AIRGAP_PLATFORM_ARTIFACT_SOURCE}" == "mission" ]] || {
  echo "expected mission-local airgap override source, got ${OURBOX_AIRGAP_PLATFORM_ARTIFACT_SOURCE}" >&2
  exit 1
}
[[ "${OURBOX_AIRGAP_PLATFORM_REF}" == "ghcr.io/example/airgap-platform@${MISSION_AIRGAP_DIGEST}" ]] || {
  echo "unexpected mission airgap ref: ${OURBOX_AIRGAP_PLATFORM_REF}" >&2
  exit 1
}
[[ -x "${AIRGAP_PLATFORM_OVERRIDE_DIR}/k3s/k3s" ]] || {
  echo "mission airgap bundle was not extracted into override dir" >&2
  exit 1
}
[[ -f "${AIRGAP_PLATFORM_OVERRIDE_DIR}/platform/images/platform-demo.tar" ]] || {
  echo "mission airgap platform image tar missing from override dir" >&2
  exit 1
}
[[ -f "${INSTALLER_CACHE_DIR}/catalog.json" ]] || {
  echo "mission application catalog was not staged into installer cache" >&2
  exit 1
}
[[ -f "${INSTALLER_CACHE_DIR}/selected-apps.json" ]] || {
  echo "mission selected-apps.json was not staged into installer cache" >&2
  exit 1
}

rm -f "${MISSION_AIRGAP_DIR}/airgap-platform.tar.gz.sha256"
set +e
(prepare_selected_airgap_platform_bundle >/dev/null 2>&1)
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "expected prepare_selected_airgap_platform_bundle to reject mission airgap payloads missing a checksum sidecar" >&2
  exit 1
fi

printf '[%s] Woodbox preinstall mission-airgap smoke passed\n' "$(date -Is)"
