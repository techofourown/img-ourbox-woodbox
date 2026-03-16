#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_SCRIPT="${ROOT}/installer/ourbox/rootfs/usr/local/sbin/ourbox-status"
MDNS_SCRIPT="${ROOT}/installer/ourbox/rootfs/usr/local/sbin/ourbox-mdns-aliases"
BOOTSTRAP_SCRIPT="${ROOT}/installer/ourbox/rootfs/usr/local/sbin/ourbox-bootstrap"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

SURFACE_FILE="${TMP}/selected-app-surface.json"
PLATFORM_STATE_FILE="${TMP}/platform-contract.env"
PAYLOAD_FILE="${TMP}/app-status.json"
PORT="18080"

cat > "${SURFACE_FILE}" <<'EOF_SURFACE'
{
  "schema": 1,
  "kind": "ourbox-selected-app-surface",
  "application_catalog_id": "merged--demo-apps--hello-world",
  "application_catalog_name": "Merged Application Catalog",
  "selection_mode": "custom",
  "box_host": "ourbox-woodbox.local",
  "default_backend_app_id": "techofourown/landing",
  "landing_selected": true,
  "landing_app_id": "techofourown/landing",
  "status_route": {
    "host": "ourbox-woodbox.local",
    "path": "/_ourbox/app-status.json",
    "path_type": "Exact",
    "service_name": "landing-status",
    "service_port": 8080,
    "expected_status": 200,
    "body_marker": "ourbox-landing-status",
    "description": "landing-app-status"
  },
  "apps": [
    {
      "id": "techofourown/landing",
      "display_name": "Landing",
      "description": "Default landing page.",
      "host": "ourbox-woodbox.local",
      "path": "/",
      "url": "http://ourbox-woodbox.local/",
      "service_name": "landing",
      "service_port": 80,
      "renderer": "landing",
      "default_backend": true,
      "show_on_landing": false,
      "publish_mdns_alias": false,
      "include_in_status": false
    },
    {
      "id": "techofourown/hello-world",
      "display_name": "Hello World",
      "description": "Small hello-world app.",
      "host": "hello.ourbox-woodbox.local",
      "path": "/",
      "url": "http://hello.ourbox-woodbox.local/",
      "service_name": "hello-world",
      "service_port": 80,
      "renderer": "hello-world",
      "default_backend": false,
      "show_on_landing": true,
      "publish_mdns_alias": true,
      "include_in_status": true
    },
    {
      "id": "techofourown/ourbox-chat",
      "display_name": "OurBox Chat",
      "description": "Local chat UI.",
      "host": "chat.ourbox-woodbox.local",
      "path": "/",
      "url": "http://chat.ourbox-woodbox.local/",
      "service_name": "ourbox-chat",
      "service_port": 8080,
      "renderer": "static-http",
      "default_backend": false,
      "show_on_landing": true,
      "publish_mdns_alias": true,
      "include_in_status": true
    },
    {
      "id": "techofourown/todo-bloom",
      "display_name": "Todo Bloom",
      "description": "Static todo app.",
      "host": "todo.ourbox-woodbox.local",
      "path": "/",
      "url": "http://todo.ourbox-woodbox.local/",
      "service_name": "todo-bloom",
      "service_port": 80,
      "renderer": "todo-bloom",
      "default_backend": false,
      "show_on_landing": true,
      "publish_mdns_alias": true,
      "include_in_status": true
    },
    {
      "id": "thirdparty/dufs",
      "display_name": "Dufs",
      "description": "File browser.",
      "host": "files.ourbox-woodbox.local",
      "path": "/",
      "url": "http://files.ourbox-woodbox.local/",
      "service_name": "dufs",
      "service_port": 5000,
      "renderer": "dufs",
      "default_backend": false,
      "show_on_landing": true,
      "publish_mdns_alias": true,
      "include_in_status": true
    },
    {
      "id": "thirdparty/flatnotes",
      "display_name": "Flatnotes",
      "description": "Notes app.",
      "host": "notes.ourbox-woodbox.local",
      "path": "/",
      "url": "http://notes.ourbox-woodbox.local/",
      "service_name": "flatnotes",
      "service_port": 8080,
      "renderer": "flatnotes",
      "default_backend": false,
      "show_on_landing": true,
      "publish_mdns_alias": true,
      "include_in_status": true
    }
  ]
}
EOF_SURFACE

cat > "${PLATFORM_STATE_FILE}" <<'EOF_PLATFORM'
BOX_HOST=ourbox-woodbox.local
EOF_PLATFORM

cat > "${PAYLOAD_FILE}" <<'EOF_PAYLOAD'
{
  "schema": 1,
  "kind": "ourbox-landing-status",
  "checked_at": "2026-03-16T12:00:00Z",
  "cluster_status": "ok",
  "apps": [
    {"id": "techofourown/hello-world", "status": "healthy"},
    {"id": "techofourown/ourbox-chat", "status": "healthy"},
    {"id": "techofourown/todo-bloom", "status": "healthy"},
    {"id": "thirdparty/dufs", "status": "healthy"},
    {"id": "thirdparty/flatnotes", "status": "healthy"}
  ]
}
EOF_PAYLOAD

python3 - <<'PY' "${PORT}" "${PAYLOAD_FILE}" >/dev/null 2>&1 &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

port = int(sys.argv[1])
payload = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path != "/_ourbox/app-status.json":
            self.send_response(404)
            self.end_headers()
            return
        body = json.dumps(payload, sort_keys=True).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):  # noqa: A003
        return


ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
SERVER_PID=$!
trap 'kill "${SERVER_PID}" 2>/dev/null || true; rm -rf "${TMP}"' EXIT
sleep 1

status_fragment="$(
  awk '
    /^was_ready=false$/ { exit }
    { print }
  ' "${STATUS_SCRIPT}"
)"

mdns_fragment="$(
  awk '
    /^ALIASES=""$/ { exit }
    { print }
  ' "${MDNS_SCRIPT}"
)"

OURBOX_STATUS_RUN_DIR='${TMP}/run' bash -c "${status_fragment}
APP_SURFACE_FILE='${SURFACE_FILE}'
PLATFORM_STATE_FILE='${PLATFORM_STATE_FILE}'
STATUS_BASE_URL='http://127.0.0.1:${PORT}'
surface_exists
[[ \"\$(surface_landing_selected >/dev/null 2>&1; echo \$?)\" == \"0\" ]]
mapfile -t urls < <(surface_app_urls)
[[ \"\${urls[0]}\" == 'http://ourbox-woodbox.local/' ]]
[[ \"\${urls[1]}\" == 'http://hello.ourbox-woodbox.local/' ]]
mapfile -t mdns_hosts < <(surface_mdns_hosts)
[[ \"\${#mdns_hosts[@]}\" == '5' ]]
[[ \"\${mdns_hosts[0]}\" == 'hello.ourbox-woodbox.local' ]]
summary=\"\$(check_app_status_endpoint 'ourbox-woodbox.local')\"
[[ \"\${summary}\" == '5/5 apps healthy' ]]
" || {
  echo "runtime app surface status smoke failed" >&2
  exit 1
}

bash -c "${mdns_fragment}
APP_SURFACE_FILE='${SURFACE_FILE}'
mapfile -t aliases < <(surface_aliases)
[[ \"\${#aliases[@]}\" == '5' ]]
[[ \"\${aliases[0]}\" == 'hello.ourbox-woodbox.local' ]]
[[ \"\${aliases[4]}\" == 'notes.ourbox-woodbox.local' ]]
" || {
  echo "runtime app surface mdns smoke failed" >&2
  exit 1
}

grep -Fq 'selected-app-surface.json' "${BOOTSTRAP_SCRIPT}" || {
  echo "bootstrap does not persist selected-app-surface.json" >&2
  exit 1
}
grep -Fq 'systemctl restart ourbox-mdns-aliases.service ourbox-status.service' "${BOOTSTRAP_SCRIPT}" || {
  echo "bootstrap does not restart runtime surface consumers after render" >&2
  exit 1
}

printf '[%s] runtime app surface smoke passed\n' "$(date -Is)"
