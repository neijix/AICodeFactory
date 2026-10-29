"""The page's HTTP server. Local is not trusted: every other dev server and page on this machine
can reach 127.0.0.1, so the server proves who is calling.

- It listens on 127.0.0.1 only, on a port picked per run.
- A secret made per run is in the URL the CLI opens. The page is served only to a request that
  carries it, and every API call must send it back in `X-AICF-Token` (a cross-site page can
  neither read it nor set that header without a CORS preflight, which is never answered).
- `Host` must be exactly 127.0.0.1:<port> (no DNS rebinding); a present `Origin` must be this
  server's own; `Sec-Fetch-Site`, when sent, must be same-origin or none.
- Responses are never cached and the page runs under a CSP that allows only this server.

One thread per connection: a browser keeps idle keep-alive sockets open (and opens spare ones
ahead of time), and a single-threaded server would wait on one of them while the page's script
or API call hangs on another. The actions themselves run one at a time (they write and commit).
"""

from __future__ import annotations

import hmac
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from engine.config_ui import actions
from engine.factory_env.schema import ConfigError

STATIC = Path(__file__).resolve().parent / "static"
ASSETS = {"/app.js": ("app.js", "text/javascript"), "/app.css": ("app.css", "text/css")}
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; "
       "img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
MAX_BODY = 1 << 20
TOKEN_HEADER = "X-AICF-Token"


class ConfigServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False   # an idle keep-alive socket must not hold up the stop

    def __init__(self, brain: Path, token: str, port: int = 0) -> None:
        super().__init__(("127.0.0.1", port), Handler)
        self.brain = brain
        self.token = token
        self.origin = f"http://127.0.0.1:{self.server_address[1]}"
        self.last_seen = time.monotonic()
        self.lock = threading.Lock()

    @property
    def url(self) -> str:
        return f"{self.origin}/?t={self.token}"

    def stop_soon(self) -> None:
        threading.Thread(target=self.shutdown, daemon=True).start()


class Handler(BaseHTTPRequestHandler):
    server: ConfigServer
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args) -> None:  # noqa: A002 — the base class's name
        return  # the URL carries the secret: never print request lines

    def do_GET(self) -> None:  # noqa: N802 — http.server's naming
        if not self._trusted_caller():
            return
        url = urlsplit(self.path)
        if url.path == "/favicon.ico":
            self._send(204, "image/x-icon", b"")
            return
        if url.path in ASSETS:
            name, kind = ASSETS[url.path]
            self._send(200, kind, (STATIC / name).read_bytes())
            return
        if url.path == "/":
            self._page(parse_qs(url.query).get("t", [""])[0])
            return
        if url.path != "/api/state":
            self._json(404, {"error": "not found"})
        elif self._has_token():
            self._answer(lambda: actions.state(self.server.brain))

    def do_POST(self) -> None:  # noqa: N802
        if not self._trusted_caller() or not self._has_token():
            return
        path = urlsplit(self.path).path
        if not path.startswith("/api/"):
            self._json(404, {"error": "not found"})
            return
        body = self._body()
        if body is None:
            return
        if path == "/api/shutdown":
            self._json(200, {"ok": True})
            self.server.stop_soon()
            return
        self._answer(lambda: actions.run(self.server.brain, path[len("/api/"):], body))

    def _answer(self, work) -> None:
        """Run one read or action at a time; any failure is a JSON error the page shows, never a
        dropped connection."""
        try:
            with self.server.lock:
                data = work()
        except ConfigError as exc:
            self._json(400, {"error": str(exc)})
        except Exception as exc:  # noqa: BLE001 — the page must see what failed
            self._json(500, {"error": f"unexpected {type(exc).__name__}: {exc} — run aicf config again; report it if it repeats"})
        else:
            self._json(200, data)

    def _trusted_caller(self) -> bool:
        self.server.last_seen = time.monotonic()
        host_ok = self.headers.get("Host", "") == self.server.origin[len("http://"):]
        origin = self.headers.get("Origin")
        origin_ok = origin is None or origin == self.server.origin
        site_ok = self.headers.get("Sec-Fetch-Site") in (None, "same-origin", "none")
        if host_ok and origin_ok and site_ok:
            return True
        self._json(403, {"error": "this page only answers itself — open the URL aicf config printed"})
        return False

    def _has_token(self) -> bool:
        if hmac.compare_digest(self.headers.get(TOKEN_HEADER, ""), self.server.token):
            return True
        self._json(403, {"error": "missing or wrong token — reload the URL aicf config printed"})
        return False

    def _page(self, token: str) -> None:
        if not hmac.compare_digest(token, self.server.token):
            self._send(403, "text/plain; charset=utf-8",
                       b"Open the full URL that `aicf config` printed (it carries this run's key).\n")
            return
        html = (STATIC / "index.html").read_text(encoding="utf-8").replace("__AICF_TOKEN__", self.server.token)
        self._send(200, "text/html; charset=utf-8", html.encode("utf-8"))

    def _body(self) -> dict | None:
        if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
            self._json(415, {"error": "send JSON"})
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY:
            self._json(413, {"error": "request too large"})
            return None
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            body = None
        if not isinstance(body, dict):
            self._json(400, {"error": "the body must be a JSON object"})
            return None
        return body

    def _json(self, status: int, data: dict) -> None:
        self._send(status, "application/json; charset=utf-8", json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def _send(self, status: int, kind: str, payload: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        if kind.startswith("text/html"):
            self.send_header("Content-Security-Policy", CSP)
        self.end_headers()
        self.wfile.write(payload)
