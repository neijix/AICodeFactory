"""factory-config: get, set and validate. D3SKHAND calls this. The sync calls apply.

stdout is the result. stderr is `ERROR: what failed — what to do`. Exit 0, 1, or 2 (usage).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from engine.factory_env.apply import apply_project
from engine.factory_env.merge import recover
from engine.factory_env.paths import (
    brain_dir,
    environment_file,
    factory_file,
    home,
    is_brain,
    overlay_dir,
    read_layer,
    read_raw,
    write_layer,
)
from engine.factory_env.resolve import at_root, overlay_skill_dirs
from engine.factory_env.schema import STEPS, ConfigError, known_key, validate_document
from engine.factory_env.skills import (
    skill_keep, skill_stamp, skills_begin, skills_current, skills_finish, tree_hash,
)
from engine.factory_env.status import collect
from engine.factory_env.textio import write_lf

AGENTS = (
    "claude", "inherit", "implementer", "reviewer", "verifier", "devops",
    "mlx", "fable", "helpers", "none", "codex", "gemini", "cursor", "copilot",
)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="factory-config")
    sub = parser.add_subparsers(dest="command")
    get = sub.add_parser("get")
    get.add_argument("--root", action="append", default=[])
    get.add_argument("--json", action="store_true")
    put = sub.add_parser("set")
    put.add_argument("--json", action="store_true")
    check = sub.add_parser("validate")
    check.add_argument("--root", action="append", default=[])
    applied = sub.add_parser("apply")
    applied.add_argument("project")
    applied.add_argument("--dry-run", action="store_true")
    current = sub.add_parser("skills-current")
    current.add_argument("roots", nargs="*")
    sub.add_parser("skills-begin")
    sub.add_parser("skills-finish")
    keep = sub.add_parser("skill-keep")
    keep.add_argument("dest")
    keep.add_argument("source")
    stamp = sub.add_parser("skill-stamp")
    stamp.add_argument("dest")
    stamp.add_argument("source")
    stamp.add_argument("origin", nargs="?")
    hashed = sub.add_parser("skill-hash")
    hashed.add_argument("source")
    rebase = sub.add_parser("merge-rebase")
    rebase.add_argument("--git-dir", required=True)
    rebase.add_argument("--work-tree", required=True)
    rebase.add_argument("--ref", default="")
    synced = sub.add_parser("unsynced")
    synced.add_argument("--root", required=True)
    synced.add_argument("--lines", action="store_true")
    brain = sub.add_parser("brain-set")
    brain.add_argument("path")
    sub.add_parser("overlay-dirs")
    args = parser.parse_args(argv)
    if not args.command:
        parser.print_help(sys.stderr)
        return 2
    try:
        return _run(args)
    except ConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


def _run(args: argparse.Namespace) -> int:
    command = args.command
    if command == "get":
        json.dump(_view([Path(item) for item in args.root]), sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return 0
    if command == "set":
        return _set()
    if command == "validate":
        _view([Path(item) for item in args.root])
        print("ok")
        return 0
    if command == "apply":
        return apply_project(Path(args.project), dry_run=args.dry_run)
    if command == "skills-current":
        return skills_current(args.roots)
    if command == "skills-begin":
        return skills_begin()
    if command == "skills-finish":
        return skills_finish()
    if command == "skill-keep":
        return skill_keep(Path(args.dest), Path(args.source))
    if command == "skill-stamp":
        return skill_stamp(Path(args.dest), Path(args.source), args.origin or "")
    if command == "skill-hash":
        print(tree_hash(Path(args.source)))
        return 0
    if command == "merge-rebase":
        return recover(Path(args.git_dir), Path(args.work_tree), args.ref)
    if command == "unsynced":
        return _unsynced(Path(args.root), args.lines)
    if command == "brain-set":
        return _brain_set(Path(args.path))
    if command == "overlay-dirs":
        for item in overlay_skill_dirs():
            print(item)
        return 0
    print(f"ERROR: unknown command {command}", file=sys.stderr)
    return 2


def _view(roots: list[Path]) -> dict:
    brain = brain_dir()
    if not roots:
        parent = brain.parent
        if (parent / ".ai-root").is_dir():
            roots = [parent]
    environments = []
    for root in roots:
        if not root.is_dir():
            continue
        resolved = at_root(root)
        environments.append({
            "root": str(root),
            "label": resolved.label,
            "kind": resolved.kind,
            "file": resolved.environment_path,
            "exists": Path(resolved.environment_path).is_file() if resolved.environment_path else False,
            "claude_profile": resolved.claude_profile,
            "overlays": resolved.environment_raw.get("overlays") or [],
            "skills": [{"name": item.name, "source": item.source, "enabled": item.enabled} for item in resolved.skills],
            "off": resolved.off,
            "workflow": {step: {"agent": choice.agent, "model": choice.model, "effort": choice.effort}
                         for step, choice in resolved.workflow.items()},
            "raw": resolved.environment_raw,
            "error": resolved.error,
        })
    factory_path = factory_file()
    return {
        "brain": str(brain),
        "overlay": str(overlay_dir() or ""),
        "factory_file": str(factory_path or ""),
        "mlx": sys.platform == "darwin",
        "steps": list(STEPS),
        "agents": list(AGENTS),
        "identity": read_layer(factory_path).get("identity", "") if factory_path else "",
        "taste": read_layer(factory_path).get("taste", "") if factory_path else "",
        "factory": read_layer(factory_path) if factory_path else {},
        "environments": environments,
    }


def _set() -> int:
    try:
        body = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        raise ConfigError(f"the settings body is not JSON — {exc.msg}") from exc
    if not isinstance(body, dict):
        raise ConfigError("the settings body must be a JSON object")
    layer = body.get("layer")
    values = body.get("values")
    if not isinstance(values, dict):
        raise ConfigError("values must be an object of settings to change")
    if layer == "factory":
        return _set_factory(values)
    if layer == "environment":
        root = body.get("root")
        if not isinstance(root, str) or not root:
            raise ConfigError("environment settings need a root path")
        return _set_environment(Path(root), values)
    raise ConfigError("layer must be factory or environment")


def _set_factory(values: dict) -> int:
    path = factory_file()
    if path is None:
        raise ConfigError(
            "no personal overlay — create <brain>-private or write its path in ~/.ai-template-overlay-dir, then set again"
        )
    current = read_raw(path)
    updated = _merge(current, values, kind=str(current.get("kind") or ""))
    write_layer(path, updated)
    _commit(path.parent, path, "chore(factory): update personal settings")
    print(str(path))
    return 0


def _set_environment(root: Path, values: dict) -> int:
    if not root.is_dir():
        raise ConfigError(f"{root} is not a folder — pick a code root folder")
    path = environment_file(root)
    current = read_raw(path)
    kind = str(values.get("kind") or current.get("kind") or "")
    updated = _merge(current, values, kind=kind)
    write_layer(path, updated)
    repo = root / ".ai-root"
    _commit(repo if (repo / ".git").exists() else None, path, "chore(factory): update environment settings")
    print(str(path))
    return 0


def _merge(current: dict, values: dict, *, kind: str) -> dict:
    """The file as written plus the changed keys. Only the changes are checked strictly; a key
    this brain does not know (a newer brain on another machine wrote it) is kept as it is."""
    removed = [key for key, value in values.items() if value in ("", [], None)]
    for key in removed:
        if not known_key(key):
            raise ConfigError(f"unknown setting {key!r}")
    changed = validate_document(
        {key: value for key, value in values.items() if key not in removed}, kind=kind, strict=True, check_work=False,
    )
    merged = {key: value for key, value in current.items() if key not in removed}
    merged.update(changed)
    validate_document(merged, kind=kind, strict=False, check_work=True)
    return merged


def _commit(repo: Path | None, path: Path, message: str) -> None:
    if repo is None or not (repo / ".git").exists():
        return
    if _busy(repo):
        print(f"factory: wrote {path} — not committed, the repo is mid-merge or mid-rebase", file=sys.stderr)
        return
    status = _git(repo, ["status", "--porcelain"])
    if status is None:
        return
    relative = path.resolve().relative_to(repo.resolve()).as_posix()
    other = [line for line in status.splitlines() if line[3:].strip() not in (relative, path.name)]
    if other:
        print(f"factory: wrote {path} — not committed, the repo has other changes", file=sys.stderr)
        return
    _git(repo, ["add", "--", relative])
    result = _git(repo, ["commit", "-m", message, "--", relative])
    if result is None:
        print(f"factory: wrote {path} — the commit failed", file=sys.stderr)


def _busy(repo: Path) -> bool:
    git = repo / ".git"
    return (git / "MERGE_HEAD").exists() or (git / "rebase-merge").is_dir() or (git / "rebase-apply").is_dir()


def _git(repo: Path, args: list[str]) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=15, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return "" if result.returncode != 0 and args[0] != "commit" else result.stdout


def _unsynced(root: Path, lines: bool) -> int:
    rows = collect(root)
    if lines:
        for row in rows:
            print(f"{row['role']} {row['path']}: {row.get('detail') or ''}")
        return 0
    json.dump(rows, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def _brain_set(path: Path) -> int:
    if not is_brain(path):
        raise ConfigError(f"{path} is not an AICodeFactory checkout — it needs sync-ai-templates.sh and templates-manifest.txt")
    marker = home() / ".ai-template-dir"
    resolved = str(path.resolve())
    write_lf(marker, resolved + "\n")
    print(resolved)
    return 0
