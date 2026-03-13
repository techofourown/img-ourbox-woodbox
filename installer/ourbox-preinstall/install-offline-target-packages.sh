#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_SH="${SCRIPT_DIR}/../../tools/lib.sh"
if [[ ! -f "${LIB_SH}" ]]; then
  LIB_SH="${SCRIPT_DIR}/lib.sh"
fi
# shellcheck disable=SC1090
source "${LIB_SH}"

TARGET="/target"
REPO_DIR="/cdrom/ourbox/apt"
PACKAGE_MANIFEST=""

usage() {
  cat <<'EOF'
Usage: install-offline-target-packages.sh [options]

Install required target packages from a local file-backed APT repo only.

Options:
  --target DIR             Install into DIR via curtin in-target (default: /target)
  --repo-dir DIR           Local file-backed APT repo root (default: /cdrom/ourbox/apt)
  --package-manifest PATH  File listing top-level package names to install
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      TARGET="$2"
      shift 2
      ;;
    --repo-dir)
      [[ $# -ge 2 ]] || die "--repo-dir requires a value"
      REPO_DIR="$2"
      shift 2
      ;;
    --package-manifest)
      [[ $# -ge 2 ]] || die "--package-manifest requires a value"
      PACKAGE_MANIFEST="$2"
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

need_cmd curtin
need_cmd awk
need_cmd apt-get

if [[ -z "${PACKAGE_MANIFEST}" ]]; then
  PACKAGE_MANIFEST="${REPO_DIR}/target-packages.txt"
fi

[[ -d "${TARGET}" ]] || die "target root not found: ${TARGET}"
[[ -d "${REPO_DIR}" ]] || die "offline target APT repo not found: ${REPO_DIR}"
[[ -f "${PACKAGE_MANIFEST}" ]] || die "offline target package manifest not found: ${PACKAGE_MANIFEST}"
[[ -f "${REPO_DIR}/Packages" || -f "${REPO_DIR}/Packages.gz" ]] || \
  die "offline target APT repo is missing Packages metadata: ${REPO_DIR}"

mapfile -t target_packages < <(awk 'NF && $1 !~ /^#/ {print $1}' "${PACKAGE_MANIFEST}")
if (( ${#target_packages[@]} == 0 )); then
  log "No offline target packages requested; skipping target package installation"
  exit 0
fi

staged_repo_dir="${TARGET}/opt/ourbox/installer/local-apt"
target_source_list="${TARGET}/tmp/ourbox-local-apt.list"
mkdir -p "${TARGET}/opt/ourbox/installer" "${TARGET}/tmp"
rm -rf "${staged_repo_dir}"
mkdir -p "${staged_repo_dir}"
cp -a "${REPO_DIR}/." "${staged_repo_dir}/"

cat > "${target_source_list}" <<'EOF'
deb [trusted=yes] file:///opt/ourbox/installer/local-apt ./
EOF

apt_opts=(
  -o Dir::Etc::sourcelist=/tmp/ourbox-local-apt.list
  -o Dir::Etc::sourceparts=-
  -o Acquire::Languages=none
)

log "Installing target packages from local repo: ${target_packages[*]}"
curtin in-target --target="${TARGET}" -- apt-get "${apt_opts[@]}" update
curtin in-target --target="${TARGET}" -- env DEBIAN_FRONTEND=noninteractive \
  apt-get "${apt_opts[@]}" install -y --no-install-recommends "${target_packages[@]}"
curtin in-target --target="${TARGET}" -- rm -f /tmp/ourbox-local-apt.list
curtin in-target --target="${TARGET}" -- rm -rf /var/lib/apt/lists/*
rm -rf "${staged_repo_dir}"

log "Installed target packages from local substrate repo"
