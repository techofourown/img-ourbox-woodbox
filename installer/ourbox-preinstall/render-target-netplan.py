#!/usr/bin/env python3
import argparse
import pathlib
import re
import sys


MAC_RE = re.compile(r"^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$")


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def is_physical_ethernet(iface_path: pathlib.Path) -> bool:
    if iface_path.name == "lo":
        return False
    device_path = iface_path / "device"
    if not (device_path.exists() or device_path.is_symlink()):
        return False
    try:
        real_path = iface_path.resolve()
    except FileNotFoundError:
        return False
    if "/virtual/" in str(real_path):
        return False
    try:
        if read_text(iface_path / "type") != "1":
            return False
    except FileNotFoundError:
        return False
    try:
        mac = read_text(iface_path / "address").lower()
    except FileNotFoundError:
        return False
    return bool(MAC_RE.fullmatch(mac)) and mac != "00:00:00:00:00:00"


def collect_candidates(sys_class_net: pathlib.Path):
    entries = []
    for iface_path in sorted(sys_class_net.iterdir(), key=lambda path: path.name):
        if not iface_path.is_dir():
            continue
        if not is_physical_ethernet(iface_path):
            continue
        device_path = (iface_path / "device").resolve(strict=False)
        entries.append(
            {
                "name": iface_path.name,
                "mac": read_text(iface_path / "address").lower(),
                "is_usb": "/usb" in str(device_path).lower(),
            }
        )
    return entries


def choose_interfaces(entries):
    non_usb = [entry for entry in entries if not entry["is_usb"]]
    return non_usb or entries


def render_yaml(entries) -> str:
    lines = [
        "network:",
        "  version: 2",
        "  ethernets:",
    ]
    for idx, entry in enumerate(entries):
        lines.extend(
            [
                f"    lan{idx}:",
                "      match:",
                f"        macaddress: {entry['mac']}",
                "      dhcp4: true",
                "      optional: true",
            ]
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render target netplan from physical Ethernet hardware inventory."
    )
    parser.add_argument(
        "--sys-class-net",
        default="/sys/class/net",
        help="Path to the sysfs network inventory root (default: /sys/class/net)",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Write the rendered netplan YAML to this file",
    )
    args = parser.parse_args()

    sys_class_net = pathlib.Path(args.sys_class_net)
    if not sys_class_net.is_dir():
        raise SystemExit(f"sysfs network root is not a directory: {sys_class_net}")

    candidates = collect_candidates(sys_class_net)
    if not candidates:
        raise SystemExit(f"no physical Ethernet interfaces found under {sys_class_net}")

    selected = choose_interfaces(candidates)
    output_path = pathlib.Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(render_yaml(selected), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
