#!/usr/bin/env bash
# Installs the global AI customizations (skills, auto-bootstrap instruction) into your user
# profile for every tool, and removes the MCP servers older versions registered (no MCP server
# anywhere). Run once per machine; afterwards the session-start sync (`sync-ai-templates.sh
# --skills`, run by every project's SessionStart hook) keeps the skill folders fresh. Re-run only
# after editing ai-autobootstrap.instructions.md.
#
# Claude Code also gets one global SessionStart hook in ~/.claude/settings.json
# (templates/global/claude-global-hook.json, merged by install_claude_global_hook: other keys and
# hooks kept, never duplicated). It runs `sync-ai-templates.sh --global-hook`, a no-op unless the
# project sits in a code root and its own .claude/settings.json lacks the sync hook — a fresh
# clone of a private project, whose layer C is not there yet. There is no global Stop hook: the
# project's own Stop hook takes over once layer C exists.
#
# Usage: aicf setup [--copy] [--overlay <dir>] [--apps-config-dir <dir>]
#                  [--ai-context-remote <url>|<root>=<url>] [--work-root <name>|<path>]...
#                  [--claude-profile <root>[=<config-dir>|none]]... [--claude-env <root>=<NAME>=<value>]...
#   --copy            install skills as plain copies instead of symlinks (the default on
#                     Windows; on macOS/Linux symlinks are live-editable, so they stay the default)
#   --overlay <dir>   record a private overlay repo for this machine (see the header of
#                     sync-ai-templates.sh): written to ~/.ai-template-overlay-dir and published
#                     as AI_TEMPLATE_OVERLAY_DIR in ~/.claude/settings.json. Its skills are
#                     installed in the same run. Without the flag an existing record is kept.
#   --apps-config-dir <dir>
#                     where this machine keeps the owner's personal app settings (one subfolder
#                     per app, e.g. a synced "AppsSync" folder): written to ~/.apps-config-dir,
#                     read by every app that follows the apps-config skill. Without the flag an
#                     existing record is kept.
#   --ai-context-remote <url> | <root>=<url>
#                     a code root's private git remote (one branch per project, plus _root for the
#                     root's own config) that carries the owner's private AI docs between machines
#                     for projects switched with `sync-ai-templates.sh --private-layer`: written to
#                     <root>/.ai-context-remote. <root>=<url> when the part before the first = is
#                     an existing folder; else the URL is for the root holding this repo, refused
#                     when that root is a work root (name it). A github.com URL is refused for a
#                     work root. `none` keeps the docs in each project's local hidden repo only.
#                     ~/.ai-context-remote is no longer written (the engine still reads it outside
#                     a work root).
#   --work-root <name>|<path>
#                     mark a code root as a work root, whose private AI docs never reach a personal
#                     remote: appended to ~/.ai-work-roots (one per line) unless already listed. A
#                     name without / matches that folder anywhere in a path (any case); an absolute
#                     path matches that folder and below. $AI_WORK_ROOTS (':' between entries;
#                     none = no work roots) replaces the file; a root whose
#                     .ai-root/environment.json has the label work is one as well. Repeatable.
#   --claude-profile <root>[=<config-dir>|none]
#                     define that code root's Claude Code profile (below): writes and commits
#                     <root>/.ai-root/claude-profile.json — its config dir (default: the one it
#                     has, else ~/.claude-<root name, lower case>), or none to remove it. Repeatable.
#   --claude-env <root>=<NAME>=<value>
#                     an environment variable of that profile's sessions (e.g. the work gateway's
#                     ANTHROPIC_BASE_URL); an empty value removes it. Refused when it looks like a
#                     secret (the file is committed): an apiKeyHelper or /login. Repeatable.
#                     Both are engine/claude-profile-define.py, run before anything else is
#                     written; the profiles are then installed in the same run.
#
# Claude Code profiles: every code root (this one and its siblings) whose .ai-root holds
# claude-profile.json gets its own config dir, ~/.claude-profiles records it, and a managed
# `claude` function in the shell profiles picks it by folder (install_claude_profiles in the
# engine) — e.g. the work account beside the personal one, both at once.
#
# Root repo: for the root holding this repo and the one --ai-context-remote names, a missing
# <root>/.ai-root is cloned from branch _root of that root's remote (bounded; a failure is one
# line and the install carries on). An existing .ai-root is left alone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the template repo (this file is in engine/)
SRC="$SCRIPT_DIR/engine"
# The code root is simply the folder holding this repo — ~/Code on macOS, F:\Code on a Windows
# box, D:\Dev anywhere else. Never assume $HOME/Code: it is wrong on any machine whose projects
# live off the home volume. Sibling program repos (your own tools) hang
# off this, and it is published to agents as $AI_CODE_ROOT below.
CODE_ROOT="$(dirname "$SCRIPT_DIR")"

OVERLAY_ARG=""
APPS_CONFIG_ARG=""
AIC_REMOTE_ARG=""
WORK_ROOT_ARGS=()
CLAUDE_DEFINE=()
expect=""
for arg in "$@"; do
  if [ "$expect" = overlay ]; then OVERLAY_ARG="$arg"; expect=""; continue; fi
  if [ "$expect" = apps ]; then APPS_CONFIG_ARG="$arg"; expect=""; continue; fi
  if [ "$expect" = aic ]; then AIC_REMOTE_ARG="$arg"; expect=""; continue; fi
  if [ "$expect" = work ]; then WORK_ROOT_ARGS+=("$arg"); expect=""; continue; fi
  if [ "$expect" = profile ] || [ "$expect" = env ]; then CLAUDE_DEFINE+=("--$expect" "$arg"); expect=""; continue; fi
  case "$arg" in
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
    --copy) export AI_SKILLS_MODE=copy ;;
    --overlay) expect=overlay ;;
    --overlay=*) OVERLAY_ARG="${arg#--overlay=}" ;;
    --apps-config-dir) expect=apps ;;
    --apps-config-dir=*) APPS_CONFIG_ARG="${arg#--apps-config-dir=}" ;;
    --ai-context-remote) expect=aic ;;
    --ai-context-remote=*) AIC_REMOTE_ARG="${arg#--ai-context-remote=}" ;;
    --work-root) expect=work ;;
    --work-root=*) WORK_ROOT_ARGS+=("${arg#--work-root=}") ;;
    --claude-profile) expect=profile ;;
    --claude-profile=*) CLAUDE_DEFINE+=(--profile "${arg#--claude-profile=}") ;;
    --claude-env) expect=env ;;
    --claude-env=*) CLAUDE_DEFINE+=(--env "${arg#--claude-env=}") ;;
    *) echo "Unknown option: $arg (usage: aicf setup [--copy] [--overlay <dir>] [--apps-config-dir <dir>] [--ai-context-remote <url>|<root>=<url>] [--work-root <name>|<path>] [--claude-profile <root>[=<config-dir>|none]] [--claude-env <root>=<NAME>=<value>])" >&2; exit 2 ;;
  esac
done
if [ -n "$expect" ]; then
  case "$expect" in
    apps) echo "Error: --apps-config-dir needs a directory" >&2 ;;
    aic)  echo "Error: --ai-context-remote needs a git URL (or none)" >&2 ;;
    work) echo "Error: --work-root needs a folder name or an absolute path" >&2 ;;
    profile) echo "Error: --claude-profile needs a code root: <root>[=<config-dir>|none]" >&2 ;;
    env) echo "Error: --claude-env needs <root>=<NAME>=<value>" >&2 ;;
    *)    echo "Error: --overlay needs a directory" >&2 ;;
  esac
  exit 2
fi
for wr in ${WORK_ROOT_ARGS[@]+"${WORK_ROOT_ARGS[@]}"}; do
  case "$wr" in *[![:space:]]*) ;; *) echo "Error: --work-root needs a folder name or an absolute path" >&2; exit 2 ;; esac
done
if [ -n "$APPS_CONFIG_ARG" ]; then
  if [ ! -d "$APPS_CONFIG_ARG" ]; then
    echo "Error: apps config dir not found: $APPS_CONFIG_ARG — create it (or let your sync client download it) first." >&2; exit 2
  fi
  APPS_CONFIG_ARG="$(cd "$APPS_CONFIG_ARG" && pwd)"
fi
if [ -n "$OVERLAY_ARG" ]; then
  if [ ! -d "$OVERLAY_ARG" ]; then
    echo "Error: overlay dir not found: $OVERLAY_ARG — clone your private overlay repo there first." >&2; exit 2
  fi
  OVERLAY_ARG="$(cd "$OVERLAY_ARG" && pwd)"
  export AI_TEMPLATE_OVERLAY_DIR="$OVERLAY_ARG"   # the engine below picks it up for --skills
fi

# shellcheck source=sync-ai-templates.sh
source "$SCRIPT_DIR/sync-ai-templates.sh"

# --ai-context-remote: checked before anything is written (sets ROOT_REMOTE_DIR / ROOT_REMOTE_URL).
ROOT_REMOTE_DIR=""
ROOT_REMOTE_URL=""
if [ -n "$AIC_REMOTE_ARG" ]; then
  root_remote_parse "$AIC_REMOTE_ARG" "$CODE_ROOT" || exit 2
fi
# --claude-profile / --claude-env: every argument checked now; each root's profile file is written
# and committed once its .ai-root is cloned (below), and install_claude_profiles installs it.
if [ ${#CLAUDE_DEFINE[@]} -gt 0 ]; then
  CLAUDE_PY="$(_memory_py 2>/dev/null)" || { echo "Error: --claude-profile / --claude-env need python3 (or uv)" >&2; exit 2; }
  "$CLAUDE_PY" "$SRC/claude-profile-define.py" --check "${CLAUDE_DEFINE[@]}" || exit 2
fi

# Detect VS Code user folder (supports Code and Code - Insiders)
case "$(uname -s)" in
  Darwin) BASE="$HOME/Library/Application Support" ;;
  Linux)
    if grep -q WSL /proc/version 2>/dev/null; then
      echo "Error: You are running this in WSL. Please run bin\\aicf.ps1 setup from Windows PowerShell instead so VS Code picks up the config." >&2
      exit 1
    fi
    BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
    ;;
  *)      echo "Unsupported OS. Use bin\\aicf.ps1 setup on Windows." >&2; exit 1 ;;
esac

DEST_DIR="$BASE/Code/User/prompts"
mkdir -p "$DEST_DIR"

# Overlay-aware like every manifest entry: the base file wins, else the overlay's, then its .append.
_overlay_layout_note
_render templates/global/ai-autobootstrap.instructions.md "$DEST_DIR/ai-autobootstrap.instructions.md"

# Personal skills — SKILL.md / Agent Skills format (agentskills.io open standard) read by
# Copilot CLI (~/.copilot/skills/ and the standard ~/.agents/skills/), Claude Code
# (~/.claude/skills/), Cursor 2.4+ (~/.cursor/skills/), Google Antigravity
# (~/.gemini/config/skills/), and Codex (~/.agents/skills/). Every folder under
# skills/ is installed — no list to maintain. Symlinked on macOS/Linux (edit a
# skill here, every tool sees it immediately); copied on Windows or with --copy, in which
# case the session-start sync refreshes the copies.
for root in "${SKILL_ROOTS[@]}"; do mkdir -p "$root"; done
refresh_global_skills

# Gemini CLI uses a different format (TOML custom command) — delegate to the same
# SKILL.md instead of duplicating its content, so there's still one source of truth.
GEMINI_CMD_DEST="$HOME/.gemini/commands"
mkdir -p "$GEMINI_CMD_DEST"
cat > "$GEMINI_CMD_DEST/bootstrap-ai.toml" <<EOF
description = "Bootstrap or refresh this project's AI instructions from my canonical template."
prompt = """
Read and follow the instructions in $SCRIPT_DIR/skills/bootstrap-ai/SKILL.md
exactly, then execute them for the current project. If that path doesn't exist, clone
https://github.com/neijix/AICodeFactory.git into a temp dir first and use
SKILL.md from there instead.
"""
EOF

# GitHub Copilot CLI (the "Copilot CLI" harness in VS Code's Agents window) is a
# separate tool from the Copilot Chat extension above — it reads its own config
# from ~/.copilot/, not from VS Code's User folder. Wire it up too.
COPILOT_HOME="$HOME/.copilot"
mkdir -p "$COPILOT_HOME"

# Global instructions: same auto-bootstrap rules, minus the VS Code-only YAML
# frontmatter (Copilot CLI's personal instructions file is plain Markdown).
COPILOT_INSTRUCTIONS_DEST="$COPILOT_HOME/copilot-instructions.md"
MARKER="Global AI Behavior — Auto-Bootstrap Every Project"
BOOTSTRAP_SRC="$DEST_DIR/ai-autobootstrap.instructions.md"   # the rendered copy (overlay included)
# Install / refresh the managed auto-bootstrap block. Keep any user text that
# appears *before* the managed H1; replace from that H1 through EOF so edits to
# ai-autobootstrap.instructions.md actually propagate on re-install.
MARKER="$MARKER" DEST="$COPILOT_INSTRUCTIONS_DEST" BOOTSTRAP_SRC="$BOOTSTRAP_SRC" python3 - <<'PY'
import os
from pathlib import Path

marker = os.environ["MARKER"]
dest = Path(os.environ["DEST"])
src = Path(os.environ["BOOTSTRAP_SRC"])

lines = src.read_text().splitlines(keepends=True)
dashes = 0
body_parts = []
for line in lines:
    if line.strip() == "---" and dashes < 2:
        dashes += 1
        continue
    if dashes < 2:
        continue
    body_parts.append(line)
body = "".join(body_parts).rstrip() + "\n"

if not dest.exists():
    dest.write_text(body)
    print(f"Installed global Copilot CLI instructions: {dest}")
elif marker not in dest.read_text():
    with dest.open("a") as f:
        f.write("\n" + body)
    print(f"Appended auto-bootstrap rules to existing: {dest}")
else:
    text = dest.read_text()
    idx = text.find(marker)
    line_start = text.rfind("\n", 0, idx)
    prefix = text[: line_start + 1] if line_start >= 0 else ""
    if prefix.endswith("\n\n"):
        prefix = prefix[:-1]
    dest.write_text(prefix + body)
    print(f"Refreshed managed auto-bootstrap block: {dest}")
PY

# Machine-local marker: where this repo lives on THIS machine. The SessionStart hook reads it as
# its last-resort candidate, so a project under a second root (e.g. F:\WorkCode\proj beside
# F:\Code\AICodeFactory) still finds the templates. It lives in $HOME, outside every repo, so it
# is never committed and never travels between machines — which is the whole point.
printf '%s\n' "$SCRIPT_DIR" > "$HOME/.ai-template-dir"
echo "Recorded this machine's template dir: $HOME/.ai-template-dir -> $SCRIPT_DIR"
# Same idea for the optional private overlay: the path lives in $HOME, never in a repo.
if [ -n "$OVERLAY_ARG" ]; then
  printf '%s\n' "$OVERLAY_ARG" > "$HOME/.ai-template-overlay-dir"
  echo "Recorded this machine's overlay dir: $HOME/.ai-template-overlay-dir -> $OVERLAY_ARG"
fi
# The owner's personal app settings (apps-config skill): also a path in $HOME, never in a repo, so
# a friend who clones an app gets its local defaults and nothing personal.
if [ -n "$APPS_CONFIG_ARG" ]; then
  printf '%s\n' "$APPS_CONFIG_ARG" > "$HOME/.apps-config-dir"
  echo "Recorded this machine's apps config dir: $HOME/.apps-config-dir -> $APPS_CONFIG_ARG"
fi
# Where a root's private AI docs travel between machines (sync-ai-templates.sh --private-layer):
# <root>/.ai-context-remote, outside every project repo.
root_remote_write
# Work roots (engine/work-roots.sh): each --work-root entry goes to ~/.ai-work-roots (LF), once —
# an entry already listed (same text, any case, spaces trimmed) is not added again.
for wr in ${WORK_ROOT_ARGS[@]+"${WORK_ROOT_ARGS[@]}"}; do
  wr="$(printf '%s' "$wr" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -f "$HOME/.ai-work-roots" ] && WR="$wr" awk '{ sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
       tolower($0) == tolower(ENVIRON["WR"]) { f = 1 } END { exit !f }' "$HOME/.ai-work-roots"; then
    echo "Work root already recorded: $wr ($HOME/.ai-work-roots)"
  else
    [ ! -s "$HOME/.ai-work-roots" ] || [ -z "$(tail -c 1 "$HOME/.ai-work-roots")" ] || echo >> "$HOME/.ai-work-roots"
    printf '%s\n' "$wr" >> "$HOME/.ai-work-roots"
    echo "Recorded a work root: $HOME/.ai-work-roots += $wr"
  fi
done
# The root repo (.ai-root: registry, dev-context, private terms) of each known root, when missing.
net_budget_reset
ai_root_clone "$CODE_ROOT"
if [ -n "$ROOT_REMOTE_DIR" ] && ! _same_path "$ROOT_REMOTE_DIR" "$CODE_ROOT"; then
  ai_root_clone "$ROOT_REMOTE_DIR"
fi
if [ ${#CLAUDE_DEFINE[@]} -gt 0 ]; then
  "$CLAUDE_PY" "$SRC/claude-profile-define.py" --code-root "$CODE_ROOT" "${CLAUDE_DEFINE[@]}" || exit 2
fi

# No MCP server anywhere (endpoint-security tools flag them): own tools (`mlx-local`,
# `d3skwebscout`, `bw-auto`) are shell commands agents run through their shell tool, behind skills
# from your overlay. Earlier versions of this script registered `mlx-local` and the third-party
# `bitwarden` server in every harness, and `d3skwebscout` was registered by hand: delete those
# stale entries, keeping a `<file>.bak` of each file it changes. A file without those entries is
# never rewritten, so re-running is a no-op.
MLX_DIR="$CODE_ROOT/MLX_Local"
if [ -d "$MLX_DIR" ] && ! command -v mlx-local >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mlx-local" ]; then
  echo "NOTE: mlx-local is not on PATH — run $MLX_DIR/start.command once (it links ~/.local/bin/mlx-local)."
fi
CURSOR_MCP="$HOME/.cursor/mcp.json"
GEMINI_AGY_MCP="$HOME/.gemini/antigravity/mcp_config.json"
GEMINI_CONFIG_MCP="$HOME/.gemini/config/mcp_config.json"
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
if command -v python3 >/dev/null 2>&1; then
  VSCODE_MCP="$BASE/Code/User/mcp.json" COPILOT_MCP="$COPILOT_HOME/mcp-config.json" \
  CLAUDE_JSON="$HOME/.claude.json" CURSOR_MCP="$CURSOR_MCP" \
  GEMINI_AGY_MCP="$GEMINI_AGY_MCP" GEMINI_CONFIG_MCP="$GEMINI_CONFIG_MCP" \
  GEMINI_SETTINGS="$GEMINI_SETTINGS" \
  CLAUDE_SETTINGS="$HOME/.claude/settings.json" \
  TEMPLATE_DIR_VAL="$SCRIPT_DIR" CODE_ROOT_VAL="$CODE_ROOT" OVERLAY_DIR_VAL="$OVERLAY_ARG" \
  python3 - <<'PY'
import json, os, shutil

def load(path):
    try:
        raw = open(path, encoding="utf-8").read().strip()
        data = json.loads(raw) if raw else {}
    except Exception:
        print(f"  skipped (unparseable JSON): {path}")
        return None
    if not isinstance(data, dict):
        print(f"  skipped (JSON root not an object): {path}")
        return None
    return data

def save(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

def upsert(path, container_key, name, entry, create=False):
    if not os.path.exists(path):
        if not create:
            return
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        data = {}
    else:
        data = load(path)
        if data is None:
            return
    cont = data.get(container_key)
    if not isinstance(cont, dict):
        cont = {}
    prev = cont.get(name)
    if prev == entry:
        print(f"  {name} up to date: {path}")
        return
    cont[name] = entry
    data[container_key] = cont
    save(path, data)
    action = "refreshed" if prev is not None else "registered"
    print(f"  {action} {name}: {path}")

STALE_MCP = ("mlx-local", "d3skwebscout", "bitwarden")

def remove_stale_mcp(path):
    """Delete the stale MCP entries from one harness config; .bak first; no-op when absent."""
    if not os.path.exists(path):
        return
    data = load(path)
    if data is None:
        return
    # Top-level "mcpServers" (Claude, Cursor, Gemini, Copilot CLI) / "servers" (VS Code), plus
    # Claude Code's local-scope entries under projects.<path>.mcpServers in ~/.claude.json.
    containers = [data.get("mcpServers"), data.get("servers")]
    projects = data.get("projects")
    if isinstance(projects, dict):
        containers += [p.get("mcpServers") for p in projects.values() if isinstance(p, dict)]
    removed = []
    for cont in containers:
        if isinstance(cont, dict):
            for name in STALE_MCP:
                if name in cont:
                    del cont[name]
                    removed.append(name)
    if not removed:
        return
    shutil.copy2(path, path + ".bak")
    save(path, data)
    print(f"  removed stale MCP {', '.join(sorted(set(removed)))}: {path} (backup: {path}.bak)")

for key in ("VSCODE_MCP", "COPILOT_MCP", "CURSOR_MCP", "CLAUDE_JSON",
            "GEMINI_AGY_MCP", "GEMINI_CONFIG_MCP", "GEMINI_SETTINGS"):
    remove_stale_mcp(os.environ[key])

# Machine-local paths, published to agents as env vars. This is Claude Code's USER settings file
# (~/.claude/settings.json) — outside every repo, so these absolute paths never get committed and
# never travel to another machine. AI_TEMPLATE_DIR is the hook's first candidate; AI_CODE_ROOT is
# what skills use instead of a hardcoded ~/Code when they reach for a sibling program repo.
upsert(os.environ["CLAUDE_SETTINGS"], "env", "AI_TEMPLATE_DIR",
       os.environ["TEMPLATE_DIR_VAL"], create=True)
upsert(os.environ["CLAUDE_SETTINGS"], "env", "AI_CODE_ROOT",
       os.environ["CODE_ROOT_VAL"], create=True)
if os.environ.get("OVERLAY_DIR_VAL"):
    upsert(os.environ["CLAUDE_SETTINGS"], "env", "AI_TEMPLATE_OVERLAY_DIR",
           os.environ["OVERLAY_DIR_VAL"], create=True)
PY
else
  echo "NOTE: python3 not found — stale MCP entries not checked; AI_TEMPLATE_DIR / AI_CODE_ROOT not written to ~/.claude/settings.json"
fi
# The global SessionStart hook (see the header): a fresh clone of a private project has no
# .claude/settings.json yet, so only this one can restore its private layer at session start.
install_claude_global_hook "$HOME/.claude/settings.json"
# Claude Code profiles (a code root's .ai-root/claude-profile.json, read after the clone above): a
# separate config dir per declaring root, chosen by the `claude` shell function. See the engine's
# install_claude_profiles; the second refresh only fills the profiles' skills dirs.
install_claude_profiles "$CODE_ROOT"
refresh_global_skills

SKILLS=""   # skill folders only (skills/RETIRED is a list, not a skill)
for d in "$SCRIPT_DIR"/skills/*/; do SKILLS="${SKILLS:+$SKILLS,}$(basename "$d")"; done
echo "Installed global customizations to:"
echo "  $DEST_DIR/ai-autobootstrap.instructions.md  (VS Code / Copilot auto-bootstrap trigger)"
echo "  ~/.agents/skills/{$SKILLS}  (open-standard shared dir — Copilot CLI, Codex)"
echo "  ~/.copilot/skills/{$SKILLS}  (Copilot)"
echo "  ~/.claude/skills/{$SKILLS}  (Claude Code)"
echo "  ~/.cursor/skills/{$SKILLS}  (Cursor)"
echo "  ~/.gemini/config/skills/{$SKILLS}  (Google Antigravity)"
if [ "$SKILL_MODE" = link ]; then
  echo "  (symlinks into $SCRIPT_DIR/skills — edits there apply everywhere immediately)"
else
  echo "  (plain copies — refreshed by every project's session-start sync, or re-run this script)"
fi
echo "  $GEMINI_CMD_DEST/bootstrap-ai.toml  (Gemini CLI — type /bootstrap-ai)"
echo "  $COPILOT_INSTRUCTIONS_DEST  (Copilot CLI / VS Code Agents window)"
echo "  stale mlx-local / d3skwebscout / bitwarden MCP entries removed from VS Code / Copilot CLI / Cursor / Claude / Gemini configs (no MCP server anywhere)"
if [ -n "$OVERLAY_DIR" ]; then
  echo "  overlay: $OVERLAY_DIR (skills and template overrides layered on top)"
else
  echo "  overlay: none (aicf setup --overlay <dir> to add a private one)"
fi
if [ -s "$HOME/.apps-config-dir" ]; then
  echo "  apps config: $(head -n 1 "$HOME/.apps-config-dir") (personal app settings, apps-config skill)"
else
  echo "  apps config: none (aicf setup --apps-config-dir <dir> to keep app settings in one folder)"
fi
echo "  ~/.claude/settings.json  (global SessionStart hook: sync-ai-templates.sh --global-hook)"
if [ -s "$HOME/.claude-profiles" ]; then
  echo "  Claude Code profiles: $(cut -f2 "$HOME/.claude-profiles" | tr '\n' ' ')(\`claude\` in a root with a profile uses it — open a new terminal)"
else
  echo "  Claude Code profiles: none (aicf setup --claude-profile <root> to give a code root its own)"
fi
if [ -s "$CODE_ROOT/.ai-context-remote" ]; then
  echo "  private AI docs remote of $CODE_ROOT: $(head -n 1 "$CODE_ROOT/.ai-context-remote" | tr -d '\r') (projects switched with --private-layer)"
else
  echo "  private AI docs remote of $CODE_ROOT: none (aicf setup --ai-context-remote <url> to share them between machines)"
fi
echo
echo "Next: reload VS Code and Cursor (Developer: Reload Window). Claude Code / Gemini pick up"
echo "new skills in any new session."
echo "Ensure these VS Code user settings are enabled:"
echo '  "chat.promptFiles": true'
echo '  "github.copilot.chat.codeGeneration.useInstructionFiles": true'
