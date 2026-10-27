#!/usr/bin/env python3
"""Drift gate for the user documentation. One line per problem, exit 1 on any.

    python3 tests/check-docs.py

Checks:
1. every relative link and #anchor resolves, in README.md, CONTRIBUTING.md, SECURITY.md,
   docs/**/*.md (docs/plans and docs/state excluded: maintainer notes) and examples/**/*.md;
2. every AI_* / AICF_* variable the engine mentions (sync-ai-templates.sh|.ps1, install.sh|.ps1, engine/, bin/)
   is listed in docs/reference/environment.md;
3. docs/reference/cli.md matches the commands' --help (tests/gen-cli-reference.py --check);
4. every file a project receives (templates-manifest.txt: [POINTERS], [LIVING_DOCS],
   [SHARED_HOOKS]) is named in docs/reference/project-files.md.
Stdlib only.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
ENV_DOC = ROOT / "docs" / "reference" / "environment.md"
SKIP_DIRS = {ROOT / "docs" / "plans", ROOT / "docs" / "state"}

FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
INLINE_CODE = re.compile(r"(`+)(?:(?!\1).)+?\1")
LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s+.*)?$")
HTML_HREF = re.compile(r"<a\s[^>]*href=\"([^\"]+)\"", re.I)
HTML_ID = re.compile(r"<a\s[^>]*(?:id|name)=\"([^\"]+)\"", re.I)
HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
ENV_NAME = re.compile(r"\b(?:AI|AICF)_[A-Z0-9_]*[A-Z0-9]\b")


def doc_files() -> list[Path]:
    files = [ROOT / n for n in ("README.md", "CONTRIBUTING.md", "SECURITY.md")]
    for base in (ROOT / "docs", ROOT / "examples"):
        if base.is_dir():
            for f in sorted(base.rglob("*.md")):
                if not any(d == f or d in f.parents for d in SKIP_DIRS):
                    files.append(f)
    return [f for f in files if f.is_file()]


def prose_lines(text: str):
    """(line number, line) outside fenced code blocks, with inline code blanked."""
    fence = None
    for n, line in enumerate(text.splitlines(), 1):
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        yield n, INLINE_CODE.sub("", line)


def slug(heading: str) -> str:
    """GitHub's heading anchor: lower case, punctuation dropped, spaces to hyphens."""
    text = re.sub(r"<[^>]+>", "", heading)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = text.replace("`", "").strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


_anchor_cache: dict[Path, set[str]] = {}


def anchors(path: Path) -> set[str]:
    if path not in _anchor_cache:
        found: set[str] = set()
        seen: dict[str, int] = {}
        text = path.read_text(encoding="utf-8")
        for _, line in prose_lines(text):
            found.update(HTML_ID.findall(line))
        fence = None
        for line in text.splitlines():
            m = FENCE.match(line)
            if fence:
                if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                    fence = None
                continue
            if m:
                fence = m.group(1)
                continue
            h = HEADING.match(line)
            if h:
                base = slug(h.group(2))
                n = seen.get(base, 0)
                seen[base] = n + 1
                found.add(base if n == 0 else f"{base}-{n}")
        _anchor_cache[path] = found
    return _anchor_cache[path]


def check_links(problems: list[str]) -> None:
    for f in doc_files():
        rel = f.relative_to(ROOT)
        for n, line in prose_lines(f.read_text(encoding="utf-8")):
            targets = LINK.findall(line) + HTML_HREF.findall(line)
            m = REF_DEF.match(line)
            if m:
                targets.append(m.group(1))
            for target in targets:
                if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                    continue          # http:, https:, mailto:, … — not checked offline
                path_part, _, anchor = target.partition("#")
                dest = f if not path_part else (f.parent / unquote(path_part)).resolve()
                if path_part and not dest.exists():
                    problems.append(f"{rel}:{n}: broken link: {target}")
                    continue
                if anchor and dest.is_file() and dest.suffix == ".md":
                    if unquote(anchor).lower() not in anchors(dest):
                        problems.append(f"{rel}:{n}: missing anchor: {target}")
                elif anchor and dest.is_dir():
                    problems.append(f"{rel}:{n}: anchor on a folder link: {target}")


def engine_files() -> list[Path]:
    files = [ROOT / n for n in ("sync-ai-templates.sh", "sync-ai-templates.ps1", "install.sh", "install.ps1")]
    for base in (ROOT / "engine", ROOT / "bin"):
        for f in sorted(base.rglob("*")):
            if f.is_file() and "__pycache__" not in f.parts and f.suffix not in (".pyc",):
                files.append(f)
    return [f for f in files if f.is_file()]


def check_env(problems: list[str]) -> None:
    names: dict[str, str] = {}
    for f in engine_files():
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for name in ENV_NAME.findall(text):
            names.setdefault(name, str(f.relative_to(ROOT)))
    documented = set(ENV_NAME.findall(ENV_DOC.read_text(encoding="utf-8"))) if ENV_DOC.is_file() else set()
    if not ENV_DOC.is_file():
        problems.append("docs/reference/environment.md: missing")
    for name in sorted(names):
        if name not in documented:
            problems.append(
                f"docs/reference/environment.md: {name} (read in {names[name]}) is not documented"
            )


def check_cli(problems: list[str]) -> None:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tests" / "gen-cli-reference.py"), "--check"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    if proc.returncode != 0:
        for line in proc.stdout.decode("utf-8", "replace").splitlines():
            if "note:" not in line:
                problems.append(line)


def check_manifest(problems: list[str]) -> None:
    doc = (ROOT / "docs" / "reference" / "project-files.md").read_text(encoding="utf-8")
    section = ""
    for n, line in enumerate((ROOT / "templates-manifest.txt").read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            section = line
            continue
        if section in ("[POINTERS]", "[LIVING_DOCS]", "[SHARED_HOOKS]") and "|" in line:
            dest = line.split("|", 1)[1].strip()
            if f"`{dest}`" not in doc and f"`.git/hooks/{dest}`" not in doc:
                problems.append(f"templates-manifest.txt:{n}: {dest} is not in docs/reference/project-files.md")


def main() -> int:
    problems: list[str] = []
    check_links(problems)
    check_env(problems)
    check_cli(problems)
    check_manifest(problems)
    for p in problems:
        print(p)
    if problems:
        print(f"check-docs: {len(problems)} problem(s)")
        return 1
    print("check-docs: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
