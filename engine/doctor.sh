#!/usr/bin/env bash
# doctor.sh — one command, safe to run at any time, that checks this machine's whole AI setup and,
# with --yes, puts it right. It holds no logic of its own beyond the checks: every fix is the
# existing scripts (install-global, sync-ai-templates, update-projects), run in the right order.
#
# Usage: aicf doctor [--yes] [--clone] [--push] [--copy] | --json
#   (no flag)  check only — one line per item, nothing written, no network:
#                OK    as it should be
#                FIX   wrong, and `aicf doctor --yes` puts it right
#                TODO  wrong, and only you can put it right (the line says how)
#                WARN  worth knowing, nothing to fix (unpushed commits, optional tools…)
#   --yes      fix, in this order: fast-forward this repo (+ overlay; re-runs itself when it moved)
#              and the code root's .ai-root, re-run install-global (skills, markers, global hook,
#              Claude env, stale MCP entries), re-sync this repo's pointer copies, switch the
#              projects that miss the private-layer plan (update-projects --migrate --yes), refresh
#              every bootstrapped sibling (update-projects --yes --pull), then check again
#   --clone    with --yes: also clone your GitHub repos that have no local folder (needs gh)
#   --push     with --yes: also push the sync commits (never done otherwise)
#   --copy     with --yes: install skills as copies (install-global --copy; Windows always copies)
#   --json     the check-only pass as one JSON document on stdout (schema 1: ok, counts, checks,
#              projects, unsynced) for a UI to read; alone — not with --yes/--clone/--push/--copy (exit 2)
#
# Run it from the main checkout: in a linked worktree --yes refuses (install-global would point
# this machine at the worktree).
# Exit status: 0 when nothing is FIX or TODO (WARN lines allowed), 1 otherwise, 2 on bad usage.
# macOS/Linux; under Git Bash on Windows it hands over to doctor.ps1 (install-global.sh is not
# for Windows).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the template repo (this file is in engine/)

case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*)
    for ps in pwsh powershell.exe powershell; do
      if command -v "$ps" >/dev/null 2>&1; then
        exec "$ps" -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$SCRIPT_DIR/engine/doctor.ps1")" "$@"
      fi
    done
    echo "Error: on Windows run engine/doctor.ps1 (no PowerShell found on PATH)." >&2
    exit 1 ;;
esac

YES=false
CLONE=false
PUSH=false
COPY=false
JSON=false
TEMPLATE_PULLED=false   # --template-pulled: internal, set by the re-run after this repo moved
RERUN=()
for arg in "$@"; do
  case "$arg" in
    --yes) YES=true ;;
    --clone) CLONE=true ;;
    --push) PUSH=true ;;
    --copy) COPY=true ;;
    --json) JSON=true ;;
    --template-pulled) TEMPLATE_PULLED=true ;;
    -h|--help) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (usage: aicf doctor [--yes] [--clone] [--push] [--copy] | --json)" >&2; exit 2 ;;
  esac
  [ "$arg" = --template-pulled ] || RERUN+=("$arg")
done
if [ "$JSON" = true ] && [ "$YES$CLONE$PUSH$COPY" != falsefalsefalsefalse ]; then
  echo "Error: --json only reports; it cannot be combined with --yes, --clone, --push or --copy." >&2
  exit 2
fi

# shellcheck source=../sync-ai-templates.sh
source "$SCRIPT_DIR/sync-ai-templates.sh"

CODE_ROOT="$(dirname "$SCRIPT_DIR")"
# A linked worktree has a .git FILE; install-global run from one would repoint this machine at it.
LINKED_WORKTREE=false
[ -f "$SCRIPT_DIR/.git" ] && LINKED_WORKTREE=true
case "$(uname -s)" in
  Darwin) VSCODE_USER="$HOME/Library/Application Support/Code/User" ;;
  *)      VSCODE_USER="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ;;
esac

N_FIX=0
N_TODO=0
N_WARN=0
N_OK=0
# --json: _row records instead of printing; _section names the group the next rows belong to.
SECTION=""
CHECKS_JSON=""      # the "checks" array body, built row by row
PROJECTS_LINES=""   # "name<TAB>record" per project, sorted and joined at the end

# _jq <string> — the string as a JSON string literal (quotes, backslashes, control chars escaped).
_jq() {
  local s="$1" out="" c i code
  case "$s" in
    *[\\\"[:cntrl:]]*) ;;
    *) printf '"%s"' "$s"; return 0 ;;
  esac
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \\) out="$out\\\\" ;;
      \") out="$out\\\"" ;;
      $'\n') out="$out\\n" ;;
      $'\r') out="$out\\r" ;;
      $'\t') out="$out\\t" ;;
      *)
        code="$(printf '%d' "'$c")"
        if [ "$code" -lt 32 ]; then out="$out$(printf '\\u%04x' "$code")"; else out="$out$c"; fi ;;
    esac
  done
  printf '"%s"' "$out"
}

# _section <heading> — the "== heading" line, or (--json) the section of the rows that follow.
_section() {
  if [ "$JSON" = true ]; then SECTION="$1"; else echo "== $1"; fi
}

# _row <OK|FIX|TODO|WARN> <what> [hint] — one report line, counted.
_row() {
  if [ "$JSON" = true ]; then
    CHECKS_JSON="${CHECKS_JSON:+$CHECKS_JSON,}{\"section\":$(_jq "$SECTION"),\"status\":\"$1\",\"what\":$(_jq "$2"),\"hint\":$(_jq "${3:-}")}"
  else
    printf '%-6s%s\n' "$1" "$2"
    [ -z "${3:-}" ] || printf '      -> %s\n' "$3"
  fi
  case "$1" in
    OK)   N_OK=$((N_OK + 1)) ;;
    FIX)  N_FIX=$((N_FIX + 1)) ;;
    TODO) N_TODO=$((N_TODO + 1)) ;;
    WARN) N_WARN=$((N_WARN + 1)) ;;
  esac
  return 0
}

# _join <name>... — "a, b, c", at most 8 names then "…".
_join() {
  local out="" n=0 x
  for x in "$@"; do
    n=$((n + 1))
    if [ "$n" -gt 8 ]; then out="$out, …"; break; fi
    [ -n "$out" ] && out="$out, "
    out="$out$x"
  done
  printf '%s' "$out"
}

check_tools() {
  _section "Tools"
  local py
  py="$(_memory_py 2>/dev/null)" || py=""
  if [ -n "$py" ]; then _row OK "python ($py)"
  else _row TODO "python not found" "install Python 3 or uv: the settings merges and the AGENTS.md refresh need it"; fi
  if command -v uv >/dev/null 2>&1; then _row OK "uv"
  else _row WARN "uv not found" "optional: skills' scripts prefer uv run (https://docs.astral.sh/uv/)"; fi
  if command -v dotnet >/dev/null 2>&1; then _row OK "dotnet"
  else _row WARN "dotnet not found" "optional: project tools in C# need the .NET 10 SDK (csharp-tools skill)"; fi
  if ! command -v gh >/dev/null 2>&1; then
    _row WARN "gh not found" "optional: --clone and the GitHub skills need it"
  elif gh auth token >/dev/null 2>&1; then _row OK "gh (authenticated)"
  else _row WARN "gh is not authenticated" "gh auth login (--clone needs it)"; fi
}

check_template_repo() {
  _section "$TEMPLATE_NAME ($TEMPLATE_DIR)"
  local ahead
  [ "$LINKED_WORKTREE" = false ] || _row TODO "this is a linked git worktree, not the main checkout"     "run doctor from the main checkout: --yes refuses here"
  if [ -n "$(git -C "$TEMPLATE_DIR" status --porcelain 2>/dev/null)" ]; then
    _row WARN "uncommitted changes" "commit them: --yes does not pull a dirty tree"
  else
    _row OK "working tree clean"
  fi
  ahead="$(ahead_count "$TEMPLATE_DIR")"
  case "$ahead" in
    ""|0) ;;
    no-remote) _row WARN "no upstream branch" "other machines cannot get this repo's changes" ;;
    *) _row WARN "$ahead commit(s) not on origin" "git -C \"$TEMPLATE_DIR\" push" ;;
  esac
  if [ -s "$OVERLAY_MARKER" ] && [ -z "$OVERLAY_DIR" ]; then
    _row TODO "overlay $(head -n 1 "$OVERLAY_MARKER" | tr -d '\r') not found" \
      "clone it there, or aicf setup --overlay <dir>"
  elif [ -n "$OVERLAY_DIR" ]; then
    _row OK "overlay $OVERLAY_DIR"
  fi
  sync_ai_templates "$TEMPLATE_DIR" --dry-run >/dev/null 2>&1 || true
  if [ ${#SYNC_CHANGED[@]} -eq 0 ]; then _row OK "pointer copies match their templates"
  else _row FIX "pointer copies differ from their templates: $(_join "${SYNC_CHANGED[@]}")"; fi
}

check_machine() {
  _section "This machine (install-global)"
  local marker="" root missing=() out py line status what hint
  [ -s "$HOME/.ai-template-dir" ] && marker="$(head -n 1 "$HOME/.ai-template-dir" | tr -d '\r')"
  if [ "$marker" = "$TEMPLATE_DIR" ]; then _row OK "~/.ai-template-dir"
  elif [ -n "$marker" ]; then _row FIX "~/.ai-template-dir points at $marker"
  else _row FIX "~/.ai-template-dir is missing"; fi

  for root in "${SKILL_ROOTS[@]}"; do [ -d "$root" ] || missing+=("${root#"$HOME"/}"); done
  if [ ${#missing[@]} -gt 0 ]; then _row FIX "skills folder(s) missing: $(_join "${missing[@]}")"; fi
  out="$(SYNC_QUIET=false refresh_global_skills --dry-run 2>/dev/null | grep -c '^  \[' || true)"
  if [ "${out:-0}" -eq 0 ]; then _row OK "global skills up to date ($SKILL_MODE mode)"
  else _row FIX "$out global skill folder(s) out of date ($SKILL_MODE mode)"; fi

  # What install-global writes: the template plus the overlay's .append (the factory self-check
  # above rendered without the overlay).
  bootstrap="$(mktemp)"
  (TPL_OVERLAY="$OVERLAY_DIR"; _render templates/global/ai-autobootstrap.instructions.md "$bootstrap")
  if cmp -s "$bootstrap" "$VSCODE_USER/prompts/ai-autobootstrap.instructions.md"; then
    _row OK "VS Code auto-bootstrap instructions"
  else
    _row FIX "VS Code auto-bootstrap instructions missing or stale"
  fi
  if grep -qF "$TEMPLATE_DIR/skills/bootstrap-ai/SKILL.md" "$HOME/.gemini/commands/bootstrap-ai.toml" 2>/dev/null; then
    _row OK "Gemini CLI /bootstrap-ai command"
  else
    _row FIX "Gemini CLI /bootstrap-ai command missing or stale"
  fi

  py="$(_memory_py 2>/dev/null)" || py=""
  if [ -z "$py" ]; then
    _row TODO "Claude settings, Copilot instructions and MCP configs not checked (no python)"
  else
    # One line per finding: STATUS<TAB>what<TAB>hint. Paths travel in the environment.
    out="$(DOC_HOME="$HOME" DOC_TEMPLATE="$TEMPLATE_DIR" DOC_ROOT="$CODE_ROOT" \
      DOC_HOOK="$TEMPLATE_DIR/templates/global/claude-global-hook.json" \
      DOC_BOOTSTRAP="$bootstrap" \
      DOC_VSCODE_MCP="$VSCODE_USER/mcp.json" "$py" - <<'PY' 2>&1 || true
import json, os

home = os.environ["DOC_HOME"]
def j(*p): return os.path.join(home, *p)
def say(status, what, hint=""): print(f"{status}\t{what}\t{hint}")

def load(path):
    if not os.path.exists(path):
        return None, "missing"
    try:
        with open(path, encoding="utf-8-sig") as fh:
            raw = fh.read()
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        return None, "unparseable"
    return (data, "") if isinstance(data, dict) else (None, "not an object")

settings = j(".claude", "settings.json")
data, err = load(settings)
if err == "unparseable" or err == "not an object":
    say("TODO", f"~/.claude/settings.json is {err} JSON", "fix it by hand: Claude Code and install-global cannot read it")
else:
    data = data or {}
    env = data.get("env") if isinstance(data.get("env"), dict) else {}
    for key, want in (("AI_TEMPLATE_DIR", os.environ["DOC_TEMPLATE"]), ("AI_CODE_ROOT", os.environ["DOC_ROOT"])):
        if env.get(key) == want:
            say("OK", f"Claude env {key}")
        else:
            say("FIX", f"Claude env {key} " + ("is missing" if key not in env else f"is {env.get(key)}"))
    with open(os.environ["DOC_HOOK"], encoding="utf-8") as fh:
        entry = json.load(fh)
    starts = ((data.get("hooks") or {}).get("SessionStart") or []) if isinstance(data.get("hooks"), dict) else []
    ours = [e for e in starts if isinstance(starts, list) and "--global-hook" in json.dumps(e)]
    if len(ours) == 1 and ours[0] == entry:
        say("OK", "Claude global SessionStart hook")
    else:
        say("FIX", "Claude global SessionStart hook " + ("missing" if not ours else "stale or duplicated"))

dest = j(".copilot", "copilot-instructions.md")
lines = open(os.environ["DOC_BOOTSTRAP"], encoding="utf-8").read().splitlines(keepends=True)
dashes, body = 0, []
for line in lines:
    if line.strip() == "---" and dashes < 2:
        dashes += 1
        continue
    if dashes >= 2:
        body.append(line)
body = "".join(body).rstrip() + "\n"
try:
    text = open(dest, encoding="utf-8").read().replace("\r\n", "\n")
except OSError:
    text = ""
if text.endswith(body) or text.endswith(body + "\n"):
    say("OK", "Copilot CLI auto-bootstrap instructions")
else:
    say("FIX", "Copilot CLI auto-bootstrap instructions missing or stale")

stale = ("mlx-local", "d3skwebscout", "bitwarden")
found = []
for path in (os.environ["DOC_VSCODE_MCP"], j(".copilot", "mcp-config.json"), j(".cursor", "mcp.json"),
             j(".claude.json"), j(".gemini", "antigravity", "mcp_config.json"),
             j(".gemini", "config", "mcp_config.json"), j(".gemini", "settings.json")):
    d, _ = load(path)
    if not d:
        continue
    conts = [d.get("mcpServers"), d.get("servers")]
    if isinstance(d.get("projects"), dict):
        conts += [p.get("mcpServers") for p in d["projects"].values() if isinstance(p, dict)]
    if any(isinstance(c, dict) and any(n in c for n in stale) for c in conts):
        found.append(os.path.basename(path))
if found:
    say("FIX", "stale MCP entries (mlx-local / d3skwebscout / bitwarden) in " + ", ".join(found))
else:
    say("OK", "no stale MCP server entries")
PY
)"
    out="$(printf '%s\n' "$out" | tr -d '\r')"   # a Windows python ends its lines with CRLF
    while IFS="$(printf '\t')" read -r status what hint; do
      [ -n "$status" ] || continue
      case "$status" in
        OK|FIX|TODO|WARN) _row "$status" "$what" "$hint" ;;
        *) _row TODO "settings check failed: $status $what" ;;
      esac
    done <<EOF
$out
EOF
  fi
  rm -f "$bootstrap"

  local remote=""
  [ -s "$CODE_ROOT/.ai-context-remote" ] && remote="$(head -n 1 "$CODE_ROOT/.ai-context-remote" | tr -d '\r')"
  if [ -d "$CODE_ROOT/.ai-root/.git" ] || [ -f "$CODE_ROOT/.ai-root/.git" ]; then
    if [ -n "$(git -C "$CODE_ROOT/.ai-root" status --porcelain 2>/dev/null)" ]; then
      _row WARN ".ai-root has uncommitted changes" "commit them in $CODE_ROOT/.ai-root: the sync never pulls a dirty registry"
    else
      _row OK ".ai-root (project registry)"
    fi
  elif [ -n "$remote" ] && [ "$remote" != none ]; then
    _row FIX ".ai-root missing (cloned from $remote)"
  else
    _row WARN "no .ai-root and no private AI docs remote for $CODE_ROOT" \
      "aicf setup --ai-context-remote <url> to carry private AI docs between machines"
  fi
}

# One markdown doc, with fenced blocks skipped and `code spans` removed. mode=tokens prints every
# "[text]" that is not a link; mode=check exits 0 when the doc still holds a template placeholder:
# a <!-- BOOTSTRAP_PENDING --> line, a token listed in the file `toks`, or a line that is nothing
# but a "[placeholder]" (older templates' style; [NEEDS HUMAN INPUT] is intentional).
_PLACEHOLDER_AWK='
BEGIN { if (mode == "check") while ((getline t < toks) > 0) want[t] = 1 }
{ l = $0; sub(/\r$/, "", l) }
mode == "check" && l ~ /^<!-- BOOTSTRAP_PENDING -->/ { found = 1; exit }
l ~ /^[ \t]*```/ { fence = !fence; next }
fence { next }
{
  gsub(/`[^`]*`/, "", l)
  if (mode == "check" && l ~ /^[ \t]*([-*] |[0-9]+\. )?\[[^] [][^]]*[^] ]\][ \t]*$/ && l !~ /NEEDS HUMAN INPUT/) { found = 1; exit }
  while (match(l, /\[[^]]+\]/)) {
    t = substr(l, RSTART, RLENGTH); nx = substr(l, RSTART + RLENGTH, 1); l = substr(l, RSTART + RLENGTH)
    if (nx == "(" || nx == "[" || nx == ":") continue
    if (mode == "tokens") print t
    else if (t in want) { found = 1; exit }
  }
}
END { if (mode == "check") exit !found }'
PLACEHOLDER_TOKENS=""   # file: the placeholders of the rendered living-doc templates (built once)
GENERIC_HEADINGS=""     # refresh-agents-sections.py's GENERIC_HEADINGS, one per line (read once)

# _doc_gaps <dir> — sets DOC_PLACEHOLDERS (living docs still holding a template placeholder),
# DOC_MISSING (generic AGENTS.md headings the project lacks) and DOC_REMOTE (true|false).
_doc_gaps() {
  local dir="$1" entry rel tmp h
  DOC_PLACEHOLDERS=(); DOC_MISSING=(); DOC_REMOTE=false
  [ -z "$(git -C "$dir" remote 2>/dev/null)" ] || DOC_REMOTE=true
  if [ -z "$PLACEHOLDER_TOKENS" ]; then
    PLACEHOLDER_TOKENS="$(mktemp)"; tmp="$(mktemp)"
    echo '[PROJECT NAME]' > "$PLACEHOLDER_TOKENS"
    for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
      case "${entry#*|}" in *.md) ;; *) continue ;; esac
      _render "${entry%%|*}" "$tmp"
      awk -v mode=tokens "$_PLACEHOLDER_AWK" "$tmp" >> "$PLACEHOLDER_TOKENS"
    done
    rm -f "$tmp"
    GENERIC_HEADINGS="$(sed -n '/^GENERIC_HEADINGS = \[/,/^\]/s/^ *"\(.*\)",\{0,1\} *$/\1/p' \
      "$TEMPLATE_DIR/skills/bootstrap-ai/scripts/refresh-agents-sections.py" | tr -d '\r')"
  fi
  for entry in ${LIVING_DOCS_MAP[@]+"${LIVING_DOCS_MAP[@]}"}; do
    rel="${entry#*|}"
    case "$rel" in *.md) ;; *) continue ;; esac
    [ -f "$dir/$rel" ] || continue
    if awk -v mode=check -v toks="$PLACEHOLDER_TOKENS" "$_PLACEHOLDER_AWK" "$dir/$rel"; then DOC_PLACEHOLDERS+=("$rel"); fi
  done
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    tr -d '\r' < "$dir/AGENTS.md" | grep -qxF -- "$h" || DOC_MISSING+=("$h")
  done <<EOF
$GENERIC_HEADINGS
EOF
}

# _project_record <dir> <name> <current|stale|not-bootstrapped> — (--json) one project's record,
# appended to PROJECTS_LINES. "stale" reads SYNC_CHANGED of the dry-run just made, and the
# living-doc fields the DOC_* of the _doc_gaps just made.
_project_record() {
  local dir="$1" name="$2" state="$3" plan=ok dirty=false unp=null ahead files="" budget="" docs="" heads="" f line rel kb
  if ! _conforms "$dir"; then
    if [ "$(_expected_mode "$dir")" = tracked ]; then plan=tracked-mismatch; else plan=off-plan; fi
  fi
  [ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ] || dirty=true
  ahead="$(ahead_count "$dir")"
  case "$ahead" in ""|*[!0-9]*) ;; *) unp="$ahead" ;; esac
  if [ "$state" = stale ]; then
    for f in ${SYNC_CHANGED[@]+"${SYNC_CHANGED[@]}"}; do files="${files:+$files,}$(_jq "$f")"; done
  fi
  while IFS= read -r line; do
    case "$line" in "ai-sync: context budget: "*" KB (> "*) ;; *) continue ;; esac
    line="${line#ai-sync: context budget: }"
    rel="${line%% is *}"
    kb="${line#"$rel is "}"; kb="${kb%% KB*}"
    budget="${budget:+$budget,}{\"file\":$(_jq "$rel"),\"kb\":$kb}"
  done < <(_check_context_budget "$dir")
  for f in ${DOC_PLACEHOLDERS[@]+"${DOC_PLACEHOLDERS[@]}"}; do docs="${docs:+$docs,}$(_jq "$f")"; done
  for f in ${DOC_MISSING[@]+"${DOC_MISSING[@]}"}; do heads="${heads:+$heads,}$(_jq "$f")"; done
  PROJECTS_LINES="${PROJECTS_LINES:+$PROJECTS_LINES
}$name	{\"name\":$(_jq "$name"),\"path\":$(_jq "$dir"),\"bootstrapped\":$([ "$state" = not-bootstrapped ] && echo false || echo true),\"ai_files\":\"$state\",\"stale_files\":[$files],\"plan\":\"$plan\",\"dirty\":$dirty,\"unpushed\":$unp,\"over_budget\":[$budget],\"remote\":$DOC_REMOTE,\"placeholder_docs\":[$docs],\"missing_headings\":[$heads]}"
}

# _emit_json <ok> — the whole report, one document, on stdout.
_emit_json() {
  local projects="" name rec
  while IFS="$(printf '\t')" read -r name rec; do
    [ -n "$name" ] || continue
    projects="${projects:+$projects,}$rec"
  done <<EOF
$(printf '%s\n' "$PROJECTS_LINES" | LC_ALL=C sort -t "$(printf '\t')" -k1,1)
EOF
  printf '{"schema":1,"template_dir":%s,"code_root":%s,"ok":%s,' "$(_jq "$TEMPLATE_DIR")" "$(_jq "$CODE_ROOT")" "$1"
  printf '"counts":{"ok":%d,"fix":%d,"todo":%d,"warn":%d},' "$N_OK" "$N_FIX" "$N_TODO" "$N_WARN"
  printf '"checks":[%s],"projects":[%s],"unsynced":%s}\n' "$CHECKS_JSON" "$projects" "${UNSYNCED_JSON:-[]}"
}

# _unsynced_report — ahead, behind, dirty, conflict, or a leftover skill copy. Read-only.
# One pass: JSON for --json, else one WARN row per line.
_unsynced_report() {
  UNSYNCED_JSON='[]'
  local py line
  py="$(_memory_py 2>/dev/null)" || return 0
  if [ "$JSON" = true ]; then
    UNSYNCED_JSON="$("$py" "$TEMPLATE_DIR/engine/factory-env.py" unsynced --root "$CODE_ROOT" 2>/dev/null |
      tr -d '\r\n')" || UNSYNCED_JSON='[]'
    case "$UNSYNCED_JSON" in \[*) ;; *) UNSYNCED_JSON='[]' ;; esac
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] && _row WARN "$line"
  done <<EOF
$("$py" "$TEMPLATE_DIR/engine/factory-env.py" unsynced --root "$CODE_ROOT" --lines 2>/dev/null | tr -d '\r' || true)
EOF
  return 0
}

check_projects() {
  _section "Projects in $CODE_ROOT"
  local dir name expected misses=() tracked_misses=() stale=() bare=() unpushed=() ahead
  local unfilled=() headless=() remoteless=() moved=() docs f root_known=false
  # A root with neither knows no hidden ai-context repo: a project that moved its AGENTS.md there
  # (deleted from the code repo) cannot get it back on this machine.
  { [ -e "$CODE_ROOT/.ai-root/.git" ] || [ -s "$CODE_ROOT/.ai-context-remote" ]; } && root_known=true
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    _conforms "$dir" && continue
    expected="$(_expected_mode "$dir")"
    if [ "$expected" = tracked ]; then tracked_misses+=("$(basename "$dir")")
    else misses+=("$(basename "$dir")"); fi
  done < <(_conform_repos "$CODE_ROOT" | LC_ALL=C sort)
  if [ ${#misses[@]} -gt 0 ]; then _row FIX "${#misses[@]} project(s) off the private-layer plan: $(_join "${misses[@]}")"
  else _row OK "every project on the private-layer plan"; fi
  [ ${#tracked_misses[@]} -eq 0 ] || _row TODO "registry says tracked, project is not: $(_join "${tracked_misses[@]}")" \
    "edit .ai-root/projects/<name>, or switch the project by hand"

  local overlay_real=""   # the overlay is part of the factory, not a project
  [ -z "$OVERLAY_DIR" ] || overlay_real="$(cd "$OVERLAY_DIR" 2>/dev/null && pwd -P)" || overlay_real=""
  for dir in "$CODE_ROOT"/*/; do
    dir="${dir%/}"
    name="$(basename "$dir")"
    [ "$name" != "$TEMPLATE_NAME" ] || continue
    [ -z "$overlay_real" ] || [ "$(cd "$dir" && pwd -P)" != "$overlay_real" ] || continue
    case "$name" in *.worktrees) continue ;; esac
    [ -e "$dir/.git" ] || continue
    if [ ! -f "$dir/AGENTS.md" ] || [ -L "$dir/AGENTS.md" ]; then
      if [ "$root_known" = false ] && [ -n "$(git -C "$dir" log --diff-filter=D --format=%h -1 -- AGENTS.md 2>/dev/null)" ]; then
        moved+=("$name")
      else bare+=("$name"); fi
      if [ "$JSON" = true ]; then
        DOC_PLACEHOLDERS=(); DOC_MISSING=(); DOC_REMOTE=false
        [ -z "$(git -C "$dir" remote 2>/dev/null)" ] || DOC_REMOTE=true
        _project_record "$dir" "$name" not-bootstrapped
      fi
      continue
    fi
    _doc_gaps "$dir"
    if [ ${#DOC_PLACEHOLDERS[@]} -gt 0 ]; then
      docs=""
      for f in "${DOC_PLACEHOLDERS[@]}"; do docs="${docs:+$docs }${f##*/}"; done
      unfilled+=("$name ($docs)")
    fi
    [ ${#DOC_MISSING[@]} -eq 0 ] || headless+=("$name")
    [ "$DOC_REMOTE" = true ] || remoteless+=("$name")
    sync_ai_templates "$dir" --dry-run >/dev/null 2>&1 || true
    [ ${#SYNC_CHANGED[@]} -eq 0 ] || stale+=("$name")
    ahead="$(ahead_count "$dir")"
    case "$ahead" in ""|0|no-remote|"?") ;; *) unpushed+=("$name ($ahead)") ;; esac
    if [ "$JSON" = true ]; then
      if [ ${#SYNC_CHANGED[@]} -eq 0 ]; then _project_record "$dir" "$name" current
      else _project_record "$dir" "$name" stale; fi
    fi
  done
  if [ ${#stale[@]} -gt 0 ]; then _row FIX "${#stale[@]} project(s) with stale AI files: $(_join "${stale[@]}")"
  else _row OK "every bootstrapped project's AI files up to date"; fi
  if [ ${#unfilled[@]} -gt 0 ]; then
    _row TODO "${#unfilled[@]} project(s) with living docs still holding template placeholders: $(_join "${unfilled[@]}")" \
      "run /bootstrap-ai in each: it fills them and drops <!-- BOOTSTRAP_PENDING -->"
  else _row OK "every bootstrapped project's living docs filled"; fi
  if [ ${#headless[@]} -gt 0 ]; then
    _row TODO "${#headless[@]} project(s) whose AGENTS.md misses generic sections: $(_join "${headless[@]}")" \
      "run /bootstrap-ai in each: it brings AGENTS.md onto the template (the sync only refreshes sections already there)"
  else _row OK "every bootstrapped project's AGENTS.md has the generic sections"; fi
  if [ ${#remoteless[@]} -gt 0 ]; then
    _row TODO "${#remoteless[@]} project(s) with no git remote: $(_join "${remoteless[@]}")" \
      "gh repo create <name> --private --source <dir> --push, or git -C <dir> remote add origin <url>"
  else _row OK "every bootstrapped project has a git remote"; fi
  [ ${#moved[@]} -eq 0 ] || _row TODO "${#moved[@]} project(s) whose AI files are in a private repo $CODE_ROOT has no remote for: $(_join "${moved[@]}")"     "aicf setup --ai-context-remote <url> (the one in .ai-context-remote of the root on the machine that moved them), then open a session in each"
  [ ${#bare[@]} -eq 0 ] || _row WARN "${#bare[@]} git repo(s) not bootstrapped: $(_join "${bare[@]}")" \
    "aicf update <name> or /bootstrap-ai, if they should be"
  [ ${#unpushed[@]} -eq 0 ] || _row WARN "commits not on their remote: $(_join "${unpushed[@]}")" \
    "aicf doctor --yes --push, or push them yourself"
  [ -z "$PLACEHOLDER_TOKENS" ] || rm -f "$PLACEHOLDER_TOKENS"
  PLACEHOLDER_TOKENS=""
  return 0
}

run_checks() {
  N_FIX=0; N_TODO=0; N_WARN=0; N_OK=0
  check_tools
  check_template_repo
  check_machine
  check_projects
  _unsynced_report
  if [ "$JSON" = true ]; then
    if [ $((N_FIX + N_TODO)) -eq 0 ]; then _emit_json true >&3; else _emit_json false >&3; fi
    return 0
  fi
  echo
  if [ $((N_FIX + N_TODO)) -eq 0 ]; then
    if [ "$N_WARN" -eq 0 ]; then echo "All good."; else echo "All good ($N_WARN warning(s))."; fi
  else
    echo "$N_FIX to fix, $N_TODO for you, $N_WARN warning(s)."
    [ "$N_FIX" -eq 0 ] || [ "$YES" = true ] || echo "Run aicf doctor --yes to fix the FIX lines."
  fi
}

# _step <label> <command>... — one fix step; a failure is reported and the next step still runs.
_step() {
  local label="$1"; shift
  echo
  echo "== $label"
  "$@" || echo "STEP FAILED   $label (exit $?) — carrying on"
}

if [ "$YES" = true ]; then
  if [ "$LINKED_WORKTREE" = true ]; then
    echo "Error: $SCRIPT_DIR is a linked git worktree. Run doctor --yes from the main checkout:" >&2
    echo "install-global would point this machine at the worktree." >&2
    exit 1
  fi
  if [ "$TEMPLATE_PULLED" = false ]; then
    echo "== Pull $TEMPLATE_NAME"
    net_budget_reset
    pull_template
    if [ "$PULL_UPDATED" = true ]; then
      echo "PULLED        $TEMPLATE_NAME — re-running with the new version"
      exec "$BASH" "${BASH_SOURCE[0]}" ${RERUN[@]+"${RERUN[@]}"} --template-pulled
    fi
  fi
  net_budget_reset
  ai_root_pull "$CODE_ROOT"
  if [ "$COPY" = true ]; then
    _step "install-global" "$BASH" "$SCRIPT_DIR/engine/install-global.sh" --copy
  else
    _step "install-global" "$BASH" "$SCRIPT_DIR/engine/install-global.sh"
  fi
  _step "Sync $TEMPLATE_NAME's pointer copies" "$BASH" "$SCRIPT_DIR/sync-ai-templates.sh" "$SCRIPT_DIR" --commit
  _step "Private-layer plan" "$BASH" "$SCRIPT_DIR/engine/update-projects.sh" --migrate --yes
  up=(--yes --pull --template-pulled)
  [ "$CLONE" = false ] || up+=(--clone)
  [ "$PUSH" = false ] || up+=(--push)
  _step "Projects" "$BASH" "$SCRIPT_DIR/engine/update-projects.sh" "${up[@]}"
  echo
  echo "== Checking again"
fi

if [ "$JSON" = true ]; then exec 3>&1 1>&2; fi   # stdout is the JSON alone: stray engine output goes to stderr
run_checks
[ $((N_FIX + N_TODO)) -eq 0 ]
