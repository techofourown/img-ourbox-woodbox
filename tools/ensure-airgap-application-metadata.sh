#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

BUNDLE_DIR=""
CONTRACT_ROOT=""
PROFILE_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage:
  ensure-airgap-application-metadata.sh \
    --bundle-dir DIR \
    --contract-root DIR \
    [--profile PROFILE]

Ensure a baked airgap bundle carries the application catalog metadata expected by
the Woodbox runtime. Older upstream bundles may lack:
  - platform/catalog.json
  - platform/selected-apps.json

This helper backfills them from the synced platform contract profile.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-dir)
      [[ $# -ge 2 ]] || die "--bundle-dir requires a value"
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --contract-root)
      [[ $# -ge 2 ]] || die "--contract-root requires a value"
      CONTRACT_ROOT="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value"
      PROFILE_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${BUNDLE_DIR}" ]] || die "--bundle-dir is required"
[[ -d "${BUNDLE_DIR}" ]] || die "bundle dir not found: ${BUNDLE_DIR}"
[[ -n "${CONTRACT_ROOT}" ]] || die "--contract-root is required"
[[ -d "${CONTRACT_ROOT}" ]] || die "contract root not found: ${CONTRACT_ROOT}"

need_cmd python3

BUNDLE_DIR="$(readlink -m "${BUNDLE_DIR}")"
CONTRACT_ROOT="$(readlink -m "${CONTRACT_ROOT}")"

MANIFEST_ENV="${BUNDLE_DIR}/manifest.env"
PROFILE_ENV="${BUNDLE_DIR}/platform/profile.env"
CATALOG_JSON="${BUNDLE_DIR}/platform/catalog.json"
SELECTED_APPS_JSON="${BUNDLE_DIR}/platform/selected-apps.json"

[[ -f "${MANIFEST_ENV}" ]] || die "bundle missing manifest.env: ${MANIFEST_ENV}"
[[ -f "${PROFILE_ENV}" ]] || die "bundle missing platform/profile.env: ${PROFILE_ENV}"
mkdir -p "${BUNDLE_DIR}/platform"

profile_dump="$(
  python3 - <<'PY' "${MANIFEST_ENV}" "${PROFILE_ENV}" "${PROFILE_OVERRIDE}"
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
profile_env_path = pathlib.Path(sys.argv[2])
profile_override = sys.argv[3].strip()


def load_env(path: pathlib.Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key] = value
    return data


manifest = load_env(manifest_path)
profile_env = load_env(profile_env_path)

profile = profile_override or manifest.get("OURBOX_PLATFORM_PROFILE", "").strip() or profile_env.get("OURBOX_PLATFORM_PROFILE", "").strip() or profile_env.get("PROFILE", "").strip()
if not profile:
    raise SystemExit("unable to determine application profile from bundle manifest/profile.env")

print(profile)
PY
)"

[[ -n "${profile_dump}" ]] || die "failed to resolve application profile for ${BUNDLE_DIR}"
PROFILE_NAME="${profile_dump}"
PROFILE_DIR="${CONTRACT_ROOT}/profiles/${PROFILE_NAME}"
PROFILE_CATALOG="${PROFILE_DIR}/catalog.json"

if [[ ! -f "${CATALOG_JSON}" ]]; then
  [[ -f "${PROFILE_CATALOG}" ]] || die "bundle is missing platform/catalog.json and synced contract profile has no catalog: ${PROFILE_CATALOG}"
  cp -f "${PROFILE_CATALOG}" "${CATALOG_JSON}"
  log "Backfilled application catalog metadata into ${CATALOG_JSON} from ${PROFILE_CATALOG}"
fi

if [[ ! -f "${SELECTED_APPS_JSON}" ]]; then
  python3 - <<'PY' "${CATALOG_JSON}" "${SELECTED_APPS_JSON}"
import json
import pathlib
import sys

catalog_path = pathlib.Path(sys.argv[1])
selected_path = pathlib.Path(sys.argv[2])

with catalog_path.open("r", encoding="utf-8") as handle:
    catalog = json.load(handle)

if catalog.get("schema") != 1:
    raise SystemExit(f"application catalog at {catalog_path} must declare schema=1")
if catalog.get("kind") != "ourbox-application-catalog":
    raise SystemExit(f"application catalog at {catalog_path} must declare kind=ourbox-application-catalog")

catalog_id = str(catalog.get("catalog_id", "")).strip()
if not catalog_id:
    raise SystemExit(f"application catalog at {catalog_path} must declare catalog_id")

default_app_ids = catalog.get("default_app_ids")
if not isinstance(default_app_ids, list) or not default_app_ids:
    raise SystemExit(f"application catalog at {catalog_path} must declare non-empty default_app_ids")

selected = {
    "schema": 1,
    "kind": "ourbox-selected-applications",
    "catalog_id": catalog_id,
    "selection_mode": "defaults",
    "selected_app_ids": list(default_app_ids),
}
with selected_path.open("w", encoding="utf-8") as handle:
    json.dump(selected, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  log "Synthesized default selected applications into ${SELECTED_APPS_JSON}"
fi

python3 - <<'PY' "${CATALOG_JSON}" "${SELECTED_APPS_JSON}"
import json
import pathlib
import sys

catalog_path = pathlib.Path(sys.argv[1])
selected_path = pathlib.Path(sys.argv[2])

with catalog_path.open("r", encoding="utf-8") as handle:
    catalog = json.load(handle)
with selected_path.open("r", encoding="utf-8") as handle:
    selected = json.load(handle)

if catalog.get("schema") != 1:
    raise SystemExit(f"application catalog at {catalog_path} must declare schema=1")
if catalog.get("kind") != "ourbox-application-catalog":
    raise SystemExit(f"application catalog at {catalog_path} must declare kind=ourbox-application-catalog")

apps = catalog.get("apps")
if not isinstance(apps, list) or not apps:
    raise SystemExit(f"application catalog at {catalog_path} must declare a non-empty apps list")
app_ids: set[str] = set()
for app in apps:
    app_id = str(app.get("id", "")).strip()
    if not app_id:
        raise SystemExit(f"application catalog at {catalog_path} contains an app without an id")
    if app_id in app_ids:
        raise SystemExit(f"application catalog at {catalog_path} contains duplicate app id {app_id}")
    app_ids.add(app_id)

default_app_ids = catalog.get("default_app_ids")
if not isinstance(default_app_ids, list) or not default_app_ids:
    raise SystemExit(f"application catalog at {catalog_path} must declare non-empty default_app_ids")
unknown_defaults = sorted(set(str(item).strip() for item in default_app_ids) - app_ids)
if unknown_defaults:
    raise SystemExit(
        f"application catalog at {catalog_path} declares unknown default_app_ids: {', '.join(unknown_defaults)}"
    )

if selected.get("schema") != 1:
    raise SystemExit(f"selected applications file at {selected_path} must declare schema=1")
if selected.get("kind") != "ourbox-selected-applications":
    raise SystemExit(f"selected applications file at {selected_path} must declare kind=ourbox-selected-applications")
if str(selected.get("catalog_id", "")).strip() != str(catalog.get("catalog_id", "")).strip():
    raise SystemExit(f"selected applications file at {selected_path} must match catalog_id from {catalog_path}")

selection_mode = str(selected.get("selection_mode", "")).strip()
if not selection_mode:
    raise SystemExit(f"selected applications file at {selected_path} must declare selection_mode")

selected_app_ids = selected.get("selected_app_ids")
if not isinstance(selected_app_ids, list) or not selected_app_ids:
    raise SystemExit(f"selected applications file at {selected_path} must declare a non-empty selected_app_ids list")

seen_ids: set[str] = set()
for raw_app_id in selected_app_ids:
    app_id = str(raw_app_id).strip()
    if not app_id:
        raise SystemExit(f"selected applications file at {selected_path} contains an empty app id")
    if app_id in seen_ids:
        raise SystemExit(f"selected applications file at {selected_path} duplicates app id {app_id}")
    if app_id not in app_ids:
        raise SystemExit(f"selected applications file at {selected_path} references unknown app id {app_id}")
    seen_ids.add(app_id)
PY

log "Verified baked application metadata for profile ${PROFILE_NAME}"
