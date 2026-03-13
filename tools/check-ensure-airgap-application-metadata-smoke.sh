#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

BUNDLE_DIR="${TMP}/bundle"
CONTRACT_ROOT="${TMP}/contract"
PROFILE_DIR="${CONTRACT_ROOT}/profiles/demo-apps"

mkdir -p "${BUNDLE_DIR}/k3s" "${BUNDLE_DIR}/platform/images" "${PROFILE_DIR}"

printf '#!/bin/sh\nexit 0\n' > "${BUNDLE_DIR}/k3s/k3s"
chmod +x "${BUNDLE_DIR}/k3s/k3s"
printf 'fixture\n' > "${BUNDLE_DIR}/k3s/k3s-airgap-images-amd64.tar"
printf '{"images":[]}\n' > "${BUNDLE_DIR}/platform/images.lock.json"
printf 'PROFILE=demo-apps\n' > "${BUNDLE_DIR}/platform/profile.env"
printf 'fixture image tar\n' > "${BUNDLE_DIR}/platform/images/demo.tar"
cat > "${BUNDLE_DIR}/manifest.env" <<'EOF'
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=fixture-revision
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.0-fixture
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-13T00:00:00Z
OURBOX_PLATFORM_CONTRACT_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
AIRGAP_PLATFORM_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EOF

cat > "${PROFILE_DIR}/catalog.json" <<'EOF'
{
  "schema": 1,
  "kind": "ourbox-application-catalog",
  "catalog_id": "demo-apps",
  "catalog_name": "Demo Application Catalog",
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

bash "${ROOT}/tools/ensure-airgap-application-metadata.sh" \
  --bundle-dir "${BUNDLE_DIR}" \
  --contract-root "${CONTRACT_ROOT}"

[[ -f "${BUNDLE_DIR}/platform/catalog.json" ]] || {
  echo "expected catalog.json to be synthesized" >&2
  exit 1
}
[[ -f "${BUNDLE_DIR}/platform/selected-apps.json" ]] || {
  echo "expected selected-apps.json to be synthesized" >&2
  exit 1
}

python3 - <<'PY' "${BUNDLE_DIR}/platform/catalog.json" "${BUNDLE_DIR}/platform/selected-apps.json"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    catalog = json.load(handle)
with open(sys.argv[2], "r", encoding="utf-8") as handle:
    selected = json.load(handle)

if catalog["catalog_id"] != "demo-apps":
    raise SystemExit("unexpected synthesized catalog id")
if selected["catalog_id"] != "demo-apps":
    raise SystemExit("unexpected synthesized selected-apps catalog id")
if selected["selection_mode"] != "defaults":
    raise SystemExit("unexpected synthesized selection_mode")
if selected["selected_app_ids"] != ["landing", "dufs"]:
    raise SystemExit("unexpected synthesized selected_app_ids")
PY

printf '[%s] airgap application metadata synthesis smoke passed\n' "$(date -Is)"
