"""What the page shows about each project: doctor's record, its status, and its skills.

Bootstrap state is never computed here: `aicf doctor --json` is the one implementation, this
module only reads its `projects` records and adds what doctor does not know (skills).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

from engine.factory_env.paths import overlay_dir, skills_dir
from engine.factory_env.resolve import overlay_skill_dirs

# status key -> (label, rank). A lower rank sorts first: the projects that need work on top.
STATUSES = {
    "missing": ("Not bootstrapped", 0),
    "unfinished": ("Bootstrap unfinished", 1),
    "stale": ("AI files stale", 2),
    "off-plan": ("Off the private-layer plan", 3),
    "ok": ("Bootstrapped", 4),
}


class DoctorError(Exception):
    """doctor could not run or did not print its JSON document."""


def run_doctor(brain: Path) -> dict:
    """`aicf doctor --json`, check-only: it writes nothing."""
    if os.name == "nt":
        shell = shutil.which("pwsh") or shutil.which("powershell")
        if not shell:
            raise DoctorError("PowerShell not found — doctor.ps1 needs pwsh or powershell")
        cmd = [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
               str(brain / "engine" / "doctor.ps1"), "--json"]
    else:
        cmd = ["bash", str(brain / "engine" / "doctor.sh"), "--json"]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900)
    return parse_doctor(proc.stdout.decode("utf-8", "replace"))


def parse_doctor(text: str) -> dict:
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise DoctorError(f"doctor --json printed no JSON document ({exc}) — run aicf doctor to see why") from exc
    if not isinstance(data, dict) or not isinstance(data.get("projects"), list):
        raise DoctorError("doctor --json has no projects list — is this brain older than schema 1?")
    return data


def classify(record: dict, code_root: str = "") -> tuple[str, str]:
    """(status key, next step) for one doctor project record. A project of another code root than
    `code_root` (the brain's) is named by its path: `aicf update` finds only siblings by name."""
    name = record.get("name", "")
    root = str(record.get("root") or "")
    if code_root and root and _key(root) != _key(code_root):
        name = str(record.get("path") or name)
    if not record.get("bootstrapped"):
        return "missing", f"aicf update {name}, then run /bootstrap-ai in it"
    if record.get("placeholder_docs") or record.get("missing_headings"):
        return "unfinished", "run /bootstrap-ai in it: living docs or AGENTS.md sections still pending"
    if record.get("ai_files") == "stale":
        return "stale", f"aicf update {name}"
    if record.get("plan") not in (None, "ok"):
        return "off-plan", "preview: aicf update --migrate; apply: aicf update --migrate --yes"
    return "ok", ""


def _skill_names(folder: Path | None) -> list[str]:
    """Sub-folders holding a SKILL.md; an unreadable or missing folder has none."""
    if folder is None:
        return []
    try:
        return sorted(p.name for p in folder.iterdir() if (p / "SKILL.md").is_file())
    except OSError:
        return []


def _skill_sources(brain: Path) -> list[tuple[Path, str]]:
    """Every skills folder this machine installs from, lowest precedence first: the brain wins."""
    overlays: list[Path] = []
    first = overlay_dir()
    if first is not None:
        overlays.append(skills_dir(first) or first / "skills")
    overlays += [Path(p) for p in overlay_skill_dirs()]
    return [(folder, "overlay") for folder in overlays] + [(brain / "skills", "brain")]


def skill_catalog(brain: Path) -> dict[str, str]:
    """Every skill this machine installs, name -> source (`brain` or `overlay`). The brain wins."""
    catalog: dict[str, str] = {}
    for folder, source in _skill_sources(brain):
        for name in _skill_names(folder):
            catalog[name] = source
    return catalog


def metadata_project(skill_md: Path) -> str:
    """The `metadata: project:` of a SKILL.md frontmatter: the program repo the skill drives."""
    try:
        lines = skill_md.read_text(encoding="utf-8-sig").splitlines()
    except OSError:
        return ""
    if not lines or lines[0].strip() != "---":
        return ""
    in_metadata = False
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if not line.startswith((" ", "\t")):
            in_metadata = line.rstrip() == "metadata:"
        elif in_metadata:
            key, _, value = line.strip().partition(":")
            if key == "project":
                return value.strip().strip("\"'")
    return ""


def skill_projects(brain: Path) -> dict[str, str]:
    """Skill name -> the project it drives, for the skill that wins each name."""
    drives: dict[str, str] = {}
    for folder, _ in _skill_sources(brain):
        for name in _skill_names(folder):
            drives[name] = metadata_project(folder / name / "SKILL.md")
    return {name: project for name, project in drives.items() if project}


def local_skills(project: Path) -> list[str]:
    """Skills only this project carries: `.claude/skills/<name>/SKILL.md`."""
    return _skill_names(project / ".claude" / "skills")


def skills_off(project: Path) -> list[str]:
    """Names set to "off" in the project's `.claude/settings.local.json` `skillOverrides`."""
    path = project / ".claude" / "settings.local.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return []
    overrides = data.get("skillOverrides") if isinstance(data, dict) else None
    if not isinstance(overrides, dict):
        return []
    return sorted(name for name, value in overrides.items() if value == "off")


def _key(path: str) -> str:
    return os.path.normcase(os.path.normpath(path))


def build_projects(doctor: dict, usage: dict, drives: dict[str, str] | None = None) -> list[dict]:
    """One row per doctor project, need-work first, then by name. `drives`: skill -> project."""
    rows = []
    drives = drives or {}
    code_root = str(doctor.get("code_root") or "")
    for record in doctor.get("projects", []):
        if not isinstance(record, dict) or not record.get("name"):
            continue
        status, action = classify(record, code_root)
        path = Path(str(record.get("path", "")))
        rows.append({
            "name": record["name"],
            "path": str(path),
            "root": str(record.get("root") or ""),
            "status": status,
            "status_label": STATUSES[status][0],
            "action": action,
            "remote": bool(record.get("remote")),
            "dirty": bool(record.get("dirty")),
            "unpushed": record.get("unpushed"),
            "placeholder_docs": list(record.get("placeholder_docs") or []),
            "missing_headings": list(record.get("missing_headings") or []),
            "local_skills": local_skills(path),
            "agent_skills": sorted(k for k, v in drives.items() if v.lower() == str(record["name"]).lower()),
            "skills_off": skills_off(path),
            "skills_used": usage.get(str(record.get("path", "")), {}),
        })
    rows.sort(key=lambda r: (STATUSES[r["status"]][1], r["name"].lower()))
    return rows


def build_skills(catalog: dict[str, str], projects: list[dict],
                 drives: dict[str, str] | None = None) -> list[dict]:
    """One row per skill (installed, project-local, or seen in a transcript), most used first."""
    sources = dict(catalog)
    drives = drives or {}
    for project in projects:
        for name in project["local_skills"]:
            sources.setdefault(name, f"local: {project['name']}")
        for name in project["skills_used"]:
            sources.setdefault(name, "other")
    rows = []
    for name, source in sources.items():
        users = {p["name"]: p["skills_used"][name] for p in projects if name in p["skills_used"]}
        lasts = [u["last"] for u in users.values() if u.get("last")]
        rows.append({
            "name": name,
            "source": source,
            "drives": drives.get(name, ""),
            "uses": sum(u["count"] for u in users.values()),
            "last": max(lasts) if lasts else "",
            "projects": {k: users[k]["count"] for k in sorted(users, key=str.lower)},
            "off_in": sorted(p["name"] for p in projects if name in p["skills_off"]),
        })
    rows.sort(key=lambda r: (-r["uses"], r["name"]))
    return rows


def summary(projects: list[dict]) -> dict[str, int]:
    counts = {key: 0 for key in STATUSES}
    for project in projects:
        counts[project["status"]] += 1
    counts["total"] = len(projects)
    return counts
