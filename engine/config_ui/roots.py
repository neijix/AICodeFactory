"""Code roots: the folders whose projects AICodeFactory serves.

A folder is a code root when it holds `.ai-root/` (or `.ai-context-remote`): the engine and the
global hook look for nothing else. Adding one here writes its `.ai-root/environment.json`. The
page remembers a root it was told about in `~/.ai-code-roots` (one absolute path per line), so a
root outside the brain's parent is listed again next time; the engine never reads that file.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from engine.factory_env.cli import set_layer
from engine.factory_env.paths import _git_top, default_label, home, work_roots
from engine.factory_env.schema import ConfigError
from engine.factory_env.textio import write_lf

ROOTS_FILE = ".ai-code-roots"


@dataclass(frozen=True)
class Root:
    path: Path
    brain_root: bool
    recorded: bool

    @property
    def is_code_root(self) -> bool:
        return (self.path / ".ai-root").is_dir() or (self.path / ".ai-context-remote").exists()


def key(path: Path) -> str:
    return os.path.normcase(os.path.realpath(str(path)))


def recorded() -> list[str]:
    listing = home() / ROOTS_FILE
    try:
        lines = listing.read_text(encoding="utf-8-sig").splitlines() if listing.is_file() else []
    except OSError:
        return []
    return [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]


def known_roots(brain: Path) -> list[Root]:
    """The brain's parent, its sibling code roots, absolute work roots, then the recorded ones."""
    mine = {key(Path(item)) for item in recorded()}
    candidates = [brain.parent]
    candidates += _siblings(brain.parent)
    candidates += [Path(item) for item in work_roots() if os.path.isabs(item)]
    candidates += [Path(item) for item in recorded()]
    roots: list[Root] = []
    seen: set[str] = set()
    for path in candidates:
        marker = key(path)
        if marker in seen or not path.is_dir():
            continue
        seen.add(marker)
        roots.append(Root(path, marker == key(brain.parent), marker in mine))
    return roots


def _siblings(root: Path) -> list[Path]:
    try:
        children = sorted(root.parent.iterdir())
    except OSError:
        return []
    return [child for child in children if child.is_dir() and (child / ".ai-root").is_dir()]


def add_root(raw: str, label: str) -> Path:
    path = checked_folder(raw, "the folder that holds your projects")
    top = _git_top(path)   # AICodeFactory itself included: it is a git repo
    if top is not None:
        raise ConfigError(f"{path} is inside the git repo {top} — pick the folder that holds your projects, not a project")
    set_layer({"layer": "environment", "root": str(path), "values": {"label": label or default_label(path)}})
    if key(path) not in (key(Path(item)) for item in recorded()):
        _write_recorded([*recorded(), str(path)])
    return path


def forget_root(brain: Path, raw: str) -> None:
    """Drop a root from the page's list. Its `.ai-root` stays: it holds the registry and the
    dev context, and deleting it is the owner's call."""
    target = key(Path(raw))
    if target == key(brain.parent):
        raise ConfigError("the folder holding AICodeFactory is always a root — it cannot be forgotten")
    kept = [item for item in recorded() if key(Path(item)) != target]
    if len(kept) == len(recorded()):
        raise ConfigError(f"{raw} was not added on this page — it is found on its own (a sibling or a work root)")
    _write_recorded(kept)


def _write_recorded(items: list[str]) -> None:
    write_lf(home() / ROOTS_FILE, "".join(item + "\n" for item in items))


def checked_folder(raw: object, what: str) -> Path:
    """An existing absolute folder (`~` expanded), else a ConfigError naming what was expected."""
    if not isinstance(raw, str) or not raw.strip():
        raise ConfigError(f"give the path of {what}")
    text = raw.strip()
    if text == "~" or text.startswith(("~/", "~\\")):
        text = str(home()) + text[1:]
    path = Path(text)
    if not path.is_absolute():
        raise ConfigError(f"{raw} is not an absolute path — give the full path of {what}")
    if not path.is_dir():
        raise ConfigError(f"{path} is not a folder on this machine")
    return Path(os.path.abspath(str(path)))


def project_count(root: Path) -> int:
    try:
        return sum(1 for child in root.iterdir() if (child / ".git").exists())
    except OSError:
        return 0
