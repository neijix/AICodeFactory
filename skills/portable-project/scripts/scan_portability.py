#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""List what stops a stranger from installing a repo: things only the owner's machine has.

    uv run scan_portability.py [<repo>] [--all] [--strict]

Scans the repo's tracked text files for machine paths, private-network addresses and LAN host
names, path dependencies on other checkouts, references to sibling folders of the code root and
`sibling-deps.txt` entries. Findings in test files are only counted unless --all (fixtures are
usually fake values). Advisory — an example address or network-classification code is fine:
judge each line. Exit 0 unless --strict and something outside tests was found (exit 1); exit 2
when <repo> is not a git checkout. Each finding names its fix in the portable-project skill.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

MAX_BYTES = 1_000_000
SKIP_SUFFIXES = (
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".icns", ".webp", ".pdf", ".zip", ".gz", ".woff",
    ".woff2", ".ttf", ".mp3", ".mp4", ".wav", ".onnx", ".bin", ".exe", ".dll", ".so", ".dylib",
)
# Lockfiles repeat what their manifest says; the manifest is the line to fix.
SKIP_NAMES = ("uv.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "poetry.lock",
              "Cargo.lock", "go.sum")
# Names docs and fixtures use for "some user": not the owner's.
PLACEHOLDER_USERS = r"(?:me|you|user|username|name|example|runner|alice|bob|foo|Shared|Public)\b"
TEST_PATH = re.compile(r"(?:^|/)(?:tests?|__tests__|spec|fixtures)/|(?:^|/)test_[^/]*$"
                       r"|[._](?:test|spec)\.[^/]+$|_test\.[^/]+$")

RULES: list[tuple[str, re.Pattern[str], str]] = [
    ("machine-path",
     re.compile(r"(?:/Users/|/home/|\b[A-Za-z]:[\\/]+Users[\\/]+)(?!" + PLACEHOLDER_USERS + r")"
                r"[A-Za-z0-9_-][A-Za-z0-9._-]*"),
     "path relative to the app, OS app-data dir, or a setting with a default"),
    ("code-root-path",
     re.compile(r"~/Code\b|\$HOME/Code\b|\$\{?AI_CODE_ROOT\b|\b[A-Za-z]:[\\/]+[A-Za-z]*Code\b"),
     "path relative to the app; another repo = package or optional integration"),
    ("private-ip",
     re.compile(r"(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.])"),
     "setting whose empty default disables the feature; placeholder in .env.example"),
    ("lan-host",
     # In a URL, after user@ or quoted — a `.lan` attribute in code is a property, not a host.
     re.compile(r"""(?:(?<=//)|(?<=[@"']))[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.(?:lan|home\.arpa|internal)\b(?![\w(])"""
                r"|\\\\[A-Za-z0-9-]+\\[A-Za-z0-9$_-]+"),
     "setting whose empty default disables the feature"),
    ("path-dependency",
     re.compile(r"""\bpath\s*=\s*["']\.\.[\\/]|["']file:\.\.[\\/]|=>\s*\.\.[\\/]"""),
     "published package or git dependency pinned to a tag; local checkout as dev-only override"),
]

Finding = tuple[str, int, str, str, str]


def git_files(repo: Path) -> list[str]:
    out = subprocess.run(["git", "-C", str(repo), "ls-files", "-z"], capture_output=True, check=True)
    return [f for f in out.stdout.decode("utf-8", "replace").split("\0") if f]


def sibling_names(repo: Path) -> set[str]:
    """Folders beside the repo that are git checkouts: the owner's other projects."""
    here = repo.resolve()
    try:
        entries = list(here.parent.iterdir())
    except OSError:
        return set()
    return {e.name for e in entries
            if e.is_dir() and e.name != here.name and len(e.name) > 2 and (e / ".git").exists()}


def scan(repo: Path) -> list[Finding]:
    findings: list[Finding] = []
    siblings = sorted(sibling_names(repo))
    sibling_re = (re.compile(r"\.\.[\\/](" + "|".join(re.escape(s) for s in siblings) + r")\b")
                  if siblings else None)
    for rel in git_files(repo):
        path = repo / rel
        if rel.lower().endswith(SKIP_SUFFIXES) or os.path.basename(rel) in SKIP_NAMES:
            continue
        try:
            if not path.is_file() or path.stat().st_size > MAX_BYTES:
                continue
            raw = path.read_bytes()
        except OSError:
            continue
        if b"\0" in raw[:4096]:
            continue
        lines = raw.decode("utf-8", "replace").splitlines()
        if os.path.basename(rel) == "sibling-deps.txt":
            for n, line in enumerate(lines, 1):
                if line.strip() and not line.lstrip().startswith("#"):
                    findings.append((rel, n, "sibling-dep", line.strip()[:120],
                                     "public repo + optional feature, or a package"))
            continue
        for n, line in enumerate(lines, 1):
            for rule, pattern, fix in RULES:
                m = pattern.search(line)
                if m:
                    findings.append((rel, n, rule, m.group(0), fix))
            m = sibling_re.search(line) if sibling_re else None
            if m:
                findings.append((rel, n, "sibling-repo", m.group(0),
                                 "package, vendored code, or optional integration"))
    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", nargs="?", default=".")
    ap.add_argument("--all", action="store_true", help="also list findings in test files")
    ap.add_argument("--strict", action="store_true", help="exit 1 when anything outside tests is found")
    args = ap.parse_args()
    repo = Path(args.repo)
    try:
        findings = scan(repo)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"scan_portability: {repo} is not a git checkout (or git is missing)", file=sys.stderr)
        return 2
    in_tests = [f for f in findings if TEST_PATH.search(f[0])]
    outside = [f for f in findings if not TEST_PATH.search(f[0])]
    shown = outside + in_tests if args.all else outside
    by_rule: dict[str, int] = {}
    for rel, n, rule, match, fix in shown:
        by_rule[rule] = by_rule.get(rule, 0) + 1
        print(f"{rel}:{n}: [{rule}] {match}  ->  {fix}")
    hidden = "" if args.all or not in_tests else f"; {len(in_tests)} more in test files (--all)"
    if not shown:
        print(f"portable: no machine path, LAN address, path dependency or sibling repo found{hidden}")
        return 0
    summary = ", ".join(f"{k} {v}" for k, v in sorted(by_rule.items()))
    print(f"\n{len(shown)} finding(s): {summary}{hidden}. "
          "Advisory: judge each line; fixes in the portable-project skill.")
    return 1 if args.strict and outside else 0


if __name__ == "__main__":
    sys.exit(main())
