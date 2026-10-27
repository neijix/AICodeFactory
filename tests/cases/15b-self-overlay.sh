# shellcheck shell=bash
# Sourced by tests/run-tests.sh (its helpers and sandbox). The template repo syncing itself takes
# no overlay (no fragment, no override, no overlay-manifest entry): its pointer copies stay the base
# ones, while a project synced by the same engine gets the overlay.
echo "--- 15b. the template repo syncing itself takes no overlay; its projects still do"
ST="$S/selftpl"; mkdir -p "$ST" "$S/proj-st" "$S/ov-st/templates"
(cd "$T" && tar -cf - --exclude=.git --exclude=.DS_Store .) | (cd "$ST" && tar -xf -)
printf 'ST-FRAGMENT\n' > "$S/ov-st/templates/CLAUDE.md.template.append"
printf '[POINTERS]\ntemplates/CLAUDE.md.template|st-extra.md\n' > "$S/ov-st/overlay-manifest.txt"
(cd "$ST" && git init -q) && (cd "$S/proj-st" && git init -q)
export AI_TEMPLATE_OVERLAY_DIR="$S/ov-st"
"$BASH_BIN" "$ST/sync-ai-templates.sh" "$S/proj-st" >/dev/null
[ "$(tail -1 "$S/proj-st/CLAUDE.md")" = ST-FRAGMENT ] || fail "a project must get the overlay fragment"
[ -f "$S/proj-st/st-extra.md" ] || fail "a project must get the overlay-manifest pointer"
out=$("$BASH_BIN" "$ST/sync-ai-templates.sh" "$ST" 2>&1)
cmp -s "$ST/templates/CLAUDE.md.template" "$ST/CLAUDE.md" || fail "the template repo must not take the overlay fragment: $(tail -1 "$ST/CLAUDE.md")"
[ ! -e "$ST/st-extra.md" ] || fail "the template repo must not take overlay-manifest entries"
out=$("$BASH_BIN" "$ST/sync-ai-templates.sh" "$S/proj-st" --quiet); [ -z "$out" ] || fail "a project after the template repo must still settle: $out"
export AI_TEMPLATE_OVERLAY_DIR=none
