#!/usr/bin/env bash
# Sibling-repo dependencies (launch-and-deploy skill; canonical copy in AICodeFactory, copy it
# unchanged into an app's scripts/). Every repo listed in the app's sibling-deps.txt is cloned
# beside the app when missing, fast-forwarded when its tree is clean (at most once a day; every
# time with `update`), then its own idempotent `install.sh --start` runs.
# Never fails the caller: a dependency that cannot be fetched or installed is a warning line.
#
# Usage: scripts/sibling-deps.sh [start|update]      (install and start scripts: start)
# sibling-deps.txt, one per line:  NAME  GIT_URL  [DIR_ENV_VAR]     (# starts a comment)
# Lookup: $DIR_ENV_VAR when set, else $AI_CODE_ROOT/NAME, ~/Code/NAME, ../NAME; a clone goes to
# $DIR_ENV_VAR when set, else ../NAME.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 0
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

mode="${1:-start}"
list="sibling-deps.txt"
[ -f "$list" ] || exit 0
if ! command -v git >/dev/null 2>&1; then
  echo "  ! git not found — sibling dependencies not checked"
  exit 0
fi
parent="$(cd .. && pwd)"

dep_dir() {  # NAME DIR_ENV_VAR → the checkout to use (it may not exist yet)
  local name="$1" var="$2" explicit="" base
  if [ -n "$var" ]; then
    explicit="$(printenv "$var" 2>/dev/null || true)"
  fi
  if [ -n "$explicit" ]; then
    printf '%s\n' "${explicit/#\~/$HOME}"
    return 0
  fi
  for base in "${AI_CODE_ROOT:-}" "$HOME/Code" "$parent"; do
    if [ -n "$base" ] && [ -d "$base/$name/.git" ]; then
      printf '%s\n' "$base/$name"
      return 0
    fi
  done
  printf '%s\n' "$parent/$name"
}

while read -r name url var _ <&3 || [ -n "${name:-}" ]; do
  case "${name:-}" in '' | '#'*) continue ;; esac
  if [ -z "${url:-}" ]; then
    echo "  ! $list: no URL for $name — skipped"
    continue
  fi
  dir="$(dep_dir "$name" "${var:-}")"
  if [ ! -d "$dir/.git" ]; then
    echo "Fetching dependency $name into ${dir}…"
    if ! git clone --quiet "$url" "$dir"; then
      echo "  ! could not clone $name ($url) — clone it beside this app, then start again"
      continue
    fi
  elif [ "$mode" = update ] || [ -z "$(find "$dir/.git/FETCH_HEAD" -mmin -1440 2>/dev/null)" ]; then
    if [ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
      GIT_TERMINAL_PROMPT=0 git -C "$dir" pull --ff-only --quiet </dev/null >/dev/null 2>&1 \
        || echo "  ! $name: could not fast-forward (offline, or another branch) — using it as is"
    fi
  fi
  if [ -x "$dir/install.sh" ]; then
    "$dir/install.sh" --start </dev/null || echo "  ! $name: install.sh failed — continuing without it"
  fi
done 3<"$list"
exit 0
