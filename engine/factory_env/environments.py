"""Every code root on this machine: the environments the engine installs skills for and doctor checks.

The brain's parent, the sibling folders of that parent holding `.ai-root/`, the absolute work
roots, then the folders listed in `~/.ai-code-roots` (one absolute path per line, written by
`aicf config` when a root is added there). A listed folder counts only once it is a code root
(`.ai-root/` or `.ai-context-remote`), except the brain's parent, which always does.
"""

from __future__ import annotations

import os
from pathlib import Path

from engine.factory_env.paths import brain_dir, environment_file, home, read_layer, skills_dir, work_roots
from engine.factory_env.schema import ConfigError

ROOTS_FILE = ".ai-code-roots"


def key(path: Path) -> str:
    return os.path.normcase(os.path.realpath(str(path)))


def recorded_roots() -> list[str]:
    listing = home() / ROOTS_FILE
    try:
        lines = listing.read_text(encoding="utf-8-sig").splitlines() if listing.is_file() else []
    except OSError:
        return []
    return [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]


def is_code_root(path: Path) -> bool:
    return (path / ".ai-root").is_dir() or (path / ".ai-context-remote").exists()


def candidate_roots(brain: Path) -> list[Path]:
    """The brain's parent, its sibling code roots, absolute work roots, then the recorded ones;
    each existing folder once, in that order."""
    parent = brain.parent
    candidates = [parent, *_siblings(parent)]
    candidates += [Path(item) for item in work_roots() if os.path.isabs(item)]
    candidates += [Path(item) for item in recorded_roots()]
    found: list[Path] = []
    seen: set[str] = set()
    for path in candidates:
        marker = key(path)
        if marker in seen or not path.is_dir():
            continue
        seen.add(marker)
        found.append(path)
    return found


def code_roots() -> list[Path]:
    """The environments: every candidate that is a code root, the brain's parent always first."""
    try:
        brain = brain_dir()
    except ConfigError:
        return []
    parent = key(brain.parent)
    return [path for path in candidate_roots(brain) if key(path) == parent or is_code_root(path)]


def _siblings(root: Path) -> list[Path]:
    try:
        children = sorted(root.parent.iterdir())
    except OSError:
        return []
    return [child for child in children if child.is_dir() and (child / ".ai-root").is_dir()]


def factory_overlays(factory: dict) -> list[Path]:
    """The extra overlays the personal overlay's factory.json names (`overlays`), each as the
    folder holding its skills. A bare folder name is looked up in every code root, the brain's
    parent first, so the file names no machine path; a path is taken as written. An overlay not
    cloned on this machine is skipped."""
    folders: list[Path] = []
    seen: set[str] = set()
    for item in factory.get("overlays") or []:
        repo = _find_overlay(str(item).strip())
        chosen = (skills_dir(repo) or repo) if repo is not None else None
        if chosen is not None and chosen.is_dir() and key(chosen) not in seen:
            seen.add(key(chosen))
            folders.append(chosen)
    return folders


def _find_overlay(item: str) -> Path | None:
    if item in ("", ".", ".."):
        return None
    if os.path.isabs(item) or "/" in item or "\\" in item or item.startswith("~"):
        path = Path(os.path.expanduser(item))
        return path if path.is_dir() else None
    for root in code_roots():
        if (root / item).is_dir():
            return root / item
    return None


def skill_folders(root: Path) -> list[Path]:
    """The skills folders an environment names (`overlays`), each as the folder holding the skills."""
    try:
        data = read_layer(environment_file(root))
    except (ConfigError, OSError):
        return []
    folders = []
    for item in data.get("overlays") or []:
        path = Path(str(item))
        chosen = skills_dir(path) or path
        if chosen.is_dir():
            folders.append(chosen)
    return folders


def is_shared_root(root: Path | None) -> bool:
    """The brain's parent: its skills folders serve every environment (personal or work by where
    they sit); any other environment's folders are its own."""
    if root is None:
        return False
    try:
        return key(root) == key(brain_dir().parent)
    except ConfigError:
        return False


def other_skill_folders(root: Path | None) -> list[tuple[Path, bool]]:
    """(folder, shared) for the skills folders of every environment but `root`: all are installed
    on this machine, so a project of `root` must be told which of them are off."""
    own = key(root) if root is not None else ""
    folders: list[tuple[Path, bool]] = []
    for other in code_roots():
        if key(other) != own:
            shared = is_shared_root(other)
            folders += [(folder, shared) for folder in skill_folders(other)]
    return folders
