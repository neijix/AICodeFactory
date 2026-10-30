"""Repos that are ahead, behind, dirty, or holding a recorded conflict."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from engine.factory_env.paths import brain_dir, home
from engine.factory_env.schema import ConfigError
from engine.factory_env.skills import ORIGIN


def collect(root: Path) -> list[dict]:
    rows: list[dict] = []
    if not root.is_dir():
        return rows
    air = root / ".ai-root"
    if (air / ".git").exists():
        _add(rows, air, "ai-root")
    projects = []
    try:
        projects = sorted(child for child in root.iterdir() if child.is_dir() and not child.name.startswith("."))
    except OSError:
        projects = []
    for project in projects:
        if (project / ".git").exists():
            _add(rows, project, "code")
        hidden = project / ".git" / "ai-context"
        if (hidden / "HEAD").is_file():
            _add(rows, project, "ai-context", git_dir=hidden)
            if (hidden / "sync-conflict.json").is_file():
                rows.append({
                    "path": str(project),
                    "role": "conflict",
                    "ahead": 0,
                    "behind": 0,
                    "dirty": False,
                    "conflict": True,
                    "detail": "hidden AI-docs repo: a sync conflict is recorded (sync-conflict.json)",
                })
    rows.extend(_orphan_copies())
    return [row for row in rows if row.get("ahead") or row.get("behind") or row.get("dirty") or row.get("conflict")]


def _add(rows: list[dict], path: Path, role: str, git_dir: Path | None = None) -> None:
    state = _git_state(path, git_dir)
    if state is None:
        return
    state["path"] = str(path)
    state["role"] = role
    rows.append(state)


def _git_state(path: Path, git_dir: Path | None) -> dict | None:
    prefix = ["git"]
    if git_dir is not None:
        prefix += [f"--git-dir={git_dir}", f"--work-tree={path}"]
    else:
        prefix += ["-C", str(path)]
    status = _run(prefix + ["status", "--porcelain"])
    if status is None:
        return None
    dirty = bool(status.strip())
    counts = _run(prefix + ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
    ahead = behind = 0
    if counts:
        parts = counts.split()
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            ahead, behind = int(parts[0]), int(parts[1])
    return {"ahead": ahead, "behind": behind, "dirty": dirty, "conflict": False, "detail": _detail(ahead, behind, dirty)}


def _detail(ahead: int, behind: int, dirty: bool) -> str:
    bits = []
    if dirty:
        bits.append("uncommitted changes")
    if ahead:
        bits.append(f"{ahead} commit(s) not pushed")
    if behind:
        bits.append(f"{behind} commit(s) to pull")
    return ", ".join(bits)


def _orphan_copies() -> list[dict]:
    """Installed copies whose origin names us, that no current source ships and RETIRED does not list."""
    try:
        brain = brain_dir()
    except ConfigError:
        return []
    shipped = _shipped(brain / "skills")
    retired = _retired(brain / "skills" / "RETIRED")
    ours = {_src_key(str(brain / "skills")), _src_key(str(brain / "vscode-global" / "skills"))}
    rows = []
    for skills_root in _install_roots():
        if not skills_root.is_dir():
            continue
        try:
            children = list(skills_root.iterdir())
        except OSError:
            continue
        for child in children:
            marker = child / ORIGIN
            if not child.is_dir() or child.is_symlink() or not marker.is_file():
                continue
            try:
                origin = marker.read_text(encoding="utf-8").splitlines()
            except OSError:
                continue
            first = origin[0].strip() if origin else ""
            # Exact skills root, not a substring: AICodeFactory-private's copies are the overlay's.
            if _src_key(first) not in ours:
                continue
            if child.name in shipped or child.name in retired:
                continue
            rows.append({
                "path": str(child),
                "role": "skill-copy",
                "ahead": 0,
                "behind": 0,
                "dirty": False,
                "conflict": True,
                "detail": f"installed skill {child.name} is not shipped and not listed in RETIRED",
            })
    return rows


def _src_key(text: str) -> str:
    """An origin marker's skills root, keyed as sync-skills.sh does: either slash, /c/ or C:, case on Windows."""
    path = re.sub(r"^([A-Za-z]):", r"/\1", text.strip().replace("\\", "/")).rstrip("/")
    return path.lower() if os.name == "nt" else path


def _shipped(folder: Path) -> set[str]:
    if not folder.is_dir():
        return set()
    return {child.name for child in folder.iterdir() if child.is_dir() and (child / "SKILL.md").is_file()}


def _retired(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    names = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        name = line.split("#", 1)[0].strip()
        if name:
            names.add(name)
    return names


def _install_roots() -> list[Path]:
    base = home()
    return [
        base / ".agents" / "skills",
        base / ".claude" / "skills",
        base / ".copilot" / "skills",
        base / ".cursor" / "skills",
        base / ".gemini" / "config" / "skills",
    ]


def _run(args: list[str]) -> str | None:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return ""
    return result.stdout
