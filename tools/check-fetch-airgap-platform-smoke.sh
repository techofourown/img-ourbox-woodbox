#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
BIN_DIR="${TMP}/bin"
BUNDLE_DIR="${TMP}/bundle"
mkdir -p "${TOOLS_DIR}" "${BIN_DIR}" "${BUNDLE_DIR}"

cp "${ROOT}/tools/fetch-airgap-platform.sh" "${TOOLS_DIR}/fetch-airgap-platform.sh"
cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/tools/strict-kv-metadata.py" "${TOOLS_DIR}/strict-kv-metadata.py"

AIRGAP_DIGEST="sha256:1111111111111111111111111111111111111111111111111111111111111111"
PLATFORM_CONTRACT_DIGEST="sha256:2222222222222222222222222222222222222222222222222222222222222222"
MISMATCH_CONTRACT_DIGEST="sha256:3333333333333333333333333333333333333333333333333333333333333333"

cat > "${TOOLS_DIR}/fetch-platform-contract.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/artifacts/platform-contract/extracted/platform-contract"
printf '%s\n' "${FAKE_PLATFORM_CONTRACT_DIGEST:?}" > "${ROOT}/artifacts/platform-contract/extracted/platform-contract/contract.digest"
EOF
chmod +x "${TOOLS_DIR}/fetch-platform-contract.sh"

cat > "${TOOLS_DIR}/sync-platform-contract-into-installer.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/artifacts/platform-contract/synced"
mkdir -p "${ROOT}/installer/ourbox/rootfs/opt/ourbox/airgap/platform/profiles/demo-apps"
printf 'synced\n' > "${ROOT}/artifacts/platform-contract/synced/status.txt"
EOF
chmod +x "${TOOLS_DIR}/sync-platform-contract-into-installer.sh"

cat > "${BIN_DIR}/oras" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:?}"
shift || true

case "${cmd}" in
  pull)
    ref="${1:?}"
    shift || true
    out=""
    while [[ $# -gt 0 ]]; do
      case "${1}" in
        -o)
          out="${2:?}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [[ -n "${out}" ]] || {
      echo "oras stub pull missing -o" >&2
      exit 2
    }
    mkdir -p "${out}/dist"
    tar -C "${FAKE_AIRGAP_BUNDLE_DIR:?}" -czf "${out}/dist/airgap-platform.tar.gz" .
    printf 'Digest: %s\n' "${FAKE_AIRGAP_DIGEST:?}"
    ;;
  resolve)
    printf '%s\n' "${FAKE_AIRGAP_DIGEST:?}"
    ;;
  *)
    echo "unsupported oras command: ${cmd}" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${BIN_DIR}/oras"

write_bundle() {
  local contract_digest="$1"
  local variant="${2:-valid}"
  rm -rf "${BUNDLE_DIR}"
  mkdir -p "${BUNDLE_DIR}/k3s" "${BUNDLE_DIR}/platform/images"
  printf '#!/bin/sh\nexit 0\n' > "${BUNDLE_DIR}/k3s/k3s"
  chmod +x "${BUNDLE_DIR}/k3s/k3s"
  : > "${BUNDLE_DIR}/k3s/k3s-airgap-images-amd64.tar"
  : > "${BUNDLE_DIR}/platform/images/app.tar"
  printf '{"images":[{"name":"landing","ref":"ghcr.io/example/landing@sha256:4444444444444444444444444444444444444444444444444444444444444444"}]}\n' > "${BUNDLE_DIR}/platform/images.lock.json"
  printf 'PROFILE=demo-apps\n' > "${BUNDLE_DIR}/platform/profile.env"
  cat > "${BUNDLE_DIR}/platform/catalog.json" <<'EOF'
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
  if [[ "${variant}" != "missing-selected-apps" ]]; then
    cat > "${BUNDLE_DIR}/platform/selected-apps.json" <<EOF
{
  "schema": 1,
  "kind": "ourbox-selected-applications",
  "catalog_id": "demo-apps",
  "selection_mode": "${variant:-catalog-defaults}"
}
EOF
    python3 - <<'PY' "${BUNDLE_DIR}/platform/selected-apps.json" "${variant}"
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
variant = sys.argv[2]
payload = json.loads(path.read_text(encoding="utf-8"))
payload["selection_mode"] = "catalog-defaults" if variant == "valid" else "defaults"
payload["selected_app_ids"] = ["landing"]
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
  fi
  cat > "${BUNDLE_DIR}/manifest.env" <<EOF
OURBOX_AIRGAP_PLATFORM_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_AIRGAP_PLATFORM_REVISION=fixture-airgap-revision
OURBOX_AIRGAP_PLATFORM_VERSION=v0.0.0-fixture
OURBOX_AIRGAP_PLATFORM_CREATED=2026-03-11T00:00:00Z
OURBOX_PLATFORM_CONTRACT_REF=ghcr.io/techofourown/sw-ourbox-os/platform-contract@${contract_digest}
OURBOX_PLATFORM_CONTRACT_DIGEST=${contract_digest}
AIRGAP_PLATFORM_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=4444444444444444444444444444444444444444444444444444444444444444
EOF
}

run_fetch() {
  PATH="${BIN_DIR}:${PATH}" \
  FAKE_AIRGAP_BUNDLE_DIR="${BUNDLE_DIR}" \
  FAKE_AIRGAP_DIGEST="${AIRGAP_DIGEST}" \
  FAKE_PLATFORM_CONTRACT_DIGEST="${PLATFORM_CONTRACT_DIGEST}" \
  OURBOX_AIRGAP_PLATFORM_REF="ghcr.io/techofourown/sw-ourbox-os/airgap-platform@${AIRGAP_DIGEST}" \
  CI=1 \
  bash "${TOOLS_DIR}/fetch-airgap-platform.sh"
}

write_bundle "${PLATFORM_CONTRACT_DIGEST}"
run_fetch

SELECTED_ENV="${FIXTURE_ROOT}/artifacts/airgap/selected-bundle.env"
[[ -f "${SELECTED_ENV}" ]] || {
  echo "selected-bundle.env was not written" >&2
  exit 1
}
grep -F "OURBOX_AIRGAP_PLATFORM_REF=ghcr.io/techofourown/sw-ourbox-os/airgap-platform@${AIRGAP_DIGEST}" "${SELECTED_ENV}" >/dev/null
grep -F "OURBOX_AIRGAP_PLATFORM_DIGEST=${AIRGAP_DIGEST}" "${SELECTED_ENV}" >/dev/null
grep -F "OURBOX_AIRGAP_PLATFORM_ARCH=amd64" "${SELECTED_ENV}" >/dev/null
grep -F "OURBOX_PLATFORM_CONTRACT_DIGEST=${PLATFORM_CONTRACT_DIGEST}" "${SELECTED_ENV}" >/dev/null

write_bundle "${MISMATCH_CONTRACT_DIGEST}" valid
set +e
run_fetch >"${TMP}/mismatch.log" 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || {
  echo "fetch-airgap-platform.sh should reject a contract digest mismatch" >&2
  exit 1
}
grep -F "airgap-platform contract digest mismatch" "${TMP}/mismatch.log" >/dev/null \
  || {
    cat "${TMP}/mismatch.log" >&2
    exit 1
  }

write_bundle "${PLATFORM_CONTRACT_DIGEST}" missing-selected-apps
set +e
run_fetch >"${TMP}/missing-selected-apps.log" 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || {
  echo "fetch-airgap-platform.sh should reject bundles missing selected-apps.json" >&2
  exit 1
}
grep -F "airgap bundle missing platform/selected-apps.json" "${TMP}/missing-selected-apps.log" >/dev/null || {
  cat "${TMP}/missing-selected-apps.log" >&2
  exit 1
}

write_bundle "${PLATFORM_CONTRACT_DIGEST}" invalid-selection-mode
set +e
run_fetch >"${TMP}/invalid-selection-mode.log" 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || {
  echo "fetch-airgap-platform.sh should reject bundles with invalid selected-apps selection_mode" >&2
  exit 1
}
grep -F "selection_mode must be one of catalog-defaults, all-apps, custom" "${TMP}/invalid-selection-mode.log" >/dev/null || {
  cat "${TMP}/invalid-selection-mode.log" >&2
  exit 1
}

printf '[%s] Woodbox fetch-airgap-platform smoke passed\n' "$(date -Is)"
