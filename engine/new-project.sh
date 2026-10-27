#!/usr/bin/env bash
# Bootstrap a brand new project as a sibling of this template repo.
#
# Usage: bin/aicf init <project-name> [--tracked]   (or engine/new-project.sh)
#
# Creates <this repo's parent>/<project-name> — i.e. the same code root this repo sits in, so it
# works whether that is ~/Code or F:\Code. Git-inits it, copies every AI-tool pointer file and the
# per-project living docs from this repo (no symlinks — the project refreshes itself from the
# template at every session start), commits, then — if the `claude` CLI is available — runs
# the AI bootstrap to finish the smart fill (codebase scan, architecture description).
#
# PRIVATE by default (sync-ai-templates.sh --private-layer, see its header): the owner's AI layer
# stays out of the code repo — the exclude block in .git/info/exclude, the hidden repo
# .git/ai-context (pushed to the root's remote, if any), mode=private in the code root's registry
# when it has .ai-root/. The first commit holds no layer path (.gitignore and .env.example only);
# a staged one stops the script before it commits. When the switch waits for an unreachable
# remote, nothing is committed: one error with the command to re-run.
#   --tracked   the code repo commits every AI file instead (the former default).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the template repo (this file is in engine/)
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
USAGE="Usage: aicf init <project-name> [--tracked]"

NAME=""
TRACKED=false
for arg in "$@"; do
  case "$arg" in
    --tracked) TRACKED=true ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    -*) echo "Unknown option: $arg ($USAGE)" >&2; exit 2 ;;
    *)
      if [ -n "$NAME" ]; then echo "Error: one project name only ($USAGE)" >&2; exit 2; fi
      NAME="$arg" ;;
  esac
done
if [ -z "$NAME" ]; then echo "$USAGE" >&2; exit 2; fi
TARGET="$PARENT_DIR/$NAME"

if [ -e "$TARGET" ]; then
  echo "Error: $TARGET already exists. Use aicf update \"$NAME\" to refresh it instead." >&2
  exit 1
fi

echo "Creating $TARGET ..."
mkdir -p "$TARGET"
git -C "$TARGET" init -q

if [ ! -e "$TARGET/.gitignore" ]; then
  cat > "$TARGET/.gitignore" <<'GITIGNORE'
.DS_Store
.env
node_modules/
__pycache__/
*.pyc
.venv/
GITIGNORE
fi

# shellcheck source=sync-ai-templates.sh
source "$SCRIPT_DIR/sync-ai-templates.sh"
if [ "$TRACKED" = true ]; then
  sync_ai_templates "$TARGET"
  git -C "$TARGET" add -A
else
  sync_ai_templates "$TARGET" --private-layer
  case "$(_project_mode "$TARGET")" in
    private|team) ;;
    *)
      echo "Error: $TARGET is not private yet (the switch waits for its remote — see above). Nothing committed. Re-run when online: $SCRIPT_DIR/sync-ai-templates.sh $TARGET --private-layer --commit" >&2
      exit 1 ;;
  esac
  # The hidden repo's first commit (and push), as the session-start sync does after a switch.
  ai_context_sync "$TARGET" --no-fetch
  git -C "$TARGET" add -A
  leaked="$(_tracked_layer_paths "$TARGET")"
  if [ -n "$leaked" ]; then
    git -C "$TARGET" reset -q
    echo "Error: the first commit would hold private-layer paths ($(printf '%s' "$leaked" | tr '\n' ' ')) — nothing committed." >&2
    exit 1
  fi
fi
git -C "$TARGET" commit -q -m "docs: bootstrap project documentation"
echo "Mechanical bootstrap done: AI files copied, git init, first commit."

if command -v claude >/dev/null 2>&1; then
  echo "claude CLI found - running AI bootstrap to fill in project-specific details ..."
  if (cd "$TARGET" && claude -p "/bootstrap-ai" --permission-mode acceptEdits); then
    echo "AI bootstrap complete."
  else
    echo "AI bootstrap didn't finish automatically - open '$TARGET' in your AI tool and run /bootstrap-ai to finish."
  fi
else
  echo "Next: open '$TARGET' in your AI tool (Claude Code, Copilot, ...) so it can scan the code and finish filling in the project details."
fi

echo "Done: $TARGET"
