#!/usr/bin/env python3
"""The ui-doctor skill's script against tests/ui-doctor/{bad,good}: every static rule fires on the
bad project at the expected file:line and stays OK on the good one; exit codes and the JSON
contract; --skip. The live half (headless Chrome on the same fixtures over file://) runs when
`uv` and a Chrome / Edge are found, otherwise it prints one SKIP line.
Alone: python3 tests/test-ui-doctor.py. Silent apart from a SKIP note; status 0 when every check holds."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "skills" / "ui-doctor" / "scripts" / "ui_doctor.py"
BAD, GOOD = HERE / "ui-doctor" / "bad", HERE / "ui-doctor" / "good"
fails = []

# rule id -> (status on the bad project, a place it must name)
BAD_STATIC = {
    "html-lang": ("FIX", "index.html:2"), "viewport": ("OK", None), "zoom-blocked": ("FIX", "index.html:5"),
    "title": ("FIX", "index.html:1"), "third-party": ("WARN", "cdn.example.com"),
    "img-alt": ("FIX", "Card.tsx:4"), "img-size": ("WARN", "index.html:12"),
    "button-name": ("FIX", "Card.tsx:5"), "link-name": ("FIX", "index.html:14"),
    "field-label": ("FIX", "only a placeholder"), "click-div": ("FIX", "Card.tsx:3"),
    "tabindex-positive": ("FIX", "tabindex=3"), "paste-blocked": ("FIX", "Card.tsx:6"),
    "outline-none": ("FIX", "style.css:4"), "transition-all": ("WARN", "Card.tsx:5"),
    "layout-animation": ("WARN", "keyframes animate width"), "vh-100": ("WARN", "h-screen"),
    "tiny-font": ("WARN", "style.css:3"), "font-display": ("WARN", "style.css:1"), "select-none": ("OK", None),
    "reduced-motion": ("FIX", None), "color-scheme": ("WARN", None), "theme-color": ("WARN", None),
    "hover-guard": ("WARN", None), "token-sprawl": ("OK", None),
}
# live check (start of its `what`) -> status on the bad page
BAD_LIVE = {
    "the rendered page has a lang": "FIX", "the rendered page has a title": "FIX",
    "text contrast in light mode": "FIX", "buttons and links have an accessible name": "FIX",
    "rendered images have alt": "FIX", "rendered form fields have a label": "FIX",
    "pointer targets": "WARN", "heading levels do not skip": "WARN", "no undefined": "FIX",
    "real ellipsis": "WARN", "no sideways scroll": "FIX", "inputs are 16px+": "WARN",
    "nothing loops forever": "WARN", "focus is visible": "WARN",
}


def check(cond, what, out=""):
    if not cond:
        fails.append(f"{what}\n    {str(out).strip()[:2000]}")


def run(*args, uv=False):
    cmd = ["uv", "run", "-q", str(SCRIPT), *args] if uv else [sys.executable, str(SCRIPT), *args]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout, r.stderr


def report(*args, uv=False):
    code, out, err = run(*args, "--json", uv=uv)
    try:
        return code, json.loads(out), err
    except ValueError:
        check(False, f"--json is not one JSON document: {args}", out + err)
        return code, {"checks": [], "counts": {}}, err


def static_checks():
    code, doc, err = report(str(BAD))
    check(code == 1 and doc.get("ok") is False and doc.get("schema") == 1, "bad project: exit 1, ok false, schema 1", f"{code} {err}")
    rows = {r["rule"]: r for r in doc["checks"] if r.get("rule")}
    for rule, (status, place) in BAD_STATIC.items():
        row = rows.get(rule)
        check(row is not None, f"bad project: no row for rule {rule}")
        if row:
            check(row["status"] == status, f"bad project: {rule} is {row['status']}, expected {status}", row)
            check(place is None or any(place in w for w in row["where"]), f"bad project: {rule} does not name {place}", row["where"])
            check(status == "OK" or row["hint"], f"bad project: {rule} has no hint")
    code, doc, err = report(str(GOOD))
    bad_rows = [r for r in doc["checks"] if r["status"] != "OK"]
    check(code == 0 and doc.get("ok") is True and not bad_rows, "good project: exit 0 and every row OK", bad_rows or err)
    code, out, _ = run(str(BAD))
    check(code == 1 and "== Keyboard" in out and "      -> " in out and "to fix" in out.splitlines()[-1], "text report: sections, hints and a summary line", out)
    check(out.count("== Focus and motion") == 1, "text report: one header per section", out)
    code, doc, _ = report(str(BAD), "--skip", "outline-none", "--skip", "reduced-motion")
    check(not {"outline-none", "reduced-motion"} & {r.get("rule") for r in doc["checks"]}, "--skip leaves the rule out", doc["checks"][:3])
    code, out, err = run("--no-static")
    check(code == 2 and "--url" in err, "--no-static without --url is a usage error (exit 2)", out + err)
    code, out, err = run(str(BAD / "index.html"))
    check(code == 2, "a file instead of a folder is a usage error (exit 2)", out + err)


def browser_found():
    if not shutil.which("uv"):
        return False
    sys.path.insert(0, str(SCRIPT.parent.parent.parent / "headless-ui-smoke" / "scripts"))
    try:
        import cdp_smoke
        cdp_smoke.find_chrome(None)
        return True
    except (ImportError, SystemExit):
        return False


def live_checks():
    extra = ["--no-sandbox"] if sys.platform.startswith("linux") and os.environ.get("CI") else []
    code, doc, err = report("--no-static", "--url", (BAD / "index.html").as_uri(), *extra, uv=True)
    check(code == 1, "live, bad page: exit 1", err)
    rows = doc["checks"]
    for start, status in BAD_LIVE.items():
        row = next((r for r in rows if r["what"].startswith(start)), None)
        check(row is not None and row["status"] == status, f"live, bad page: '{start}' should be {status}", row or err)
    code, doc, err = report(str(GOOD), "--url", (GOOD / "index.html").as_uri(), "--ignore", "ERR_FILE_NOT_FOUND", *extra, uv=True)
    bad_rows = [r for r in doc["checks"] if r["status"] != "OK"]
    check(code == 0 and not bad_rows, "live, good page (light and dark): every row OK", bad_rows or err)


static_checks()
if browser_found():
    live_checks()
else:
    print("SKIP ui-doctor live checks: needs uv and Chrome / Edge")
for f in fails:
    print(f"FAIL {f}")
sys.exit(1 if fails else 0)
