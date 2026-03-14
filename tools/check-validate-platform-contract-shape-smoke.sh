#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_ROOT="$(cd "${ROOT}/../sw-ourbox-os" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

CONTRACT_DIR="${TMP}/platform-contract"
TOOLS_DIR="${CONTRACT_DIR}/tools"
PROFILE_DIR="${CONTRACT_DIR}/profiles/demo-apps"
MANIFEST_DIR="${CONTRACT_DIR}/manifests"

mkdir -p "${TOOLS_DIR}" "${PROFILE_DIR}" "${MANIFEST_DIR}"

cp "${UPSTREAM_ROOT}/tools/platform-contract/check-target-prereqs.sh" "${TOOLS_DIR}/check-target-prereqs.sh"
cp "${UPSTREAM_ROOT}/tools/platform-contract/contract-identity.sh" "${TOOLS_DIR}/contract-identity.sh"
cp "${UPSTREAM_ROOT}/tools/platform-contract/render-contract.py" "${TOOLS_DIR}/render-contract.py"
cp "${UPSTREAM_ROOT}/tools/platform-contract/verify-runtime.sh" "${TOOLS_DIR}/verify-runtime.sh"
cp "${UPSTREAM_ROOT}/platform-contract/profiles/demo-apps/profile.env" "${PROFILE_DIR}/profile.env"
cp "${UPSTREAM_ROOT}/platform-contract/profiles/demo-apps/images.lock.json" "${PROFILE_DIR}/images.lock.json"

chmod +x "${TOOLS_DIR}/check-target-prereqs.sh" "${TOOLS_DIR}/contract-identity.sh" "${TOOLS_DIR}/verify-runtime.sh"

cat > "${CONTRACT_DIR}/contract.env" <<'EOF_CONTRACT'
OURBOX_PLATFORM_CONTRACT_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_PLATFORM_CONTRACT_REVISION=fixture-revision
OURBOX_PLATFORM_CONTRACT_VERSION=fixture-version
EOF_CONTRACT

for manifest in \
  20-landing-deployment.yaml \
  31-dufs-deployment.yaml \
  41-flatnotes-deployment.yaml \
  50-demo-apps-ingress.yaml; do
  printf '# fixture manifest: %s\n' "${manifest}" > "${MANIFEST_DIR}/${manifest}"
done

bash "${ROOT}/tools/validate-platform-contract-shape.sh" "${CONTRACT_DIR}"

cat > "${TOOLS_DIR}/render-contract.py" <<'EOF_BAD_RENDER'
#!/usr/bin/env python3
import sys

if "--help" in sys.argv:
    print("usage: render-contract.py [--contract-root] [--output-dir] [--selected-apps-file] [--images-lock-file]")
    raise SystemExit(0)

raise SystemExit("unexpected invocation")
EOF_BAD_RENDER

set +e
bash "${ROOT}/tools/validate-platform-contract-shape.sh" "${CONTRACT_DIR}" >"${TMP}/bad-render.log" 2>&1
status=$?
set -e

[[ "${status}" -ne 0 ]] || {
  echo "validator should reject render-contract.py without application catalog support" >&2
  exit 1
}
grep -F -- "--application-catalog" "${TMP}/bad-render.log" >/dev/null || {
  cat "${TMP}/bad-render.log" >&2
  exit 1
}

cp "${UPSTREAM_ROOT}/tools/platform-contract/render-contract.py" "${TOOLS_DIR}/render-contract.py"
cat > "${TOOLS_DIR}/contract-identity.sh" <<'EOF_BAD_IDENTITY'
#!/usr/bin/env bash
set -euo pipefail
cat <<'EOF_OUTPUT'
OURBOX_PLATFORM_CONTRACT_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_PLATFORM_CONTRACT_REVISION=fixture-revision
OURBOX_PLATFORM_CONTRACT_VERSION=fixture-version
OURBOX_PLATFORM_CONTRACT_DIGEST=unknown
OURBOX_PLATFORM_PROFILE=demo-apps
OURBOX_PLATFORM_PROFILE_KIND=demo-apps
OURBOX_PLATFORM_ROUTE_MODEL=ingress
BOX_HOST=smoke.ourbox.local
TLS_MODE=lan-http
INGRESS_CLASS=traefik
STORAGE_CLASS=local-path
OURBOX_APPLICATION_CATALOG_ID=
OURBOX_APPLICATION_SELECTION_MODE=
OURBOX_SELECTED_APPLICATION_IDS=
OURBOX_APPLICATION_CATALOG_SHA256=
EOF_OUTPUT
EOF_BAD_IDENTITY
chmod +x "${TOOLS_DIR}/contract-identity.sh"

set +e
bash "${ROOT}/tools/validate-platform-contract-shape.sh" "${CONTRACT_DIR}" >"${TMP}/bad-identity.log" 2>&1
status=$?
set -e

[[ "${status}" -ne 0 ]] || {
  echo "validator should reject contract-identity.sh without application image metadata output" >&2
  exit 1
}
grep -F "OURBOX_APPLICATION_IMAGES_LOCK_SHA256" "${TMP}/bad-identity.log" >/dev/null || {
  cat "${TMP}/bad-identity.log" >&2
  exit 1
}

printf '[%s] Woodbox validate-platform-contract-shape smoke passed\n' "$(date -Is)"
