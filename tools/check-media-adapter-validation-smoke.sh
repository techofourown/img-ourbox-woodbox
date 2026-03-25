#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

MISSION_DIR="${TMP}/mission"
OS_DIR="${MISSION_DIR}/artifacts/os"
SUBSTRATE_DIR="${MISSION_DIR}/artifacts/substrate"
SUBSTRATE_SOURCE_DIR="${TMP}/substrate-source"
SSH_DIR="${MISSION_DIR}/artifacts/installed-target-ssh"
mkdir -p "${OS_DIR}" "${SUBSTRATE_DIR}" "${SSH_DIR}"

OS_PAYLOAD="${OS_DIR}/os-payload.tar.gz"
OS_META_ENV="${OS_DIR}/os.meta.env"
SUBSTRATE_PAYLOAD="${SUBSTRATE_DIR}/ourbox-substrate.tar.gz"
SUBSTRATE_MANIFEST="${SUBSTRATE_DIR}/manifest.env"
APP_CATALOG="${SUBSTRATE_DIR}/catalog.json"
SELECTED_APPS="${SUBSTRATE_DIR}/selected-apps.json"
AUTHORIZED_KEY="${SSH_DIR}/authorized-key.pub"
MISSION_MANIFEST="${MISSION_DIR}/mission-manifest.json"

printf 'payload bytes\n' > "${OS_PAYLOAD}"
cat > "${OS_META_ENV}" <<'EOF'
OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1
OURBOX_PRODUCT=ourbox
OURBOX_DEVICE=woodbox
OURBOX_TARGET=x86
OURBOX_SKU=TOO-OBX-WBX-BASE-JU3XK8
OURBOX_VARIANT=prod
OURBOX_VERSION=v0.0.1
OURBOX_RECIPE_GIT_HASH=abc123def456
BUILD_TS=2026-03-12T00:00:00Z
OURBOX_SUBSTRATE_REF=ghcr.io/example/ourbox-substrate@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_SUBSTRATE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=abc123def456
OURBOX_SUBSTRATE_VERSION=v0.0.1
OURBOX_SUBSTRATE_CREATED=2026-03-12T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
OURBOX_BASE_ISO_URL=https://example.invalid/ubuntu.iso
OURBOX_BASE_ISO_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
K3S_VERSION=v1.35.0+k3s1
GITHUB_RUN_ID=
GITHUB_RUN_ATTEMPT=
EOF

printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBF4tZb5mB7mN7kI8dAcLhY3CS4n4L35YVjgx1qX7QvZ fixture@host\n' > "${AUTHORIZED_KEY}"

build_substrate_bundle() {
  local variant="${1:-valid}"

  rm -rf "${SUBSTRATE_SOURCE_DIR}"
  mkdir -p "${SUBSTRATE_SOURCE_DIR}/k3s" "${SUBSTRATE_SOURCE_DIR}/platform/images"

  cat > "${SUBSTRATE_SOURCE_DIR}/manifest.env" <<'EOF'
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=abc123def456
OURBOX_SUBSTRATE_VERSION=v0.0.1
OURBOX_SUBSTRATE_CREATED=2026-03-12T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
EOF
  printf '#!/bin/sh\nexit 0\n' > "${SUBSTRATE_SOURCE_DIR}/k3s/k3s"
  chmod +x "${SUBSTRATE_SOURCE_DIR}/k3s/k3s"
  printf 'fixture k3s images\n' > "${SUBSTRATE_SOURCE_DIR}/k3s/k3s-images-amd64.tar"
  printf 'PROFILE=demo-apps\n' > "${SUBSTRATE_SOURCE_DIR}/platform/profile.env"
  printf 'fixture image tar\n' > "${SUBSTRATE_SOURCE_DIR}/platform/images/platform-demo.tar"
  if [[ "${variant}" != "missing-images-lock" ]]; then
    printf '{"images":[]}\n' > "${SUBSTRATE_SOURCE_DIR}/platform/images.lock.json"
  fi

  case "${variant}" in
    valid|missing-images-lock)
      tar -C "${SUBSTRATE_SOURCE_DIR}" -czf "${SUBSTRATE_PAYLOAD}" k3s platform manifest.env
      ;;
    invalid-tar)
      printf 'not a tarball\n' > "${SUBSTRATE_PAYLOAD}"
      ;;
    *)
      echo "unknown substrate bundle variant: ${variant}" >&2
      exit 1
      ;;
  esac

  printf '%s  %s\n' "$(sha256sum "${SUBSTRATE_PAYLOAD}" | awk '{print $1}')" "ourbox-substrate.tar.gz" > "${SUBSTRATE_PAYLOAD}.sha256"
  cp -f "${SUBSTRATE_SOURCE_DIR}/manifest.env" "${SUBSTRATE_MANIFEST}"
  cat > "${APP_CATALOG}" <<'EOF'
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
  cat > "${SELECTED_APPS}" <<'EOF'
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
}

write_manifest() {
  local include_selected_substrate="${1}"
  cat > "${MISSION_MANIFEST}" <<'EOF'
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
    "phase": "adapter-validation-smoke",
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
      "selection_mode": "host-selected",
      "selection_source": "catalog",
      "release_channel": "stable",
      "requested_ref": ""
    }
  },
  "resolved": {
    "os": {
      "selection_source": "catalog",
      "release_channel": "stable",
      "artifact_ref": "ghcr.io/example/ourbox-woodbox-os@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "artifact_digest": "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "artifact_type": "application/vnd.techofourown.ourbox.woodbox.os-payload.v1",
      "payload": {
        "relpath": "artifacts/os/os-payload.tar.gz"
      },
      "metadata_relpath": "artifacts/os/os.meta.env"
    }
  }
}
EOF
  if [[ "${include_selected_substrate}" == "1" ]]; then
    python3 - <<'PY' "${MISSION_MANIFEST}"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

manifest["resolved"]["selected_substrate"] = {
    "selection_mode": "host-selected",
    "selection_source": "catalog",
    "release_channel": "stable",
    "artifact_ref": "ghcr.io/example/ourbox-substrate@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "artifact_digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "arch": "amd64",
    "payload_relpath": "artifacts/substrate/ourbox-substrate.tar.gz",
    "manifest_relpath": "artifacts/substrate/manifest.env",
    "present_in_selected_os_payload": False
}
manifest["resolved"]["applications"] = {
    "catalog_id": "demo-apps",
    "catalog_name": "Demo Apps",
    "selection_mode": "catalog-defaults",
    "selected_app_ids": ["landing", "dufs"],
    "catalog_relpath": "artifacts/substrate/catalog.json",
    "selection_relpath": "artifacts/substrate/selected-apps.json"
}
manifest["resolved"]["installed_target_ssh"] = {
    "mode": "host-generated-authorized-key",
    "key_name": "fixture-shared-dev",
    "key_type": "ssh-ed25519",
    "public_key_fingerprint": "SHA256:fixtureFingerprint0123456789abcdef==",
    "authorized_key_relpath": "artifacts/installed-target-ssh/authorized-key.pub"
}

with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
  fi
}

expect_validation_failure() {
  local description="$1"
  if bash "${ROOT}/tools/media-adapter/validate-media.sh" \
    --mission-dir "${MISSION_DIR}" \
    --os-payload "${OS_PAYLOAD}" \
    --os-meta-env "${OS_META_ENV}" >/dev/null 2>&1; then
    echo "expected validate-media.sh to reject ${description}" >&2
    exit 1
  fi
}

mutate_manifest() {
  local snippet="$1"
  python3 - <<'PY' "${MISSION_MANIFEST}" "${snippet}"
import json
import sys

path = sys.argv[1]
snippet = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
exec(snippet, {"manifest": manifest})
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
}

build_substrate_bundle valid
write_manifest 1
bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${MISSION_DIR}" \
  --os-payload "${OS_PAYLOAD}" \
  --os-meta-env "${OS_META_ENV}"

write_manifest 0
expect_validation_failure "mission manifests missing selected_substrate and applications"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'del manifest["resolved"]["selected_substrate"]["artifact_digest"]'
expect_validation_failure "mission manifests missing selected_substrate.artifact_digest"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'del manifest["resolved"]["applications"]'
expect_validation_failure "mission manifests missing selected_applications"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'del manifest["resolved"]["applications"]["selection_relpath"]'
expect_validation_failure "mission manifests missing selected_applications.selection_relpath"

build_substrate_bundle valid
write_manifest 1
cat > "${SELECTED_APPS}" <<'EOF'
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
expect_validation_failure "mission selected applications files that do not match manifest selected_applications.selected_app_ids"

build_substrate_bundle valid
write_manifest 1
cat > "${SELECTED_APPS}" <<'EOF'
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
expect_validation_failure "mission selected applications files with an unsupported selection_mode"

build_substrate_bundle valid
write_manifest 1
rm -f "${OS_META_ENV}"
expect_validation_failure "mission payloads missing os.meta.env"
cat > "${OS_META_ENV}" <<'EOF'
OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1
OURBOX_PRODUCT=ourbox
OURBOX_DEVICE=woodbox
OURBOX_TARGET=x86
OURBOX_SKU=TOO-OBX-WBX-BASE-JU3XK8
OURBOX_VARIANT=prod
OURBOX_VERSION=v0.0.1
OURBOX_RECIPE_GIT_HASH=abc123def456
BUILD_TS=2026-03-12T00:00:00Z
OURBOX_SUBSTRATE_REF=ghcr.io/example/ourbox-substrate@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_SUBSTRATE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=abc123def456
OURBOX_SUBSTRATE_VERSION=v0.0.1
OURBOX_SUBSTRATE_CREATED=2026-03-12T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
OURBOX_BASE_ISO_URL=https://example.invalid/ubuntu.iso
OURBOX_BASE_ISO_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
K3S_VERSION=v1.35.0+k3s1
GITHUB_RUN_ID=
GITHUB_RUN_ATTEMPT=
EOF

build_substrate_bundle valid
write_manifest 1
rm -f "${SUBSTRATE_PAYLOAD}.sha256"
expect_validation_failure "mission substrate payloads missing ourbox-substrate.tar.gz.sha256"

build_substrate_bundle valid
write_manifest 1
printf 'OURBOX_SUBSTRATE_VERSION=v9.9.9\n' >> "${SUBSTRATE_MANIFEST}"
expect_validation_failure "mission substrate payloads whose staged manifest sidecar differs from the tarball manifest"

build_substrate_bundle valid
write_manifest 1
printf '%s  %s\n' 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' 'ourbox-substrate.tar.gz' > "${SUBSTRATE_PAYLOAD}.sha256"
expect_validation_failure "mission substrate payloads with mismatched ourbox-substrate.tar.gz.sha256"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'manifest["resolved"]["os"]["artifact_digest"] = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
expect_validation_failure "mission manifests with mismatched selected_os artifact digest"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'manifest["resolved"]["selected_substrate"]["artifact_digest"] = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
expect_validation_failure "mission manifests with mismatched selected_substrate artifact digest"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'manifest["resolved"]["selected_substrate"]["payload_relpath"] = "../outside.tar.gz"'
expect_validation_failure "mission manifests with selected_substrate.payload_relpath escaping the mission directory"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'manifest["resolved"]["selected_substrate"]["manifest_relpath"] = "../outside.env"'
expect_validation_failure "mission manifests with selected_substrate.manifest_relpath escaping the mission directory"

build_substrate_bundle valid
write_manifest 1
mutate_manifest 'manifest["resolved"]["os"]["metadata_relpath"] = "../outside.env"'
expect_validation_failure "mission manifests with selected_os.metadata_relpath escaping the mission directory"

build_substrate_bundle invalid-tar
write_manifest 1
expect_validation_failure "mission substrate payloads that are not valid gzip tar archives"

build_substrate_bundle missing-images-lock
write_manifest 1
expect_validation_failure "mission substrate payloads missing required bundle files"

printf '[%s] Woodbox media adapter validation smoke passed\n' "$(date -Is)"
