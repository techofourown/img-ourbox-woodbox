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
OVERRIDE_DIR="${TMP}/cache/ourbox-substrate-override"
MISSION_SUBSTRATE_DIR="${MISSION_ROOT}/artifacts/substrate"
MISSION_OS_DIR="${MISSION_ROOT}/artifacts/os"
MISSION_SSH_DIR="${MISSION_ROOT}/artifacts/installed-target-ssh"
SOURCE_BUNDLE_DIR="${TMP}/source-substrate"
INSTALLER_CACHE_DIR="${TMP}/cache"

mkdir -p "${TOOLS_DIR}" "${PREINSTALL_DIR}" "${MISSION_SUBSTRATE_DIR}" "${MISSION_OS_DIR}" "${MISSION_SSH_DIR}" "${PAYLOAD_DIR}" "${INSTALLER_CACHE_DIR}" "${SOURCE_BUNDLE_DIR}/k3s" "${SOURCE_BUNDLE_DIR}/platform/images"

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
SUBSTRATE_OVERRIDE_DIR="${OVERRIDE_DIR}"

BAKED_SUBSTRATE_DIGEST="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
MISSION_OS_DIGEST="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
MISSION_SUBSTRATE_DIGEST="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

cat > "${PAYLOAD_CACHE_DIR}/payload.meta.env" <<EOF
OURBOX_SUBSTRATE_REF=ghcr.io/example/ourbox-substrate@${BAKED_SUBSTRATE_DIGEST}
OURBOX_SUBSTRATE_DIGEST=${BAKED_SUBSTRATE_DIGEST}
OURBOX_SUBSTRATE_SOURCE=https://github.com/example/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=baked-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-baked
OURBOX_SUBSTRATE_CREATED=2026-03-12T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
EOF

cat > "${SOURCE_BUNDLE_DIR}/manifest.env" <<EOF
OURBOX_SUBSTRATE_SOURCE=https://github.com/example/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=mission-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-mission
OURBOX_SUBSTRATE_CREATED=2026-03-12T00:10:00Z
OURBOX_SUBSTRATE_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
EOF

printf '#!/bin/sh\nexit 0\n' > "${SOURCE_BUNDLE_DIR}/k3s/k3s"
chmod +x "${SOURCE_BUNDLE_DIR}/k3s/k3s"
printf 'fixture\n' > "${SOURCE_BUNDLE_DIR}/k3s/k3s-images-amd64.tar"
printf '{"images":[]}\n' > "${SOURCE_BUNDLE_DIR}/platform/images.lock.json"
printf 'PROFILE=demo-apps\n' > "${SOURCE_BUNDLE_DIR}/platform/profile.env"
printf 'fixture image tar\n' > "${SOURCE_BUNDLE_DIR}/platform/images/platform-demo.tar"
cat > "${MISSION_SUBSTRATE_DIR}/catalog.json" <<'EOF'
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
cat > "${MISSION_SUBSTRATE_DIR}/selected-apps.json" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-selected-applications",
  "catalog_id": "demo-apps",
  "selection_mode": "catalog-defaults",
  "selected_app_ids": [
    "landing",
    "dufs"
  ]
}
EOF
cat > "${MISSION_SUBSTRATE_DIR}/application-images.lock.json" <<'EOF'
{
  "schema": 1,
  "images": [
    {
      "name": "landing",
      "ref": "ghcr.io/example/landing@sha256:1111111111111111111111111111111111111111111111111111111111111111"
    },
    {
      "name": "dufs",
      "ref": "ghcr.io/example/dufs@sha256:2222222222222222222222222222222222222222222222222222222222222222"
    }
  ]
}
EOF

tar -C "${SOURCE_BUNDLE_DIR}" -czf "${MISSION_SUBSTRATE_DIR}/ourbox-substrate.tar.gz" k3s platform manifest.env
sha256sum "${MISSION_SUBSTRATE_DIR}/ourbox-substrate.tar.gz" | awk '{print $1"  ourbox-substrate.tar.gz"}' > "${MISSION_SUBSTRATE_DIR}/ourbox-substrate.tar.gz.sha256"
cp "${SOURCE_BUNDLE_DIR}/manifest.env" "${MISSION_SUBSTRATE_DIR}/manifest.env"

printf 'fixture os payload\n' > "${MISSION_OS_DIR}/os-payload.tar.gz"
printf 'OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1\n' > "${MISSION_OS_DIR}/os.meta.env"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBF4tZb5mB7mN7kI8dAcLhY3CS4n4L35YVjgx1qX7QvZ fixture@host\n' > "${MISSION_SSH_DIR}/authorized-key.pub"

cat > "${MISSION_MANIFEST}" <<EOF
{
  "kind": "ourbox-mission",
  "compose_id": "woodbox-fixture",
  "created": "2026-03-12T00:00:00Z",
  "target": {
    "id": "woodbox",
    "media_kind": "installer-usb"
  },
  "composer": {
    "name": "img-ourbox-woodbox",
    "phase": "preinstall-mission-substrate-smoke",
    "source_revision": "abc123def456"
  },
  "adapter": {
    "source_repo": "https://github.com/techofourown/img-ourbox-woodbox",
    "source_revision": "abc123def456",
    "adapter_json_relpath": "tools/media-adapter/adapter.json",
    "runtime_prompts_kept": [
      "os-disk-selection",
      "data-disk-selection",
      "data-disk-format-confirmation",
      "identity",
      "install-confirmation"
    ]
  },
  "operator_mode": {
    "mode": "install",
    "prompt_hostname_on_target": true,
    "prompt_identity_on_target": true
  },
  "mission_media": {
    "compose_strategy": "woodbox-fat-iso-with-host-selected-os-application-catalog-and-app-selection",
    "mission_only": false
  },
  "requested": {
    "os": {
      "selection_source": "catalog",
      "release_channel": "stable",
      "requested_ref": ""
    },
    "selected_substrate": {
      "selection_source": "catalog",
      "release_channel": "stable",
      "requested_ref": ""
    },
    "applications": {
      "catalog_id": "demo-apps",
      "catalog_name": "Demo Apps",
      "selection_mode": "catalog-defaults",
      "selected_app_ids": [
        "landing",
        "dufs"
      ],
      "source_catalogs": [
        {
          "catalog_id": "demo-apps",
          "catalog_name": "Demo Apps"
        }
      ]
    },
    "installed_target_ssh": {
      "mode": "host-generated-authorized-key",
      "key_name": "fixture-shared-dev"
    }
  },
  "resolved": {
    "os": {
      "artifact_ref": "ghcr.io/example/ourbox-woodbox-os@${MISSION_OS_DIGEST}",
      "artifact_digest": "${MISSION_OS_DIGEST}",
      "selection_source": "catalog",
      "release_channel": "stable",
      "payload": {
        "relpath": "artifacts/os/os-payload.tar.gz",
        "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "size_bytes": 18
      },
      "metadata_relpath": "artifacts/os/os.meta.env"
    },
    "selected_substrate": {
      "artifact_ref": "ghcr.io/example/ourbox-substrate@${MISSION_SUBSTRATE_DIGEST}",
      "artifact_digest": "${MISSION_SUBSTRATE_DIGEST}",
      "selection_source": "catalog",
      "release_channel": "stable",
      "arch": "amd64",
      "payload_relpath": "artifacts/substrate/ourbox-substrate.tar.gz",
      "manifest_relpath": "artifacts/substrate/manifest.env",
      "present_in_selected_os_payload": false
    },
    "applications": {
      "catalog_id": "demo-apps",
      "catalog_name": "Demo Apps",
      "selection_mode": "catalog-defaults",
      "selected_app_ids": [
        "landing",
        "dufs"
      ],
      "catalog_relpath": "artifacts/substrate/catalog.json",
      "images_lock_relpath": "artifacts/substrate/application-images.lock.json",
      "selection_relpath": "artifacts/substrate/selected-apps.json"
    },
    "installed_target_ssh": {
      "mode": "host-generated-authorized-key",
      "key_name": "fixture-shared-dev",
      "authorized_key_relpath": "artifacts/installed-target-ssh/authorized-key.pub",
      "key_type": "ssh-ed25519",
      "public_key_fingerprint": "SHA256:fixtureFingerprint0123456789abcdef=="
    }
  },
  "staged_files": []
}
EOF

load_selected_payload_substrate_metadata
[[ "${MISSION_PRESENT}" == "1" ]] || {
  echo "expected embedded mission metadata to be loaded" >&2
  exit 1
}
[[ "${OS_ARTIFACT_SOURCE}" == "mission" ]] || {
  echo "expected OS artifact source to switch to mission provenance" >&2
  exit 1
}
[[ "${OS_ARTIFACT_REF}" == "ghcr.io/example/ourbox-woodbox-os@${MISSION_OS_DIGEST}" ]] || {
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

prepare_selected_substrate_bundle
stage_selected_application_metadata
[[ "${OURBOX_SUBSTRATE_ARTIFACT_SOURCE}" == "mission" ]] || {
  echo "expected mission-local substrate override source, got ${OURBOX_SUBSTRATE_ARTIFACT_SOURCE}" >&2
  exit 1
}
[[ "${OURBOX_SUBSTRATE_REF}" == "ghcr.io/example/ourbox-substrate@${MISSION_SUBSTRATE_DIGEST}" ]] || {
  echo "unexpected mission substrate ref: ${OURBOX_SUBSTRATE_REF}" >&2
  exit 1
}
[[ -x "${SUBSTRATE_OVERRIDE_DIR}/k3s/k3s" ]] || {
  echo "mission substrate bundle was not extracted into override dir" >&2
  exit 1
}
[[ -f "${SUBSTRATE_OVERRIDE_DIR}/platform/images/platform-demo.tar" ]] || {
  echo "mission substrate platform image tar missing from override dir" >&2
  exit 1
}
[[ -f "${INSTALLER_CACHE_DIR}/catalog.json" ]] || {
  echo "mission application catalog was not staged into installer cache" >&2
  exit 1
}
[[ -f "${INSTALLER_CACHE_DIR}/application-images.lock.json" ]] || {
  echo "mission application-images.lock.json was not staged into installer cache" >&2
  exit 1
}
[[ -f "${INSTALLER_CACHE_DIR}/selected-apps.json" ]] || {
  echo "mission selected-apps.json was not staged into installer cache" >&2
  exit 1
}

python3 - <<'PY' "${MISSION_MANIFEST}"
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["resolved"]["selected_substrate"]["payload_relpath"] = "../outside-ourbox-substrate.tar.gz"
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

set +e
( load_selected_payload_substrate_metadata ) >"${TMP}/mission-relpath.log" 2>&1
status=$?
set -e

[[ "${status}" -ne 0 ]] || {
  echo "expected embedded mission relpath traversal to be rejected" >&2
  exit 1
}
grep -F "must stay within the mission directory" "${TMP}/mission-relpath.log" >/dev/null || {
  cat "${TMP}/mission-relpath.log" >&2
  exit 1
}

rm -f "${MISSION_SUBSTRATE_DIR}/ourbox-substrate.tar.gz.sha256"
set +e
(prepare_selected_substrate_bundle >/dev/null 2>&1)
rc=$?
set -e
if [[ "${rc}" -eq 0 ]]; then
  echo "expected prepare_selected_substrate_bundle to reject mission substrate payloads missing a checksum sidecar" >&2
  exit 1
fi

printf '[%s] Woodbox preinstall mission-substrate smoke passed\n' "$(date -Is)"
