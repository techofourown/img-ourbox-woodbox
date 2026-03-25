#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd python3

FIXTURE_K3S_VERSION="v1.31.6+k3s1"
AIRGAP_BUNDLE_DIGEST="sha256:6666666666666666666666666666666666666666666666666666666666666666"
AIRGAP_LOCK_SHA="7777777777777777777777777777777777777777777777777777777777777777"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
DEPLOY_DIR="${TMP}/deploy"
BIN_DIR="${TMP}/bin"
STATE_DIR="${TMP}/state"
mkdir -p "${DEPLOY_DIR}" "${BIN_DIR}" "${STATE_DIR}"

printf 'fixture os payload\n' > "${DEPLOY_DIR}/os-payload-ourbox-woodbox-x86-fixture.tar.gz"
cat > "${DEPLOY_DIR}/os-payload-ourbox-woodbox-x86-fixture.meta.env" <<EOF
K3S_VERSION=${FIXTURE_K3S_VERSION}
OURBOX_SUBSTRATE_REF=ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@${AIRGAP_BUNDLE_DIGEST}
OURBOX_SUBSTRATE_DIGEST=${AIRGAP_BUNDLE_DIGEST}
OURBOX_SUBSTRATE_SOURCE=https://github.com/techofourown/sw-ourbox-os
OURBOX_SUBSTRATE_REVISION=fixture-substrate-revision
OURBOX_SUBSTRATE_VERSION=v0.0.0-substrate-fixture
OURBOX_SUBSTRATE_CREATED=2026-03-09T00:00:00Z
OURBOX_SUBSTRATE_ARCH=amd64
OURBOX_SUBSTRATE_PROFILE=demo-apps
OURBOX_SUBSTRATE_K3S_VERSION=${FIXTURE_K3S_VERSION}
OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256=${AIRGAP_LOCK_SHA}
EOF

export ORAS_STUB_STATE="${STATE_DIR}"
export ORAS_STUB_LOG="${STATE_DIR}/oras.log"
export ORAS_STUB_CATALOG_TAG="x86-catalog"
cat > "${BIN_DIR}/oras" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state="${ORAS_STUB_STATE:?}"
log="${ORAS_STUB_LOG:?}"
catalog_tag="${ORAS_STUB_CATALOG_TAG:?}"
mkdir -p "${state}"

cmd="${1:?}"
shift || true
printf '%s\t%s\n' "${cmd}" "$*" >> "${log}"

case "${cmd}" in
  pull)
    ref="${1:?}"
    if [[ "${ref}" == *":${catalog_tag}" ]]; then
      echo "manifest not found" >&2
      exit 1
    fi
    echo "unexpected oras pull: ${ref}" >&2
    exit 97
    ;;
  push)
    ref="${1:?}"
    if [[ "${ref}" == *":${catalog_tag}" ]]; then
      cp "catalog.tsv" "${state}/latest-catalog.tsv"
      printf 'Digest: sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\n'
    else
      printf 'Digest: sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\n'
    fi
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
export OURBOX_VERSION="test-publish-smoke"
export GITHUB_WORKFLOW="Official Candidate Build & Publish (Woodbox)"

"${ROOT}/tools/publish-os-artifact.sh" "${DEPLOY_DIR}"

python3 "${ROOT}/tools/strict-kv-metadata.py" "${DEPLOY_DIR}/os-artifact.meta.env" --json >/dev/null
if grep -F 'GITHUB_WORKFLOW=' "${DEPLOY_DIR}/os-artifact.meta.env" >/dev/null; then
  die "strict os-artifact.meta.env must not contain free-form GITHUB_WORKFLOW"
fi

python3 - "${DEPLOY_DIR}/os-artifact.meta.json" "${DEPLOY_DIR}/os-artifact.publish.json" "${STATE_DIR}/latest-catalog.tsv" "${AIRGAP_BUNDLE_DIGEST}" "${AIRGAP_LOCK_SHA}" "${FIXTURE_K3S_VERSION}" <<'PY'
import json
import sys

meta_path, publish_path, catalog_path, airgap_digest, lock_sha, k3s_version = sys.argv[1:]

with open(meta_path, "r", encoding="utf-8") as fh:
    meta = json.load(fh)
with open(publish_path, "r", encoding="utf-8") as fh:
    publish = json.load(fh)
with open(catalog_path, "r", encoding="utf-8") as fh:
    catalog = fh.read()

assert meta["OURBOX_SUBSTRATE_REF"] == f"ghcr.io/techofourown/sw-ourbox-os/ourbox-substrate@{airgap_digest}"
assert meta["OURBOX_SUBSTRATE_DIGEST"] == airgap_digest
assert meta["OURBOX_SUBSTRATE_SOURCE"] == "https://github.com/techofourown/sw-ourbox-os"
assert meta["OURBOX_SUBSTRATE_ARCH"] == "amd64"
assert meta["OURBOX_SUBSTRATE_PROFILE"] == "demo-apps"
assert meta["OURBOX_SUBSTRATE_K3S_VERSION"] == k3s_version
assert meta["OURBOX_SUBSTRATE_IMAGES_LOCK_SHA256"] == lock_sha
assert "GITHUB_WORKFLOW" not in meta
assert publish["meta_env"]["OURBOX_SUBSTRATE_DIGEST"] == airgap_digest
assert publish["meta_env"]["OURBOX_SUBSTRATE_K3S_VERSION"] == k3s_version
assert "GITHUB_WORKFLOW" not in publish["meta_env"]
PY
grep -F "techofourown.build.workflow=${GITHUB_WORKFLOW}" "${ORAS_STUB_LOG}" >/dev/null \
  || die "ORAS push did not preserve the workflow annotation"

log "OS publish smoke passed"
