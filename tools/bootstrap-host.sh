#!/usr/bin/env bash
set -euo pipefail

log(){ printf '[%s] %s\n' "$(date -Is)" "$*"; }
die(){ log "ERROR: $*"; exit 1; }

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

main() {
  log "Bootstrapping host dependencies (podman + xorriso + basics)"
  install_packages

  log "Installed:"
  command -v podman >/dev/null 2>&1 && log "  podman: $(podman --version || true)" || true
  command -v xorriso >/dev/null 2>&1 && log "  xorriso: $(xorriso -version 2>/dev/null | head -n1 || true)" || true
  command -v envsubst >/dev/null 2>&1 && log "  envsubst: OK" || true

  log "Bootstrap complete."
}

main "$@"
