#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

FIXTURE_ROOT="${TMP}/repo"
TOOLS_DIR="${FIXTURE_ROOT}/tools"
BIN_DIR="${TMP}/bin"
mkdir -p "${TOOLS_DIR}" "${BIN_DIR}"

cp "${ROOT}/tools/fetch-platform-contract.sh" "${TOOLS_DIR}/fetch-platform-contract.sh"
cp "${ROOT}/tools/fetch-airgap-platform.sh" "${TOOLS_DIR}/fetch-airgap-platform.sh"
cp "${ROOT}/tools/lib.sh" "${TOOLS_DIR}/lib.sh"

cat > "${BIN_DIR}/oras" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${BIN_DIR}/oras"

expect_fail() {
  local log_file="$1"
  shift

  set +e
  "$@" >"${log_file}" 2>&1
  local status=$?
  set -e

  [[ "${status}" -ne 0 ]] || {
    echo "expected failure but command succeeded: $*" >&2
    cat "${log_file}" >&2 || true
    exit 1
  }
}

expect_fail "${TMP}/platform-missing-inputs.log" \
  env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" bash "${TOOLS_DIR}/fetch-platform-contract.sh"
grep -F "Missing ${FIXTURE_ROOT}/release/official-inputs.env and OURBOX_PLATFORM_CONTRACT_REF is not set." \
  "${TMP}/platform-missing-inputs.log" >/dev/null || {
    cat "${TMP}/platform-missing-inputs.log" >&2
    exit 1
  }
grep -F "Legacy contracts/platform-contract.ref fallback has been removed." \
  "${TMP}/platform-missing-inputs.log" >/dev/null || {
    cat "${TMP}/platform-missing-inputs.log" >&2
    exit 1
  }

expect_fail "${TMP}/airgap-missing-inputs.log" \
  env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" bash "${TOOLS_DIR}/fetch-airgap-platform.sh"
grep -F "Missing ${FIXTURE_ROOT}/release/official-inputs.env and OURBOX_AIRGAP_PLATFORM_REF is not set." \
  "${TMP}/airgap-missing-inputs.log" >/dev/null || {
    cat "${TMP}/airgap-missing-inputs.log" >&2
    exit 1
  }
grep -F "Legacy contracts/airgap-platform.ref fallback has been removed." \
  "${TMP}/airgap-missing-inputs.log" >/dev/null || {
    cat "${TMP}/airgap-missing-inputs.log" >&2
    exit 1
  }

mkdir -p "${FIXTURE_ROOT}/release"
cat > "${FIXTURE_ROOT}/release/official-inputs.env" <<'EOF'
AIRGAP_PLATFORM_REF=ghcr.io/example/airgap-platform@sha256:1111111111111111111111111111111111111111111111111111111111111111
EOF

expect_fail "${TMP}/platform-missing-key.log" \
  env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" bash "${TOOLS_DIR}/fetch-platform-contract.sh"
grep -F "PLATFORM_CONTRACT_REF not set in ${FIXTURE_ROOT}/release/official-inputs.env" \
  "${TMP}/platform-missing-key.log" >/dev/null || {
    cat "${TMP}/platform-missing-key.log" >&2
    exit 1
  }

cat > "${FIXTURE_ROOT}/release/official-inputs.env" <<'EOF'
PLATFORM_CONTRACT_REF=ghcr.io/example/platform-contract@sha256:2222222222222222222222222222222222222222222222222222222222222222
EOF

expect_fail "${TMP}/airgap-missing-key.log" \
  env -i PATH="${BIN_DIR}:${PATH}" HOME="${HOME}" bash "${TOOLS_DIR}/fetch-airgap-platform.sh"
grep -F "AIRGAP_PLATFORM_REF not set in ${FIXTURE_ROOT}/release/official-inputs.env" \
  "${TMP}/airgap-missing-key.log" >/dev/null || {
    cat "${TMP}/airgap-missing-key.log" >&2
    exit 1
  }

printf '[%s] Woodbox upstream input fail-closed smoke passed\n' "$(date -Is)"
