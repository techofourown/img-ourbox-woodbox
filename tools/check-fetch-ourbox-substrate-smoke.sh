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

cp "${ROOT}/tools/fetch-ourbox-substrate.sh" "${TOOLS_DIR}/fetch-ourbox-substrate.sh"
cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"
cp "${ROOT}/tools/strict-kv-metadata.py" "${TOOLS_DIR}/strict-kv-metadata.py"

SUBSTRATE_DIGEST="sha256:1111111111111111111111111111111111111111111111111111111111111111"

cat > "${TOOLS_DIR}/fetch-platform-contract.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/artifacts/platform-contract/extracted/platform-contract"
EOF
chmod +x "${TOOLS_DIR}/fetch-platform-contract.sh"

cat > "${TOOLS_DIR}/sync-platform-contract-into-installer.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/artifacts/platform-contract/synced"
mkdir -p "${ROOT}/installer/ourbox/rootfs/opt/ourbox/substrate/platform/profiles/demo-apps"
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
    tar -C "${FAKE_SUBSTRATE_BUNDLE_DIR:?}" -czf "${out}/dist/ourbox-substrate.tar.gz" .
    printf 'Digest: %s\n' "${FAKE_SUBSTRATE_DIGEST:?}"
    ;;
  resolve)
    printf '%s\n' "${FAKE_SUBSTRATE_DIGEST:?}"
    ;;
  *)
    echo "unsupported oras command: ${cmd}" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${BIN_DIR}/oras"

write_bundle() {
  local variant="${1:-valid}"
  rm -rf "${BUNDLE_DIR}"
  mkdir -p "${BUNDLE_DIR}/k3s" "${BUNDLE_DIR}/platform/images"
  printf '#!/bin/sh\nexit 0\n' > "${BUNDLE_DIR}/k3s/k3s"
  chmod +x "${BUNDLE_DIR}/k3s/k3s"
  : > "${BUNDLE_DIR}/k3s/k3s-images-amd64.tar"
  : > "${BUNDLE_DIR}/platform/images/app.tar"
  if [[ "${variant}" != "missing-images-lock" ]]; then
    printf '{"images":[{"name":"landing","ref":"ghcr.io/example/landing@sha256:4444444444444444444444444444444444444444444444444444444444444444"}]}\n' > "${BUNDLE_DIR}/platform/images.lock.json"
  fi
  printf 'OURBOX_PLATFORM_PROFILE=demo-apps\n' > "${BUNDLE_DIR}/platform/profile.env"
  cat > "${BUNDLE_DIR}/manifest.env" <<EOF
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-substrate-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-11T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
K3S_VERSION=v1.35.0+k3s1
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_IMAGES_LOCK_PATH=platform/images.lock.json
OURBOX_PLATFORM_IMAGES_LOCK_SHA256=4444444444444444444444444444444444444444444444444444444444444444
EOF
}

run_fetch() {
  PATH="${BIN_DIR}:${PATH}" \
  FAKE_SUBSTRATE_BUNDLE_DIR="${BUNDLE_DIR}" \
  FAKE_SUBSTRATE_DIGEST="${SUBSTRATE_DIGEST}" \
  OURBOX_SUBSTRATE_REF="ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${SUBSTRATE_DIGEST}" \
  CI=1 \
  bash "${TOOLS_DIR}/fetch-ourbox-substrate.sh"
}

write_bundle
run_fetch

SELECTED_ENV="${FIXTURE_ROOT}/artifacts/substrate/selected-bundle.env"
[[ -f "${SELECTED_ENV}" ]] || {
  echo "selected-bundle.env was not written" >&2
  exit 1
}
grep -F "OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${SUBSTRATE_DIGEST}" "${SELECTED_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_DIGEST=${SUBSTRATE_DIGEST}" "${SELECTED_ENV}" >/dev/null
grep -F "OURBOX_SUBSTRATE_ARCH=amd64" "${SELECTED_ENV}" >/dev/null
[[ ! -f "${FIXTURE_ROOT}/artifacts/substrate/platform/catalog.json" ]] || {
  echo "fetch-ourbox-substrate.sh must not expect or stage platform/catalog.json" >&2
  exit 1
}
[[ ! -f "${FIXTURE_ROOT}/artifacts/substrate/platform/selected-apps.json" ]] || {
  echo "fetch-ourbox-substrate.sh must not expect or stage platform/selected-apps.json" >&2
  exit 1
}

write_bundle missing-images-lock
set +e
run_fetch >"${TMP}/missing-images-lock.log" 2>&1
status=$?
set -e
[[ "${status}" -ne 0 ]] || {
  echo "fetch-ourbox-substrate.sh should reject bundles missing platform/images.lock.json" >&2
  exit 1
}
grep -F "substrate bundle missing platform/images.lock.json" "${TMP}/missing-images-lock.log" >/dev/null || {
  cat "${TMP}/missing-images-lock.log" >&2
  exit 1
}

printf '[%s] Woodbox fetch-ourbox-substrate smoke passed\n' "$(date -Is)"
