"""`aicf config`: serve the settings page on 127.0.0.1 until it is closed or left idle."""

from __future__ import annotations

import json
import secrets
import sys
import threading
import time
import webbrowser
from pathlib import Path

from engine.config_ui import actions
from engine.config_ui.server import ConfigServer
from engine.factory_env.schema import ConfigError

HELP = """Usage: aicf config [--no-open] [--port <n>] [--idle <minutes>] [--json]

Opens a settings page in the browser, served from this machine only (127.0.0.1, a key made for
this run in the URL). On it:

  - the code roots: the folders whose projects AICodeFactory serves (add one: it gets
    .ai-root/environment.json) and their label (work makes a work environment);
  - your personal skills: the personal overlay folder (~/.ai-template-overlay-dir);
  - per root, its own skills folders (on only in its projects) and a check of its projects
    (aicf doctor --json: which are set up for AICodeFactory, and what the others need);
  - each skill on or off, and the agent of each workflow step, per root;
  - a scan of your folders for skills, each found folder one click from being added.

Changes are written at once, through the same code as `factory-env.py set`. Skills land in
every tool at the next session start. Ctrl+C, the page's Close button or --idle minutes without
a request stop the server.

  --no-open          print the URL, do not open a browser
  --port <n>         listen on this port (default: a free one)
  --idle <minutes>   stop after this long without a request (default: 30)
  --json             print the page's data as JSON and exit (no server)
"""


def parse_args(argv: list[str]) -> dict:
    opts = {"open": True, "port": 0, "idle": 30.0, "json": False}
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg in ("-h", "--help"):
            opts["help"] = True
        elif arg == "--no-open":
            opts["open"] = False
        elif arg == "--json":
            opts["json"] = True
        elif arg in ("--port", "--idle") and args:
            opts[arg[2:]] = _number(arg, args.pop(0))
        else:
            raise ValueError(f"unknown option or missing value: {arg}")
    return opts


def _number(flag: str, text: str) -> float:
    try:
        value = float(text) if flag == "--idle" else int(text)
    except ValueError:
        raise ValueError(f"{flag} needs a number, not {text!r}") from None
    if value < 0 or (flag == "--port" and value > 65535):
        raise ValueError(f"{flag} is out of range: {text}")
    return value


def main(argv: list[str], brain: Path) -> int:
    try:
        opts = parse_args(argv)
    except ValueError as exc:
        print(f"aicf config: {exc}", file=sys.stderr)
        print(HELP, file=sys.stderr, end="")
        return 2
    if opts.get("help"):
        print(HELP, end="")
        return 0
    if opts["json"]:
        try:
            print(json.dumps(actions.state(brain), indent=2, ensure_ascii=False))
        except ConfigError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        return 0
    return serve(brain, opts)


def serve(brain: Path, opts: dict) -> int:
    try:
        server = ConfigServer(brain, secrets.token_urlsafe(32), int(opts["port"]))
    except OSError as exc:
        print(f"ERROR: cannot listen on 127.0.0.1:{opts['port']} — {exc.strerror or exc}; pick another --port", file=sys.stderr)
        return 1
    print(f"AICodeFactory settings: {server.url}")
    print("Ctrl+C or the page's Close button stops it.")
    sys.stdout.flush()
    threading.Thread(target=_idle_watch, args=(server, opts["idle"] * 60), daemon=True).start()
    if opts["open"]:
        webbrowser.open(server.url)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    print("aicf config: stopped")
    return 0


def _idle_watch(server: ConfigServer, limit: float) -> None:
    if limit <= 0:
        return
    while True:
        time.sleep(min(limit, 15))
        if time.monotonic() - server.last_seen > limit:
            print(f"aicf config: no request for {limit / 60:g} minutes — stopping")
            server.shutdown()
            return
