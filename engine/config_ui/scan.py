"""Find folders of skills on this disk: a folder whose sub-folders hold a SKILL.md.

Bounded on every axis (depth, folders visited, seconds), never follows a link, skips hidden
folders (the installed copies under ~/.claude/skills and the like are hidden) and the usual
dependency and system trees. Read-only.
"""

from __future__ import annotations

import os
import time
from pathlib import Path

SKIP = {
    "node_modules", "__pycache__", "venv", "env", "site-packages", "vendor", "pods", "bin", "obj",
    "dist", "build", "target", "appdata", "library", "applications", "windows", "program files",
    "program files (x86)", "programdata", "$recycle.bin", "system volume information",
}
MAX_DEPTH = 6
MAX_FOLDERS = 60000
MAX_SECONDS = 20.0


def scan(folders: list[Path], *, depth: int = MAX_DEPTH, budget: int = MAX_FOLDERS,
         seconds: float = MAX_SECONDS) -> dict:
    """{"candidates": [{"path", "skills"}], "visited", "truncated"} — each skills folder once."""
    found: dict[str, list[str]] = {}
    seen: set[str] = set()
    stack = [(folder, 0) for folder in reversed(folders)]
    deadline = time.monotonic() + seconds
    visited = 0
    truncated = False
    while stack:
        if visited >= budget or time.monotonic() > deadline:
            truncated = True
            break
        folder, level = stack.pop()
        marker = os.path.normcase(os.path.realpath(str(folder)))
        if marker in seen:
            continue
        seen.add(marker)
        visited += 1
        skills, deeper = _children(folder)
        if skills:
            found[str(folder)] = sorted(skills)
        if level < depth:
            stack.extend((child, level + 1) for child in reversed(deeper))
    candidates = [{"path": path, "skills": names} for path, names in sorted(found.items())]
    return {"candidates": candidates, "visited": visited, "truncated": truncated}


def _children(folder: Path) -> tuple[list[str], list[Path]]:
    """(skill names directly under the folder, sub-folders worth walking)."""
    skills: list[str] = []
    deeper: list[Path] = []
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return [], []
    for entry in entries:
        if not _walkable(entry):
            continue
        child = Path(entry.path)
        if (child / "SKILL.md").is_file():
            skills.append(entry.name)
        else:
            deeper.append(child)
    return skills, deeper


def _walkable(entry: os.DirEntry) -> bool:
    if entry.name.startswith(".") or entry.name.lower() in SKIP:
        return False
    try:
        junction = getattr(entry, "is_junction", None)   # Windows, Python 3.12+
        return entry.is_dir(follow_symlinks=False) and not (junction and junction())
    except OSError:
        return False
