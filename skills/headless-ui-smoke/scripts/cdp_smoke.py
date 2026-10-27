#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["websockets>=13"]
# ///
"""Load a page in headless Chrome over the DevTools protocol and report what broke.

    uv run cdp_smoke.py http://127.0.0.1:3000/ --wait-for "document.querySelector('#app .row')" \
        --shot /tmp/home.png --expect-text "Dashboard"

Visits each URL in order (one tab, one profile: a first URL may sign in for the next), waits
until the page is really rendered, runs any --eval snippets, saves a screenshot, and prints every
page error: uncaught exceptions, console.error, failed requests. Exit code 1 when the page
reported an error or an expectation failed, 2 when Chrome could not be driven at all.

Why not `chrome --headless --dump-dom/--screenshot`: both fire at the load event, before a
client-rendered app has fetched anything; --virtual-time-budget hangs on pages with timers or
open connections; and on macOS headless Chrome does not exit by itself.
"""
from __future__ import annotations

import argparse
import base64
import contextlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

CHROME_CANDIDATES = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge",
    "chrome", "msedge",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
)


def _windows_candidates() -> list[str]:
    """Chrome and Edge install per machine *or* per user on Windows, on whichever drive."""
    found = []
    for variable in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
        base = os.environ.get(variable)
        if base:
            found.append(str(Path(base) / "Google" / "Chrome" / "Application" / "chrome.exe"))
            found.append(str(Path(base) / "Microsoft" / "Edge" / "Application" / "msedge.exe"))
    return found


def find_chrome(explicit: str | None) -> str:
    candidates = [explicit or "", os.environ.get("CHROME_PATH", ""), *_windows_candidates(), *CHROME_CANDIDATES]
    for candidate in candidates:
        if not candidate:
            continue
        path = candidate if Path(candidate).is_file() else shutil.which(candidate)
        if path:
            return str(path)
    raise SystemExit("cdp_smoke: no Chrome / Chromium / Edge found — pass --chrome or set CHROME_PATH")


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Browser:
    def __init__(self, chrome: str, profile: Path, size: tuple[int, int], scale: float, no_sandbox: bool) -> None:
        from websockets.sync.client import connect

        port = free_port()
        argv = [
            chrome, "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
            f"--user-data-dir={profile}", f"--remote-debugging-port={port}",
            f"--window-size={size[0]},{size[1]}", "--hide-scrollbars",
        ]
        if no_sandbox:  # containers / CI running as root
            argv.append("--no-sandbox")
        # Chrome's stderr goes to a temp file (a pipe nobody reads could fill and block it): it says
        # why Chrome died when it exits before opening its DevTools port.
        self._stderr = tempfile.TemporaryFile()
        self._process = subprocess.Popen([*argv, "about:blank"], stdout=subprocess.DEVNULL, stderr=self._stderr)
        self._stack = contextlib.ExitStack()
        self._socket = None
        self._next_id = 0
        self.errors: list[str] = []
        target = None
        deadline = time.monotonic() + 30
        while target is None and time.monotonic() < deadline and self._process.poll() is None:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=1) as response:
                    pages = [t for t in json.loads(response.read()) if t.get("type") == "page"]
                target = pages[0]["webSocketDebuggerUrl"] if pages else None
            except OSError:
                time.sleep(0.2)
        if target is None:
            code = self._process.poll()
            self._stderr.seek(0)
            last = [line for line in self._stderr.read().decode(errors="replace").splitlines() if line.strip()][-1:]
            self.close()
            why = f" (Chrome exited with code {code})" if code is not None else " in 30 s"
            raise SystemExit(f"cdp_smoke: Chrome did not open its DevTools port{why}" + (f": {last[0][:300]}" if last else ""))
        self._socket = self._stack.enter_context(connect(target, max_size=256 * 1024 * 1024))
        for method in ("Runtime.enable", "Page.enable", "Log.enable", "Network.enable"):
            self.call(method)
        self.call("Emulation.setDeviceMetricsOverride", {
            "width": size[0], "height": size[1], "deviceScaleFactor": scale, "mobile": False,
        })

    def _note(self, message: dict) -> None:
        method, params = message.get("method"), message.get("params") or {}
        if method == "Runtime.exceptionThrown":
            details = params.get("exceptionDetails") or {}
            text = (details.get("exception") or {}).get("description") or details.get("text") or "exception"
            self.errors.append(f"uncaught: {text.splitlines()[0]} ({details.get('url', '')}:{details.get('lineNumber', '')})")
        elif method == "Runtime.consoleAPICalled" and params.get("type") == "error":
            parts = [str(arg.get("value") or arg.get("description") or "") for arg in params.get("args") or []]
            self.errors.append("console.error: " + " ".join(parts))
        elif method == "Log.entryAdded":
            entry = params.get("entry") or {}
            if entry.get("level") == "error":
                self.errors.append(f"{entry.get('source')}: {entry.get('text')} {entry.get('url') or ''}".strip())
        elif method == "Network.loadingFailed" and not params.get("canceled"):
            self.errors.append(f"request failed: {params.get('errorText')} ({params.get('type')})")

    def call(self, method: str, params: dict | None = None, timeout: float = 30) -> dict:
        self._next_id += 1
        call_id = self._next_id
        self._socket.send(json.dumps({"id": call_id, "method": method, "params": params or {}}))
        while True:
            message = json.loads(self._socket.recv(timeout=timeout))
            if message.get("id") == call_id:
                if "error" in message:
                    raise RuntimeError(f"{method}: {message['error']}")
                return message.get("result") or {}
            self._note(message)

    def settle(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while (remaining := deadline - time.monotonic()) > 0:
            try:
                self._note(json.loads(self._socket.recv(timeout=remaining)))
            except TimeoutError:
                return

    def evaluate(self, expression: str):
        """Run JavaScript in the page. A promise is awaited: end a fire-and-forget call with
        `; 0`, or the call returns only when the promise settles (a long fetch, a whole stream)."""
        result = self.call("Runtime.evaluate", {"expression": expression, "awaitPromise": True, "returnByValue": True})
        if result.get("exceptionDetails"):
            text = (result["exceptionDetails"].get("exception") or {}).get("description", "evaluate failed")
            self.errors.append(f"evaluate: {text.splitlines()[0]}")
        return (result.get("result") or {}).get("value")

    def wait_for(self, expression: str, timeout: float) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = self.call("Runtime.evaluate", {"expression": f"Boolean({expression})", "returnByValue": True})
            if (result.get("result") or {}).get("value") is True:
                return True
            self.settle(0.25)
        return False

    def screenshot(self, path: Path, full_page: bool) -> None:
        params: dict = {"format": "png"}
        if full_page:
            params["captureBeyondViewport"] = True
            metrics = self.call("Page.getLayoutMetrics").get("cssContentSize") or {}
            if metrics:
                params["clip"] = {"x": 0, "y": 0, "width": metrics["width"], "height": metrics["height"], "scale": 1}
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(base64.b64decode(self.call("Page.captureScreenshot", params)["data"]))

    def close(self) -> None:
        with contextlib.suppress(Exception):
            self._stack.close()
        self._process.terminate()
        with contextlib.suppress(subprocess.TimeoutExpired):
            self._process.wait(timeout=10)
        if self._process.poll() is None:
            self._process.kill()
        self._stderr.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("urls", nargs="+", help="pages to visit, in order, in one tab (a first URL may sign in for the next)")
    parser.add_argument("--wait-for", metavar="JS", help="JavaScript condition that means 'rendered' (polled after the last URL)")
    parser.add_argument("--settle", type=float, default=1.5, help="seconds to let each page run after it loads (default 1.5)")
    parser.add_argument("--timeout", type=float, default=20, help="seconds --wait-for may take (default 20)")
    parser.add_argument("--eval", action="append", default=[], metavar="JS", help="JavaScript to run before the screenshot (repeatable; end fire-and-forget calls with '; 0')")
    parser.add_argument("--shot", type=Path, help="save a PNG screenshot here")
    parser.add_argument("--full-page", action="store_true", help="capture the whole document, not only the viewport")
    parser.add_argument("--size", default="1400x900", help="viewport WxH (default 1400x900)")
    parser.add_argument("--scale", type=float, default=2, help="device scale factor (default 2: text stays readable in the PNG)")
    parser.add_argument("--dump-dom", type=Path, help="save the rendered DOM here")
    parser.add_argument("--expect-text", action="append", default=[], help="fail unless the rendered page contains this (repeatable)")
    parser.add_argument("--forbid-text", action="append", default=[], help="fail if the rendered page contains this (repeatable)")
    parser.add_argument("--ignore", action="append", default=[], metavar="REGEX", help="page errors to ignore, e.g. 'favicon' (repeatable)")
    parser.add_argument("--profile", type=Path, help="Chrome profile dir to reuse (keeps cookies between runs); default: a temp one")
    parser.add_argument("--chrome", help="browser binary (default: search the usual places, or $CHROME_PATH)")
    parser.add_argument("--no-sandbox", action="store_true", help="needed in containers / CI running as root")
    args = parser.parse_args()

    try:
        width, height = (int(part) for part in args.size.lower().split("x", 1))
    except ValueError:
        raise SystemExit("cdp_smoke: --size is WIDTHxHEIGHT, e.g. 1400x900") from None
    profile = args.profile or Path(tempfile.mkdtemp(prefix="cdp-smoke-profile-"))
    failures: list[str] = []
    try:
        browser = Browser(find_chrome(args.chrome), profile, (width, height), args.scale, args.no_sandbox)
    except (OSError, RuntimeError) as exc:
        print(f"cdp_smoke: could not drive Chrome: {exc}", file=sys.stderr)
        return 2
    try:
        for url in args.urls:
            browser.call("Page.navigate", {"url": url})
            browser.settle(args.settle)
        if args.wait_for and not browser.wait_for(args.wait_for, args.timeout):
            failures.append(f"never became true within {args.timeout:g}s: {args.wait_for}")
        for expression in args.eval:
            browser.evaluate(expression)
            browser.settle(args.settle)
        dom = str(browser.evaluate("document.documentElement.outerHTML") or "")
        text = str(browser.evaluate("document.body ? document.body.innerText : ''") or "")
        if args.shot:
            browser.screenshot(args.shot, args.full_page)
        if args.dump_dom:
            args.dump_dom.write_text(dom, encoding="utf-8")
        ignored = [re.compile(pattern) for pattern in args.ignore]
        failures += [error for error in dict.fromkeys(browser.errors) if not any(p.search(error) for p in ignored)]
        failures += [f"expected text not on the page: {needle!r}" for needle in args.expect_text if needle not in text and needle not in dom]
        failures += [f"forbidden text is on the page: {needle!r}" for needle in args.forbid_text if needle in text]
    finally:
        browser.close()
        if args.profile is None:
            shutil.rmtree(profile, ignore_errors=True)
    if args.shot:
        print(f"screenshot: {args.shot}")
    for failure in failures:
        print(f"FAIL {failure}")
    print("OK — no page errors" if not failures else f"{len(failures)} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
