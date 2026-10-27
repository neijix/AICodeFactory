"""`aicf projects`: write the projects page, print a summary, optionally open it."""

from __future__ import annotations

import json
import os
import sys
import webbrowser
from datetime import datetime
from pathlib import Path

from engine.projects_page.collect import (
    DoctorError, build_projects, build_skills, local_skills, parse_doctor, run_doctor, skill_catalog,
    summary,
)
from engine.projects_page.render import render_html, render_text
from engine.projects_page.usage import ProjectResolver, config_dirs, scan

HELP = """Usage: aicf projects [--open] [--out <file>] [--json] [--no-usage] [--doctor-json <file>]

Writes one HTML page about every project of the code root: which are bootstrapped, which still
need it (and the command that does it), and which skills each one uses. Prints a one-line-per-
project summary and the page's path. Check-only: no project is touched.

  --open                open the page in the default browser
  --out <file>          write the page there (default: ~/.cache/aicf/projects.html,
                        %LOCALAPPDATA%\\aicf\\projects.html on Windows)
  --json                print the page's data as JSON instead of the summary (no page written)
  --no-usage            skip reading Claude Code transcripts (no skill-use counts)
  --doctor-json <file>  read a saved `aicf doctor --json` document instead of running doctor

Skill use is counted from this machine's Claude Code transcripts (~/.claude/projects and every
profile in ~/.claude-profiles); they are read locally and never sent anywhere.
"""


def default_out(home: Path) -> Path:
    if os.environ.get("XDG_CACHE_HOME"):
        base = Path(os.environ["XDG_CACHE_HOME"])
    elif os.name == "nt" and os.environ.get("LOCALAPPDATA"):
        base = Path(os.environ["LOCALAPPDATA"])
    else:
        base = home / ".cache"
    return base / "aicf" / "projects.html"


def parse_args(argv: list[str]) -> dict:
    opts = {"open": False, "out": None, "json": False, "usage": True, "doctor_json": None}
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg in ("-h", "--help"):
            opts["help"] = True
        elif arg == "--open":
            opts["open"] = True
        elif arg == "--json":
            opts["json"] = True
        elif arg == "--no-usage":
            opts["usage"] = False
        elif arg in ("--out", "--doctor-json") and args:
            opts[arg[2:].replace("-", "_")] = args.pop(0)
        else:
            raise ValueError(f"unknown option or missing value: {arg}")
    return opts


def collect(brain: Path, home: Path, opts: dict) -> dict:
    if opts["doctor_json"]:
        doctor = parse_doctor(Path(opts["doctor_json"]).read_text(encoding="utf-8-sig"))
    else:
        doctor = run_doctor(brain)
    code_root = Path(str(doctor.get("code_root") or brain.parent))
    catalog = skill_catalog(brain)
    usage, orphans, dirs = {}, 0, []
    if opts["usage"]:
        names = [str(p.get("name")) for p in doctor["projects"] if isinstance(p, dict)]
        known = set(catalog)
        for p in doctor["projects"]:
            known.update(local_skills(Path(str(p.get("path", "")))))
        dirs = config_dirs(home)
        usage, orphans = scan(dirs, ProjectResolver(code_root, names), known)
    projects = build_projects(doctor, usage)
    if not opts["usage"]:
        note = "Skill use not read (--no-usage)."
    else:
        note = (f"Skill use: Skill tool calls and /skill prompts in Claude Code transcripts under "
                f"{', '.join(str(d) for d in dirs) or 'no config dir'}. Other agents keep no such log. "
                f"{orphans} use(s) from sessions outside this code root's projects are not shown.")
    return {
        "code_root": str(code_root),
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "summary": summary(projects),
        "projects": projects,
        "skills": build_skills(catalog, projects),
        "usage_note": note,
    }


def main(argv: list[str], brain: Path) -> int:
    try:
        opts = parse_args(argv)
    except ValueError as exc:
        print(f"aicf projects: {exc}", file=sys.stderr)
        print(HELP, file=sys.stderr)
        return 2
    if opts.get("help"):
        print(HELP, end="")
        return 0
    home = Path(os.path.expanduser("~"))
    try:
        data = collect(brain, home, opts)
    except (DoctorError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    if opts["json"]:
        print(json.dumps(data, indent=2))
        return 0
    out = Path(opts["out"]) if opts["out"] else default_out(home)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(render_html(data))
    print(render_text(data))
    print(f"Page: {out}")
    if opts["open"]:
        webbrowser.open(out.resolve().as_uri())
    return 0
