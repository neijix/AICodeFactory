# shellcheck shell=bash
# Sourced by tests/run-tests.sh after case 9c (its helpers, sandbox $HOME and $S/proj). Skills
# moved from <repo>/vscode-global/skills to <repo>/skills: what machines installed from the old
# path is re-pointed by the next --skills pass, never left stale or taken for another repo's.
echo "--- 9d. installs from a moved skills source (vscode-global/skills -> skills) follow it"
K="$HOME/.claude/skills"
# This repo: a copy stamped with its pre-move origin is ours, so it is re-copied and re-stamped.
rm -rf "$K/bootstrap-ai"; mkdir -p "$K/bootstrap-ai"; echo stale > "$K/bootstrap-ai/SKILL.md"
echo "$T/vscode-global/skills" > "$K/bootstrap-ai/.ai-template-origin"
AI_SKILLS_MODE=copy E "$S/proj" --skills --quiet >/dev/null
[ "$(head -n 1 "$K/bootstrap-ai/.ai-template-origin")" = "$T/skills" ] \
  || fail "a pre-move copy was not re-stamped: $(head -n 1 "$K/bootstrap-ai/.ai-template-origin")"
cmp -s "$T/skills/bootstrap-ai/SKILL.md" "$K/bootstrap-ai/SKILL.md" || fail "a pre-move copy was not refreshed"
# An overlay installed from vscode-global/skills, then moved to skills/: the copy follows.
OD="$S/ov9d"; mkdir -p "$OD/vscode-global/skills/ov-moved"
printf -- '---\nname: ov-moved\n---\n' > "$OD/vscode-global/skills/ov-moved/SKILL.md"
AI_TEMPLATE_OVERLAY_DIR="$OD" AI_SKILLS_MODE=copy E "$S/proj" --skills --quiet >/dev/null
[ "$(head -n 1 "$K/ov-moved/.ai-template-origin" 2>/dev/null)" = "$OD/vscode-global/skills" ] \
  || fail "an old-layout overlay skill was not installed from vscode-global/skills"
mv "$OD/vscode-global/skills" "$OD/skills"; rmdir "$OD/vscode-global"
AI_TEMPLATE_OVERLAY_DIR="$OD" AI_SKILLS_MODE=copy E "$S/proj" --skills --quiet >/dev/null
[ "$(head -n 1 "$K/ov-moved/.ai-template-origin")" = "$OD/skills" ] \
  || fail "the copy did not follow its moved source: $(head -n 1 "$K/ov-moved/.ai-template-origin")"
if [ "$SYMLINKS" = true ]; then
  # Links: one dangling (this repo's old path is gone), one into a leftover old folder (a stale
  # __pycache__ keeps vscode-global/skills/<name> alive): both are ours, both are re-linked.
  mkdir -p "$OD/vscode-global/skills/ov-moved/__pycache__"
  rm -rf "$K/ov-moved" "$K/bootstrap-ai"
  ln -s "$OD/vscode-global/skills/ov-moved" "$K/ov-moved"
  ln -s "$T/vscode-global/skills/bootstrap-ai" "$K/bootstrap-ai"
  AI_TEMPLATE_OVERLAY_DIR="$OD" AI_SKILLS_MODE=link E "$S/proj" --skills --quiet >/dev/null
  [ "$(readlink "$K/ov-moved")" = "$OD/skills/ov-moved" ] || fail "a link into the old folder was not re-linked: $(readlink "$K/ov-moved")"
  [ "$(readlink "$K/bootstrap-ai")" = "$T/skills/bootstrap-ai" ] || fail "a dangling pre-move link was not re-linked"
fi
rm -rf "$K/ov-moved" "$OD"
