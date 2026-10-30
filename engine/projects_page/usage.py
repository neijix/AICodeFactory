"""Which skill each project used, read from this machine's Claude Code transcripts.

A use is a `Skill` tool call in an assistant message, or a user prompt that typed `/<skill>`.
Transcripts are read locally and never leave the machine. Other agents keep no comparable log,
so only Claude Code sessions count (every config dir: the default, `CLAUDE_CONFIG_DIR`, and the
profiles `install-global` records in `~/.claude-profiles`).
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


def config_dirs(home: Path) -> list[Path]:
    """Every Claude Code config dir on this machine, once each."""
    found = [home / ".claude"]
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        found.append(Path(os.environ["CLAUDE_CONFIG_DIR"]).expanduser())
    try:
        lines = (home / ".claude-profiles").read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    for line in lines:
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1].strip():
            raw = parts[1].strip()
            found.append(home / raw[2:] if raw.startswith("~/") else Path(raw))
    unique: list[Path] = []
    seen = set()
    for folder in found:
        key = os.path.normcase(os.path.abspath(str(folder)))
        if key not in seen and folder.is_dir():
            seen.add(key)
            unique.append(folder)
    return unique


class ProjectResolver:
    """Maps a session's cwd to the path of the project it ran in, or None. Projects come from
    every code root doctor walks, so a work root's sessions count too."""

    def __init__(self, projects: list[str]) -> None:
        # As given and resolved: git prints a worktree's main checkout resolved (macOS: /private/var).
        self.paths: dict[str, str] = {}
        for project in projects:
            for form in (os.path.abspath(project), os.path.realpath(project)):
                self.paths.setdefault(os.path.normcase(form), project)
        # Longest first: a project nested in another one's folder wins over its parent.
        self.order = sorted(self.paths, key=len, reverse=True)
        self.cache: dict[str, str | None] = {}

    def _under_root(self, path: str) -> str | None:
        path = os.path.normcase(os.path.abspath(path))
        for folder in self.order:
            if path == folder or path.startswith(folder.rstrip(os.sep) + os.sep):
                return self.paths[folder]
        return None

    def __call__(self, cwd: str) -> str | None:
        if not cwd:
            return None
        if cwd not in self.cache:
            self.cache[cwd] = self._under_root(cwd) or self._from_worktree(cwd)
        return self.cache[cwd]

    def _from_worktree(self, cwd: str) -> str | None:
        """A worktree outside the root (D3SKHAND's): its main checkout, while it still exists."""
        if not os.path.isdir(cwd):
            return None
        try:
            out = subprocess.run(
                ["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=10,
            ).stdout.decode("utf-8", "replace").strip()
        except (OSError, subprocess.SubprocessError):
            return None
        return self._under_root(os.path.dirname(out)) if out else None


def _blocks(message: object) -> list:
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return content if isinstance(content, list) else []


def skills_in_line(entry: dict, known: set[str]) -> list[tuple[str, str]]:
    """(dedupe key, skill name) for each skill use in one transcript entry."""
    kind = entry.get("type")
    uses = []
    for block in _blocks(entry.get("message")):
        if not isinstance(block, dict):
            continue
        if kind == "assistant" and block.get("type") == "tool_use" and block.get("name") == "Skill":
            name = (block.get("input") or {}).get("skill")
            if isinstance(name, str) and name:
                uses.append((str(block.get("id") or entry.get("uuid")), name.lstrip("/")))
        elif kind == "user" and block.get("type") == "text":
            text = block.get("text") or ""
            start = text.find("<command-name>")
            end = text.find("</command-name>")
            if start >= 0 and end > start:
                name = text[start + len("<command-name>"):end].strip().lstrip("/")
                if name in known:
                    uses.append((str(entry.get("uuid")), name))
    return uses


def scan(dirs: list[Path], resolve: ProjectResolver, known: set[str]) -> tuple[dict, int]:
    """({project path: {skill: {count, last}}}, uses whose session is in no known project)."""
    usage: dict[str, dict[str, dict]] = {}
    seen: set[str] = set()
    orphans = 0
    for folder in dirs:
        for path in sorted((folder / "projects").glob("**/*.jsonl")):
            try:
                handle = path.open("rb")
            except OSError:
                continue
            with handle:
                for raw in handle:
                    # Only assistant/user lines matter; api-request lines repeat the history.
                    if b'"Skill"' not in raw and b"<command-name>" not in raw:
                        continue
                    try:
                        entry = json.loads(raw)
                    except ValueError:
                        continue
                    if not isinstance(entry, dict):
                        continue
                    for key, name in skills_in_line(entry, known):
                        if key in seen:
                            continue
                        seen.add(key)
                        project = resolve(str(entry.get("cwd") or ""))
                        if project is None:
                            orphans += 1
                            continue
                        slot = usage.setdefault(project, {}).setdefault(name, {"count": 0, "last": ""})
                        slot["count"] += 1
                        stamp = str(entry.get("timestamp") or "")
                        if stamp > slot["last"]:
                            slot["last"] = stamp
    return usage, orphans
