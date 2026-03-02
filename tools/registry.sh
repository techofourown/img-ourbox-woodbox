#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
[ -f "$(dirname "${BASH_SOURCE[0]}")/versions.env" ] && source "$(dirname "${BASH_SOURCE[0]}")/versions.env"

# Safe public defaults — may be overridden by an untracked local file (never committed).
: "${REGISTRY:=ghcr.io}"
: "${REGISTRY_NAMESPACE:=techofourown}"
: "${REGISTRY_CA_CERT:=}"
: "${ORAS_VERSION:=1.3.0}"

# Source optional local registry override (gitignored; never commit internal values).
_local_reg="${OURBOX_LOCAL_REGISTRY_ENV:-$(dirname "${BASH_SOURCE[0]}")/local/registry.env}"
# shellcheck disable=SC1090
[[ -f "${_local_reg}" ]] && source "${_local_reg}"
unset _local_reg

if ! declare -F need_cmd >/dev/null 2>&1; then
  need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
fi

pick_container_cli() {
  # Honor explicit override.
  if [ -n "${DOCKER:-}" ]; then
    echo "$DOCKER"
    return 0
  fi

  # Prefer Podman. Default to rootful when not root.
  if command -v podman >/dev/null 2>&1; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
      echo podman
    else
      if command -v sudo >/dev/null 2>&1; then
        echo "sudo podman"
      else
        echo podman
      fi
    fi
    return 0
  fi

  # Fallbacks (rootful defaults if not root).
  if command -v docker >/dev/null 2>&1; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then echo docker; else echo "sudo docker"; fi
    return 0
  fi

  if command -v nerdctl >/dev/null 2>&1; then
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then echo nerdctl; else echo "sudo nerdctl"; fi
    return 0
  fi

  echo "No container CLI found (need podman, docker, or nerdctl)." >&2
  exit 1
}

imgref() {
  # Usage: imgref name tag
  local name="$1" tag="$2"
  echo "${REGISTRY}/${REGISTRY_NAMESPACE}/${name}:${tag}"
}

canonicalize_image_ref() {
  local ref="$1"
  # No slash => definitely not registry-qualified (it's image[:tag] or image@digest)
  if [[ "${ref}" != */* ]]; then
    echo "docker.io/library/${ref}"
    return 0
  fi

  local first="${ref%%/*}"
  # With a slash present, first segment can be a registry (docker.io, quay.io, localhost:5000, etc.)
  if [[ "${first}" == *"."* || "${first}" == *":"* || "${first}" == "localhost" ]]; then
    echo "${ref}"
    return 0
  fi

  echo "docker.io/${ref}"
}

mirror_image() {
  local src="$1" dst="$2"
  local cli; cli="$(pick_container_cli)"

  echo ">> Pull: $src"
  # shellcheck disable=SC2086
  $cli pull "$src"

  echo ">> Tag:  $src -> $dst"
  # shellcheck disable=SC2086
  $cli tag "$src" "$dst"

  echo ">> Push: $dst"
  # shellcheck disable=SC2086
  $cli push "$dst"
}
