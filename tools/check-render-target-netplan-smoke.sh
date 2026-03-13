#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
SYSFS="${TMP}/sys-class-net"
mkdir -p "${SYSFS}"/{lo,enp2s0,enp3s0,usb0}

printf '1\n' > "${SYSFS}/enp2s0/type"
printf '1\n' > "${SYSFS}/enp3s0/type"
printf '1\n' > "${SYSFS}/usb0/type"
printf '772\n' > "${SYSFS}/lo/type"
printf 'aa:bb:cc:dd:ee:01\n' > "${SYSFS}/enp2s0/address"
printf 'aa:bb:cc:dd:ee:02\n' > "${SYSFS}/enp3s0/address"
printf 'aa:bb:cc:dd:ee:99\n' > "${SYSFS}/usb0/address"
ln -s "/devices/pci0000:00/0000:00:1f.6" "${SYSFS}/enp2s0/device"
ln -s "/devices/pci0000:00/0000:03:00.0" "${SYSFS}/enp3s0/device"
ln -s "/devices/pci0000:00/0000:00:14.0/usb1/1-1" "${SYSFS}/usb0/device"

OUT_ONE="${TMP}/target-netplan.yaml"
python3 "${ROOT}/installer/ourbox-preinstall/render-target-netplan.py" \
  --sys-class-net "${SYSFS}" \
  --output "${OUT_ONE}"

grep -q 'macaddress: aa:bb:cc:dd:ee:01' "${OUT_ONE}" \
  || { echo "missing first onboard NIC MAC in rendered netplan" >&2; exit 1; }
grep -q 'macaddress: aa:bb:cc:dd:ee:02' "${OUT_ONE}" \
  || { echo "missing second onboard NIC MAC in rendered netplan" >&2; exit 1; }
if grep -q 'aa:bb:cc:dd:ee:99' "${OUT_ONE}"; then
  echo "USB NIC must not be preferred when onboard Ethernet exists" >&2
  exit 1
fi
grep -q 'optional: true' "${OUT_ONE}" \
  || { echo "rendered netplan must mark installer-discovered NICs optional" >&2; exit 1; }

rm -rf "${SYSFS}/enp2s0" "${SYSFS}/enp3s0"
OUT_TWO="${TMP}/target-netplan-usb.yaml"
python3 "${ROOT}/installer/ourbox-preinstall/render-target-netplan.py" \
  --sys-class-net "${SYSFS}" \
  --output "${OUT_TWO}"

grep -q 'macaddress: aa:bb:cc:dd:ee:99' "${OUT_TWO}" \
  || { echo "renderer must fall back to the remaining physical Ethernet NICs" >&2; exit 1; }

printf '[%s] Woodbox target netplan renderer smoke passed\n' "$(date -Is)"
