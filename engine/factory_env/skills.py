"""Skill-install stamp, and a copy that was edited by hand is not overwritten."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

from engine.factory_env.paths import brain_dir, home, overlay_dir, skills_dir
from engine.factory_env.resolve import overlay_skill_dirs
from engine.factory_env.schema import ConfigError
from engine.factory_env.textio import write_lf

ORIGIN = ".ai-template-origin"
UNFINISHED = "ai-sync: previous skill install did not finish"


def _stamp_path() -> Path:
    return home() / ".ai-skills-stamp"


def _running_path() -> Path:
    return home() / ".ai-skills-stamp.running"


def skills_current(roots: list[str] | None = None) -> int:
    """Exit 0 when the last finished install matches the sources. Otherwise exit 1.

    A leftover running marker means the previous install was killed: say so, then install.
    ``roots`` are the installed skill folders to compare. The shell passes them as arguments
    because Git Bash rewrites only the first line of a multiline environment variable.
    """
    running = _running_path()
    if running.is_file():
        print(UNFINISHED)
        return 1
    stamp = _stamp_path()
    if not stamp.is_file():
        return 1
    try:
        recorded = stamp.read_text(encoding="utf-8").strip()
    except OSError:
        return 1
    if recorded != _fingerprint():
        return 1
    return 0 if _installed_fresh(stamp, roots) else 1


def skills_begin() -> int:
    path = _running_path()
    try:
        write_lf(path, "running\n")
    except OSError as exc:
        print(f"ai-sync: could not record the skill install ({exc})")
    return 0


def skills_finish() -> int:
    try:
        write_lf(_stamp_path(), _fingerprint() + "\n")
        _running_path().unlink(missing_ok=True)
    except OSError as exc:
        print(f"ai-sync: could not finish the skill stamp ({exc})")
    return 0


def _fingerprint() -> str:
    folders = _source_folders()
    if not folders:
        return "missing"
    digest = hashlib.sha256()
    # Mode is part of the install: copy and link are not the same result.
    digest.update(os.environ.get("AI_SKILLS_MODE", "").encode())
    digest.update(b"\0")
    for folder in folders:
        digest.update(str(folder).encode())
        digest.update(tree_hash(folder).encode())
    return digest.hexdigest()


def _source_folders() -> list[Path]:
    try:
        brain = brain_dir()
    except ConfigError:
        return []
    folders = [brain / "skills"]
    # The engine's own lookup (variable, ~/.ai-template-overlay-dir, <brain>-private), so an
    # edit in the overlay found by the marker file also starts a new install. An overlay still
    # in the old layout keeps its vscode-global/skills.
    overlay = overlay_dir()
    overlay_skills = skills_dir(overlay) if overlay is not None else None
    if overlay_skills is not None:
        folders.append(overlay_skills)
    for item in overlay_skill_dirs():
        folders.append(Path(item))
    return folders


def _skill_names(folder: Path) -> list[str]:
    if not folder.is_dir():
        return []
    names = []
    try:
        children = list(folder.iterdir())
    except OSError:
        return []
    for child in children:
        if child.is_dir() and (child / "SKILL.md").is_file():
            names.append(child.name)
    return names


def _retired_names(folder: Path) -> list[str]:
    path = folder / "RETIRED"
    if not path.is_file():
        return []
    names = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    for line in lines:
        name = line.split("#", 1)[0].strip()
        if name:
            names.append(name)
    return names


def _installed_roots(roots: list[str] | None) -> list[Path]:
    """Skill folders the caller named, or ``AI_SKILL_ROOTS`` when the command line named none."""
    named = [item.strip() for item in (roots or []) if item.strip()]
    if not named:
        named = [line.strip() for line in os.environ.get("AI_SKILL_ROOTS", "").splitlines() if line.strip()]
    return [path for path in (Path(line) for line in named) if path.is_dir()]


def _installed_fresh(stamp: Path, roots: list[str] | None = None) -> bool:
    """False when a root is missing a source skill, a file there is newer than the stamp, or a retired copy remains.

    No roots and no ``AI_SKILL_ROOTS`` means the caller did not ask (the unit test): the source stamp is enough.
    """
    roots_found = _installed_roots(roots)
    if not roots_found:
        return True
    try:
        stamp_mtime = stamp.stat().st_mtime
    except OSError:
        return False
    folders = _source_folders()
    names: list[str] = []
    retired: list[str] = []
    for folder in folders:
        names.extend(_skill_names(folder))
        retired.extend(_retired_names(folder))
    shipped = set(names)
    for root in roots_found:
        for name in retired:
            # Only a copy we installed: the engine never removes the user's own folder of that
            # name, and counting it would mean a full install at every session.
            if name not in shipped and _ours(root / name, folders):
                return False
        for name in names:
            dest = root / name
            if not dest.exists():
                return False
            try:
                files = _content_files(dest)
            except OSError:
                return False
            for path in files:
                try:
                    if path.stat().st_mtime > stamp_mtime:
                        return False
                except OSError:
                    return False
    return True


def _ours(dest: Path, folders: list[Path]) -> bool:
    if dest.is_symlink() or not dest.is_dir():
        return False
    lines = _origin_lines(dest)
    origin = _path_key(lines[0]) if lines else ""
    # A copy made before skills/ moved to the repo root names <repo>/vscode-global/skills.
    keys = [_path_key(str(folder)) for folder in folders]
    keys += [_path_key(str(folder.parent / "vscode-global" / "skills")) for folder in folders]
    return bool(origin) and origin in keys


def _path_key(raw: str) -> str:
    """One spelling for /f/Code/x (Git Bash), F:\\Code\\x (PowerShell) and their case on Windows."""
    text = raw.strip().replace("\\", "/").rstrip("/")
    if os.name == "nt":
        if len(text) > 2 and text[0] == "/" and text[2] == "/" and text[1].isalpha():
            text = f"{text[1]}:{text[2:]}"
        text = text.lower()
    return text


def _content_files(folder: Path) -> list[Path]:
    """A skill's files. A script run from the installed copy leaves __pycache__: not an edit."""
    return [
        path for path in folder.rglob("*")
        if path.is_file() and "__pycache__" not in path.relative_to(folder).parts
    ]


def tree_hash(folder: Path) -> str:
    digest = hashlib.sha256()
    if not folder.is_dir():
        digest.update(b"missing")
        return digest.hexdigest()
    files = sorted(
        (path for path in _content_files(folder) if path.name != ORIGIN),
        key=lambda path: path.relative_to(folder).as_posix(),
    )
    for path in files:
        digest.update(path.relative_to(folder).as_posix().encode())
        digest.update(b"\0")
        try:
            digest.update(path.read_bytes())
        except OSError:
            digest.update(b"unreadable")
        digest.update(b"\0")
    return digest.hexdigest()


def _origin_lines(dest: Path) -> list[str]:
    marker = dest / ORIGIN
    if not marker.is_file():
        return []
    try:
        return marker.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []


def skill_keep(dest: Path, source: Path) -> int:
    """Exit 0 when the installed copy was edited and must be kept. Exit 1 to replace it.

    A copy with no recorded hash (an install from before this stamp) is replaced, as before.
    """
    lines = _origin_lines(dest)
    recorded = lines[1].strip() if len(lines) > 1 else ""
    if not recorded:
        return 1
    current = tree_hash(dest)
    fresh = tree_hash(source)
    if current == fresh or current == recorded:
        return 1
    name = dest.name
    print(f"ai-sync: skill {name} was edited in the installed copy; not overwritten")
    return 0


def skill_stamp(dest: Path, source: Path, origin: str = "") -> int:
    marker = dest / ORIGIN
    # Line 1 is the skills-root path the shell compares. Line 2 is this skill's content hash.
    line1 = origin if origin else str(source)
    body = f"{line1}\n{tree_hash(source)}\n"
    try:
        write_lf(marker, body)
    except OSError as exc:
        print(f"ai-sync: could not stamp {dest} ({exc})")
        return 1
    return 0
