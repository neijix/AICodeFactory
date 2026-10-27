# shellcheck shell=bash
# Sourced by tests/run-tests.sh inside case 30 (IG, $IGH, $R30, $F30): install-global --work-root
# and the overlay-aware auto-bootstrap instructions.
# --work-root: appended to ~/.ai-work-roots once (any case), one line per run.
out=$(IG --work-root Office 2>&1) || fail "install-global --work-root failed: $out"
printf '%s\n' "$out" | grep -qxF "Recorded a work root: $IGH/.ai-work-roots += Office" || fail "--work-root must say what it recorded: $out"
out=$(IG --work-root=office 2>&1) || fail "a second --work-root failed: $out"
printf '%s\n' "$out" | grep -qxF "Work root already recorded: office ($IGH/.ai-work-roots)" || fail "a listed work root must say so: $out"
[ "$(cat "$IGH/.ai-work-roots")" = Office ] || fail "--work-root must append once: $(cat "$IGH/.ai-work-roots")"
out=$(IG --work-root 2>&1) && fail "--work-root needs a value: $out"
rm -f "$IGH/.ai-work-roots"
# The auto-bootstrap instructions are overlay-aware: the overlay's .append reaches both copies.
mkdir -p "$R30/ova/templates/global"; printf 'OVA-FRAGMENT\n' > "$R30/ova/templates/global/ai-autobootstrap.instructions.md.append"
out=$(AI_TEMPLATE_OVERLAY_DIR="$R30/ova" IG 2>&1) || fail "install-global with an overlay failed: $out"
case "$(uname -s)" in Darwin) P30="$IGH/Library/Application Support/Code/User/prompts" ;; *) P30="$IGH/.config/Code/User/prompts" ;; esac
{ cat "$F30/templates/global/ai-autobootstrap.instructions.md"; printf 'OVA-FRAGMENT\n'; } | cmp -s - "$P30/ai-autobootstrap.instructions.md" \
  || fail "the VS Code instructions must be the base plus the overlay fragment"
[ "$(tail -n 1 "$IGH/.copilot/copilot-instructions.md")" = OVA-FRAGMENT ] || fail "the Copilot CLI block must carry the overlay fragment"
out=$(IG 2>&1) || fail "install-global without an overlay failed: $out"
cmp -s "$F30/templates/global/ai-autobootstrap.instructions.md" "$P30/ai-autobootstrap.instructions.md" || fail "no overlay must give the base file"
grep -q OVA-FRAGMENT "$IGH/.copilot/copilot-instructions.md" && fail "the Copilot CLI block must drop a fragment that is gone"
