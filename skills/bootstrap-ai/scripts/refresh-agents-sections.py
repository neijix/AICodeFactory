#!/usr/bin/env python3
"""refresh-agents-sections.py — carry template-generic AGENTS.md sections into projects.

AGENTS.md is a living doc owned by each project, so the sync engine never overwrites it.
This script automates the one thing that is safe: for each *generic* section (session start,
checkpoint policy) it compares the project's text against every historical version of
AGENTS.md.template in the template repo's git history. A section identical (modulo trailing whitespace) to some past template
version was never customized, so it is replaced with the current template's section. Anything
customized is left alone and listed as KEPT — decide by hand what to carry over.

*Retired* sections (dropped from the template to save context) go the same way: removed when
the project's text matches a past template version, else left alone and listed as KEPT.

*Scaffold* sections (`## Taste`) belong to the project from day one: one that is missing — a
project bootstrapped before the template had it — gets the template's empty scaffold, inserted
before the next template section the project has, and is never touched again.

With --commit, a project whose AGENTS.md has uncommitted edits is skipped: the commit would
sweep them in. The project's mode (as sync-ai-templates.* reads it: the managed block in
<git-common-dir>/info/exclude, else the legacy .gitignore markers) decides the rest:
- shared: skipped (its AGENTS.md speaks to every contributor);
- private (`--private-layer`): AGENTS.md is excluded from the code repo, the owner's alone, and
  the engine's hidden repo commits it — this script only writes the file, never commits it;
- team: the same, unless the team tracks AGENTS.md — then it is the team's and skipped.
--quiet (the session-start sync's mode) prints one `ai-sync:` line when a project's AGENTS.md
changed and nothing otherwise.

Usage:
  refresh-agents-sections.py [--dry-run] [--commit] [--quiet] <project-dir> [<project-dir> ...]
  refresh-agents-sections.py [--dry-run] [--commit] [--quiet] --all   # every bootstrapped sibling

Needs python3 + git; works on macOS, Linux and Windows. The template repo is located from
this file's position (…/AICodeFactory/skills/bootstrap-ai/scripts).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
TEMPLATE_DIR = HERE.parents[3]  # scripts -> bootstrap-ai -> skills -> repo
TEMPLATE_FILE = "templates/AGENTS.md.template"
# Where it lived before templates/ existed: its history there still counts.
TEMPLATE_FILE_OLD = "AGENTS.md.template"
# Same line sync-ai-templates.* looks for (--shared): the project is cloned by other people.
SHARED_SENTINEL = "# ai-templates: local-only"
# Legacy line sync-ai-templates.* wrote for --private-docs (now --private-layer): private mode.
PRIVATE_DOCS_MARK = "# ai-templates: private AI docs"
# First line of the managed block sync-ai-templates.* keeps in <git-common-dir>/info/exclude:
# it names the project's mode, and wins over the legacy .gitignore markers.
EXCLUDE_MODE_RE = re.compile(r"^# ai-templates: (tracked|private|team|shared)[ \t]*$")
COMMIT_MSG = "docs(agents): refresh generic sections from template"

GENERIC_HEADINGS = [
    "## Session start (do this first, ~10s)",
    "## Post-task checklist — checkpoint policy (every response, no exceptions)",
]
# Dropped from the template (their rules moved into the sections above or into skill
# descriptions): removed from a project only while never customized.
RETIRED_SECTIONS = [
    "## Bootstrap mode — delegate only",
    "## On-demand skills (loaded when relevant — don't duplicate their content here)",
    "## Delegation — spend expensive context on judgment, not mechanics",
    "## Living documents",
]
# Owned by the project: added when missing, never replaced. tests/lint-skills.py checks that
# every heading in both lists is still a line of AGENTS.md.template.
SCAFFOLD_HEADINGS = [
    "## Taste",
]


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True, encoding="utf-8"
    ).stdout


def split_sections(lines: list[str]) -> list[tuple[str, int, int]]:
    """(heading, start, end) per '## ' section; a section ends at the next '## ' heading or a
    bare '---' separator (exclusive). Indices are into `lines`."""
    out: list[tuple[str, int, int]] = []
    start = None
    heading = ""
    for i, raw in enumerate(lines):
        line = raw.rstrip("\r\n")
        is_heading = line.startswith("## ")
        is_rule = line.strip() == "---"
        if start is not None and (is_heading or is_rule):
            out.append((heading, start, i))
            start = None
        if is_heading:
            start, heading = i, line.rstrip()
    if start is not None:
        out.append((heading, start, len(lines)))
    return out


def norm(lines: list[str]) -> tuple[str, ...]:
    body = [l.rstrip() for l in lines]
    while body and not body[-1]:
        body.pop()
    return tuple(body)


def sections_of(text: str) -> dict[str, list[str]]:
    lines = text.splitlines(keepends=True)
    return {h: lines[s:e] for h, s, e in split_sections(lines)}


def template_versions() -> list[str]:
    shas = git(TEMPLATE_DIR, "log", "--format=%H", "--", TEMPLATE_FILE, TEMPLATE_FILE_OLD).split()
    versions = []
    for sha in shas:
        for path in (TEMPLATE_FILE, TEMPLATE_FILE_OLD):
            try:
                versions.append(git(TEMPLATE_DIR, "show", f"{sha}:{path}"))
                break
            except subprocess.CalledProcessError:
                continue
    return versions


def exclude_block_mode(project: Path) -> str:
    """The mode named by the managed block in <git-common-dir>/info/exclude, or '' (no block,
    or not a git work tree)."""
    try:
        if git(project, "rev-parse", "--is-inside-work-tree").strip() != "true":
            return ""
        common = Path(git(project, "rev-parse", "--git-common-dir").strip())
    except (subprocess.CalledProcessError, OSError):
        return ""
    if not common.is_absolute():
        common = project / common
    try:
        lines = (common / "info" / "exclude").read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    for line in lines:
        m = EXCLUDE_MODE_RE.match(line)
        if m:
            return m.group(1)
    return ""


def project_mode(project: Path) -> str:
    """tracked | private | team | shared, read as sync-ai-templates.* reads it: the info/exclude
    block, else the legacy .gitignore markers, else tracked (the registry is not read here)."""
    mode = exclude_block_mode(project)
    if mode:
        return mode
    gitignore = project / ".gitignore"
    ignore_lines = gitignore.read_text(encoding="utf-8", errors="replace").splitlines() if gitignore.is_file() else []
    if PRIVATE_DOCS_MARK in ignore_lines:
        return "private"
    if SHARED_SENTINEL in ignore_lines:
        return "shared"
    return "tracked"


def refresh(project: Path, current: dict[str, list[str]], known: dict[str, set], *,
            dry_run: bool, commit: bool, quiet: bool = False) -> None:
    say = (lambda *_: None) if quiet else print
    agents = project / "AGENTS.md"
    if not agents.is_file() or agents.is_symlink():
        say(f"SKIP     {project.name} (no owned AGENTS.md)")
        return
    mode = project_mode(project)
    if mode == "shared":
        # Other people clone a shared project: its AGENTS.md speaks to every contributor, so the
        # owner's personal generic sections (commit policy, secrets vault, …) must not land there.
        say(f"SKIP     {project.name} (shared project — AGENTS.md is written for every contributor)")
        return
    if mode == "team" and git(project, "ls-files", "--", "AGENTS.md").strip():
        say(f"SKIP     {project.name} (team repo — its tracked AGENTS.md belongs to the team)")
        return
    if mode in ("private", "team"):
        commit = False  # excluded from the code repo; the engine's hidden repo commits it
    if commit and git(project, "status", "--porcelain", "--", "AGENTS.md").strip():
        say(f"SKIP     {project.name} (AGENTS.md has uncommitted edits — commit them, then re-run)")
        return
    raw = agents.read_bytes().decode("utf-8")
    eol = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.splitlines(keepends=True)
    secs = {h: (s, e) for h, s, e in split_sections(lines)}

    updated, kept, missing = [], [], []
    replacements: list[tuple[int, int, list[str]]] = []
    for heading in GENERIC_HEADINGS:
        if heading not in current:
            continue
        cur_norm = norm(current[heading])
        if heading not in secs:
            missing.append(heading)
            continue
        s, e = secs[heading]
        proj_norm = norm(lines[s:e])
        if proj_norm == cur_norm:
            continue
        if proj_norm in known[heading]:
            new_lines = [l.rstrip("\r\n") + eol for l in current[heading]]
            replacements.append((s, e, new_lines))
            updated.append(heading)
        else:
            kept.append(heading)

    removed = []
    for heading in RETIRED_SECTIONS:
        if heading not in secs:
            continue
        s, e = secs[heading]
        if norm(lines[s:e]) in known.get(heading, ()):
            replacements.append((s, e, []))
            removed.append(heading)
        else:
            kept.append(heading)

    added = []
    order = list(current)
    for heading in SCAFFOLD_HEADINGS:
        if heading in secs or heading not in current:
            continue
        anchor = next((secs[h][0] for h in order[order.index(heading) + 1:] if h in secs), None)
        if anchor is None:
            missing.append(heading)
            continue
        # Land above the `---` rule that opens the anchor's group, as in the template.
        j = anchor - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        if j >= 0 and lines[j].strip() == "---":
            anchor = j
        replacements.append((anchor, anchor, [l.rstrip("\r\n") + eol for l in current[heading]]))
        added.append(heading)

    label = lambda hs: ", ".join(h[3:].split(" (")[0].split(" —")[0] for h in hs)
    if not updated and not kept and not missing and not added and not removed:
        say(f"OK       {project.name} (generic sections already current)")
        return
    if updated:
        say(f"{'PLAN' if dry_run else 'UPDATED':8} {project.name}: {label(updated)}")
    if removed:
        say(f"{'PLAN' if dry_run else 'REMOVED':8} {project.name}: {label(removed)} (retired from the template)")
    if added:
        say(f"{'PLAN' if dry_run else 'ADDED':8} {project.name}: {label(added)} (empty scaffold)")
    if kept:
        say(f"KEPT     {project.name}: {label(kept)} (customized — merge by hand if wanted)")
    if missing:
        say(f"MISSING  {project.name}: {label(missing)} (heading not found)")
    if dry_run or not (updated or added or removed):
        return
    if commit:
        gitdir = Path(git(project, "rev-parse", "--absolute-git-dir").strip())
        if (gitdir / "MERGE_HEAD").exists() or (gitdir / "rebase-merge").exists() or (gitdir / "rebase-apply").exists():
            say(f"         {project.name}: merge/rebase in progress — left alone")
            return

    # Bottom-up so earlier indices stay valid; at a shared start line the replacement goes first,
    # then the insertion lands above it.
    for s, e, new_lines in sorted(replacements, key=lambda r: (r[0], r[1]), reverse=True):
        lines[s:e] = new_lines
    agents.write_bytes("".join(lines).encode("utf-8"))

    if commit:
        subprocess.run(["git", "-C", str(project), "add", "--", "AGENTS.md"], check=True)
        subprocess.run(["git", "-C", str(project), "commit", "-q", "-m", COMMIT_MSG, "--", "AGENTS.md"], check=True)
        say(f"         {project.name}: committed")
    if quiet:
        what = "; ".join(x for x in (label(updated), "added " + label(added) if added else "",
                                     "removed " + label(removed) if removed else "") if x)
        print(f"ai-sync: AGENTS.md generic sections refreshed — {what}{' (committed)' if commit else ''}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("projects", nargs="*", type=Path)
    ap.add_argument("--all", action="store_true", help="every bootstrapped sibling of the template repo")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--commit", action="store_true", help="commit AGENTS.md in each updated project")
    ap.add_argument("--quiet", action="store_true", help="one ai-sync line per changed project, nothing else")
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # the em dashes, on a Windows cp1252 console

    projects = list(args.projects)
    if args.all:
        for d in sorted(TEMPLATE_DIR.parent.iterdir()):
            if d.is_dir() and d != TEMPLATE_DIR and (d / ".git").exists() and (d / "AGENTS.md").is_file() and not (d / "AGENTS.md").is_symlink():
                projects.append(d)
    if not projects:
        ap.error("give at least one project dir, or --all")

    current = sections_of((TEMPLATE_DIR / TEMPLATE_FILE).read_text(encoding="utf-8"))
    known: dict[str, set] = {h: set() for h in GENERIC_HEADINGS + RETIRED_SECTIONS}
    for version in template_versions():
        for h, body in sections_of(version).items():
            if h in known:
                known[h].add(norm(body))
    for h in GENERIC_HEADINGS:
        if h in current:
            known[h].add(norm(current[h]))

    for p in projects:
        refresh(p.resolve(), current, known, dry_run=args.dry_run, commit=args.commit, quiet=args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
