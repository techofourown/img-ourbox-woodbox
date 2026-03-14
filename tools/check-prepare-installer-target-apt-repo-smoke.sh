#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/tools/lib.sh"

need_cmd dpkg-deb
need_cmd python3

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
DEB_SRC="${TMP}/debs"
REPO_OUT="${TMP}/repo"
mkdir -p "${DEB_SRC}/avahi-daemon/DEBIAN" "${DEB_SRC}/avahi-utils/DEBIAN" "${DEB_SRC}/openssh-server/DEBIAN"

cat > "${DEB_SRC}/avahi-daemon/DEBIAN/control" <<'EOF'
Package: avahi-daemon
Version: 1.0-1
Architecture: amd64
Maintainer: Fixture <fixture@example.com>
Description: fixture avahi daemon
EOF

cat > "${DEB_SRC}/avahi-utils/DEBIAN/control" <<'EOF'
Package: avahi-utils
Version: 1.0-1
Architecture: amd64
Maintainer: Fixture <fixture@example.com>
Description: fixture avahi utils
EOF

cat > "${DEB_SRC}/openssh-server/DEBIAN/control" <<'EOF'
Package: openssh-server
Version: 1.0-1
Architecture: amd64
Maintainer: Fixture <fixture@example.com>
Description: fixture openssh server
EOF

dpkg-deb --build "${DEB_SRC}/avahi-daemon" "${DEB_SRC}/avahi-daemon_1.0-1_amd64.deb" >/dev/null
dpkg-deb --build "${DEB_SRC}/avahi-utils" "${DEB_SRC}/avahi-utils_1.0-1_amd64.deb" >/dev/null
dpkg-deb --build "${DEB_SRC}/openssh-server" "${DEB_SRC}/openssh-server_1.0-1_amd64.deb" >/dev/null

[[ -x "${ROOT}/tools/prepare-installer-target-apt-repo.sh" ]] \
  || die "prepare-installer-target-apt-repo.sh must be executable"

"${ROOT}/tools/prepare-installer-target-apt-repo.sh" \
  --output-dir "${REPO_OUT}" \
  --source-deb-dir "${DEB_SRC}" \
  --package avahi-daemon \
  --package avahi-utils \
  --repo-package openssh-server

[[ -f "${REPO_OUT}/Packages" ]] || die "local installer target repo is missing Packages"
[[ -f "${REPO_OUT}/Packages.gz" ]] || die "local installer target repo is missing Packages.gz"
[[ -f "${REPO_OUT}/target-packages.txt" ]] || die "local installer target repo is missing target-packages.txt"
grep -q '^avahi-daemon$' "${REPO_OUT}/target-packages.txt" || die "target package manifest missing avahi-daemon"
grep -q '^avahi-utils$' "${REPO_OUT}/target-packages.txt" || die "target package manifest missing avahi-utils"
! grep -q '^openssh-server$' "${REPO_OUT}/target-packages.txt" || die "target package manifest must not install openssh-server by default"
grep -q '^Package: avahi-daemon$' "${REPO_OUT}/Packages" || die "Packages index missing avahi-daemon stanza"
grep -q '^Package: avahi-utils$' "${REPO_OUT}/Packages" || die "Packages index missing avahi-utils stanza"
grep -q '^Package: openssh-server$' "${REPO_OUT}/Packages" || die "Packages index missing openssh-server stanza"

printf '[%s] Woodbox installer target APT repo smoke passed\n' "$(date -Is)"
