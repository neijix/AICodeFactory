# shellcheck shell=bash
# Sourced by tests/run-tests.sh (its helpers and sandbox): the dev-context packs (19) and the work
# roots that pick a pack's scope (19b).
echo "--- 19. dev-context: personal in a code root, work under a work root, nowhere else"
# Each root's pack lives in its .ai-root/dev-context/ (the only source). The projects are
# registered tracked so the code roots add no conformance line.
D19="$S/dc19"; NR="$D19/Code/.ai-root"; UR="$D19/WorkCode/.ai-root"
mkdir -p "$NR/dev-context" "$NR/projects" "$UR/dev-context" "$UR/projects"
printf 'PERSONAL-RULE\n' > "$NR/dev-context/rules.md"
printf '%s\n' '{"note":"personal-pref"}' > "$NR/dev-context/settings.json"
printf 'WORK-RULE\n' > "$UR/dev-context/rules.md"
printf '%s\n' '{"note":"work-pref"}' > "$UR/dev-context/settings.json"
mkproj() { mkdir -p "$1" && git -C "$1" init -q; }
mkproj19() { mkproj "$1" && printf 'mode=tracked\n' > "$(dirname "$1")/.ai-root/projects/$(basename "$1")"; }
mkproj19 "$D19/Code/personal-proj"
out=$(E "$D19/Code/personal-proj" --quiet --commit)
echo "$out" | grep -q 'ai-sync: dev-context personal' || fail "personal pack not announced: $out"
echo "$out" | grep -q 'WORK-RULE' && fail "personal run leaked the work pack: $out"
grep -q 'PERSONAL-RULE' "$D19/Code/personal-proj/CLAUDE.local.md" || fail "personal rules not in CLAUDE.local.md"
grep -q 'personal-pref' "$D19/Code/personal-proj/CLAUDE.local.md" || fail "personal settings not in CLAUDE.local.md"
grep -q 'WORK-RULE' "$D19/Code/personal-proj/CLAUDE.local.md" && fail "work rules written into a personal project"
grep -qF "Source: ../.ai-root/dev-context/" "$D19/Code/personal-proj/CLAUDE.local.md" || fail "the note must name the .ai-root source"
git -C "$D19/Code/personal-proj" check-ignore -q CLAUDE.local.md || fail "CLAUDE.local.md is not gitignored"
git -C "$D19/Code/personal-proj" status --porcelain | grep -q 'CLAUDE.local.md' && fail "CLAUDE.local.md shows up in git status"
out=$(E "$D19/Code/personal-proj" --quiet)
echo "$out" | grep -q 'ai-sync: dev-context personal' || fail "a settled project must still announce the pack: $out"
[ -z "$(git -C "$D19/Code/personal-proj" status --porcelain)" ] || fail "announcing the pack dirtied the tree"
cp "$D19/Code/personal-proj/CLAUDE.local.md" "$S/dc-before"
E "$D19/Code/personal-proj" --dry-run >/dev/null
cmp -s "$S/dc-before" "$D19/Code/personal-proj/CLAUDE.local.md" || fail "dry-run rewrote CLAUDE.local.md"
mkproj19 "$D19/WorkCode/work-proj"
out=$(E "$D19/WorkCode/work-proj" --quiet --commit)
echo "$out" | grep -q 'ai-sync: dev-context work' || fail "work pack not announced: $out"
grep -q 'WORK-RULE' "$D19/WorkCode/work-proj/CLAUDE.local.md" || fail "work rules missing"
grep -q 'work-pref' "$D19/WorkCode/work-proj/CLAUDE.local.md" || fail "work settings missing"
grep -q 'PERSONAL-RULE' "$D19/WorkCode/work-proj/CLAUDE.local.md" && fail "personal rules written into a work project"
out=$(E "$D19/WorkCode/work-proj")
echo "$out" | grep -q 'ai-sync: dev-context work' || fail "a normal run must name the pack: $out"
mkproj "$S/other/proj"
out=$(E "$S/other/proj" --quiet --commit)
echo "$out" | grep -q 'dev-context' && fail "a project outside both roots got a pack: $out"
[ ! -e "$S/other/proj/CLAUDE.local.md" ] || fail "unscoped project must not grow CLAUDE.local.md"
printf '%s\n%s\n' '<!-- ai-templates: dev-context personal -->' stale > "$S/other/proj/CLAUDE.local.md"
out=$(E "$S/other/proj" --quiet)
[ -z "$out" ] || fail "removing a stale pack must stay quiet: $out"
[ ! -e "$S/other/proj/CLAUDE.local.md" ] || fail "a pack we wrote must go when the project has no scope"
mkproj "$S/CodeWork/dropped"
out=$(E "$S/CodeWork/dropped" --quiet --commit)
echo "$out" | grep -q 'dev-context' && fail "CodeWork is not a scope: $out"
mkproj "$S/Code/nopack"
out=$(E "$S/Code/nopack" --quiet --commit)
echo "$out" | grep -q 'dev-context' && fail "a Code project outside a code root has no pack: $out"
mkproj19 "$D19/Code/foreign"
echo 'my notes' > "$D19/Code/foreign/CLAUDE.local.md"
out=$(E "$D19/Code/foreign" --quiet --commit)
echo "$out" | grep -q 'not ours' || fail "a hand-written CLAUDE.local.md must be reported: $out"
grep -qx 'my notes' "$D19/Code/foreign/CLAUDE.local.md" || fail "a hand-written CLAUDE.local.md was overwritten"
mv "$NR/dev-context" "$S/dc19-away"
out=$(E "$D19/Code/personal-proj" --quiet)
[ -z "$out" ] || fail "no pack must be silent: $out"
[ ! -e "$D19/Code/personal-proj/CLAUDE.local.md" ] || fail "no pack must remove a pack we wrote"
# dry-run must not delete either
printf '%s\n%s\n' '<!-- ai-templates: dev-context personal -->' keep > "$D19/Code/personal-proj/CLAUDE.local.md"
E "$D19/Code/personal-proj" --dry-run >/dev/null
grep -q keep "$D19/Code/personal-proj/CLAUDE.local.md" || fail "dry-run removed CLAUDE.local.md"
mv "$S/dc19-away" "$NR/dev-context"
if [ "$UNREADABLE" = true ]; then
  chmod 000 "$NR/dev-context/rules.md"
  mkproj19 "$D19/Code/unreadable"
  out=$(E "$D19/Code/unreadable" --quiet --commit)
  rc=$?
  chmod 644 "$NR/dev-context/rules.md"
  [ "$rc" = 0 ] || fail "an unreadable rules.md must not fail the sync ($rc)"
  echo "$out" | grep -q 'cannot read .ai-root/dev-context/rules.md' || fail "unreadable rules.md must be reported: $out"
  grep -q 'could not be read' "$D19/Code/unreadable/CLAUDE.local.md" || fail "the copy must say the rules could not be read"
  grep -q 'personal-pref' "$D19/Code/unreadable/CLAUDE.local.md" || fail "settings must still be copied when rules cannot be read"
else
  echo "    (unreadable-pack half skipped: chmod 000 has no effect in this shell)"
fi
"$PY" -c 'import sys; sys.stdout.write("A"*20000)' > "$UR/dev-context/rules.md"
printf '\nTAIL-MARKER\n' >> "$UR/dev-context/rules.md"
mkproj19 "$D19/WorkCode/big"
out=$(E "$D19/WorkCode/big" --quiet --commit)
echo "$out" | grep -q 'truncated' || fail "an oversized rules.md must be truncated: $out"
grep -q 'TAIL-MARKER' "$D19/WorkCode/big/CLAUDE.local.md" && fail "the truncated copy kept the tail"
grep -q '(truncated)' "$D19/WorkCode/big/CLAUDE.local.md" || fail "the copy must say it was truncated"

echo "--- 19b. work roots: the ~/.ai-work-roots list, environment.json kind, AI_WORK_ROOTS=none"
# Office is a code root of no special name: personal until a list or its environment.json says work.
OR19="$D19/Office/.ai-root"; mkdir -p "$OR19/dev-context" "$OR19/projects"
printf 'OFFICE-RULE\n' > "$OR19/dev-context/rules.md"
mkproj19 "$D19/Office/office-proj"
out=$(E "$D19/Office/office-proj" --quiet)
echo "$out" | grep -q 'ai-sync: dev-context personal' || fail "a root on no list is personal: $out"
printf '# work roots\n\n  office  \r\n' > "$HOME/.ai-work-roots"
out=$(env -u AI_WORK_ROOTS "$BASH_BIN" "$T/sync-ai-templates.sh" "$D19/Office/office-proj" --quiet)
echo "$out" | grep -q 'ai-sync: dev-context work' || fail "a ~/.ai-work-roots entry must make the root work: $out"
out=$(AI_WORK_ROOTS=none E "$D19/Office/office-proj" --quiet)
echo "$out" | grep -q 'ai-sync: dev-context personal' || fail "AI_WORK_ROOTS=none must not read ~/.ai-work-roots: $out"
rm -f "$HOME/.ai-work-roots"
printf '%s\n' '{"kind": "work"}' > "$OR19/environment.json"
out=$(AI_WORK_ROOTS=none E "$D19/Office/office-proj" --quiet)
echo "$out" | grep -q 'ai-sync: dev-context work' || fail "environment.json kind work must make the root work: $out"
rm -f "$OR19/environment.json"
# The helper itself: a name matches a whole component, a path a whole-component prefix (any case).
W19() { AI_WORK_ROOTS="$1" "$BASH_BIN" -c '. "$1/sync-ai-templates.sh" && _is_work_path "$2"' w19 "$T" "$2"; }
W19 'office' "$D19/Office/x" || fail "a name entry must match a path component"
W19 'offi' "$D19/Office/x" && fail "a name entry must match a whole component"
W19 "$D19/OFFICE/" "$D19/Office/x" || fail "a path entry must match a prefix, case-insensitively"
W19 "$D19/Off" "$D19/Office/x" && fail "a path entry must match whole components"
W19 'none' "$D19/Office/x" && fail "AI_WORK_ROOTS=none must give no work root"
W19 "nope:office" "$D19/Office/x" || fail "AI_WORK_ROOTS takes several entries"
