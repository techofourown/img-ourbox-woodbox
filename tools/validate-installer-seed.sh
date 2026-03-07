#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd envsubst
need_cmd python3

usage() {
  cat <<'EOF'
Usage:
  validate-installer-seed.sh
  validate-installer-seed.sh --rendered PATH

Default mode renders installer/autoinstall/user-data.tpl with representative
values and validates the rendered cloud-config as YAML.

Options:
  --rendered PATH   Validate an already-rendered cloud-config file.
EOF
}

RENDERED_FILE=""
TEMP_RENDERED_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rendered)
      [[ $# -ge 2 ]] || die "--rendered requires a path"
      RENDERED_FILE="$2"
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

render_seed_to_temp() {
  local rendered_path="$1"

  : "${OURBOX_HOSTNAME:=ourbox-woodbox}"
  : "${OURBOX_USERNAME:=ourbox}"
  : "${OURBOX_PASSWORD_HASH:=\$6\$rounds=4096\$example\$W5v5k0f2F8x8vM0Q7x3jzdH8m9oGQf3hVqM1U6K1zj6m7U1P7p0m1N2B3c4D5e6F7g8H9i0j1k2l3m4n5o6p0}"
  : "${OURBOX_PRODUCT:=ourbox}"
  : "${OURBOX_DEVICE:=woodbox}"
  : "${OURBOX_TARGET:=x86}"
  : "${OURBOX_SKU:=TOO-OBX-WBX-BASE-JU3XK8}"
  : "${OURBOX_VARIANT:=prod}"
  : "${OURBOX_VERSION:=seed-validation}"

  export OURBOX_HOSTNAME OURBOX_USERNAME OURBOX_PASSWORD_HASH
  export OURBOX_PRODUCT OURBOX_DEVICE OURBOX_TARGET OURBOX_SKU OURBOX_VARIANT OURBOX_VERSION

  # shellcheck disable=SC2016
  local subst_vars='${OURBOX_HOSTNAME} ${OURBOX_USERNAME} ${OURBOX_PASSWORD_HASH} ${OURBOX_PRODUCT} ${OURBOX_DEVICE} ${OURBOX_TARGET} ${OURBOX_SKU} ${OURBOX_VARIANT} ${OURBOX_VERSION}'
  envsubst "${subst_vars}" \
    < "${ROOT}/installer/autoinstall/user-data.tpl" \
    > "${rendered_path}"
}

validate_with_python() {
  local rendered_path="$1"

  python3 - "${rendered_path}" <<'PY'
import pathlib
import sys

try:
    import yaml
except ImportError as exc:
    print(f"ERROR: PyYAML is required for installer seed validation: {exc}", file=sys.stderr)
    sys.exit(1)

rendered_path = pathlib.Path(sys.argv[1])
text = rendered_path.read_text(encoding="utf-8")

try:
    data = yaml.safe_load(text)
except yaml.YAMLError as exc:
    print(f"ERROR: invalid YAML in {rendered_path}: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print(f"ERROR: rendered seed {rendered_path} did not parse to a mapping", file=sys.stderr)
    sys.exit(1)

bootcmd = data.get("bootcmd")
if not isinstance(bootcmd, list) or not bootcmd:
    print(f"ERROR: rendered seed {rendered_path} is missing a non-empty bootcmd list", file=sys.stderr)
    sys.exit(1)

monitor_index = next(
    (idx for idx, item in enumerate(bootcmd) if "ourbox-installer-monitor.py" in str(item)),
    None,
)
bootstrap_index = next(
    (idx for idx, item in enumerate(bootcmd) if "ourbox-installer-ssh-bootstrap.sh" in str(item)),
    None,
)

if monitor_index is None:
    print(
        f"ERROR: rendered seed {rendered_path} does not reference the staged installer monitor script",
        file=sys.stderr,
    )
    sys.exit(1)

if bootstrap_index is None:
    print(
        f"ERROR: rendered seed {rendered_path} does not reference the staged installer SSH bootstrap script",
        file=sys.stderr,
    )
    sys.exit(1)

if monitor_index >= bootstrap_index:
    print(
        f"ERROR: rendered seed {rendered_path} must launch the installer monitor before SSH bootstrap",
        file=sys.stderr,
    )
    sys.exit(1)

autoinstall = data.get("autoinstall")
if not isinstance(autoinstall, dict):
    print(f"ERROR: rendered seed {rendered_path} is missing the autoinstall mapping", file=sys.stderr)
    sys.exit(1)

print(f"YAML OK: {rendered_path}")
PY
}

validate_with_cloud_init_if_available() {
  local rendered_path="$1"

  if ! command -v cloud-init >/dev/null 2>&1; then
    log "cloud-init not installed; skipping schema validation"
    return 0
  fi

  if cloud-init schema --config-file "${rendered_path}" >/dev/null 2>&1; then
    log "cloud-init schema OK: ${rendered_path}"
    return 0
  fi

  if cloud-init devel schema --config-file "${rendered_path}" >/dev/null 2>&1; then
    log "cloud-init devel schema OK: ${rendered_path}"
    return 0
  fi

  die "cloud-init schema validation failed for ${rendered_path}"
}

main() {
  local rendered_path

  if [[ -n "${RENDERED_FILE}" ]]; then
    rendered_path="${RENDERED_FILE}"
    [[ -f "${rendered_path}" ]] || die "rendered seed not found: ${rendered_path}"
  else
    TEMP_RENDERED_FILE="$(mktemp)"
    trap 'rm -f "${TEMP_RENDERED_FILE}"' EXIT
    rendered_path="${TEMP_RENDERED_FILE}"
    render_seed_to_temp "${rendered_path}"
  fi

  validate_with_python "${rendered_path}"
  validate_with_cloud_init_if_available "${rendered_path}"
}

main "$@"
