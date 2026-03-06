#!/usr/bin/env python3
"""OurBox Woodbox Installer Monitor

Tails /run/ourbox-installer.log and makes installation events visible to any
machine on the same network, with no configuration on the receiving end.

Access methods
--------------
UDP broadcast (port 9999) — live event stream, same L2 network:

  python3 -c "
  import socket
  s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
  s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  s.bind(('', 9999))
  print('Listening for OurBox installer on UDP :9999...')
  while True:
      data, _ = s.recvfrom(4096)
      print(data.decode('utf-8', 'replace'), end='', flush=True)
  "

  Or: socat UDP-RECV:9999,reuseaddr -

HTTP log viewer (port 8888) — auto-refreshing browser page:

  Open http://<installer-ip>:8888/ in a browser.
  Useful when UDP broadcast doesn't reach across subnets.

SSH (port 22) — interactive live-env shell:

  Only advertised after the installer reports SSH ready.
  On the installer: journalctl -fu ourbox-preinstall.service
                    cat /autoinstall.yaml
                    cat /run/ourbox-installer.log
"""

import html
import http.server
import os
import socket
import socketserver
import threading
import time

LOG_FILE = "/run/ourbox-installer.log"
SSH_STATUS_FILE = "/run/ourbox-installer-ssh-status.env"
DEFAULTS_FILE = "/cdrom/ourbox/installer/defaults.env"
DEFAULT_BROADCAST_ADDR = "255.255.255.255"
DEFAULT_BROADCAST_PORT = 9999
BROADCAST_ADDR = "255.255.255.255"
BROADCAST_PORT = 9999
HTTP_PORT = 8888
# Re-announce interval in seconds (so late listeners can discover)
REANNOUNCE_INTERVAL = 60


# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------

def get_ip():
    """Return the primary outgoing IP, or 'unknown'."""
    for target in ("10.255.255.255", "8.8.8.8"):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0.5)
            s.connect((target, 1))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except OSError:
            pass
    return "unknown"


def wait_for_network(timeout=30):
    """Poll until a non-loopback IP is available, up to timeout seconds."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ip = get_ip()
        if ip not in ("unknown", "127.0.0.1", "127.0.1.1"):
            return ip
        time.sleep(1)
    return get_ip()


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def read_env_file(path: str, defaults=None):
    values = dict(defaults or {})
    try:
        with open(path, "r", errors="replace") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                values[key.strip()] = _unquote(value)
    except FileNotFoundError:
        pass
    except OSError:
        pass
    return values


def read_ssh_status():
    return read_env_file(
        SSH_STATUS_FILE,
        {
            "OURBOX_INSTALLER_SSH_STATUS": "pending",
            "OURBOX_INSTALLER_SSH_USER": "ourbox-installer",
            "OURBOX_INSTALLER_SSH_MODE": "both",
            "OURBOX_INSTALLER_SSH_ALLOW_ROOT": "0",
            "OURBOX_INSTALLER_SSH_PASSWORD_STATE": "disabled",
            "OURBOX_INSTALLER_SSH_KEY_STATE": "disabled",
        },
    )


def load_monitor_settings():
    global BROADCAST_ADDR, BROADCAST_PORT

    settings = read_env_file(
        DEFAULTS_FILE,
        {
            "OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR": DEFAULT_BROADCAST_ADDR,
            "OURBOX_INSTALLER_MONITOR_BROADCAST_PORT": str(DEFAULT_BROADCAST_PORT),
        },
    )

    addr = settings.get("OURBOX_INSTALLER_MONITOR_BROADCAST_ADDR", DEFAULT_BROADCAST_ADDR).strip()
    BROADCAST_ADDR = addr or DEFAULT_BROADCAST_ADDR

    try:
        port = int(settings.get("OURBOX_INSTALLER_MONITOR_BROADCAST_PORT", str(DEFAULT_BROADCAST_PORT)))
    except ValueError:
        port = DEFAULT_BROADCAST_PORT
    if not 1 <= port <= 65535:
        port = DEFAULT_BROADCAST_PORT
    BROADCAST_PORT = port


def describe_ssh(status, ip: str):
    state = status.get("OURBOX_INSTALLER_SSH_STATUS", "pending")
    user = status.get("OURBOX_INSTALLER_SSH_USER", "ourbox-installer")
    mode = status.get("OURBOX_INSTALLER_SSH_MODE", "both")
    password_state = status.get("OURBOX_INSTALLER_SSH_PASSWORD_STATE", "disabled")
    key_state = status.get("OURBOX_INSTALLER_SSH_KEY_STATE", "disabled")

    detail_parts = []
    if state == "ready":
        if password_state == "generated-console-only":
            detail_parts.append("password shown on attached console")
        elif password_state == "configured-hash":
            detail_parts.append("preconfigured password required")

        if key_state == "configured":
            if mode == "key":
                detail_parts.append("authorized key required")
            else:
                detail_parts.append("authorized keys accepted")
        elif mode == "key":
            detail_parts.append("authorized key required")

        detail = "; ".join(detail_parts)
        if detail:
            return f"ssh {user}@{ip}", detail
        return f"ssh {user}@{ip}", "live installer SSH ready"

    if state == "disabled":
        return "disabled by media config", "installer SSH is intentionally disabled"

    if state == "error":
        return "unavailable; see installer log", "installer SSH setup failed"

    return f"pending (mode={mode})", "installer is still preparing SSH"


# ---------------------------------------------------------------------------
# UDP broadcaster
# ---------------------------------------------------------------------------

class UDPBroadcaster:
    def __init__(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    def send(self, msg: str):
        try:
            self._sock.sendto(
                msg.encode("utf-8", "replace"),
                (BROADCAST_ADDR, BROADCAST_PORT),
            )
        except OSError:
            pass

    def announce(self, ip: str, hostname: str):
        sep = "=" * 62
        ssh_cmd, ssh_detail = describe_ssh(read_ssh_status(), ip)
        lines = [
            "",
            sep,
            "OurBox Woodbox Installer",
            f"  Host    : {hostname}.local  ({ip})",
            f"  SSH     : {ssh_cmd}",
            f"            {ssh_detail}",
            f"  Browser : http://{ip}:{HTTP_PORT}/",
            f"  UDP     : listening on this port {BROADCAST_PORT}",
            sep,
            "",
        ]
        for line in lines:
            self.send(line + "\n")

    def tail_forever(self):
        pos = 0
        while True:
            try:
                size = os.path.getsize(LOG_FILE)
                if size > pos:
                    with open(LOG_FILE, "r", errors="replace") as f:
                        f.seek(pos)
                        chunk = f.read(min(8192, size - pos))
                        if chunk:
                            for line in chunk.splitlines(keepends=True):
                                self.send(line)
                            pos = f.tell()
            except (FileNotFoundError, OSError):
                pass
            time.sleep(0.1)


# ---------------------------------------------------------------------------
# HTTP log server
# ---------------------------------------------------------------------------

def _make_handler(hostname: str):
    class InstallerHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass  # suppress HTTP access log noise in the installer output

        def do_GET(self):
            ip = get_ip()
            ssh_cmd, ssh_detail = describe_ssh(read_ssh_status(), ip)
            try:
                with open(LOG_FILE, "r", errors="replace") as f:
                    log_text = f.read()
            except FileNotFoundError:
                log_text = "(installer log not yet available — check back in a moment)"

            safe_log = html.escape(log_text)
            body = f"""\
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="3">
  <title>OurBox Installer — {hostname}</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ background: #0a0a0a; color: #ccffcc;
           font-family: 'Courier New', Courier, monospace; font-size: 13px; }}
    header {{ background: #111; border-bottom: 1px solid #333; padding: 0.75em 1em; }}
    header h1 {{ color: #ffff66; font-size: 1em; margin-bottom: 0.3em; }}
    header p {{ color: #aaa; font-size: 0.9em; margin: 0.15em 0; }}
    header code {{ color: #88ccff; }}
    main {{ padding: 1em; }}
    pre {{ white-space: pre-wrap; word-break: break-all; line-height: 1.45; }}
  </style>
</head>
<body>
  <header>
    <h1>OurBox Woodbox Installer &mdash; {hostname} ({ip})</h1>
    <p>SSH: <code>{html.escape(ssh_cmd)}</code></p>
    <p>{html.escape(ssh_detail)}</p>
    <p>UDP broadcast on port {BROADCAST_PORT} &nbsp;|&nbsp; Page auto-refreshes every 3 s</p>
  </header>
  <main><pre>{safe_log}</pre></main>
</body>
</html>""".encode("utf-8")

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return InstallerHandler


def _start_http_server(hostname: str):
    try:
        socketserver.TCPServer.allow_reuse_address = True
        handler = _make_handler(hostname)
        with socketserver.TCPServer(("", HTTP_PORT), handler) as httpd:
            httpd.serve_forever()
    except OSError as exc:
        _log(f"[monitor] HTTP server could not start: {exc}")


def _log(msg: str):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(msg + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Avahi / mDNS advertisement
# ---------------------------------------------------------------------------

def _advertise_mdns(hostname: str, ip: str):
    """Try to publish an SSH + HTTP mDNS record via avahi-publish if available."""
    import subprocess
    try:
        subprocess.Popen(
            [
                "avahi-publish", "-s",
                f"OurBox Woodbox Installer ({hostname})",
                "_ssh._tcp", str(22),
                f"ip={ip}", f"http=http://{ip}:{HTTP_PORT}/",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (FileNotFoundError, OSError):
        pass  # avahi-publish not available — mDNS advertisement skipped


def _wait_for_ssh_ready_and_advertise(hostname: str):
    while True:
        status = read_ssh_status()
        ssh_state = status.get("OURBOX_INSTALLER_SSH_STATUS", "pending")
        if ssh_state == "ready":
            _advertise_mdns(hostname, get_ip())
            return
        if ssh_state in ("disabled", "error"):
            return
        time.sleep(1)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    hostname = socket.gethostname()
    load_monitor_settings()

    _log(f"[monitor] starting — host={hostname}")

    ip = wait_for_network(timeout=30)
    _log(f"[monitor] network ready — ip={ip}")
    _log(f"[monitor] UDP broadcast on {BROADCAST_ADDR}:{BROADCAST_PORT}")
    _log(f"[monitor] HTTP log at http://{ip}:{HTTP_PORT}/")
    ssh_cmd, ssh_detail = describe_ssh(read_ssh_status(), ip)
    _log(f"[monitor] SSH: {ssh_cmd} ({ssh_detail})")

    broadcaster = UDPBroadcaster()

    # HTTP server in background thread
    threading.Thread(
        target=_start_http_server, args=(hostname,), daemon=True
    ).start()

    # mDNS advertisement (best-effort)
    threading.Thread(
        target=_wait_for_ssh_ready_and_advertise, args=(hostname,), daemon=True
    ).start()

    # Initial announce burst so late listeners catch it
    broadcaster.announce(ip, hostname)

    # Periodic re-announce so listeners that start later still discover us
    def _reannounce():
        while True:
            time.sleep(REANNOUNCE_INTERVAL)
            broadcaster.announce(get_ip(), hostname)

    threading.Thread(target=_reannounce, daemon=True).start()

    # Tail log forever and broadcast each line (main thread)
    broadcaster.tail_forever()


if __name__ == "__main__":
    main()
