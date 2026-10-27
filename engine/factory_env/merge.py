"""Key-level three-way merge of config.local JSON when two machines edit different keys.

In a rebase, stage 1 is the common base, stage 2 the remote (what we rebase onto) and stage 3
the local commit being replayed. A key changed on one side only takes that side, a deletion
included. A key both sides changed differently is a clash: nothing is merged, the rebase is
aborted as before, and `sync-conflict.json` records it so the next session start says so — the
Stop hook drops the line the engine prints. Any other conflicted file is never touched.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from engine.factory_env.textio import write_lf

MARKER = "sync-conflict.json"
_MISSING = object()


def merge_values(base: dict, remote: dict, local: dict) -> tuple[dict, dict]:
    """Three-way merge by top-level key. Returns (merged, clashes)."""
    merged: dict = {}
    clashes: dict = {}
    for key in list(remote) + [key for key in local if key not in remote] + [
        key for key in base if key not in remote and key not in local
    ]:
        was = base.get(key, _MISSING)
        theirs = remote.get(key, _MISSING)
        ours = local.get(key, _MISSING)
        if ours == was:
            value = theirs
        elif theirs == was or theirs == ours:
            value = ours
        else:
            clashes[key] = {
                "base": None if was is _MISSING else was,
                "remote": None if theirs is _MISSING else theirs,
                "local": None if ours is _MISSING else ours,
            }
            value = theirs
        if value is not _MISSING:
            merged[key] = value
    return merged, clashes


def recover(git_dir: Path, work_tree: Path, ref: str = "") -> int:
    """Finish a rebase that only conflicts on config.local JSON. Exit 1 when it was aborted.

    ``ref`` is the branch rebased onto, kept in the marker for the line that tells how to redo it.
    """
    try:
        return _recover(git_dir, work_tree, ref)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        _write_marker(git_dir, {"clashes": {}, "other": [], "error": str(exc), "ref": ref})
        _abort(git_dir, work_tree)
        return 1


def _recover(git_dir: Path, work_tree: Path, ref: str) -> int:
    unmerged = _unmerged(git_dir, work_tree)
    json_paths = [path for path in unmerged if _is_config_json(path)]
    others = [path for path in unmerged if path not in json_paths]
    clashes: dict = {}
    merged_files: dict[str, dict] = {}
    for relative in json_paths:
        base = _stage(git_dir, work_tree, relative, 1)
        remote = _stage(git_dir, work_tree, relative, 2)
        local = _stage(git_dir, work_tree, relative, 3)
        if remote is None or local is None:
            others.append(relative)
            continue
        merged, clash = merge_values(base or {}, remote, local)
        merged_files[relative] = merged
        if clash:
            clashes[relative] = clash
    if others or clashes or not json_paths:
        _write_marker(git_dir, {"clashes": clashes, "other": others, "ref": ref})
        _abort(git_dir, work_tree)
        return 1
    for relative, data in merged_files.items():
        destination = work_tree / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        write_lf(destination, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        _git(git_dir, work_tree, ["add", "--", relative])
    continued = _git(git_dir, work_tree, ["rebase", "--continue"], editor=True)
    if continued.returncode != 0:
        _write_marker(git_dir, {"clashes": {}, "other": json_paths, "ref": ref})
        _abort(git_dir, work_tree)
        return 1
    marker = git_dir / MARKER
    if marker.is_file():
        marker.unlink()
    return 0


def _is_config_json(relative: str) -> bool:
    parts = Path(relative).parts
    return len(parts) >= 2 and parts[0] == "config.local" and parts[-1].endswith(".json")


def _unmerged(git_dir: Path, work_tree: Path) -> list[str]:
    result = _git(git_dir, work_tree, ["diff", "--name-only", "--diff-filter=U"])
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _stage(git_dir: Path, work_tree: Path, relative: str, stage: int) -> dict | None:
    result = _git(git_dir, work_tree, ["show", f":{stage}:{relative}"])
    if result.returncode != 0:
        return None
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    return data


def _write_marker(git_dir: Path, payload: dict) -> None:
    try:
        write_lf(git_dir / MARKER, json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    except OSError:
        return


def _abort(git_dir: Path, work_tree: Path) -> None:
    try:
        _git(git_dir, work_tree, ["rebase", "--abort"])
    except (OSError, subprocess.SubprocessError):
        return


def _git(git_dir: Path, work_tree: Path, args: list[str], *, editor: bool = False) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    if editor:
        env["GIT_EDITOR"] = "true"
    return subprocess.run(
        ["git", f"--git-dir={git_dir}", f"--work-tree={work_tree}", *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15, check=False, env=env,
    )
