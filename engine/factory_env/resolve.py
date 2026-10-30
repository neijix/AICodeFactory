"""Brain defaults, then factory.json, then the environment. Work never keeps MLX."""

from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from engine.factory_env.environments import code_roots, is_shared_root, key, other_skill_folders, skill_folders
from engine.factory_env.paths import (
    brain_dir,
    code_root_of,
    environment_file,
    factory_file,
    is_work_path,
    kind_from_path,
    label_from_kind,
    overlay_dir,
    skills_dir,
    read_layer,
)
from engine.factory_env.schema import DEFAULT_WORKFLOW, STEPS, ConfigError

SOURCES = ("brain", "personal", "work", "project", "environment", "other environment")


@dataclass(frozen=True)
class StepChoice:
    agent: str
    model: str
    effort: str


@dataclass(frozen=True)
class SkillInfo:
    name: str
    source: str
    enabled: bool


@dataclass
class Resolved:
    label: str
    kind: str
    identity: str
    taste: str
    claude_profile: str
    workflow: dict[str, StepChoice]
    skills: list[SkillInfo]
    off: list[str]
    publish: bool
    brain: str
    overlay: str
    factory_path: str
    environment_path: str
    root: str
    mlx: bool
    factory_raw: dict
    environment_raw: dict
    error: str = ""


def discover(project: Path) -> Resolved:
    """What this project should enforce. A broken config file is reported, not fatal."""
    return _build(code_root_of(project), project)


def at_root(root: Path) -> Resolved:
    """The same resolution for a code root, used by the settings page."""
    return _build(root if root.is_dir() else None, root)


def _build(root: Path | None, project: Path) -> Resolved:
    loaded = _load_layers(root)
    if isinstance(loaded, str):
        return _empty(loaded)
    brain, overlay, factory_path, env_path, factory, environment, error = loaded
    if error:
        resolved = _empty(error)
        resolved.brain = str(brain)
        return resolved
    kind = str(environment.get("kind") or kind_from_path(root))
    label = str(environment.get("label") or label_from_kind(kind))
    skills = _skills(brain, overlay, environment.get("overlays") or [], root, factory, environment, kind)
    off = [item.name for item in skills if not item.enabled]
    return _resolved(root, project, brain, overlay, factory_path, env_path, factory, environment, kind, label, skills, off)


def _load_layers(root: Path | None):
    """(brain, overlay, factory path, env path, factory, environment, error) or an error string."""
    try:
        brain = brain_dir()
    except ConfigError as exc:
        return str(exc)
    factory_path = factory_file()
    env_path = environment_file(root) if root else None
    try:
        factory = read_layer(factory_path)
        environment = read_layer(env_path)
        error = ""
    except (ConfigError, OSError) as exc:
        factory, environment, error = {}, {}, str(exc)
    return brain, overlay_dir(), factory_path, env_path, factory, environment, error


def _resolved(root, project, brain, overlay, factory_path, env_path, factory, environment, kind, label, skills, off) -> Resolved:
    return Resolved(
        label=label,
        kind=kind,
        identity=str(factory.get("identity") or ""),
        taste=str(factory.get("taste") or ""),
        claude_profile=str(environment.get("claude_profile") or ""),
        workflow=_workflow([factory, environment], kind),
        skills=skills,
        off=off,
        publish=_publish(factory_path, env_path, off),
        brain=str(brain),
        overlay=str(overlay or ""),
        factory_path=str(factory_path or ""),
        environment_path=str(env_path or ""),
        root=str(root or ""),
        mlx=sys.platform == "darwin",
        factory_raw=factory,
        environment_raw=environment,
    )


def _publish(factory_path: Path | None, env_path: Path | None, off: list[str]) -> bool:
    return _is_file(factory_path) or _is_file(env_path) or bool(off)


def _is_file(path: Path | None) -> bool:
    return path is not None and path.is_file()


def _empty(error: str) -> Resolved:
    return Resolved(
        label="", kind="personal", identity="", taste="", claude_profile="",
        workflow={step: StepChoice(*DEFAULT_WORKFLOW[step]) for step in STEPS},
        skills=[], off=[], publish=False, brain="", overlay="", factory_path="",
        environment_path="", root="", mlx=sys.platform == "darwin",
        factory_raw={}, environment_raw={}, error=error,
    )


def _workflow(layers: list[dict], kind: str) -> dict[str, StepChoice]:
    choices = {step: StepChoice(*DEFAULT_WORKFLOW[step]) for step in STEPS}
    for layer in layers:
        for step in STEPS:
            current = choices[step]
            agent = layer.get(f"workflow.{step}.agent", current.agent)
            model = layer.get(f"workflow.{step}.model", current.model)
            effort = layer.get(f"workflow.{step}.effort", current.effort)
            choices[step] = StepChoice(str(agent), str(model), str(effort))
    if kind == "work":
        for step, choice in list(choices.items()):
            if choice.agent == "mlx":
                choices[step] = StepChoice("none", choice.model, choice.effort)
    return choices


def _enabled(name: str, source: str, kind: str, factory: dict, environment: dict) -> bool:
    env_off = set(environment.get("skills.off") or [])
    env_on = set(environment.get("skills.on") or [])
    factory_off = set(factory.get("skills.off") or [])
    factory_on = set(factory.get("skills.on") or [])
    if name in env_off:
        return False
    if name in env_on:
        return True
    if name in factory_off:
        return False
    if name in factory_on:
        return True
    if source in ("brain", "environment"):
        return True
    if source == "personal":
        return kind != "work"
    if source == "work":
        return kind == "work"
    return False


def _skills(brain: Path, overlay: Path | None, extra: list, root: Path | None,
            factory: dict, environment: dict, kind: str) -> list[SkillInfo]:
    found: dict[str, str] = {}
    for folder, source in _skill_roots(brain, overlay, extra, root):
        for name in _skill_names(folder):
            found.setdefault(name, source)
    return [
        SkillInfo(name, source, _enabled(name, source, kind, factory, environment))
        for name, source in sorted(found.items())
    ]


def _skill_roots(brain: Path, overlay: Path | None, extra: list, root: Path | None) -> list[tuple[Path, str]]:
    roots = [(brain / "skills", "brain")]
    if overlay is not None:
        roots.append((skills_dir(overlay) or overlay / "skills", _overlay_source(overlay)))
    shared = root is None or is_shared_root(root)
    for item in extra:
        path = Path(str(item))
        if not path.is_dir():
            continue
        roots.append((skills_dir(path) or path, _overlay_source(path) if shared else "environment"))
    if root is not None and root.is_dir():
        for project in _projects(root):
            exported = project / "skill"
            if exported.is_dir():
                roots.append((exported, "project"))
    # Installed on this machine for another environment: off here unless this one turns it on.
    for folder, shared_folder in other_skill_folders(root):
        roots.append((folder, _overlay_source(folder) if shared_folder else "other environment"))
    return roots


def _overlay_source(path: Path) -> str:
    """An overlay is "work" when it sits under a work root, or by convention when its folder
    name ends with `-work` (e.g. `AICodeFactory-work`); any other overlay is "personal"."""
    return "work" if is_work_path(path) or path.name.lower().endswith("-work") else "personal"


def _projects(root: Path) -> list[Path]:
    skipped = {".ai-root", ".git", "node_modules"}
    found = []
    try:
        children = list(root.iterdir())
    except OSError:
        return []
    for child in children:
        if child.name.startswith(".") or child.name in skipped or not child.is_dir():
            continue
        found.append(child)
    return found


def _skill_names(folder: Path) -> list[str]:
    if not folder.is_dir():
        return []
    names = []
    try:
        children = list(folder.iterdir())
    except OSError:
        return []
    for child in children:
        if child.is_dir() and (child / "SKILL.md").is_file() and _safe_name(child.name):
            names.append(child.name)
    return names


def _safe_name(name: str) -> bool:
    return bool(name) and "/" not in name and "\\" not in name and name not in (".", "..")


def overlay_skill_dirs() -> list[str]:
    """The skills folders every environment names, each once: all of them are installed on this
    machine; each environment turns on its own (resolve._enabled)."""
    dirs: list[str] = []
    seen: set[str] = set()
    for root in code_roots():
        for folder in skill_folders(root):
            if key(folder) not in seen:
                seen.add(key(folder))
                dirs.append(str(folder))
    return dirs
