#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

OUTPUT_DIR=""
SOURCE_DEB_DIR=""
declare -a REQUESTED_PACKAGES=()
: "${OURBOX_INSTALLER_TARGET_PACKAGES:=avahi-daemon avahi-utils}"

usage() {
  cat <<'EOF'
Usage: prepare-installer-target-apt-repo.sh --output-dir DIR [options]

Build a tiny local APT repo for the packages the installed Woodbox target still
needs, so the official install path never hits Ubuntu mirrors.

Options:
  --output-dir DIR      Destination repo dir (required)
  --source-deb-dir DIR  Copy pre-existing .deb files from DIR instead of downloading
  --package NAME        Add a top-level package name (repeatable)
EOF
}

collect_requested_packages() {
  local pkg=""
  if (( ${#REQUESTED_PACKAGES[@]} > 0 )); then
    return 0
  fi
  for pkg in ${OURBOX_INSTALLER_TARGET_PACKAGES}; do
    [[ -n "${pkg}" ]] || continue
    REQUESTED_PACKAGES+=("${pkg}")
  done
}

resolve_packages_via_apt() {
  local pkg=""
  {
    for pkg in "${REQUESTED_PACKAGES[@]}"; do
      printf '%s\n' "${pkg}"
    done
    apt-cache depends \
      --recurse \
      --important \
      --no-conflicts \
      --no-breaks \
      --no-recommends \
      --no-suggests \
      --no-replaces \
      --no-enhances \
      "${REQUESTED_PACKAGES[@]}" \
      | awk '
          /^[[:space:]\|]*(Pre)?Depends:/ {
            dep = $2
            if (dep ~ /^</) next
            print dep
          }
        '
  } | awk 'NF' | sort -u
}

download_debs_into() {
  local download_dir="$1"
  local pkg=""

  need_cmd apt
  need_cmd apt-cache

  while read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    log "Downloading target package .deb: ${pkg}"
    (
      cd "${download_dir}"
      apt download "${pkg}" >/dev/null
    )
  done < <(resolve_packages_via_apt)
}

copy_source_debs_into() {
  local source_dir="$1"
  local output_dir="$2"
  local deb=""

  [[ -d "${source_dir}" ]] || die "source deb dir not found: ${source_dir}"
  find "${source_dir}" -maxdepth 1 -type f -name '*.deb' -print -quit | grep -q . \
    || die "source deb dir contains no .deb files: ${source_dir}"
  while read -r deb; do
    [[ -n "${deb}" ]] || continue
    cp -a "${deb}" "${output_dir}/"
  done < <(find "${source_dir}" -maxdepth 1 -type f -name '*.deb' | sort)
}

write_repo_metadata() {
  local repo_dir="$1"

  need_cmd dpkg-deb
  need_cmd gzip
  need_cmd python3
  python3 - <<'PY' "${repo_dir}"
import gzip
import hashlib
import pathlib
import subprocess
import sys

repo_dir = pathlib.Path(sys.argv[1])
package_entries = []

for deb_path in sorted(repo_dir.glob("*.deb")):
    control = subprocess.check_output(
        ["dpkg-deb", "-f", str(deb_path)],
        text=True,
        encoding="utf-8",
    ).strip()
    data = deb_path.read_bytes()
    package_entries.append(
        "\n".join(
            [
                control,
                f"Filename: {deb_path.name}",
                f"Size: {deb_path.stat().st_size}",
                f"MD5sum: {hashlib.md5(data).hexdigest()}",
                f"SHA1: {hashlib.sha1(data).hexdigest()}",
                f"SHA256: {hashlib.sha256(data).hexdigest()}",
            ]
        )
    )

packages_path = repo_dir / "Packages"
packages_text = "\n\n".join(package_entries) + ("\n" if package_entries else "")
packages_path.write_text(packages_text, encoding="utf-8")
with gzip.open(repo_dir / "Packages.gz", "wt", encoding="utf-8") as handle:
    handle.write(packages_text)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --source-deb-dir)
      [[ $# -ge 2 ]] || die "--source-deb-dir requires a value"
      SOURCE_DEB_DIR="$2"
      shift 2
      ;;
    --package)
      [[ $# -ge 2 ]] || die "--package requires a value"
      REQUESTED_PACKAGES+=("$2")
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

[[ -n "${OUTPUT_DIR}" ]] || die "--output-dir is required"
collect_requested_packages
(( ${#REQUESTED_PACKAGES[@]} > 0 )) || die "no target packages were requested"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

if [[ -n "${SOURCE_DEB_DIR}" ]]; then
  copy_source_debs_into "${SOURCE_DEB_DIR}" "${OUTPUT_DIR}"
else
  download_debs_into "${OUTPUT_DIR}"
fi

find "${OUTPUT_DIR}" -maxdepth 1 -type f -name '*.deb' -print -quit | grep -q . \
  || die "no .deb files were prepared for the installer target repo"

printf '%s\n' "${REQUESTED_PACKAGES[@]}" > "${OUTPUT_DIR}/target-packages.txt"
write_repo_metadata "${OUTPUT_DIR}"

log "Prepared installer target APT repo: ${OUTPUT_DIR}"
