#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_DIR="${1:-${ROOT}/artifacts/platform-contract/extracted/platform-contract}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -d "${CONTRACT_DIR}" ]] || die "platform contract directory not found: ${CONTRACT_DIR}"
command -v python3 >/dev/null 2>&1 || die "python3 is required to validate platform contract capabilities"

# The current runtime seam expects render/verify tools, demo-app profile data,
# and a full rendered workload manifest set. Older upstream artifacts lacked
# those manifests entirely. Current upstream bundles use unnumbered app
# deployment filenames while retaining numbered control-plane filenames, so
# accept either unnumbered or NN-prefixed variants for workload manifests.
required_paths=(
  "contract.env"
  "tools/check-target-prereqs.sh"
  "tools/contract-identity.sh"
  "tools/render-contract.py"
  "tools/verify-runtime.sh"
  "profiles/demo-apps/profile.env"
  "profiles/demo-apps/images.lock.json"
)

required_manifest_basenames=(
  "landing-deployment.yaml"
  "dufs-deployment.yaml"
  "flatnotes-deployment.yaml"
  "demo-apps-ingress.yaml"
)

has_required_manifest() {
  local basename="$1"

  [[ -e "${CONTRACT_DIR}/manifests/${basename}" ]] && return 0
  compgen -G "${CONTRACT_DIR}/manifests/[0-9][0-9]-${basename}" >/dev/null && return 0
  return 1
}

missing=()
for rel in "${required_paths[@]}"; do
  [[ -e "${CONTRACT_DIR}/${rel}" ]] || missing+=("${rel}")
done

for basename in "${required_manifest_basenames[@]}"; do
  has_required_manifest "${basename}" || missing+=("manifests/{NN-}${basename}")
done

if (( ${#missing[@]} > 0 )); then
  echo "ERROR: platform-contract artifact shape check failed for ${CONTRACT_DIR}" >&2
  echo "Missing required files:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Update PLATFORM_CONTRACT_REF to a full-shape upstream contract artifact." >&2
  exit 1
fi

render_help="$(
  python3 "${CONTRACT_DIR}/tools/render-contract.py" --help 2>&1
)" || die "platform-contract render-contract.py is not runnable: ${CONTRACT_DIR}/tools/render-contract.py"

required_render_options=(
  "--selected-apps-file"
  "--application-catalog"
  "--images-lock-file"
)
missing_render_options=()
for option in "${required_render_options[@]}"; do
  if ! grep -Fq -- "${option}" <<<"${render_help}"; then
    missing_render_options+=("${option}")
  fi
done

if (( ${#missing_render_options[@]} > 0 )); then
  echo "ERROR: platform-contract runtime capability check failed for ${CONTRACT_DIR}" >&2
  echo "render-contract.py is missing required host-selected application options:" >&2
  printf '  - %s\n' "${missing_render_options[@]}" >&2
  echo "Update PLATFORM_CONTRACT_REF to a platform-contract artifact that supports host-selected application metadata." >&2
  exit 1
fi

identity_output="$(
  "${CONTRACT_DIR}/tools/contract-identity.sh" \
    --contract-dir "${CONTRACT_DIR}" \
    --profile demo-apps \
    --box-host smoke.ourbox.local \
    --tls-mode lan-http \
    --ingress-class traefik \
    --storage-class local-path
)" || die "platform-contract contract-identity.sh is not runnable for demo-apps"

required_identity_keys=(
  "OURBOX_APPLICATION_CATALOG_ID="
  "OURBOX_APPLICATION_SELECTION_MODE="
  "OURBOX_SELECTED_APPLICATION_IDS="
  "OURBOX_APPLICATION_CATALOG_SHA256="
  "OURBOX_APPLICATION_IMAGES_LOCK_SHA256="
)
missing_identity_keys=()
for key in "${required_identity_keys[@]}"; do
  if ! grep -Fq -- "${key}" <<<"${identity_output}"; then
    missing_identity_keys+=("${key%=}")
  fi
done

if (( ${#missing_identity_keys[@]} > 0 )); then
  echo "ERROR: platform-contract identity capability check failed for ${CONTRACT_DIR}" >&2
  echo "contract-identity.sh is missing required application metadata outputs:" >&2
  printf '  - %s\n' "${missing_identity_keys[@]}" >&2
  echo "Update PLATFORM_CONTRACT_REF to a platform-contract artifact that supports host-selected application metadata." >&2
  exit 1
fi

identity_value() {
  local key="$1"
  awk -F= -v wanted="${key}" '
    $1 == wanted {
      print substr($0, index($0, "=") + 1)
      exit
    }
  ' <<<"${identity_output}"
}

empty_identity_keys=()
if [[ -f "${CONTRACT_DIR}/selected-apps.json" ]]; then
  for key in \
    "OURBOX_APPLICATION_CATALOG_ID" \
    "OURBOX_APPLICATION_SELECTION_MODE" \
    "OURBOX_SELECTED_APPLICATION_IDS"; do
    if [[ -z "$(identity_value "${key}")" ]]; then
      empty_identity_keys+=("${key}")
    fi
  done
fi

if [[ -f "${CONTRACT_DIR}/catalog.json" ]] && [[ -z "$(identity_value "OURBOX_APPLICATION_CATALOG_SHA256")" ]]; then
  empty_identity_keys+=("OURBOX_APPLICATION_CATALOG_SHA256")
fi

if [[ -f "${CONTRACT_DIR}/images.lock.json" ]] && [[ -z "$(identity_value "OURBOX_APPLICATION_IMAGES_LOCK_SHA256")" ]]; then
  empty_identity_keys+=("OURBOX_APPLICATION_IMAGES_LOCK_SHA256")
fi

if (( ${#empty_identity_keys[@]} > 0 )); then
  echo "ERROR: platform-contract identity capability check failed for ${CONTRACT_DIR}" >&2
  echo "contract-identity.sh leaves required application metadata outputs empty:" >&2
  printf '  - %s\n' "${empty_identity_keys[@]}" >&2
  echo "Update PLATFORM_CONTRACT_REF to a platform-contract artifact that supports host-selected application metadata." >&2
  exit 1
fi

echo "OK: platform contract shape validated: ${CONTRACT_DIR}"
