"""Where the brain, the overlay and a code root's environment file live."""

from __future__ import annotations

import os
from pathlib import Path

from engine.factory_env.schema import ConfigError, dumps, fold_kind, is_work_label, load_json, validate_document
from engine.factory_env.textio import write_lf

BRAIN_FILES = ("sync-ai-templates.sh", "templates-manifest.txt")


def home() -> Path:
    raw = os.environ.get("HOME") or os.environ.get("USERPROFILE") or ""
    return Path(raw) if raw else Path.home()


def brain_dir() -> Path:
    """The checkout this module was loaded from. The sync sets PYTHONPATH to it."""
    here = Path(__file__).resolve().parents[2]
    if all((here / name).is_file() for name in BRAIN_FILES):
        return here
    raise ConfigError(
        "AICodeFactory was not found next to this module — set AI_TEMPLATE_DIR or run aicf setup"
    )


def skills_dir(repo: Path) -> Path | None:
    """A template repo's skills folder: skills/, else the old layout's vscode-global/skills/."""
    for folder in (repo / "skills", repo / "vscode-global" / "skills"):
        if folder.is_dir():
            return folder
    return None


def is_brain(path: Path) -> bool:
    return path.is_dir() and all((path / name).is_file() for name in BRAIN_FILES)


def overlay_dir() -> Path | None:
    """Same lookup as the sync engine. `none` or empty disables it."""
    if "AI_TEMPLATE_OVERLAY_DIR" in os.environ:
        raw = os.environ["AI_TEMPLATE_OVERLAY_DIR"].strip()
        if raw in ("", "none"):
            return None
        path = Path(raw)
        return path.resolve() if path.is_dir() else None
    marker = home() / ".ai-template-overlay-dir"
    if marker.is_file():
        raw = marker.read_text(encoding="utf-8").splitlines()
        text = raw[0].strip() if raw else ""
        if text:
            path = Path(text)
            if path.is_dir():
                return path.resolve()
            return None
    try:
        brain = brain_dir()
    except ConfigError:
        return None
    sibling = brain.parent / f"{brain.name}-private"
    return sibling.resolve() if sibling.is_dir() else None


def factory_file() -> Path | None:
    overlay = overlay_dir()
    if overlay is None:
        return None
    return overlay / "factory.json"


def code_root_of(project: Path) -> Path | None:
    """Parent of the git top when that parent holds .ai-root or .ai-context-remote."""
    top = _git_top(project)
    if top is None:
        return None
    root = top.parent
    if (root / ".ai-root").is_dir() or (root / ".ai-context-remote").exists():
        return root
    return None


def environment_file(root: Path) -> Path:
    return root / ".ai-root" / "environment.json"


def _git_top(project: Path) -> Path | None:
    current = project if project.is_dir() else project.parent
    try:
        current = current.resolve()
    except OSError:
        return None
    home_path = home()
    for candidate in (current, *current.parents):
        if candidate == home_path:
            return None
        git_path = candidate / ".git"
        if git_path.exists():
            return candidate
    return None


def read_layer(path: Path | None) -> dict:
    """A missing file is empty. A broken file raises ConfigError (the caller prints one line)."""
    if path is None or not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8-sig")
    data = fold_kind(load_json(text, str(path)))
    return validate_document(data, strict=False, check_work=False)


def read_raw(path: Path | None) -> dict:
    """The file as written, unknown keys included: a save must not drop what a newer brain wrote."""
    if path is None or not path.is_file():
        return {}
    return load_json(path.read_text(encoding="utf-8-sig"), str(path))


def write_layer(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    write_lf(temporary, dumps(data))
    temporary.replace(path)


WORK_ROOTS_FILE = ".ai-work-roots"


def work_roots() -> list[str]:
    """$AI_WORK_ROOTS (os.pathsep-separated; empty or `none` = none, the file unread), else the
    lines of ~/.ai-work-roots (blank and # lines skipped). Same list as the shell engine."""
    if "AI_WORK_ROOTS" in os.environ:
        raw = os.environ["AI_WORK_ROOTS"].strip()
        if raw in ("", "none"):
            return []
        return [item.strip() for item in raw.split(os.pathsep) if item.strip()]
    listing = home() / WORK_ROOTS_FILE
    try:
        lines = listing.read_text(encoding="utf-8-sig").splitlines() if listing.is_file() else []
    except OSError:
        return []
    return [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]


def _normalized(text: str) -> str:
    return text.replace("\\", "/").rstrip("/").lower()


def _matches_entry(path_text: str, components: list[str], entry: str) -> bool:
    """A folder name (no slash) matches any path component; a path matches as a component prefix."""
    if "/" not in entry and "\\" not in entry:
        return entry.lower() in components
    prefix = _normalized(entry)
    return path_text == prefix or path_text.startswith(prefix + "/")


def _environment_label(path: Path) -> str:
    """`label` of the environment.json of the code root holding `path` (itself or an ancestor)."""
    for candidate in (path, *path.parents):
        if (candidate / ".ai-root").is_dir():
            try:
                return str(fold_kind(read_raw(environment_file(candidate))).get("label") or "")
            except (ConfigError, OSError):
                return ""
    return ""


def is_work_path(path: Path | None) -> bool:
    """Under a work root: an entry of work_roots() matches, or the code root's label is work."""
    if path is None:
        return False
    absolute = Path(os.path.abspath(str(path)))
    path_text = _normalized(str(absolute))
    components = [part for part in path_text.split("/") if part]
    if any(_matches_entry(path_text, components, entry) for entry in work_roots()):
        return True
    return is_work_label(_environment_label(absolute))


def default_label(root: Path | None) -> str:
    """The label of a root whose environment.json has none: work under a work root, else personal."""
    return "work" if is_work_path(root) else "personal"
