#!/usr/bin/env python3
"""claude-profile-define.py — write a code root's Claude Code profile (install-global's
--claude-profile / --claude-env, both twins).

The profile is <root>/.ai-root/claude-profile.json ({"config_dir": "~/.claude-<x>", "settings":
{"env": {...}}}), read by install_claude_profiles / Install-ClaudeProfiles. It travels with the
root repo, so this script keeps it machine-free (the config dir must sit under the home folder and
is written as ~/...), refuses anything that looks like a secret (an apiKeyHelper or /login carries
the credential) and commits the file alone in .ai-root; the next session start's .ai-root pull
pushes it.

  --profile <root>                 declare a profile (keeps its config_dir, else ~/.claude-<root
                                   name, lower case>)
  --profile <root>=<config-dir>    ... with that config dir
  --profile <root>=none            remove the profile
  --env <root>=<NAME>=<value>      set settings.env.NAME (declares the profile if needed); an
                                   empty value removes NAME (written as null, so the engine also
                                   drops it from the installed settings.json)
  --code-root <dir>                warn when a root is not a sibling of it (never installed)
  --check                          check the arguments only (a root may still lack .ai-root)

<root> is the part before the first "=" and must be a folder holding .ai-root. Every argument
and every root's file is checked before anything is written: one error (exit 2) = no change.
"""
import json
import os
import re
import subprocess
import sys

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
# Word-wise, so MAX_THINKING_TOKENS passes while AWS_ACCESS_KEY_ID and *_TOKEN are refused.
SECRET_WORDS = {"TOKEN", "SECRET", "SECRETS", "PASSWORD", "PASSWD", "CREDENTIAL", "CREDENTIALS",
                "KEY", "APIKEY"}
SECRET_VALUE = re.compile(
    r"^\s*(authorization|x-api-key|proxy-authorization)\s*:"  # a header (ANTHROPIC_CUSTOM_HEADERS)
    r"|://[^/\s@]+@"                                          # user[:password]@ in a URL
    r"|[?&](api[_-]?key|key|token|access_token|sig|signature|password|secret)="  # in a URL query
    r"|\bbearer\s|\bsk-ant-|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{20,}",
    re.I | re.M)


def fail(msg):
    sys.stdout.flush()
    print(f"Error: {msg}", file=sys.stderr)
    sys.exit(2)


def split_root(arg, opt, check):
    head, sep, rest = arg.partition("=")
    path = os.path.expanduser(head)
    if not head or not os.path.isdir(path):
        fail(f"{opt} {arg}: '{head}' is not a folder (usage: {opt} <root>{'=<NAME>=<value>' if opt == '--claude-env' else '[=<config-dir>|none]'})")
    root = os.path.realpath(path)
    if not check and not os.path.isdir(os.path.join(root, ".ai-root")):
        fail(f"{root} has no .ai-root — clone its root repo first (aicf setup --ai-context-remote {root}=<url>)")
    return root, sep, rest


def portable(cfg, home):
    """~/... — the file travels between machines, so the config dir must be under home."""
    cfg = cfg.strip().replace("\\", "/")
    if cfg.startswith("~/") and cfg.strip("~/"):
        cfg = os.path.join(home, cfg[2:])
    elif not os.path.isabs(cfg):
        fail(f"config dir {cfg}: ~/... or an absolute path under {home}")
    try:
        rel = os.path.relpath(os.path.normpath(cfg), home).replace("\\", "/")
    except ValueError:  # Windows: another drive
        rel = ".."
    if rel == "." or rel == ".." or rel.startswith("../"):
        fail(f"config dir {cfg}: must be inside {home} (claude-profile.json is committed and travels between machines)")
    if rel == ".claude":
        fail("config dir ~/.claude: that is the default one, every session without a profile uses it")
    return "~/" + rel


def is_secret(key, val):
    """Never for an empty value (it only removes NAME); KEY_HELPER (apiKeyHelper's TTL) is fine."""
    words = re.split(r"_+", re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", key).upper().replace("KEY_HELPER", "HELPER"))
    return bool(val) and (bool(SECRET_WORDS & set(words)) or bool(SECRET_VALUE.search(val)))


def parse(argv):
    plan, code_root, check = {}, "", "--check" in argv
    it = iter(a for a in argv if a != "--check")
    for opt in it:
        arg = next(it, None)
        if arg is None:
            fail(f"{opt} needs a value")
        if opt == "--code-root":
            code_root = os.path.realpath(os.path.expanduser(arg))
        elif opt == "--profile":
            root, sep, rest = split_root(arg, "--claude-profile", check)
            if sep and not rest.strip():
                fail(f"--claude-profile {arg}: a config dir (or none) after =")
            plan.setdefault(root, {"cfg": "", "env": {}})["cfg"] = rest.strip()
        elif opt == "--env":
            root, _, rest = split_root(arg, "--claude-env", check)
            key, sep, val = rest.partition("=")
            if not sep or not NAME.fullmatch(key):
                fail(f"--claude-env {arg}: <root>=<NAME>=<value> (an empty value removes NAME)")
            if is_secret(key, val):
                fail(f"--claude-env {key}: no secret in claude-profile.json (it is committed) — an apiKeyHelper or /login")
            plan.setdefault(root, {"cfg": "", "env": {}})["env"][key] = val
        else:
            fail(f"unknown option {opt}")
    home = os.path.expanduser("~")
    for root, p in plan.items():
        if p["cfg"].lower() == "none" and p["env"]:
            fail(f"{root}: --claude-profile none and --claude-env together")
        if p["cfg"] and p["cfg"].lower() != "none":
            portable(p["cfg"], home)
    return plan, code_root, check


def git(air, *args):
    return subprocess.run(["git", "-C", air] + list(args), capture_output=True, text=True)


def commit(air, rel, msg):
    """Commit <rel> alone in .ai-root (its own git checkout); one line either way."""
    top = git(air, "rev-parse", "--show-toplevel")
    if top.returncode != 0 or os.path.realpath(top.stdout.strip()) != os.path.realpath(air):
        return "not its own git checkout: not committed"
    gdir = git(air, "rev-parse", "--absolute-git-dir").stdout.strip()
    if any(os.path.exists(os.path.join(gdir, n)) for n in ("MERGE_HEAD", "rebase-merge", "rebase-apply")):
        return "mid-merge/rebase: not committed"
    git(air, "add", "-A", "--", rel)
    if git(air, "diff", "--cached", "--quiet", "--", rel).returncode == 0:
        if not os.path.exists(os.path.join(air, rel)):
            return "it was never committed"
        if git(air, "ls-files", "--error-unmatch", "--", rel).returncode != 0:
            return "ignored by .ai-root's .gitignore: not committed"
        return "already committed"
    r = git(air, "commit", "-q", "-m", msg, "--", rel)
    if r.returncode != 0:
        git(air, "reset", "-q", "--", rel)
        return "NOT committed (" + ((r.stderr or r.stdout).strip().splitlines() or ["git commit failed"])[-1] + ")"
    return "committed in .ai-root, pushed at the next session start"


def load(f):
    """(raw text, data) of a claude-profile.json ({} when missing or blank); fails on a bad shape."""
    try:
        raw = open(f, encoding="utf-8-sig").read() if os.path.isfile(f) else ""
        data = json.loads(raw) if raw.strip() else {}
        if not isinstance(data, dict) or not isinstance(data.get("config_dir", ""), str) \
                or not isinstance(data.get("settings", {}), dict) \
                or not isinstance(data.get("settings", {}).get("env", {}), dict):
            raise ValueError
    except ValueError:
        fail(f"{f} is not a JSON object with a config_dir string and an optional settings.env object — fix or delete it")
    return raw, data


def prepare(root, p, home):
    """(file, new data or None to remove, old data, shown); fails before anything is written."""
    f = os.path.join(root, ".ai-root", "claude-profile.json")
    raw, data = load(f)
    if p["cfg"].lower() == "none":
        return f, None, data if raw.strip() else None, "none"
    old = json.loads(json.dumps(data))
    cfg = p["cfg"] or data.get("config_dir") or "~/.claude-" + os.path.basename(root).lower()
    data["config_dir"] = portable(cfg, home)
    if p["env"]:
        settings = data.setdefault("settings", {})
        env = settings.setdefault("env", {})
        env.update({k: v or None for k, v in p["env"].items() if v or k in env})
        if not env:  # only removals of keys it never had
            del settings["env"]
        if not settings:
            del data["settings"]
    env = data.get("settings", {}).get("env", {})
    shown = data["config_dir"] + "".join(f", {k}={v}" for k, v in env.items() if v is not None)
    return f, data, old, shown


def main():
    plan, code_root, check = parse(sys.argv[1:])
    home = os.path.expanduser("~")
    todo = [(root,) + prepare(root, p, home) for root, p in plan.items()
            if not check or os.path.isdir(os.path.join(root, ".ai-root"))]
    if check:
        return
    for root, f, data, old, shown in todo:
        air, rel = os.path.dirname(f), os.path.basename(f)
        if data == old:
            print(f"  Claude profile of {root} up to date: {shown}", flush=True)
        elif data is None:
            os.remove(f)
            print(f"  removed the Claude profile of {root} ({commit(air, rel, 'chore(profile): no Claude profile')})", flush=True)
        else:
            with open(f + ".tmp", "w", encoding="utf-8", newline="\n") as fh:
                fh.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
            os.replace(f + ".tmp", f)
            status = commit(air, rel, f"chore(profile): Claude profile {data['config_dir']}")
            print(f"  Claude profile of {root}: {shown} ({status})", flush=True)
        if code_root and data is not None and os.path.dirname(root) != os.path.dirname(code_root):
            print(f"  NOTE: {root} is not a sibling of {code_root}: its profile is not installed", flush=True)


if __name__ == "__main__":
    main()
