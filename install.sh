#!/usr/bin/env bash
# AICodeFactory one-line install: clone (or update) the factory, then run `aicf setup`.
#
#   curl -fsSL https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/neijix/AICodeFactory/HEAD/install.sh | bash -s -- [options] [setup options]
#   bash install.sh [options] [setup options]
#
# Options:
#   --code-root DIR        folder holding your projects (default: $AI_CODE_ROOT, else ~/Code);
#                          the factory goes to DIR/AICodeFactory
#   --channel stable|main  stable (default; or $AICF_CHANNEL): the latest release, vX.Y.Z;
#                          main: the development edge. A repo without a release gets main.
#                          Recorded as `git config aicf.channel` in the checkout
#   --repo URL             where to clone from (default: $AICF_REPO, else the GitHub repo)
#   -h, --help             this help
# Every other option goes to `aicf setup` (see `aicf setup --help`).
#
# Run it again to update: an existing checkout is fast-forwarded to its channel, never reset;
# one with uncommitted changes is refused. It never touches your projects; `aicf uninstall`
# reverses the setup.

# All in one function, called on the last line: a download cut short runs nothing.
aicf_install() {
  set -euo pipefail
  local repo="${AICF_REPO:-https://github.com/neijix/AICodeFactory.git}"
  local root="${AI_CODE_ROOT:-$HOME/Code}" channel="${AICF_CHANNEL:-stable}"
  local setup_args=() dest tag
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo|--code-root|--channel)
        [ $# -ge 2 ] || { echo "Error: $1 needs a value (see --help)." >&2; return 2; }
        case "$1" in --repo) repo="$2" ;; --code-root) root="$2" ;; --channel) channel="$2" ;; esac
        shift 2 ;;
      --repo=*) repo="${1#*=}"; shift ;;
      --code-root=*) root="${1#*=}"; shift ;;
      --channel=*) channel="${1#*=}"; shift ;;
      -h|--help)
        if [ -f "${BASH_SOURCE[0]:-}" ]; then sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        else echo "Usage: install.sh [--code-root DIR] [--channel stable|main] [--repo URL] [aicf setup options]"; fi
        return 0 ;;
      *) setup_args+=("$1"); shift ;;
    esac
  done
  case "$channel" in stable|main) ;; *) echo "Error: --channel is stable or main, not '$channel'." >&2; return 2 ;; esac
  command -v git >/dev/null 2>&1 || { echo "Error: git is required. Install it, then run this again." >&2; return 1; }

  mkdir -p "$root"
  root="$(cd "$root" && pwd)"
  dest="$root/AICodeFactory"
  if [ -e "$dest" ] && [ ! -e "$dest/.git" ]; then
    echo "Error: $dest exists and is not a git checkout. Move it away, or pick another --code-root." >&2
    return 1
  fi
  if [ -d "$dest" ]; then
    if [ -n "$(git -C "$dest" status --porcelain --untracked-files=no)" ]; then
      echo "Error: $dest has uncommitted changes. Commit or stash them (git -C \"$dest\" stash), then run this again." >&2
      return 1
    fi
    echo "Updating $dest"
    git -C "$dest" fetch -q --tags origin
  else
    echo "Cloning $repo into $dest"
    git clone -q "$repo" "$dest"
  fi

  tag=""
  [ "$channel" = stable ] && tag="$(git -C "$dest" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"
  if [ "$channel" = stable ] && [ -z "$tag" ]; then
    echo "No release yet: following main instead of stable."
    channel=main
  fi
  if [ "$channel" = stable ] && git -C "$dest" rev-parse -q --verify refs/remotes/origin/stable >/dev/null; then
    _aicf_ff "$dest" stable origin/stable
    echo "Channel: stable ($tag; the session-start pull follows each release)"
  elif [ "$channel" = stable ]; then
    git -C "$dest" -c advice.detachedHead=false checkout -q "refs/tags/$tag"
    echo "Channel: stable (pinned at $tag; run this installer again to update)"
  else
    local main
    main="$(git -C "$dest" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$main" ] || main="origin/$(git -C "$dest" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p')"
    [ "$main" != origin/ ] || { echo "Error: cannot tell the default branch of $repo." >&2; return 1; }
    _aicf_ff "$dest" "${main#origin/}" "$main"
    echo "Channel: main (${main#origin/}, the development edge)"
  fi
  git -C "$dest" config aicf.channel "$channel"

  echo "Running aicf setup"
  sh "$dest/bin/aicf" setup ${setup_args[@]+"${setup_args[@]}"} </dev/null
}

# _aicf_ff <checkout> <branch> <upstream> — put <checkout> on <branch> tracking <upstream>,
# fast-forward only: a local branch that diverged is refused, never reset.
_aicf_ff() {
  local dest="$1" branch="$2" up="$3"
  if git -C "$dest" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    [ "$(git -C "$dest" symbolic-ref -q --short HEAD || true)" = "$branch" ] || git -C "$dest" checkout -q "$branch"
    git -C "$dest" branch -q --set-upstream-to="$up" "$branch"
    if ! git -C "$dest" merge -q --ff-only "$up" >/dev/null; then
      echo "Error: $dest branch $branch has commits that are not on $up. Push or move them, then run this again." >&2
      return 1
    fi
  else
    git -C "$dest" checkout -q -b "$branch" --track "$up"
  fi
}

aicf_install "$@"
