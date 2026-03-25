#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

PAYLOAD_ROOT="${TMP}/payload-root"
PAYLOAD_SUBSTRATE="${PAYLOAD_ROOT}/substrate"
PAYLOAD_ROOTFS="${PAYLOAD_ROOT}/rootfs"
OUT_DIR="${TMP}/out"
APPLICATION_CATALOG="${TMP}/catalog.json"
SELECTED_APPS="${TMP}/selected-apps.json"
mkdir -p "${PAYLOAD_SUBSTRATE}/k3s" "${PAYLOAD_SUBSTRATE}/platform/images" "${PAYLOAD_ROOTFS}"

printf '#!/bin/sh\nexit 0\n' > "${PAYLOAD_SUBSTRATE}/k3s/k3s"
chmod +x "${PAYLOAD_SUBSTRATE}/k3s/k3s"
printf 'fixture\n' > "${PAYLOAD_SUBSTRATE}/k3s/k3s-images-amd64.tar"
printf 'fixture image tar\n' > "${PAYLOAD_SUBSTRATE}/platform/images/landing.tar"
printf '{"images":[]}\n' > "${PAYLOAD_SUBSTRATE}/platform/images.lock.json"
printf 'PROFILE=demo-apps\n' > "${PAYLOAD_SUBSTRATE}/platform/profile.env"
cat > "${PAYLOAD_SUBSTRATE}/manifest.env" <<'EOF'
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-13T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EOF

PAYLOAD_TAR="${TMP}/os-payload.tar.gz"
tar -C "${PAYLOAD_ROOT}" -czf "${PAYLOAD_TAR}" .

META_ENV="${TMP}/payload.meta.env"
cat > "${META_ENV}" <<EOF
OS_ARTIFACT_TYPE=application/vnd.techofourown.ourbox.woodbox.os-payload.v1
OURBOX_PRODUCT=ourbox
OURBOX_DEVICE=woodbox
OURBOX_TARGET=x86
OURBOX_SKU=TOO-OBX-WBX-BASE-JU3XK8
OURBOX_VARIANT=prod
OURBOX_VERSION=fixture
OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
OURBOX_SUBSTRATE_DIGEST=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-13T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=v1.35.0+k3s1
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EOF

cat > "${APPLICATION_CATALOG}" <<'EOF'
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
      "display_name": "Landing"
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
    "landing"
  ]
}
EOF

set +e
bash "${ROOT}/tools/prepare-mission-media-smoke.sh" \
  --os-payload "${PAYLOAD_TAR}" \
  --os-meta-env "${META_ENV}" \
  --output-dir "${TMP}/missing-app-selection" \
  --mission-only >"${TMP}/missing-app-selection.log" 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || {
  echo "prepare-mission-media-smoke.sh should require explicit application metadata" >&2
  exit 1
}
grep -F -- "--application-catalog is required" "${TMP}/missing-app-selection.log" >/dev/null || {
  cat "${TMP}/missing-app-selection.log" >&2
  exit 1
}

bash "${ROOT}/tools/prepare-mission-media-smoke.sh" \
  --os-payload "${PAYLOAD_TAR}" \
  --os-meta-env "${META_ENV}" \
  --application-catalog "${APPLICATION_CATALOG}" \
  --selected-apps "${SELECTED_APPS}" \
  --output-dir "${OUT_DIR}" \
  --mission-only

MISSION_DIR="${OUT_DIR}/mission"
[[ -f "${MISSION_DIR}/mission-manifest.json" ]] || {
  echo "mission-manifest.json missing" >&2
  exit 1
}
[[ -f "${MISSION_DIR}/artifacts/substrate/catalog.json" ]] || {
  echo "application catalog missing from mission output" >&2
  exit 1
}
[[ -f "${MISSION_DIR}/artifacts/substrate/selected-apps.json" ]] || {
  echo "selected-apps.json missing from mission output" >&2
  exit 1
}
[[ -f "${MISSION_DIR}/artifacts/substrate/ourbox-substrate.tar.gz.sha256" ]] || {
  echo "substrate bundle checksum sidecar missing from mission output" >&2
  exit 1
}

python3 - <<'PY' "${MISSION_DIR}/mission-manifest.json"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

selected_apps = (manifest.get("resolved") or {}).get("applications", {})
if selected_apps.get("catalog_id") != "demo-apps":
    raise SystemExit("unexpected selected_applications.catalog_id")
if selected_apps.get("selection_mode") != "catalog-defaults":
    raise SystemExit("unexpected selected_applications.selection_mode")
if selected_apps.get("selected_app_ids") != ["landing"]:
    raise SystemExit("unexpected selected_applications.selected_app_ids")
PY

printf '[%s] prepare-mission-media-smoke helper smoke passed\n' "$(date -Is)"
