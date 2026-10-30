# shellcheck shell=bash
# Sourced by tests/run-tests.sh after case 15b (its helpers and sandbox). An overlay still in the
# old layout (<x>.template and .append at its root, vscode-global/skills) keeps working, read after
# the new paths, with one note per run; once moved to templates/ and skills/ the note is gone.
echo "--- 15c. an overlay in the old layout still renders, with one note per run, until it moves"
OO="$S/ov-old"; PO="$S/proj-oo"
mkdir -p "$OO/templates" "$OO/.claude/commands" "$OO/vscode-global/skills/old-sk" "$PO"
printf 'OLD-OVERRIDE\n' > "$OO/CLAUDE.md.template"
printf 'NEW-OVERRIDE\n' > "$OO/templates/CLAUDE.md.template"      # either layout: the base wins
printf 'OLD-FRAG\n' > "$OO/copilot-instructions.md.template.append"
printf 'OLD-MINE\n' > "$OO/.claude/commands/mine.md.template"
printf '[POINTERS]\n.claude/commands/mine.md.template|.claude/commands/mine.md\nAGENTS.md.template|extra-agents.md\n' > "$OO/overlay-manifest.txt"
printf -- '---\nname: old-sk\n---\n' > "$OO/vscode-global/skills/old-sk/SKILL.md"
(cd "$PO" && git init -q)
check_oo() {   # the rendering both layouts must give
  cmp -s "$T/templates/CLAUDE.md.template" "$PO/CLAUDE.md" || fail "$1: an overlay CLAUDE.md.template replaced the base: $(head -1 "$PO/CLAUDE.md")"
  { cat "$T/templates/copilot-instructions.md.template"; printf 'OLD-FRAG\n'; } | cmp -s - "$PO/.github/copilot-instructions.md" \
    || fail "$1: the .append fragment was not rendered"
  [ "$(cat "$PO/.claude/commands/mine.md")" = OLD-MINE ] || fail "$1: the overlay's own pointer was not rendered"
  cmp -s "$T/templates/AGENTS.md.template" "$PO/extra-agents.md" || fail "$1: a manifest entry without templates/ lost the base file"
}
out=$(AI_TEMPLATE_OVERLAY_DIR="$OO" AI_SKILLS_MODE=copy E "$PO" --skills 2>&1)
[ "$(printf '%s\n' "$out" | grep -c 'overlay uses the old layout')" = 1 ] || fail "the old-layout note must print once per run: $out"
printf '%s\n' "$out" | grep -qxF 'ai-sync: overlay uses the old layout (.claude/commands/mine.md.template, CLAUDE.md.template, copilot-instructions.md.template.append, …) — move it to templates/ and skills/' \
  || fail "the old-layout note must name what to move: $out"
check_oo "old layout"
[ "$(head -n 1 "$HOME/.claude/skills/old-sk/.ai-template-origin" 2>/dev/null)" = "$OO/vscode-global/skills" ] \
  || fail "a skill under the old vscode-global/skills was not installed"
# Move it to the new layout: same rendering, no note, the skill copy follows its source.
rm "$OO/CLAUDE.md.template"
mv "$OO/copilot-instructions.md.template.append" "$OO/templates/"; mv "$OO/.claude" "$OO/templates/"
mv "$OO/vscode-global/skills" "$OO/skills"; rmdir "$OO/vscode-global"
printf '[POINTERS]\ntemplates/.claude/commands/mine.md.template|.claude/commands/mine.md\ntemplates/AGENTS.md.template|extra-agents.md\n' > "$OO/overlay-manifest.txt"
out=$(AI_TEMPLATE_OVERLAY_DIR="$OO" AI_SKILLS_MODE=copy E "$PO" --skills 2>&1)
printf '%s\n' "$out" | grep -q 'old layout' && fail "a new-layout overlay must not get the note: $out"
check_oo "new layout"
[ "$(head -n 1 "$HOME/.claude/skills/old-sk/.ai-template-origin")" = "$OO/skills" ] || fail "the skill copy did not follow the move"
rm -rf "$HOME/.claude/skills/old-sk" "$OO"
