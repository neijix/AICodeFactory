#!/usr/bin/env python3
"""Run the fenced code blocks a doc page marks as runnable, in a throw-away HOME.

    python3 tests/run-doc-blocks.py docs/getting-started.md [more.md ...]
    python3 tests/run-doc-blocks.py --list docs/getting-started.md
    python3 tests/run-doc-blocks.py --keep docs/getting-started.md   # keep the sandbox

A block is runnable when the line before its opening fence is `<!-- runnable -->`:
```bash blocks run with bash -e, ```powershell blocks with pwsh. The blocks of all the files run
in order, each in its own process started in $HOME, and the run stops at the first non-zero exit.

The sandbox never touches the real home folder or this checkout:
- HOME, TMPDIR and the XDG folders point inside a temporary directory, and the environment is
  rebuilt from scratch, so no AI_* setting, overlay marker or agent credential leaks in;
- this checkout's files (tracked and untracked, minus .gitignore'd ones) are committed into a
  scratch git repo, and the public clone URL in a block is replaced by that repo's path, so
  `git clone` installs what you are about to commit, offline;
- PATH drops every folder holding a `claude` executable, so `aicf init` does not start a real,
  paid agent session.
Stdlib only.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_URL = "https://github.com/neijix/AICodeFactory.git"
MARKER = "<!-- runnable -->"
LANGS = {"bash": "bash", "sh": "bash", "powershell": "pwsh", "pwsh": "pwsh"}
FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([\w+-]*)\s*$")


def parse_blocks(path: Path) -> list[tuple[int, str, str]]:
    """(line number, language, code) of every runnable block in a Markdown file."""
    lines = path.read_text(encoding="utf-8").splitlines()
    blocks = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == MARKER:
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            m = FENCE.match(lines[j]) if j < len(lines) else None
            if not m or m.group(3).lower() not in LANGS:
                raise SystemExit(
                    f"{path}:{i + 1}: {MARKER} must precede a ```bash or ```powershell block"
                )
            fence, lang, start = m.group(2), m.group(3).lower(), j + 1
            k = start
            while k < len(lines) and not lines[k].strip().startswith(fence):
                k += 1
            blocks.append((start, lang, "\n".join(lines[start:k]) + "\n"))
            i = k + 1
            continue
        i += 1
    return blocks


def sandbox_env(box: Path) -> dict[str, str]:
    home = box / "home"
    path = []
    for d in os.environ.get("PATH", "/usr/bin:/bin").split(os.pathsep):
        if d and not (Path(d) / "claude").exists() and d not in path:
            path.append(d)
    env = {
        "PATH": os.pathsep.join(path),
        "HOME": str(home),
        "USERPROFILE": str(home),
        "TMPDIR": str(box / "tmp"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local" / "share"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "TERM": "dumb",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
    }
    for d in ("tmp", "home/.config"):
        (box / d).mkdir(parents=True, exist_ok=True)
    (home / ".gitconfig").write_text(
        "[user]\n\tname = Docs Runner\n\temail = docs-runner@example.invalid\n"
        "[init]\n\tdefaultBranch = main\n",
        encoding="utf-8",
    )
    return env


def snapshot_checkout(box: Path, env: dict[str, str]) -> Path:
    """Commit this checkout's current files into a scratch repo; return its path."""
    src = box / "source" / "AICodeFactory"
    src.mkdir(parents=True)
    listed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-co", "--exclude-standard", "-z"],
        check=True, stdout=subprocess.PIPE,
    ).stdout.decode("utf-8").split("\0")
    for rel in filter(None, listed):
        f = ROOT / rel
        if f.is_symlink() or not f.is_file():
            continue
        dest = src / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dest)
    for cmd in (["git", "init", "-q"], ["git", "add", "-A"],
                ["git", "commit", "-q", "-m", "docs-runner snapshot"]):
        subprocess.run(cmd, cwd=src, env=env, check=True)
    return src


def run(files: list[Path], keep: bool) -> int:
    blocks = [(f, *b) for f in files for b in parse_blocks(f)]
    if not blocks:
        print("run-doc-blocks: no runnable block found")
        return 0
    box = Path(tempfile.mkdtemp(prefix="aicf-doc-blocks-")).resolve()
    real_home = Path(os.path.expanduser("~")).resolve()
    try:
        env = sandbox_env(box)
        home = Path(env["HOME"])
        assert home != real_home and box in home.parents, "sandbox HOME escaped the sandbox"
        src = snapshot_checkout(box, env)
        for n, (f, line, lang, code) in enumerate(blocks, 1):
            code = code.replace(PUBLIC_URL, str(src))
            print(f"--- [{n}/{len(blocks)}] {f}:{line} ({lang})", flush=True)
            script = box / "tmp" / f"block{n}.{'ps1' if lang in ('powershell', 'pwsh') else 'sh'}"
            if LANGS[lang] == "pwsh":
                script.write_text(
                    "$ErrorActionPreference = 'Stop'\n$PSNativeCommandUseErrorActionPreference = $true\n"
                    + code, encoding="utf-8")
                cmd = ["pwsh", "-NoProfile", "-NonInteractive", "-File", str(script)]
            else:
                script.write_text("set -eo pipefail\n" + code, encoding="utf-8")
                cmd = ["bash", str(script)]
            try:
                proc = subprocess.run(cmd, cwd=home, env=env, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, timeout=600)
            except subprocess.TimeoutExpired:
                print(f"run-doc-blocks: {f}:{line}: timed out")
                return 1
            out = proc.stdout.decode("utf-8", "replace")
            sys.stdout.write(out if out.endswith("\n") or not out else out + "\n")
            if proc.returncode != 0:
                print(f"run-doc-blocks: {f}:{line}: exit {proc.returncode}")
                return 1
        print(f"run-doc-blocks: {len(blocks)} block(s) passed")
        return 0
    finally:
        if keep:
            print(f"run-doc-blocks: sandbox kept at {box}")
        else:
            shutil.rmtree(box, ignore_errors=True)


def main(argv: list[str]) -> int:
    list_only = "--list" in argv
    keep = "--keep" in argv
    files = [Path(a) for a in argv if not a.startswith("--")]
    if not files:
        print(__doc__)
        return 2
    for f in files:
        if not f.is_file():
            print(f"run-doc-blocks: {f}: no such file")
            return 2
    if list_only:
        for f in files:
            for line, lang, code in parse_blocks(f):
                print(f"--- {f}:{line} ({lang})")
                sys.stdout.write(code)
        return 0
    return run(files, keep)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
