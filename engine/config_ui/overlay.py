"""The personal overlay: where the owner's own skills (and templates, factory.json) live.

Same lookup as the engine (`AI_TEMPLATE_OVERLAY_DIR`, `~/.ai-template-overlay-dir`,
`<brain>-private`). Setting it writes the marker, as `aicf setup --overlay` does, and rewrites
`AI_TEMPLATE_OVERLAY_DIR` in every Claude Code settings file that already carries it: that
variable wins over the marker, so a stale one would keep the old folder in every session.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from engine.config_ui.roots import checked_folder, key
from engine.factory_env.paths import brain_dir, home, overlay_dir, skills_dir
from engine.factory_env.resolve import _skill_names
from engine.factory_env.schema import ConfigError
from engine.factory_env.textio import write_lf
from engine.projects_page.usage import config_dirs

MARKER = ".ai-template-overlay-dir"
VARIABLE = "AI_TEMPLATE_OVERLAY_DIR"


def current() -> dict:
    path = overlay_dir()
    skills = skills_dir(path) if path is not None else None
    return {
        "path": str(path or ""),
        "source": _source(path),
        "skills_dir": str(skills or ""),
        "skills": sorted(_skill_names(skills)) if skills is not None else [],
        "has_factory": bool(path and (path / "factory.json").is_file()),
    }


def _source(path: Path | None) -> str:
    if path is None:
        return ""
    if os.environ.get(VARIABLE, "").strip() not in ("", "none"):
        return "variable"
    return "marker" if (home() / MARKER).is_file() else "sibling"


def set_overlay(raw: str) -> list[Path]:
    """Point the machine at this overlay. The settings files it rewrote."""
    path = checked_folder(raw, "your personal overlay folder")
    if key(path) == key(brain_dir()):
        raise ConfigError("that is AICodeFactory itself — the personal overlay is a separate folder")
    if skills_dir(path) is None and _skill_names(path):
        raise ConfigError(
            f"{path} holds skills directly; an overlay keeps them in a skills/ subfolder — "
            "add it as an extra skills folder instead, or pick its parent"
        )
    write_lf(home() / MARKER, str(path) + "\n")
    if VARIABLE in os.environ:
        os.environ[VARIABLE] = str(path)
    return _rewrite_variable(str(path))


def clear_overlay() -> list[Path]:
    """No personal overlay recorded (a `<brain>-private` sibling is still found by default)."""
    marker = home() / MARKER
    if marker.is_file():
        marker.unlink()
    os.environ.pop(VARIABLE, None)
    return _rewrite_variable(None)


def _rewrite_variable(value: str | None) -> list[Path]:
    changed = []
    for folder in config_dirs(home()):
        path = folder / "settings.json"
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            continue
        env = data.get("env") if isinstance(data, dict) else None
        if not isinstance(env, dict) or VARIABLE not in env or env[VARIABLE] == value:
            continue
        if value is None:
            del env[VARIABLE]
        else:
            env[VARIABLE] = value
        write_lf(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        changed.append(path)
    return changed
