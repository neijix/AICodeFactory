# shellcheck shell=bash
# Sourced by tests/run-tests.sh after case 30 ($F30, $R30/bin): the one-line installer, fed on
# stdin as `curl … | bash -s --` does, from a local bare clone into a fresh code root.
echo "--- 35. install.sh: clone + setup, fast-forward on a rerun, channels, a dirty checkout refused"
R35="$S/r35"; H35="$R35/home"; B35="$R35/aicf.git"; D35="$R35/Code/AICodeFactory"
mkdir -p "$H35"
git clone -q --bare "$F30" "$B35" 2>/dev/null || fail "setup: bare clone of the engine under test"
BR35="$(git -C "$B35" symbolic-ref --short HEAD)"   # the default branch, whatever the engine's checkout calls it
URL35="file://$B35"
command -v cygpath >/dev/null 2>&1 && URL35="file:///$(cygpath -m "$B35")"   # Git for Windows: file:///C:/...
# IN35 <install args…> — install.sh read from stdin, on the sandbox home.
IN35() { env -u AI_CODE_ROOT -u AICF_REPO -u AICF_CHANNEL HOME="$H35" USERPROFILE="$H35" XDG_CONFIG_HOME="$H35/.config" \
  XDG_STATE_HOME="$R35/state" PYTHONDONTWRITEBYTECODE=1 AI_SKILLS_MODE=copy AI_SHELL_PROFILES="$H35/rc35" PATH="$R30/bin:$PATH" \
  "$BASH_BIN" -s -- --repo "$URL35" --code-root "$R35/Code" "$@" < "$F30/install.sh"; }
# PUSH35 <file> <tag-or-empty> — one more commit on the bare repo's default branch (and a tag on it).
git clone -q "$B35" "$R35/dev" 2>/dev/null || fail "setup: a dev clone"
PUSH35() { printf '%s\n' "$1" >> "$R35/dev/$1" && git -C "$R35/dev" add -A && git -C "$R35/dev" commit -qm "$1" \
  && { [ -z "$2" ] || git -C "$R35/dev" tag "$2"; } && git -C "$R35/dev" push -q --tags origin "HEAD:$BR35" 2>/dev/null || fail "setup: push $1"; }
out=$(IN35 2>&1) || fail "install.sh failed: $out"
[ -f "$D35/sync-ai-templates.sh" ] && [ "$(cat "$H35/.ai-template-dir")" = "$D35" ] && [ -d "$H35/.claude/skills/bootstrap-ai" ] \
  || fail "install.sh must clone into <code root>/AICodeFactory and run setup there: $out"
printf '%s\n' "$out" | grep -qx 'No release yet: following main instead of stable.' && [ "$(git -C "$D35" config aicf.channel)" = main ] \
  && [ "$(git -C "$D35" symbolic-ref --short HEAD)" = "$BR35" ] || fail "no tag: the stable default falls back to main, recorded: $out"
# A rerun fast-forwards.
PUSH35 one35 ""
out=$(IN35 2>&1) || fail "a second install.sh failed: $out"
[ -f "$D35/one35" ] && [ "$(git -C "$D35" rev-parse HEAD)" = "$(git -C "$B35" rev-parse "$BR35")" ] && printf '%s\n' "$out" | grep -q "^Updating $D35" \
  || fail "a rerun must fast-forward the checkout: $out"
# stable: the latest vX.Y.Z tag (pinned while origin has no stable branch), then the stable branch.
PUSH35 two35 v0.1.0; PUSH35 three35 v0.2.0; PUSH35 four35 ""
out=$(IN35 --channel stable 2>&1) || fail "--channel stable failed: $out"
[ "$(git -C "$D35" rev-parse HEAD)" = "$(git -C "$B35" rev-parse 'v0.2.0^{commit}')" ] && [ "$(git -C "$D35" config aicf.channel)" = stable ] \
  && printf '%s\n' "$out" | grep -qx 'Channel: stable (pinned at v0.2.0; run this installer again to update)' \
  || fail "stable without a stable branch is the latest tag, pinned: $out"
git -C "$R35/dev" push -q origin v0.2.0^{commit}:refs/heads/stable 2>/dev/null || fail "setup: push the stable branch"
out=$(IN35 --channel=stable 2>&1) || fail "stable with a stable branch failed: $out"
[ "$(git -C "$D35" rev-parse --abbrev-ref --symbolic-full-name '@{u}')" = origin/stable ] || fail "stable must track origin/stable: $out"
out=$(IN35 --channel main 2>&1) || fail "back to main failed: $out"
[ "$(git -C "$D35" symbolic-ref --short HEAD)" = "$BR35" ] && [ -f "$D35/four35" ] && [ "$(git -C "$D35" config aicf.channel)" = main ] \
  || fail "--channel main returns to the default branch, up to date: $out"
# A dirty checkout is refused before anything moves.
PUSH35 five35 ""
printf 'local edit\n' >> "$D35/README.md"
rc=0; out=$(IN35 2>&1) || rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'has uncommitted changes' && [ ! -f "$D35/five35" ] && grep -q 'local edit' "$D35/README.md" \
  || fail "a dirty checkout must be refused, untouched (rc=$rc): $out"
rc=0; out=$(IN35 --channel edge 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "an unknown channel is exit 2 (rc=$rc): $out"
