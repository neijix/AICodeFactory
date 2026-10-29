"""What the settings page reads and changes. Every write goes through factory_env or roots/overlay."""

from __future__ import annotations

import os
from pathlib import Path

from engine.config_ui import overlay, roots, scan
from engine.factory_env.cli import set_layer, view
from engine.factory_env.paths import home, skills_dir
from engine.factory_env.schema import ConfigError

SKILL_STATES = ("default", "on", "off")


def state(brain: Path) -> dict:
    known = roots.known_roots(brain)
    data = view([root.path for root in known])
    by_key = {roots.key(root.path): root for root in known}
    for env in data["environments"]:
        root = by_key.get(roots.key(Path(env["root"])))
        raw = env.get("raw") or {}
        env["code_root"] = bool(root and root.is_code_root)
        env["brain_root"] = bool(root and root.brain_root)
        env["forgettable"] = bool(root and root.recorded and not root.brain_root)
        env["projects"] = roots.project_count(Path(env["root"]))
        on, off = set(raw.get("skills.on") or []), set(raw.get("skills.off") or [])
        for skill in env["skills"]:
            skill["state"] = "on" if skill["name"] in on else "off" if skill["name"] in off else "default"
    data["personal"] = overlay.current()
    data["scan_folders"] = default_scan_folders(known)
    return data


def default_scan_folders(known: list) -> list[str]:
    """Home and every root, without a folder already inside another one of the list."""
    kept: list[Path] = []
    for folder in (home(), *(root.path for root in known)):
        resolved = Path(os.path.realpath(str(folder)))
        if any(resolved == other or other in resolved.parents for other in kept):
            continue
        kept = [other for other in kept if resolved not in other.parents]
        kept.append(resolved)
    return [str(folder) for folder in kept]


def run(brain: Path, action: str, body: dict) -> dict:
    """One page action; the new state, or the scan result for `scan`."""
    handler = ACTIONS.get(action)
    if handler is None:
        raise ConfigError(f"unknown action {action!r}")
    result = handler(brain, body)
    if result is not None:
        return result
    return {"state": state(brain)}


def _root_add(brain: Path, body: dict) -> dict:
    path = roots.add_root(body.get("path"), str(body.get("label") or ""), str(body.get("kind") or ""))
    return {"state": state(brain), "added": str(path)}


def _root_forget(brain: Path, body: dict) -> None:
    roots.forget_root(brain, str(body.get("path") or ""))


def _environment(brain: Path, body: dict) -> None:
    values = body.get("values")
    if isinstance(values, dict) and "overlays" in values:
        values["overlays"] = _skill_folders(values["overlays"])
    set_layer({"layer": "environment", "root": body.get("root"), "values": values})


def _skill_folders(items: object) -> list[str]:
    if not isinstance(items, list):
        raise ConfigError("overlays must be a list of folders")
    folders = []
    for item in items:
        path = roots.checked_folder(item, "a folder of skills")
        if skills_dir(path) is None and not _has_skills(path):
            raise ConfigError(f"{path} holds no skill (no sub-folder with a SKILL.md, no skills/ folder)")
        if str(path) not in folders:
            folders.append(str(path))
    return folders


def _has_skills(path: Path) -> bool:
    return bool(scan.scan([path], depth=0)["candidates"])


def _skill(brain: Path, body: dict) -> None:
    root, name, wanted = body.get("root"), str(body.get("name") or ""), body.get("state")
    if wanted not in SKILL_STATES:
        raise ConfigError("state must be default, on or off")
    if not isinstance(root, str) or not root:
        raise ConfigError("a skill switch needs a root path")
    raw = next((env.get("raw") or {} for env in view([Path(root)])["environments"]), {})
    on = [item for item in raw.get("skills.on") or [] if item != name]
    off = [item for item in raw.get("skills.off") or [] if item != name]
    if wanted == "on":
        on.append(name)
    elif wanted == "off":
        off.append(name)
    set_layer({"layer": "environment", "root": root, "values": {"skills.on": on, "skills.off": off}})


def _factory(brain: Path, body: dict) -> None:
    set_layer({"layer": "factory", "values": body.get("values")})


def _overlay_set(brain: Path, body: dict) -> None:
    overlay.set_overlay(body.get("path"))


def _overlay_clear(brain: Path, body: dict) -> None:
    overlay.clear_overlay()


def _scan(brain: Path, body: dict) -> dict:
    raw = body.get("folders")
    if not isinstance(raw, list) or not raw:
        raise ConfigError("give at least one folder to scan")
    result = scan.scan([roots.checked_folder(item, "a folder to scan") for item in raw])
    used = _used_folders(brain)
    for candidate in result["candidates"]:
        path = Path(candidate["path"])
        candidate["used"] = used.get(roots.key(path), "")
        candidate["overlay"] = _overlay_candidate(brain, path)
    return result


def _overlay_candidate(brain: Path, path: Path) -> str:
    """The folder to offer as the personal overlay: a `skills/` folder's parent, unless that is
    AICodeFactory itself or the home folder."""
    if path.name != "skills" or roots.key(path.parent) in (roots.key(brain), roots.key(home())):
        return ""
    return str(path.parent)


def _used_folders(brain: Path) -> dict[str, str]:
    """Skills folder key -> what already uses it (brain, personal overlay, extra folder of a root)."""
    used = {roots.key(brain / "skills"): "AICodeFactory"}
    personal = overlay.current()["skills_dir"]
    if personal:
        used[roots.key(Path(personal))] = "personal overlay"
    for env in view([root.path for root in roots.known_roots(brain)])["environments"]:
        for item in env.get("overlays") or []:
            folder = skills_dir(Path(item)) or Path(item)
            used.setdefault(roots.key(folder), f"extra folder of {env['label'] or env['root']}")
        for project in _project_exports(Path(env["root"])):
            used.setdefault(roots.key(project), "project export")
    return used


def _project_exports(root: Path) -> list[Path]:
    try:
        return [child / "skill" for child in root.iterdir() if (child / "skill").is_dir()]
    except OSError:
        return []


ACTIONS = {
    "root-add": _root_add,
    "root-forget": _root_forget,
    "environment": _environment,
    "skill": _skill,
    "factory": _factory,
    "overlay-set": _overlay_set,
    "overlay-clear": _overlay_clear,
    "scan": _scan,
}
