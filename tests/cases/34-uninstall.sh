# shellcheck shell=bash
# Sourced by tests/run-tests.sh after case 30 ($F30, $R30/bin, $PY): aicf uninstall is the exact
# reverse of aicf setup on a home that already holds the user's own files.
echo "--- 34. aicf uninstall: a preview changes nothing, --yes gives the home back byte for byte"
R34="$S/r34"; C34="$R34/Code"; F34="$C34/AICodeFactory"; H34="$R34/home"
mkdir -p "$C34/.ai-root" "$H34/.claude/skills/foreign" "$H34/.claude/skills/mine"
git clone -q "$F30" "$F34" 2>/dev/null && git -C "$F34" remote remove origin || fail "setup: clone the engine under test"
# The user's own things, which must survive: a settings file with other keys, a shell profile, a
# skill another template repo installed, an unmarked skill, and a Claude profile (more roots).
printf '{"config_dir": "~/.claude-code"}\n' > "$C34/.ai-root/claude-profile.json"
printf 'export FOO=1\n' > "$H34/.bashrc"
printf 'x\n' > "$H34/.claude/skills/foreign/SKILL.md"; printf '/elsewhere/skills\n' > "$H34/.claude/skills/foreign/.ai-template-origin"
printf 'y\n' > "$H34/.claude/skills/mine/SKILL.md"
printf '%s\n' '{' '  "model": "opus",' '  "env": {' '    "FOO": "1"' '  }' '}' > "$H34/.claude/settings.json"
# AI34 <aicf args…> — bin/aicf on the sandbox home ($R30/bin: a python3 that runs, uname = Linux under Git Bash).
AI34() { HOME="$H34" USERPROFILE="$H34" XDG_CONFIG_HOME="$H34/.config" XDG_STATE_HOME="$R34/state" PYTHONDONTWRITEBYTECODE=1 \
  AI_SKILLS_MODE=copy AI_SHELL_PROFILES="$H34/.bashrc" PATH="$R30/bin:$PATH" sh "$F34/bin/aicf" "$@"; }
# SNAP <dir> — every path under <dir>: D, L (with its target) or F (with a hash). Run from inside
# <dir>: a native Windows python cannot open a Git Bash path.
SNAP() { (cd "$1" && "$PY" -c 'import hashlib, os
out = []
for d, dirs, files in os.walk("."):
    for n in dirs + files:
        p = os.path.join(d, n)[2:].replace(os.sep, "/")
        if os.path.islink(p): out.append("L %s -> %s" % (p, os.readlink(p)))
        elif os.path.isdir(p): out.append("D " + p)
        else: out.append("F %s %s" % (p, hashlib.sha256(open(p, "rb").read()).hexdigest()))
print("\n".join(sorted(out)))'); }
before34="$(SNAP "$H34")"
out=$(AI34 setup 2>&1) || fail "aicf setup failed: $out"
[ -d "$H34/.claude-code/skills/bootstrap-ai" ] && grep -q 'AICodeFactory claude-profiles' "$H34/.bashrc" && [ -s "$H34/.ai-template-dir" ] \
  || fail "setup must install the profile's skills, the rc block and the marker (the case needs them): $out"
setup34="$(SNAP "$H34")"
P34="$H34"; command -v cygpath >/dev/null 2>&1 && P34="$(cygpath -m "$H34")"   # Git Bash hands Python C:/... paths
out=$(AI34 uninstall 2>&1) || fail "the preview failed: $out"
[ "$(SNAP "$H34")" = "$setup34" ] || fail "the preview must change nothing: $out"
printf '%s\n' "$out" | grep -q '^Preview' && printf '%s\n' "$out" | tail -n 1 | grep -q 'aicf uninstall --yes' \
  && printf '%s\n' "$out" | grep -qF "[remove] $H34/.ai-template-dir" && printf '%s\n' "$out" | grep -qF "[edit]   $P34/.claude/settings.json" \
  || fail "the preview must list what --yes removes and edits: $out"
out=$(AI34 uninstall --yes 2>&1) || fail "uninstall --yes failed: $out"
after34="$(SNAP "$H34")"
[ "$after34" = "$before34" ] || fail "uninstall --yes must give the home back exactly: $(diff <(printf '%s\n' "$before34") <(printf '%s\n' "$after34") | head -20)"
[ -f "$C34/.ai-root/claude-profile.json" ] && [ -z "$(git -C "$F34" status --porcelain)" ] || fail "uninstall must leave .ai-root and the checkout alone"
out=$(AI34 uninstall 2>&1) || fail "a second uninstall failed: $out"
printf '%s\n' "$out" | grep -qx 'Nothing of aicf setup is installed for this checkout.' || fail "a second uninstall finds nothing: $out"
rc=0; out=$(AI34 uninstall --bogus 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "an unknown option is exit 2 (rc=$rc): $out"
out=$(AI34 uninstall --help 2>&1) && printf '%s\n' "$out" | grep -q 'Usage: aicf uninstall' || fail "--help prints the usage: $out"
