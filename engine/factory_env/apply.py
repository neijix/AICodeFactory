"""Write the generated layer a project enforces: skillOverrides and a CLAUDE.local.md section.

With no factory.json, no environment.json, nothing turned off and no conflict marker, this
writes nothing and prints nothing. A session with no config stays exactly as it was.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from engine.factory_env.merge import MARKER
from engine.factory_env.resolve import Resolved, StepChoice, discover
from engine.factory_env.schema import STEPS
from engine.factory_env.textio import write_lf

BEGIN = "<!-- ai-templates: factory -->"
END = "<!-- ai-templates: factory-end -->"
OFF_LINE = "Skills off in this environment: "
OFF_END = ". Never use them."


def apply_project(project: Path, *, dry_run: bool) -> int:
    try:
        return _apply(project, dry_run)
    except OSError as exc:
        print(f"ai-sync: factory: {exc}")
        return 0


def _apply(project: Path, dry_run: bool) -> int:
    project = project.resolve() if project.exists() else project
    resolved = discover(project)
    if resolved.error:
        print(f"ai-sync: factory: {resolved.error}")
        return 0
    note = _conflict_line(project)
    if note and not dry_run:
        print(note)
    local_md = project / "CLAUDE.local.md"
    owned = _owned_names(local_md)
    if not resolved.publish:
        # Config removed since the last run: take back what we wrote, nothing else.
        if owned or _has_block(local_md):
            _settings(project, owned, [], dry_run)
            _local_md(local_md, "", dry_run)
        return 0
    changed = _settings(project, owned, resolved.off, dry_run)
    changed = _local_md(local_md, render_block(resolved), dry_run) or changed
    # Claude Code hides an off skill itself (skillOverrides): say it again only on a change.
    if resolved.off and not dry_run and (changed or not _under_claude()):
        names = ", ".join(resolved.off)
        print(f"ai-sync: skills off in this environment: {names} — never use them.")
    return 0


def render_block(resolved: Resolved) -> str:
    lines = [BEGIN, "# Factory", ""]
    if resolved.identity or resolved.taste:
        lines.append("## Personal")
        lines.append("")
        if resolved.identity:
            lines.append(resolved.identity)
            lines.append("")
        if resolved.taste:
            lines.append(resolved.taste)
            lines.append("")
    if resolved.off:
        lines.append(OFF_LINE + ", ".join(resolved.off) + OFF_END)
        lines.append("")
    lines.append("Agent per step (brain, then factory.json, then this environment):")
    lines.append("")
    lines.append("| Step | Agent | Model |")
    lines.append("|---|---|---|")
    for step in STEPS:
        choice: StepChoice = resolved.workflow[step]
        lines.append(f"| {step} | {choice.agent} | {choice.model} |")
    lines.append("")
    design = resolved.workflow["design"]
    if design.agent == "claude":
        lines.append(
            "If you are not Claude and you start the design step, continue and warn once: "
            "the design step is configured for Claude."
        )
        lines.append("")
    prefilter = resolved.workflow["review-prefilter"]
    if prefilter.agent == "mlx":
        lines.append(
            "Review pre-filter: when mlx-local health answers, run it first, then the Claude "
            "reviewers still run and triage. Never for a work environment or a security review."
        )
        lines.append("")
    lines.append(END)
    return "\n".join(lines) + "\n"


def _settings(project: Path, owned: list[str], off: list[str], dry_run: bool) -> bool:
    """Set our names to "off" and take back the ones we no longer own. True when written.

    Only names we wrote are ours: any other entry, or a value the user changed, stays.
    """
    path = project / ".claude" / "settings.local.json"
    try:
        data = _read_settings(path)
    except ValueError:
        print(f"ai-sync: factory: {path} is not a JSON object — left untouched")
        return False
    current = data.get("skillOverrides")
    if current is not None and not isinstance(current, dict):
        print(f"ai-sync: factory: skillOverrides in {path} is not an object — left untouched")
        return False
    overrides = dict(current or {})
    for name in owned:
        if name not in off and overrides.get(name) == "off":
            overrides.pop(name)
    for name in off:
        overrides.setdefault(name, "off")
    if overrides == (current or {}):
        return False
    if _tracked(project, ".claude/settings.local.json"):
        return False  # a team's file: CLAUDE.local.md still lists the skills off
    if dry_run:
        print(f"  [write]  {path} (skillOverrides)")
        return False
    if overrides:
        data["skillOverrides"] = overrides
    else:
        data.pop("skillOverrides", None)
    path.parent.mkdir(parents=True, exist_ok=True)
    _replace(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"ai-sync: factory — skillOverrides in {path.name}")
    return True


def _tracked(project: Path, relative: str) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(project), "ls-files", "--error-unmatch", "--", relative],
            capture_output=True, text=True, timeout=10, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def _under_claude() -> bool:
    return bool(os.environ.get("CLAUDECODE") or os.environ.get("CLAUDE_PROJECT_DIR"))


def _read_settings(path: Path) -> dict | None:
    if not path.is_file() or path.stat().st_size == 0:
        return {}
    try:
        raw = path.read_text(encoding="utf-8-sig")
        data = {} if raw.strip() == "" else json.loads(raw)
    except (OSError, json.JSONDecodeError):
        raise ValueError(path)
    if not isinstance(data, dict):
        raise ValueError(path)
    return data


def _local_md(path: Path, block: str, dry_run: bool) -> bool:
    """Write the Factory section (an empty block removes it). True when written."""
    try:
        current = path.read_text(encoding="utf-8") if path.is_file() else ""
    except OSError:
        print(f"ai-sync: factory: cannot read {path}")
        return False
    updated = _splice(current, block)
    if updated == current:
        return False
    if dry_run:
        print("  [write]  CLAUDE.local.md (factory)")
        return False
    if updated == "":
        path.unlink()  # the file held our section only
        return True
    _replace(path, updated)
    if block:
        print("ai-sync: factory — read the Factory section of CLAUDE.local.md")
    return True


def _block_of(text: str) -> str:
    if BEGIN not in text or END not in text:
        return ""
    return text[text.index(BEGIN) : text.index(END) + len(END)]


def _has_block(path: Path) -> bool:
    try:
        return path.is_file() and BEGIN in path.read_text(encoding="utf-8")
    except OSError:
        return False


def _owned_names(path: Path) -> list[str]:
    """The skills our last run turned off, read back from the section it wrote."""
    try:
        block = _block_of(path.read_text(encoding="utf-8")) if path.is_file() else ""
    except OSError:
        return []
    for line in block.splitlines():
        if line.startswith(OFF_LINE) and line.endswith(OFF_END):
            listed = line[len(OFF_LINE) : -len(OFF_END)]
            return [name.strip() for name in listed.split(",") if name.strip()]
    return []


def _splice(text: str, block: str) -> str:
    if block and not block.endswith("\n"):
        block += "\n"
    if BEGIN in text and END in text:
        pre = text[: text.index(BEGIN)].rstrip()
        post = text[text.index(END) + len(END) :].lstrip("\n")
        parts = [part for part in (pre, block.rstrip("\n"), post.rstrip("\n")) if part]
        return "\n\n".join(parts) + "\n" if parts else ""
    if not block:
        return text
    if text.strip() == "":
        return block
    return text.rstrip() + "\n\n" + block


def _replace(path: Path, text: str) -> None:
    temporary = path.with_name(path.name + ".factory-tmp")
    try:
        write_lf(temporary, text)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def _conflict_line(project: Path) -> str:
    """The hidden repo's last pull stopped on a conflict (merge.py or the engine wrote it)."""
    git_dir = project / ".git" / "ai-context"
    marker = git_dir / MARKER
    if not marker.is_file():
        return ""
    files: list[str] = []
    ref = ""
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if isinstance(data, dict):
        for relative, keys in (data.get("clashes") or {}).items():
            files.append(f"{relative} ({', '.join(sorted(keys))})")
        files.extend(str(item) for item in data.get("other") or [])
        ref = str(data.get("ref") or "")
    what = f" on {'; '.join(files)}" if files else ""
    command = f"git --git-dir={git_dir} --work-tree={project} rebase {ref or '<its remote branch>'}"
    return f"ai-sync: private AI docs: the last pull stopped on a conflict{what} — resolve by hand: {command}"
