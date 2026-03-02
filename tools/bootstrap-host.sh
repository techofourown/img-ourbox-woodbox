#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "${ROOT}/tools/versions.env" ] && source "${ROOT}/tools/versions.env"

log(){ printf '[%s] %s\n' "$(date -Is)" "$*"; }
die(){ log "ERROR: $*"; exit 1; }

: "${ORAS_VERSION:=1.3.0}"

if [[ ${EUID} -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E -- "$0" "$@"
  fi
  die "must run as root (sudo not found)"
fi

pkg_install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  log "Using apt-get"
  apt-get update -y
  apt-get install -y \
    ca-certificates curl git openssl \
    xz-utils \
    util-linux coreutils \
    e2fsprogs \
    xorriso \
    p7zip-full \
    rsync \
    gettext-base

  # Podman (preferred). Rootless deps included to reduce surprises.
  apt-get install -y \
    podman \
    uidmap slirp4netns fuse-overlayfs
}

pkg_install_dnf() {
  log "Using dnf"
  dnf -y install \
    ca-certificates curl git openssl \
    xz \
    util-linux coreutils \
    e2fsprogs \
    xorriso \
    p7zip \
    rsync \
    gettext \
    podman \
    fuse-overlayfs slirp4netns shadow-utils
}

install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    pkg_install_apt
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    pkg_install_dnf
    return
  fi
  die "unsupported distro: need apt-get or dnf"
}

install_oras() {
  local ver="${ORAS_VERSION}"
  if command -v oras >/dev/null 2>&1; then
    local installed_ver
    installed_ver="$(oras version 2>/dev/null | awk '/^Version:/{print $2; exit}' || true)"
    if [[ "${installed_ver}" == "${ver}" ]]; then
      log "  oras: ${ver} (already installed)"
      return 0
    fi
    log "  oras: found ${installed_ver}, upgrading to ${ver}"
  fi

  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)       die "unsupported arch for ORAS auto-install: ${arch}" ;;
  esac

  local tarball="oras_${ver}_linux_${arch}.tar.gz"
  local url="https://github.com/oras-project/oras/releases/download/v${ver}/${tarball}"
  local tmpdir; tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  log "Downloading ORAS v${ver} (${arch})"
  curl -fsSL -o "${tmpdir}/${tarball}" "${url}"
  tar -xzf "${tmpdir}/${tarball}" -C "${tmpdir}"
  install -m 0755 "${tmpdir}/oras" /usr/local/bin/oras
  log "  oras: installed $(oras version 2>/dev/null | awk '/^Version:/{print $2; exit}' || echo "?")"
}

main() {
  log "Bootstrapping host dependencies (podman + xorriso + ORAS + basics)"
  install_packages
  install_oras

  log "Installed:"
  if command -v podman >/dev/null 2>&1; then log "  podman: $(podman --version 2>/dev/null || true)"; fi
  if command -v xorriso >/dev/null 2>&1; then log "  xorriso: $(xorriso -version 2>/dev/null | head -n1 || true)"; fi
  if command -v envsubst >/dev/null 2>&1; then log "  envsubst: OK"; fi
  if command -v oras >/dev/null 2>&1; then log "  oras: $(oras version 2>/dev/null | awk '/^Version:/{print $2; exit}' || true)"; fi

  log "Bootstrap complete."
}

main "$@"
