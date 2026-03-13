#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

MISSION_DIR="${TMP}/mission"
OS_DIR="${MISSION_DIR}/artifacts/os"
AIRGAP_DIR="${MISSION_DIR}/artifacts/airgap"
AIRGAP_SOURCE_DIR="${TMP}/airgap-source"
mkdir -p "${OS_DIR}" "${AIRGAP_DIR}"

OS_PAYLOAD="${OS_DIR}/os-payload.tar.gz"
OS_META_ENV="${OS_DIR}/os.meta.env"
AIRGAP_PAYLOAD="${AIRGAP_DIR}/airgap-platform.tar.gz"
AIRGAP_MANIFEST="${AIRGAP_DIR}/manifest.env"
APP_CATALOG="${AIRGAP_DIR}/catalog.json"
SELECTED_APPS="${AIRGAP_DIR}/selected-apps.json"
MISSION_MANIFEST="${MISSION_DIR}/mission-manifest.json"

printf 'payload bytes\n' > "${OS_PAYLOAD}"
cat > "${OS_META_ENV}" <<'EOF'
OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1
OURBOX_PLATFORM_CONTRACT_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OURBOX_PRODUCT=ourbox
OURBOX_DEVICE=woodbox
OURBOX_TARGET=x86
OURBOX_SKU=TOO-OBX-WBX-BASE-JU3XK8
OURBOX_VARIANT=prod
OURBOX_VERSION=v0.0.1
OURBOX_RECIPE_GIT_HASH=abc123def456
BUILD_TS=2026-03-12T00:00:00Z
OURBOX_PLATFORM_CONTRACT_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_PLATFORM_CONTRACT_REVISION=abc123def456
OURBOX_PLATFORM_CONTRACT_VERSION=v0.0.1
OURBOX_PLATFORM_CONTRACT_CREATED=2026-03-12T00:00:00Z
OURBOX_AIRGAP_PLATFORM_REF=ghcr.io/example/airgap-platform@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_AIRGAP_PLATFORM_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=abc123def456
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.1
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-12T00:00:00Z
OURBOX_AIRGAP_PLATFORM_ARCH=amd64
OURBOX_AIRGAP_PLATFORM_PROFILE=demo-apps
OURBOX_AIRGAP_PLATFORM_K3S_VERSION=v1.35.0+k3s1
OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
OURBOX_BASE_ISO_URL=https://example.invalid/ubuntu.iso
OURBOX_BASE_ISO_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
K3S_VERSION=v1.35.0+k3s1
GITHUB_RUN_ID=
GITHUB_RUN_ATTEMPT=
EOF

build_airgap_bundle() {
  local variant="${1:-valid}"

  rm -rf "${AIRGAP_SOURCE_DIR}"
  mkdir -p "${AIRGAP_SOURCE_DIR}/k3s" "${AIRGAP_SOURCE_DIR}/platform/images"

  cat > "${AIRGAP_SOURCE_DIR}/manifest.env" <<'EOF'
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=abc123def456
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.1
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-12T00:00:00Z
OURBOX_PLATFORM_CONTRACT_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
AIRGAP_PLATFORM_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
EOF
  printf '#!/bin/sh\nexit 0\n' > "${AIRGAP_SOURCE_DIR}/k3s/k3s"
  chmod +x "${AIRGAP_SOURCE_DIR}/k3s/k3s"
  printf 'fixture airgap images\n' > "${AIRGAP_SOURCE_DIR}/k3s/k3s-airgap-images-amd64.tar"
  printf 'PROFILE=demo-apps\n' > "${AIRGAP_SOURCE_DIR}/platform/profile.env"
  printf 'fixture image tar\n' > "${AIRGAP_SOURCE_DIR}/platform/images/platform-demo.tar"
  if [[ "${variant}" != "missing-images-lock" ]]; then
    printf '{"images":[]}\n' > "${AIRGAP_SOURCE_DIR}/platform/images.lock.json"
  fi

  case "${variant}" in
    valid|missing-images-lock)
      tar -C "${AIRGAP_SOURCE_DIR}" -czf "${AIRGAP_PAYLOAD}" k3s platform manifest.env
      ;;
    invalid-tar)
      printf 'not a tarball\n' > "${AIRGAP_PAYLOAD}"
      ;;
    *)
      echo "unknown airgap bundle variant: ${variant}" >&2
      exit 1
      ;;
  esac

  printf '%s  %s\n' "$(sha256sum "${AIRGAP_PAYLOAD}" | awk '{print $1}')" "airgap-platform.tar.gz" > "${AIRGAP_PAYLOAD}.sha256"
  cp -f "${AIRGAP_SOURCE_DIR}/manifest.env" "${AIRGAP_MANIFEST}"
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
  "selection_mode": "defaults",
  "selected_app_ids": [
    "landing",
    "dufs"
  ]
}
EOF
}

write_manifest() {
  local include_selected_airgap="${1}"
  cat > "${MISSION_MANIFEST}" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-mission",
  "target": {
    "id": "woodbox",
    "media_kind": "installer-usb"
  },
  "operator_mode": {
    "mode": "install"
  },
  "platform_contract": {
    "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "selected_os": {
    "selection_source": "catalog",
    "artifact_ref": "ghcr.io/example/ourbox-woodbox-os@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "artifact_digest": "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "artifact_type": "application/vnd.techofourown.ourbox.woodbox.os-payload.v1",
    "platform_contract_digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "payload": {
      "relpath": "artifacts/os/os-payload.tar.gz"
    },
    "metadata_relpath": "artifacts/os/os.meta.env"
  }
EOF
  if [[ "${include_selected_airgap}" == "1" ]]; then
    cat >> "${MISSION_MANIFEST}" <<'EOF'
,
  "selected_airgap": {
    "selection_mode": "host-selected",
    "selection_source": "catalog",
    "artifact_ref": "ghcr.io/example/airgap-platform@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "artifact_digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "arch": "amd64",
    "platform_contract_digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
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
  }
EOF
  fi
  cat >> "${MISSION_MANIFEST}" <<'EOF'
}
EOF
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

build_airgap_bundle valid
write_manifest 1
bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${MISSION_DIR}" \
  --os-payload "${OS_PAYLOAD}" \
  --os-meta-env "${OS_META_ENV}"

write_manifest 0
expect_validation_failure "mission manifests missing selected_airgap"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'del manifest["selected_airgap"]["artifact_digest"]'
expect_validation_failure "mission manifests missing selected_airgap.artifact_digest"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'del manifest["selected_applications"]["selection_relpath"]'
expect_validation_failure "mission manifests missing selected_applications.selection_relpath"

build_airgap_bundle valid
write_manifest 1
cat > "${SELECTED_APPS}" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-selected-applications",
  "catalog_id": "demo-apps",
  "selection_mode": "defaults",
  "selected_app_ids": [
    "landing"
  ]
}
EOF
expect_validation_failure "mission selected applications files that do not match manifest selected_applications.selected_app_ids"

build_airgap_bundle valid
write_manifest 1
rm -f "${OS_META_ENV}"
expect_validation_failure "mission payloads missing os.meta.env"
cat > "${OS_META_ENV}" <<'EOF'
OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1
OURBOX_PLATFORM_CONTRACT_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OURBOX_PRODUCT=ourbox
OURBOX_DEVICE=woodbox
OURBOX_TARGET=x86
OURBOX_SKU=TOO-OBX-WBX-BASE-JU3XK8
OURBOX_VARIANT=prod
OURBOX_VERSION=v0.0.1
OURBOX_RECIPE_GIT_HASH=abc123def456
BUILD_TS=2026-03-12T00:00:00Z
OURBOX_PLATFORM_CONTRACT_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_PLATFORM_CONTRACT_REVISION=abc123def456
OURBOX_PLATFORM_CONTRACT_VERSION=v0.0.1
OURBOX_AIRGAP_PLATFORM_REF=ghcr.io/example/airgap-platform@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_AIRGAP_PLATFORM_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=abc123def456
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.1
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-12T00:00:00Z
OURBOX_AIRGAP_PLATFORM_ARCH=amd64
OURBOX_AIRGAP_PLATFORM_PROFILE=demo-apps
OURBOX_AIRGAP_PLATFORM_K3S_VERSION=v1.35.0+k3s1
OURBOX_AIRGAP_PLATFORM_IMAGES_LOCK_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
OURBOX_BASE_ISO_URL=https://example.invalid/ubuntu.iso
OURBOX_BASE_ISO_SHA256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
K3S_VERSION=v1.35.0+k3s1
GITHUB_RUN_ID=
GITHUB_RUN_ATTEMPT=
EOF

build_airgap_bundle valid
write_manifest 1
rm -f "${AIRGAP_PAYLOAD}.sha256"
expect_validation_failure "mission airgap payloads missing airgap-platform.tar.gz.sha256"

build_airgap_bundle valid
write_manifest 1
printf 'OURBOX_AIRGAP_PLATFORM_VERSION=v9.9.9\n' >> "${AIRGAP_MANIFEST}"
expect_validation_failure "mission airgap payloads whose staged manifest sidecar differs from the tarball manifest"

build_airgap_bundle valid
write_manifest 1
printf '%s  %s\n' 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff' 'airgap-platform.tar.gz' > "${AIRGAP_PAYLOAD}.sha256"
expect_validation_failure "mission airgap payloads with mismatched airgap-platform.tar.gz.sha256"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'manifest["selected_os"]["artifact_digest"] = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
expect_validation_failure "mission manifests with mismatched selected_os artifact digest"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'manifest["selected_airgap"]["artifact_digest"] = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
expect_validation_failure "mission manifests with mismatched selected_airgap artifact digest"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'manifest["selected_airgap"]["payload_relpath"] = "../outside.tar.gz"'
expect_validation_failure "mission manifests with selected_airgap.payload_relpath escaping the mission directory"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'manifest["selected_airgap"]["manifest_relpath"] = "../outside.env"'
expect_validation_failure "mission manifests with selected_airgap.manifest_relpath escaping the mission directory"

build_airgap_bundle valid
write_manifest 1
mutate_manifest 'manifest["selected_os"]["metadata_relpath"] = "../outside.env"'
expect_validation_failure "mission manifests with selected_os.metadata_relpath escaping the mission directory"

build_airgap_bundle invalid-tar
write_manifest 1
expect_validation_failure "mission airgap payloads that are not valid gzip tar archives"

build_airgap_bundle missing-images-lock
write_manifest 1
expect_validation_failure "mission airgap payloads missing required bundle files"

printf '[%s] Woodbox media-adapter validation smoke passed\n' "$(date -Is)"
