#!/usr/bin/env bash
# Sync vendored modules from sw-ourbox-os to the approved revisions recorded
# in approved-upstream-inputs.json.
#
# Reads the JSON from sw-ourbox-os@main (same source used for OCI artifact
# resolution), compares current .upstream.env pins against the approved
# vendored_modules revisions, and updates the local files and pins if behind.
#
# Usage:
#   bash tools/sync-vendored-modules.sh           # apply updates
#   bash tools/sync-vendored-modules.sh --dry-run # report only, no changes
#
# Sets VENDORED_MODULES_CHANGED=1 in GITHUB_ENV when running inside GitHub
# Actions and at least one module was updated.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"
# shellcheck disable=SC1091
source "${ROOT}/tools/approved-upstream-inputs.upstream.env"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

INPUTS_JSON="${TMP}/approved-upstream-inputs.json"
CHANGED=0

log "Fetching approved-upstream-inputs from ${SW_OURBOX_OS_APPROVED_INPUTS_REPO}@${SW_OURBOX_OS_APPROVED_INPUTS_REVISION}"
curl -fsSL \
  "https://raw.githubusercontent.com/${SW_OURBOX_OS_APPROVED_INPUTS_REPO}/${SW_OURBOX_OS_APPROVED_INPUTS_REVISION}/${SW_OURBOX_OS_APPROVED_INPUTS_PATH}" \
  -o "${INPUTS_JSON}" \
  || die "failed to fetch approved-upstream-inputs.json"

_get_field() {
  python3 -c "import json; d=json.load(open('${INPUTS_JSON}')); print(d${1})"
}

_fetch_raw() {
  local repo="$1" revision="$2" path="$3" dest="$4"
  curl -fsSL \
    "https://raw.githubusercontent.com/${repo}/${revision}/${path}" \
    -o "${dest}" \
    || die "failed to fetch ${repo}@${revision}:${path}"
}

_update_revision_in_env() {
  local env_file="$1" new_rev="$2"
  # Replace the SW_OURBOX_OS_REVISION= line in place
  python3 - "${env_file}" "${new_rev}" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
new_rev = sys.argv[2]
lines = p.read_text().splitlines(keepends=True)
out = []
for line in lines:
    if line.startswith("SW_OURBOX_OS_REVISION="):
        out.append(f"SW_OURBOX_OS_REVISION={new_rev}\n")
    else:
        out.append(line)
p.write_text("".join(out))
PYEOF
}

# ---------------------------------------------------------------------------
# installer-ssh-helper
# ---------------------------------------------------------------------------
SSH_REVISION="$(_get_field "['vendored_modules']['installer_ssh_helper']['revision']")"
SSH_REPO="$(_get_field "['vendored_modules']['installer_ssh_helper']['repo']")"
SSH_PATH="$(_get_field "['vendored_modules']['installer_ssh_helper']['path']")"
SSH_ENV="${ROOT}/tools/installer-ssh-helper.upstream.env"
SSH_LOCAL="${ROOT}/tools/installer-ssh-helper.sh"

# shellcheck disable=SC1090
CURRENT_SSH_REVISION="$(grep '^SW_OURBOX_OS_REVISION=' "${SSH_ENV}" | cut -d= -f2)"

if [[ "${CURRENT_SSH_REVISION}" == "${SSH_REVISION}" ]]; then
  log "installer-ssh-helper: already at ${SSH_REVISION}"
else
  log "installer-ssh-helper: ${CURRENT_SSH_REVISION} -> ${SSH_REVISION}"
  if [[ "${DRY_RUN}" == "0" ]]; then
    _fetch_raw "${SSH_REPO}" "${SSH_REVISION}" "${SSH_PATH}" "${TMP}/installer-ssh-helper.sh"
    cp "${TMP}/installer-ssh-helper.sh" "${SSH_LOCAL}"
    _update_revision_in_env "${SSH_ENV}" "${SSH_REVISION}"
  fi
  CHANGED=1
fi

# ---------------------------------------------------------------------------
# release-control
# ---------------------------------------------------------------------------
RC_REVISION="$(_get_field "['vendored_modules']['release_control']['revision']")"
RC_REPO="$(_get_field "['vendored_modules']['release_control']['repo']")"
RC_BASE="$(_get_field "['vendored_modules']['release_control']['base']")"
RC_ENV="${ROOT}/tools/release-control.upstream.env"
RC_LOCAL_DIR="${ROOT}/tools/release-control"

mapfile -t RC_FILES < <(python3 -c "
import json
d = json.load(open('${INPUTS_JSON}'))
for f in d['vendored_modules']['release_control']['files']:
    print(f)
")

CURRENT_RC_REVISION="$(grep '^SW_OURBOX_OS_REVISION=' "${RC_ENV}" | cut -d= -f2)"

if [[ "${CURRENT_RC_REVISION}" == "${RC_REVISION}" ]]; then
  log "release-control: already at ${RC_REVISION}"
else
  log "release-control: ${CURRENT_RC_REVISION} -> ${RC_REVISION}"
  if [[ "${DRY_RUN}" == "0" ]]; then
    for fname in "${RC_FILES[@]}"; do
      _fetch_raw "${RC_REPO}" "${RC_REVISION}" "${RC_BASE}/${fname}" "${TMP}/${fname}"
      cp "${TMP}/${fname}" "${RC_LOCAL_DIR}/${fname}"
    done
    _update_revision_in_env "${RC_ENV}" "${RC_REVISION}"
  fi
  CHANGED=1
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [[ "${CHANGED}" == "1" ]]; then
  log "Sync complete: one or more modules updated"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "VENDORED_MODULES_CHANGED=1" >> "${GITHUB_ENV}"
    echo "VENDORED_MODULES_REVISION=${SSH_REVISION}" >> "${GITHUB_ENV}"
  fi
else
  log "Sync complete: all modules up to date"
fi
