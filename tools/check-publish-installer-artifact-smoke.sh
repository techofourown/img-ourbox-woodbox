#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd python3

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
DEPLOY_DIR="${TMP}/deploy"
BIN_DIR="${TMP}/bin"
STATE_DIR="${TMP}/state"
mkdir -p "${DEPLOY_DIR}" "${BIN_DIR}" "${STATE_DIR}"

printf 'fixture installer iso\n' > "${DEPLOY_DIR}/installer-ourbox-woodbox-x86-fixture.iso"

export ORAS_STUB_LOG="${STATE_DIR}/oras.log"
cat > "${BIN_DIR}/oras" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log="${ORAS_STUB_LOG:?}"
cmd="${1:?}"
shift || true
printf '%s\t%s\n' "${cmd}" "$*" >> "${log}"

case "${cmd}" in
  push)
    printf 'Digest: sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\n'
    ;;
  *)
    echo "unsupported oras command: ${cmd}" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${BIN_DIR}/oras"

export PATH="${BIN_DIR}:${PATH}"
export OURBOX_GIT_SHA="fedcba987654"
export OURBOX_VERSION="test-installer-publish-smoke"
export GITHUB_WORKFLOW="Official Candidate Build & Publish (Woodbox)"

"${ROOT}/tools/publish-installer-artifact.sh" "${DEPLOY_DIR}"

python3 "${ROOT}/tools/strict-kv-metadata.py" "${DEPLOY_DIR}/installer-artifact.meta.env" --json >/dev/null
if grep -F 'GITHUB_WORKFLOW=' "${DEPLOY_DIR}/installer-artifact.meta.env" >/dev/null; then
  die "strict installer-artifact.meta.env must not contain free-form GITHUB_WORKFLOW"
fi

python3 - "${DEPLOY_DIR}/installer-artifact.meta.json" "${DEPLOY_DIR}/installer-artifact.publish.json" <<'PY'
import json
import sys

meta_path, publish_path = sys.argv[1:]

with open(meta_path, "r", encoding="utf-8") as fh:
    meta = json.load(fh)
with open(publish_path, "r", encoding="utf-8") as fh:
    publish = json.load(fh)

assert "GITHUB_WORKFLOW" not in meta
assert "GITHUB_WORKFLOW" not in publish["meta_env"]
PY

grep -F "techofourown.build.workflow=${GITHUB_WORKFLOW}" "${ORAS_STUB_LOG}" >/dev/null \
  || die "ORAS push did not preserve the workflow annotation"

log "Installer publish smoke passed"
