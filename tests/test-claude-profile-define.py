#!/usr/bin/env python3
"""Rules of engine/claude-profile-define.py (install-global --claude-profile /
--claude-env) that case 30 does not drive through install-global. Run by case 30 of both suites;
alone: python3 tests/test-claude-profile-define.py. Silent and status 0 when every check holds."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

DEFINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine", "claude-profile-define.py")
tmp = os.path.realpath(tempfile.mkdtemp(prefix="cpd-"))
home = os.path.join(tmp, "home")
env = dict(os.environ, HOME=home, USERPROFILE=home, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_NOSYSTEM="1")
fails = []


def run(*args):
    r = subprocess.run([sys.executable, DEFINE] + list(args), capture_output=True, text=True, env=env)
    return r.returncode, r.stdout + r.stderr


def root(name, git=True):
    d = os.path.join(tmp, "roots", name)
    os.makedirs(os.path.join(d, ".ai-root"))
    if git:
        subprocess.run(["git", "init", "-q", os.path.join(d, ".ai-root")], check=True)
    return d


def profile(d):
    f = os.path.join(d, ".ai-root", "claude-profile.json")
    return json.load(open(f, encoding="utf-8")) if os.path.isfile(f) else None


def check(cond, what, out=""):
    if not cond:
        fails.append(f"{what}\n    {out.strip()}")


os.makedirs(home)
work, code = root("Work"), root("Code")
outside = os.path.join(tmp, "elsewhere")

rc, out = run("--profile", work)
check(rc == 0 and profile(work) == {"config_dir": "~/.claude-work"}, "the default config dir is ~/.claude-<root name>", out)
rc, out = run("--env", f"{work}=MAX_THINKING_TOKENS=8000")
check(rc == 0 and profile(work)["settings"]["env"] == {"MAX_THINKING_TOKENS": "8000"}, "*_TOKENS is not a secret", out)
rc, out = run("--env", f"{work}=MAX_THINKING_TOKENS=")
check(rc == 0 and profile(work)["settings"]["env"] == {"MAX_THINKING_TOKENS": None} and "MAX_THINKING" not in out,
      "an empty value leaves a null, which the engine drops from settings.json", out)

for arg in ("AWS_ACCESS_KEY_ID=x", "GITHUB_TOKEN=x", "ANTHROPIC_API_KEY=x", "HTTPS_PROXY=http://bob:hunter2@proxy",
            "ANTHROPIC_CUSTOM_HEADERS=Authorization: Bearer x", "X=sk-ant-abc"):
    rc, out = run("--env", f"{work}={arg}")
    check(rc == 2 and "no secret" in out, f"a secret must be refused: {arg}", out)
for cfg in ("rel/dir", outside, "~/", os.path.join(home, "..", "up")):
    rc, out = run("--profile", f"{code}={cfg}")
    check(rc == 2 and profile(code) is None, f"a config dir outside home must be refused: {cfg}", out)
rc, out = run("--profile", f"{code}={os.path.join(home, 'cc')}")
check(rc == 0 and profile(code)["config_dir"] == "~/cc", "a config dir under home is written as ~/...", out)

with open(os.path.join(work, ".ai-root", "claude-profile.json"), "w") as fh:
    fh.write("[1]")
rc, out = run("--env", f"{code}=A=1", "--profile", work)
check(rc == 2 and "settings" not in profile(code), "one root's bad file writes no root", out)
os.remove(os.path.join(work, ".ai-root", "claude-profile.json"))

rc, out = run("--profile", f"{code}=none", "--env", f"{code}=X=")
check(rc == 2 and profile(code) is not None, "none with --env must be refused", out)
rc, out = run("--profile", f"{code}=none")
st = subprocess.run(["git", "-C", os.path.join(code, ".ai-root"), "status", "--porcelain"], capture_output=True, text=True).stdout
check(rc == 0 and profile(code) is None and not st and "committed" in out, "none removes the file and commits it", out)

rc, out = run("--env", f"{work}=CLAUDE_CODE_API_KEY_HELPER_TTL_MS=60000", "--env", f"{work}=ANTHROPIC_API_KEY=", "--env", f"{work}=GONE=")
check(rc == 0 and profile(work)["settings"]["env"].get("CLAUDE_CODE_API_KEY_HELPER_TTL_MS") == "60000"
      and "GONE" not in profile(work)["settings"]["env"], "KEY_HELPER is no secret, an empty value is always allowed, a missing key adds nothing", out)
for arg in ("accessToken=x", "ANTHROPIC_BASE_URL=https://gw/?api_key=abc"):
    rc, out = run("--env", f"{work}={arg}")
    check(rc == 2 and "no secret" in out, f"a secret must be refused: {arg}", out)
rc, out = run("--profile", f"{work}=~/.claude")
check(rc == 2, "~/.claude (the default dir) must be refused", out)
with open(os.path.join(work, ".ai-root", "claude-profile.json"), "w") as fh:
    fh.write("[1]")
rc, out = run("--check", "--profile", work)
check(rc == 2, "--check reads an existing .ai-root's file", out)
os.remove(os.path.join(work, ".ai-root", "claude-profile.json"))

bare = os.path.join(tmp, "roots", "Bare")
os.makedirs(bare)
rc, out = run("--profile", bare)
check(rc == 2 and "has no .ai-root" in out, "a root without .ai-root must be refused", out)
rc, out = run("--check", "--profile", bare)
check(rc == 0 and not os.listdir(bare), "--check accepts a root whose .ai-root is still to be cloned and writes nothing", out)

rc, out = run("--code-root", os.path.join(tmp, "elsewhere-root", "Code"), "--profile", work)
check(rc == 0 and "not a sibling" in out, "a root that is not a sibling of the code root is flagged", out)

nested = os.path.join(tmp, "parentrepo")
os.makedirs(os.path.join(nested, "R", ".ai-root"))
subprocess.run(["git", "init", "-q", nested], check=True)
rc, out = run("--profile", os.path.join(nested, "R"))
check(rc == 0 and "not its own git checkout" in out, "a .ai-root inside another repo is not committed there", out)

ign = root("Ign")
with open(os.path.join(ign, ".ai-root", ".gitignore"), "w") as fh:
    fh.write("claude-profile.json\n")
rc, out = run("--profile", ign)
check(rc == 0 and "ignored" in out, "a gitignored profile file is reported, not 'already committed'", out)

shutil.rmtree(tmp, ignore_errors=True)
if fails:
    print("FAIL claude-profile-define:\n  " + "\n  ".join(fails))
    sys.exit(1)
