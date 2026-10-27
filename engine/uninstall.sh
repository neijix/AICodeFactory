#!/usr/bin/env bash
# Undoes `aicf setup` (engine/install-global.sh) on this machine, for this checkout:
#   - the global skill folders it installed: links into this checkout's skills (or the overlay's),
#     and copies whose .ai-template-origin names them — in every tool's skills dir and in each
#     Claude profile's config dir. Skills another template repo installed, and copies without
#     the marker, are not ours and stay.
#   - in ~/.claude/settings.json and each Claude profile's settings.json: the global SessionStart
#     hook (the entry running --global-hook) and the env keys AI_TEMPLATE_DIR, AI_CODE_ROOT and
#     AI_TEMPLATE_OVERLAY_DIR. Every other key stays; a file left empty is removed.
#   - the Copilot CLI block in ~/.copilot/copilot-instructions.md (your own text above it stays),
#     the VS Code prompts file ai-autobootstrap.instructions.md, ~/.gemini/commands/bootstrap-ai.toml
#   - the managed `claude` profile block in the shell profiles (~/.zshrc, ~/.bashrc, the PowerShell
#     profiles, or $AI_SHELL_PROFILES)
#   - ~/.ai-template-dir, ~/.ai-template-overlay-dir, ~/.ai-work-roots, ~/.claude-profiles and
#     ~/.ai-skills-stamp, then the folders setup created that are now empty.
#
# Never touched: any project, a code root's .ai-root and .ai-context-remote, ~/.apps-config-dir
# (your apps read it), the <file>.bak backups setup kept when it removed stale MCP entries, the
# "settings" a Claude profile merged into its config dir, and this checkout itself.
# When ~/.ai-template-dir names another checkout, that one owns the machine-wide files: only the
# skills and settings entries of this checkout go.
#
# Usage: aicf uninstall [--yes]
#   (no option)  preview: print what would be removed or edited; nothing changes
#   --yes        do it
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the template repo (this file is in engine/)
CODE_ROOT="$(dirname "$SCRIPT_DIR")"
APPLY=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y) APPLY=true ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (usage: aicf uninstall [--yes])" >&2; exit 2 ;;
  esac
done
[ -n "${HOME:-}" ] || { echo "Error: HOME is not set" >&2; exit 1; }

# shellcheck source=../sync-ai-templates.sh
source "$SCRIPT_DIR/sync-ai-templates.sh"
PY="$(_memory_py 2>/dev/null)" || { echo "Error: aicf uninstall needs python3 (or uv), as aicf setup does" >&2; exit 1; }
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  *)      BASE="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
esac

# This checkout owns the machine-wide files unless ~/.ai-template-dir names another live one.
OWNS=true
OTHER=""
if [ -s "$HOME/.ai-template-dir" ]; then
  OTHER="$(head -n 1 "$HOME/.ai-template-dir" | tr -d '\r')"
  if [ -f "$OTHER/sync-ai-templates.sh" ] && ! _same_path "$OTHER" "$SCRIPT_DIR"; then OWNS=false; fi
fi
FOUND=0

# _act <remove|edit|keep> <path> <why> — one line; in --yes mode a remove deletes <path>.
_act() {
  [ "$1" = keep ] || FOUND=$((FOUND + 1))
  printf '  %-8s %s (%s)\n' "[$1]" "$2" "$3"
  if [ "$APPLY" = true ] && [ "$1" = remove ]; then rm -rf "$2"; fi
}

# _ours_skill <dest> — a link into one of our skills sources, or a copy whose marker names one.
_ours_skill() {
  local dest="$1" target origin src
  if [ -L "$dest" ]; then
    target="$(readlink "$dest")"
    for src in "${SKILL_SRCS[@]}"; do
      case "$target" in "$src"/*|"${src%/skills}/vscode-global/skills"/*) return 0 ;; esac
    done
    return 1
  fi
  [ -d "$dest" ] && [ -f "$dest/$SKILL_ORIGIN_FILE" ] || return 1
  origin="$(head -n 1 "$dest/$SKILL_ORIGIN_FILE" 2>/dev/null)"
  for src in "${SKILL_SRCS[@]}"; do
    _same_skill_src "$origin" "$src" && return 0
    _legacy_skill_src "$origin" "$src" && return 0
  done
  return 1
}

# _prune_empty <dir> — remove <dir> and its parents while they are empty folders below $HOME.
_prune_empty() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "$HOME" ]; do
    case "$d" in "$HOME"/*) ;; *) return 0 ;; esac
    [ -d "$d" ] && [ ! -L "$d" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ] || return 0
    rmdir "$d" 2>/dev/null || return 0
    d="$(dirname "$d")"
  done
}

if [ "$APPLY" = true ]; then echo "Removing what aicf setup installed for $SCRIPT_DIR:"
else echo "Preview — what aicf uninstall --yes would remove for $SCRIPT_DIR (nothing changes now):"; fi
[ "$OWNS" = true ] || _act keep "$HOME/.ai-template-dir" "names another checkout, $OTHER: its own aicf uninstall removes the machine-wide files"

# 1. Skills (the profile dirs are in SKILL_ROOTS while ~/.claude-profiles is still there).
_factory_extra_skill_srcs || true
PROFILE_DIRS=()
if [ -r "$HOME/.claude-profiles" ]; then
  while IFS=$'\t' read -r _r _d <&3; do
    _d="${_d%$'\r'}"; [ -n "$_d" ] || continue
    # Git Bash: the list holds C:/... paths; the prune below needs them under $HOME as bash spells it.
    if command -v cygpath >/dev/null 2>&1; then
      _m="$(cygpath -m "$_d")"; _h="$(cygpath -m "$HOME")"
      case "$_m" in "$_h"/*) _d="$HOME/${_m#"$_h"/}" ;; *) _d="$(cygpath -u "$_d")" ;; esac
    fi
    PROFILE_DIRS+=("$_d")
  done 3< "$HOME/.claude-profiles"
fi
for root in "${SKILL_ROOTS[@]}"; do
  [ -d "$root" ] || continue
  n=0
  for dest in "$root"/*; do
    { [ -e "$dest" ] || [ -L "$dest" ]; } && _ours_skill "$dest" || continue
    n=$((n + 1))
    if [ "$APPLY" = true ]; then rm -rf "$dest"; fi
  done
  [ "$n" -eq 0 ] && continue
  FOUND=$((FOUND + n))
  printf '  %-8s %s skill folder(s) in %s (from this checkout; the others stay)\n' "[remove]" "$n" "$root"
done

# 2. JSON and text edits: Claude settings, the Copilot CLI block, the shell-profile blocks.
SETTINGS=("$HOME/.claude/settings.json")
for d in ${PROFILE_DIRS[@]+"${PROFILE_DIRS[@]}"}; do SETTINGS+=("$d/settings.json"); done
RCS=()
if [ -n "${AI_SHELL_PROFILES:-}" ]; then
  IFS=':' read -r -a RCS <<< "$AI_SHELL_PROFILES"
fi
RCS+=("$HOME/.zshrc" "$HOME/.bashrc" "${XDG_CONFIG_HOME:-$HOME/.config}/powershell/profile.ps1" "$HOME/.config/powershell/profile.ps1"
      "$HOME/Documents/PowerShell/profile.ps1" "$HOME/Documents/WindowsPowerShell/profile.ps1")
# A function, not a heredoc inside "$( )": bash 3.2 (macOS) misparses the quotes of that one.
_edits() {
  "$PY" - "$APPLY" "$OWNS" "$SCRIPT_DIR" "$CODE_ROOT" "$HOME/.copilot/copilot-instructions.md" \
    "${#SETTINGS[@]}" "${SETTINGS[@]}" ${RCS[@]+"${RCS[@]}"} <<'PY'
import json, os, sys
apply, owns, tdir, code_root, copilot = sys.argv[1] == "true", sys.argv[2] == "true", *sys.argv[3:6]
n = int(sys.argv[6])
settings, rcs = sys.argv[7:7 + n], list(dict.fromkeys(sys.argv[7 + n:]))
found = 0

def same(a, b):
    k = lambda p: os.path.normcase(os.path.realpath(p) if os.path.exists(p) else os.path.normpath(p))
    return bool(a) and bool(b) and k(a) == k(b)

def act(verb, path, why):
    global found
    found += verb != "keep"
    print(f"  {'[' + verb + ']':<8} {path} ({why})")

def write(path, text):
    if not apply:
        return
    if text:
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    else:
        os.remove(path)

def strip_tail(head):  # what precedes a managed block, minus the blank line setup added
    return head.rstrip("\n") + ("\n" if head.strip() else "")

for sf in settings:
    if not os.path.isfile(sf):
        continue
    try:
        raw = open(sf, encoding="utf-8-sig").read()
        data = json.loads(raw) if raw.strip() else {}
        if not isinstance(data, dict):
            raise ValueError
    except Exception:
        act("keep", sf, "not a JSON object: edit it by hand")
        continue
    env = data.get("env") if isinstance(data.get("env"), dict) else {}
    named = env.get("AI_TEMPLATE_DIR")
    if (named is not None and not same(str(named), tdir)) or (named is None and not owns):
        continue  # another checkout's entries
    gone = []
    hooks = data.get("hooks")
    if isinstance(hooks, dict) and isinstance(hooks.get("SessionStart"), list):
        kept = [e for e in hooks["SessionStart"] if e is None or "--global-hook" not in json.dumps(e)]
        if len(kept) != len(hooks["SessionStart"]):
            gone.append("global SessionStart hook")
            hooks["SessionStart"] = kept
            if not kept:
                del hooks["SessionStart"]
            if not hooks:
                del data["hooks"]
    for key in ("AI_TEMPLATE_DIR", "AI_CODE_ROOT", "AI_TEMPLATE_OVERLAY_DIR"):
        if key in env and (key != "AI_CODE_ROOT" or same(str(env[key]), code_root)):
            del env[key]
            gone.append(key)
    if "env" in data and env == {} and isinstance(data["env"], dict):
        del data["env"]
    if not gone:
        continue
    act("edit" if data else "remove", sf, ", ".join(gone) + ("" if data else "; nothing else in it"))
    write(sf, json.dumps(data, indent=2, ensure_ascii=False) + "\n" if data else "")

marker = "Global AI Behavior — Auto-Bootstrap Every Project"
if owns and os.path.isfile(copilot):
    text = open(copilot, encoding="utf-8").read()
    i = text.find(marker)
    if i >= 0:
        new = strip_tail(text[: text.rfind("\n", 0, i) + 1])
        act("edit" if new else "remove", copilot, "auto-bootstrap block" + ("" if new else "; nothing else in it"))
        write(copilot, new)

BEGIN, END = "# >>> AICodeFactory claude-profiles >>>", "# <<< AICodeFactory claude-profiles <<<"
for rc in rcs if owns else []:
    if not os.path.isfile(rc):
        continue
    text = open(rc, encoding="utf-8").read()
    i, j = text.find(BEGIN), text.find(END)
    if i < 0 or j < i:
        continue
    j = text.find("\n", j)
    j = len(text) if j < 0 else j + 1
    new = strip_tail(text[:i]) + text[j:]
    new = "" if not new.strip() else new
    act("edit" if new else "remove", rc, "claude profile function" + ("" if new else "; nothing else in it"))
    write(rc, new)
sys.exit(0 if found else 3)
PY
}
EDITS="$(_edits)" && rc=0 || rc=$?
[ -z "$EDITS" ] || printf '%s\n' "$EDITS"
[ "$rc" = 0 ] && FOUND=$((FOUND + 1))
[ "$rc" = 0 ] || [ "$rc" = 3 ] || { echo "Error: editing the settings files failed (python exit $rc)" >&2; exit 1; }

# 3. Files setup wrote whole.
TOML="$HOME/.gemini/commands/bootstrap-ai.toml"
if [ -f "$TOML" ] && { grep -qF "$SCRIPT_DIR/skills/bootstrap-ai/SKILL.md" "$TOML" ||
                       grep -qF "$SCRIPT_DIR/vscode-global/skills/bootstrap-ai/SKILL.md" "$TOML"; }; then
  _act remove "$TOML" "Gemini CLI command"
fi
if [ "$OWNS" = true ]; then
  for f in "$BASE/Code/User/prompts/ai-autobootstrap.instructions.md" "$HOME/.ai-template-dir" \
           "$HOME/.ai-template-overlay-dir" "$HOME/.ai-work-roots" "$HOME/.claude-profiles" \
           "$HOME/.ai-skills-stamp" "$HOME/.ai-skills-stamp.running"; do
    if [ -e "$f" ]; then _act remove "$f" "written by aicf setup"; fi
  done
fi
for f in "$HOME/.apps-config-dir" "$CODE_ROOT/.ai-context-remote" "$CODE_ROOT/.ai-root"; do
  if [ -e "$f" ]; then _act keep "$f" "not removed: yours, or the code root's"; fi
done

# 4. The folders setup created, once empty.
if [ "$APPLY" = true ]; then
  for root in "${SKILL_ROOTS[@]}"; do _prune_empty "$root"; done
  for d in ${PROFILE_DIRS[@]+"${PROFILE_DIRS[@]}"}; do _prune_empty "$d/skills"; done   # SKILL_ROOTS may spell it C:\...
  for d in "$HOME/.gemini/commands" "$HOME/.copilot" "$HOME/.claude" "$BASE/Code/User/prompts" \
           "${XDG_CONFIG_HOME:-$HOME/.config}/powershell" "$HOME/.config/powershell" "$HOME/Documents/PowerShell" "$HOME/Documents/WindowsPowerShell"; do
    _prune_empty "$d"
  done
fi

if [ "$FOUND" -eq 0 ]; then echo "Nothing of aicf setup is installed for this checkout."
elif [ "$APPLY" = true ]; then echo "Done. Projects keep their AI files; delete $SCRIPT_DIR by hand if you no longer want it."
else echo "Nothing changed. Run aicf uninstall --yes to apply."; fi
