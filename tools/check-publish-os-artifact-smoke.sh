#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd python3

RAW_CONTRACT_DIGEST="sha256:4444444444444444444444444444444444444444444444444444444444444444"
OVERRIDE_CONTRACT_DIGEST="sha256:5555555555555555555555555555555555555555555555555555555555555555"
FIXTURE_K3S_VERSION="v1.31.6+k3s1"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
DEPLOY_DIR="${TMP}/deploy"
BIN_DIR="${TMP}/bin"
STATE_DIR="${TMP}/state"
mkdir -p "${DEPLOY_DIR}" "${BIN_DIR}" "${STATE_DIR}"

printf 'fixture os payload\n' > "${DEPLOY_DIR}/os-payload-ourbox-woodbox-x86-fixture.tar.gz"
cat > "${DEPLOY_DIR}/os-payload-ourbox-woodbox-x86-fixture.meta.env" <<EOF
OURBOX_PLATFORM_CONTRACT_DIGEST=${RAW_CONTRACT_DIGEST}
OURBOX_PLATFORM_CONTRACT_SOURCE=ghcr.io/techofourown/sw-ourbox-os/platform-contract@${RAW_CONTRACT_DIGEST}
OURBOX_PLATFORM_CONTRACT_REVISION=fixture-revision
OURBOX_PLATFORM_CONTRACT_VERSION=v0.0.0-fixture
K3S_VERSION=${FIXTURE_K3S_VERSION}
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
export OURBOX_PLATFORM_CONTRACT_DIGEST="${OVERRIDE_CONTRACT_DIGEST}"

"${ROOT}/tools/publish-os-artifact.sh" "${DEPLOY_DIR}"

python3 - "${DEPLOY_DIR}/os-artifact.meta.json" "${DEPLOY_DIR}/os-artifact.publish.json" "${STATE_DIR}/latest-catalog.tsv" "${OVERRIDE_CONTRACT_DIGEST}" "${RAW_CONTRACT_DIGEST}" <<'PY'
import json
import sys

meta_path, publish_path, catalog_path, override_digest, raw_digest = sys.argv[1:]

with open(meta_path, "r", encoding="utf-8") as fh:
    meta = json.load(fh)
with open(publish_path, "r", encoding="utf-8") as fh:
    publish = json.load(fh)
with open(catalog_path, "r", encoding="utf-8") as fh:
    catalog = fh.read()

assert meta["OURBOX_PLATFORM_CONTRACT_DIGEST"] == override_digest
assert publish["control_fields"]["platform_contract_digest"] == override_digest
assert publish["meta_env"]["OURBOX_PLATFORM_CONTRACT_DIGEST"] == override_digest
assert override_digest in catalog
assert raw_digest not in catalog
PY

grep -F "techofourown.platform-contract.digest=${OVERRIDE_CONTRACT_DIGEST}" "${ORAS_STUB_LOG}" >/dev/null \
  || die "ORAS push did not use the effective platform contract digest override"
if grep -F "techofourown.platform-contract.digest=${RAW_CONTRACT_DIGEST}" "${ORAS_STUB_LOG}" >/dev/null; then
  die "ORAS push used the raw contract digest instead of the effective override"
fi

log "OS publish smoke passed"
