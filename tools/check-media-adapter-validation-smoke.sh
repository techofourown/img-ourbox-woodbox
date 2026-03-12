#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

MISSION_DIR="${TMP}/mission"
OS_DIR="${MISSION_DIR}/artifacts/os"
AIRGAP_DIR="${MISSION_DIR}/artifacts/airgap"
mkdir -p "${OS_DIR}" "${AIRGAP_DIR}"

OS_PAYLOAD="${OS_DIR}/os-payload.tar.gz"
OS_META_ENV="${OS_DIR}/os.meta.env"
AIRGAP_PAYLOAD="${AIRGAP_DIR}/airgap-platform.tar.gz"
AIRGAP_MANIFEST="${AIRGAP_DIR}/manifest.env"
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

printf 'airgap bytes\n' > "${AIRGAP_PAYLOAD}"
cat > "${AIRGAP_MANIFEST}" <<'EOF'
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/techofourown/sw-ourbox-os
EOF

write_manifest() {
  local include_selected_airgap="$1"
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
  }
EOF
  fi
  cat >> "${MISSION_MANIFEST}" <<'EOF'
}
EOF
}

write_manifest 1
bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${MISSION_DIR}" \
  --os-payload "${OS_PAYLOAD}" \
  --os-meta-env "${OS_META_ENV}"

write_manifest 0
if bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${MISSION_DIR}" \
  --os-payload "${OS_PAYLOAD}" \
  --os-meta-env "${OS_META_ENV}" >/dev/null 2>&1; then
  echo "expected validate-media.sh to reject mission manifests missing selected_airgap" >&2
  exit 1
fi

write_manifest 1
python3 - <<'PY' "${MISSION_MANIFEST}"
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
del manifest["selected_airgap"]["artifact_digest"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
if bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${MISSION_DIR}" \
  --os-payload "${OS_PAYLOAD}" \
  --os-meta-env "${OS_META_ENV}" >/dev/null 2>&1; then
  echo "expected validate-media.sh to reject mission manifests missing selected_airgap.artifact_digest" >&2
  exit 1
fi

write_manifest 1
rm -f "${OS_META_ENV}"
if bash "${ROOT}/tools/media-adapter/validate-media.sh" \
  --mission-dir "${MISSION_DIR}" \
  --os-payload "${OS_PAYLOAD}" \
  --os-meta-env "${OS_META_ENV}" >/dev/null 2>&1; then
  echo "expected validate-media.sh to reject mission payloads missing os.meta.env" >&2
  exit 1
fi

printf '[%s] Woodbox media-adapter validation smoke passed\n' "$(date -Is)"
