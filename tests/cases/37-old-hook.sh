# shellcheck shell=bash
# Sourced by tests/run-tests.sh after case 30 ($F30): a project bootstrapped long ago keeps the
# SessionStart hook it was given. Twin: 37-old-hook.ps1.
echo "--- 37. an old project's SessionStart hook (fa65ed9) still finds and runs the current engine"
# The hook command of .claude/settings.json.template at fa65ed9, verbatim: a literal, never read from git.
# shellcheck disable=SC2016
OLD_HOOK37='P="${CLAUDE_PROJECT_DIR:-.}"; for T in "${AI_TEMPLATE_DIR:-}" "$P/../AICodeFactory" "$P/../../Code/AICodeFactory" "$HOME/Code/AICodeFactory" "$(cat "$HOME/.ai-template-dir" 2>/dev/null)" "$P"/../*/; do [ -f "$T/sync-ai-templates.sh" ] && [ -f "$T/templates-manifest.txt" ] && exec bash "$T/sync-ai-templates.sh" "$P" --quiet --commit --pull --agents --skills; done; echo "ai-sync: AICodeFactory not found - shared AI files not refreshed. Run its install-global once on this machine, or set AI_TEMPLATE_DIR."'
R37="$S/r37"; P37="$R37/Code/old37"; H37="$R37/home"
mkdir -p "$P37" "$H37"
# The current layout in a code root beside the project (found as $P/../AICodeFactory), no origin.
git clone -q "$F30" "$R37/Code/AICodeFactory" 2>/dev/null && git -C "$R37/Code/AICodeFactory" remote remove origin || fail "setup: clone the engine"
git -C "$P37" init -q && printf 'x\n' > "$P37/app.txt" && git -C "$P37" add -A && git -C "$P37" commit -qm init || fail "setup: old37"
out=$(cd / && env -u AI_TEMPLATE_DIR HOME="$H37" CLAUDE_PROJECT_DIR="$P37" AI_SKILLS_MODE=copy sh -c "$OLD_HOOK37" </dev/null 2>&1) \
  || fail "the old hook failed: $out"
printf '%s\n' "$out" | grep -q 'not found' && fail "the old hook must find the factory: $out"
for f in CLAUDE.md .claude/settings.json .github/copilot-instructions.md AGENTS.md .github/PROJECT_STATE.md; do
  [ -f "$P37/$f" ] && git -C "$P37" ls-files --error-unmatch "$f" >/dev/null 2>&1 || fail "the old hook must write and commit $f: $out"
done
cmp -s "$P37/.claude/settings.json" "$R37/Code/AICodeFactory/templates/.claude/settings.json.template" \
  || fail "the old hook must install the current settings template (the new hook)"
[ -z "$(git -C "$P37" status --porcelain)" ] || fail "the old hook leaves a clean tree: $(git -C "$P37" status --porcelain)"
