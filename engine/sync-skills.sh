# shellcheck shell=bash
# Skills install and the dev-context pack. Sourced by sync-ai-templates.sh.
# Kept in this file so the engine script stays under the code-health line record.

# _same_skill_src <a> <b> — true when two origin markers name the same skills dir. On Windows
# this engine writes /f/Code/..., the PowerShell twin F:\Code\..., in whatever case was typed.
_same_skill_src() {
  [ "$1" = "$2" ] && return 0
  [ "$ON_WINDOWS" = true ] || return 1
  [ "$(_skill_src_key "$1")" = "$(_skill_src_key "$2")" ]
}
_skill_src_key() {
  printf '%s\n' "${1%$'\r'}" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\1|' -e 's|/$||' |
    tr '[:upper:]' '[:lower:]'
}

# _legacy_skill_src <origin> <src> — true when an install names <src>'s pre-move home
# (<repo>/vscode-global/skills, before skills/ moved to the repo root): ours, to re-install.
_legacy_skill_src() {
  _same_skill_src "$1" "${2%/skills}/vscode-global/skills"
}

# _skill_owned_elsewhere <dest> — true when another template repo installed this skill name
# (a live symlink pointing outside our skills dir, or a copy whose origin marker names another
# repo that still exists). Whichever template installed first keeps it; dangling links, unmarked
# copies and copies from a renamed or deleted repo are ours to fix.
_skill_owned_elsewhere() {
  local dest="$1" target origin src
  if [ -L "$dest" ]; then
    [ -e "$dest" ] || return 1
    target="$(readlink "$dest")"
    for src in "${SKILL_SRCS[@]}"; do
      case "$target" in "$src"/*|"${src%/skills}/vscode-global/skills"/*) return 1 ;; esac
    done
    return 0
  elif [ -f "$dest/$SKILL_ORIGIN_FILE" ]; then
    origin="$(head -n 1 "$dest/$SKILL_ORIGIN_FILE" 2>/dev/null)"
    for src in "${SKILL_SRCS[@]}"; do
      _same_skill_src "$origin" "$src" && return 1
      _legacy_skill_src "$origin" "$src" && return 1
    done
    origin="${origin%$'\r'}"
    if [ "$ON_WINDOWS" = true ]; then
      origin="$(printf '%s\n' "$origin" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\1|')"
    fi
    [ -n "$origin" ] && [ ! -d "$origin" ] && return 1
    return 0
  fi
  return 1
}

# _prune_retired_skills <dry-run true|false> <shipped name>... — remove installed copies of the
# names each skills source lists in RETIRED, unless a source ships that name again, in any case
# (Windows and macOS file systems fold it: a RETIRED line in another case would reach the shipped
# folder). Only a real folder whose origin marker names that source goes (a renamed or unmarked
# copy is the user's). A name must look like a skill folder name: no separator, so a line cannot
# leave the root. Sets RETIRED_PRUNED to the count.
RETIRED_PRUNED=0
_prune_retired_skills() {
  local dry_run="$1"; shift
  local src name key root dest shipped origin
  RETIRED_PRUNED=0
  shipped=" $(printf '%s ' "$@" | tr '[:upper:]' '[:lower:]')"
  for src in "${SKILL_SRCS[@]}"; do
    [ -f "$src/$SKILL_RETIRED_FILE" ] || continue
    while IFS= read -r name || [ -n "$name" ]; do
      name="${name%$'\r'}"
      case "$name" in [A-Za-z0-9]*) ;; *) continue ;; esac
      case "$name" in *[!A-Za-z0-9._-]*) continue ;; esac
      key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
      case "$shipped" in *" $key "*) continue ;; esac   # shipped again (here or by the overlay)
      for root in "${SKILL_ROOTS[@]}"; do
        dest="$root/$name"
        [ -d "$root" ] && [ ! -L "$dest" ] && [ -f "$dest/$SKILL_ORIGIN_FILE" ] || continue
        origin="$(head -n 1 "$dest/$SKILL_ORIGIN_FILE" 2>/dev/null)"
        _same_skill_src "$origin" "$src" || _legacy_skill_src "$origin" "$src" || continue
        _say "  [remove] $dest (skill retired from the template)"
        RETIRED_PRUNED=$((RETIRED_PRUNED + 1))
        [ "$dry_run" = true ] || rm -rf "$dest" ||
          echo "ai-sync: could not remove $dest — delete it by hand" >&2
      done
    done < "$src/$SKILL_RETIRED_FILE"
  done
  return 0
}

# refresh_global_skills [--dry-run] — mirror skills/* (this repo first, then the overlays; a
# name shipped by both installs this repo's) into every tool's global skills dir that
# exists on this machine (install-global.* creates them). Link mode replaces stale copies with
# symlinks; copy mode replaces symlinks/outdated copies with fresh copies. A skill name already
# installed by another template repo is left alone.
refresh_global_skills() {
  local dry_run=false
  [ "${1:-}" = "--dry-run" ] && dry_run=true
  [ -n "${HOME:-}" ] || return 0
  _overlay_layout_note
  [ "$dry_run" = true ] || _heal_gemini_bootstrap
  _factory_extra_skill_srcs || true
  local sources_current=false
  if [ "$dry_run" != true ] && _factory_skills_current; then sources_current=true; fi
  if [ "$dry_run" != true ] && [ "$sources_current" != true ]; then _factory_skills_begin; fi
  local src skill_dir name root dest d seen changed=0
  if [ "$sources_current" != true ]; then
  local done_names=()
  for src in "${SKILL_SRCS[@]}"; do
    [ -d "$src" ] || continue
    for skill_dir in "$src"/*/; do
      skill_dir="${skill_dir%/}"
      [ -f "$skill_dir/SKILL.md" ] || continue
      name="$(basename "$skill_dir")"
      seen=false
      for d in ${done_names[@]+"${done_names[@]}"}; do [ "$d" = "$name" ] && seen=true; done
      [ "$seen" = true ] && continue             # an earlier source (this repo first) shipped it
      done_names+=("$name")
      for root in "${SKILL_ROOTS[@]}"; do
        [ -d "$root" ] || continue               # tool not installed here — leave it alone
        dest="$root/$name"
        if _skill_owned_elsewhere "$dest"; then continue; fi
        if [ "$SKILL_MODE" = link ]; then
          if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$skill_dir" ]; then continue; fi
          _say "  [link]   $dest -> $skill_dir"
        else
          if [ ! -L "$dest" ] && [ -d "$dest" ] && _same_skill_src "$(head -n 1 "$dest/$SKILL_ORIGIN_FILE" 2>/dev/null)" "$src"; then
            # diff first: Python starts only for a copy that differs (one per skill and tool).
            diff -rq -x "$SKILL_ORIGIN_FILE" "$skill_dir" "$dest" >/dev/null 2>&1 && continue
            _factory_skill_keep "$dest" "$skill_dir" && continue
          fi
          _say "  [copy]   $dest"
        fi
        changed=$((changed + 1))
        [ "$dry_run" = true ] && continue
        rm -rf "$dest"                           # a symlink is removed as a link, not followed
        if [ "$SKILL_MODE" = link ]; then
          ln -s "$skill_dir" "$dest"
        else
          cp -R "$skill_dir" "$dest"
          _factory_skill_stamp "$dest" "$skill_dir" "$src" \
            || printf '%s\n' "$src" > "$dest/$SKILL_ORIGIN_FILE"
        fi
      done
    done
  done
  fi
  # Skills deleted from the template: dangling links, and retired copies (_prune_retired_skills).
  for root in "${SKILL_ROOTS[@]}"; do
    [ -d "$root" ] || continue
    for d in "$root"/*; do
      [ -L "$d" ] && [ ! -e "$d" ] || continue
      _say "  [remove] $d (dangling skill link)"
      changed=$((changed + 1))
      [ "$dry_run" = true ] || rm -f "$d"
    done
  done
  if [ "$sources_current" != true ]; then
    _prune_retired_skills "$dry_run" ${done_names[@]+"${done_names[@]}"}
    changed=$((changed + RETIRED_PRUNED))
  fi
  if [ "$SYNC_QUIET" = true ] && [ "$changed" -gt 0 ]; then
    echo "ai-sync: refreshed $changed global skill folder(s) ($SKILL_MODE mode)"
  fi
  if [ "$dry_run" != true ] && [ "$sources_current" != true ]; then _factory_skills_finish; fi
  return 0
}

# _heal_gemini_bootstrap — install-global wrote ~/.gemini/commands/bootstrap-ai.toml
# with this repo's pre-move skills path (vscode-global/skills/): point it at skills/.
_heal_gemini_bootstrap() {
  local toml="$HOME/.gemini/commands/bootstrap-ai.toml" old="$TEMPLATE_DIR/vscode-global/skills/"
  [ -f "$toml" ] && grep -qF "$old" "$toml" 2>/dev/null || return 0
  local tmp="$toml.tmp.$$"
  awk -v o="$old" -v n="$TEMPLATE_DIR/skills/" '{ while ((i = index($0, o)) > 0) $0 = substr($0, 1, i - 1) n substr($0, i + length(o)); print }' \
    "$toml" > "$tmp" && mv -f "$tmp" "$toml" || rm -f "$tmp"
  return 0
}

# Dev-context packs (see the header). DEV_CONTEXT_MAX caps one pack file so a huge rules.md
# cannot fill the session. The marker is the first line of a CLAUDE.local.md we wrote.
DEV_CONTEXT_MAX=16384
DEV_CONTEXT_MARK='<!-- ai-templates: dev-context'

# _dev_context_scope <target> — the dev-context scope: the code root's .ai-root/environment.json
# "label" (else the legacy "kind"), else work under a work root (_is_work_path), else personal inside a
# code root (_code_root). Status 1 (no scope) anywhere else.
_dev_context_scope() {
  local croot v=""
  croot="$(_code_root "$1" 2>/dev/null)" || croot=""
  if [ -n "$croot" ]; then
    v="$(_env_json_field "$croot/.ai-root/environment.json" label)"
    [ -n "$v" ] || v="$(_env_json_field "$croot/.ai-root/environment.json" kind)"
  fi
  if [ -z "$v" ] && _is_work_path "$1"; then v=work; fi
  [ -n "$v" ] || [ -z "$croot" ] || v=personal
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

# Keep a Factory section already in CLAUDE.local.md so this rewrite does not drop it.
_keep_factory_section() {
  local build="$1" localfile="$2" chunk
  [ -f "$localfile" ] || return 0
  chunk="$(awk '
    $0 ~ /<!-- ai-templates: factory -->/ { keep=1 }
    keep { print }
    $0 ~ /<!-- ai-templates: factory-end -->/ { keep=0 }
  ' "$localfile")"
  [ -n "$chunk" ] || return 0
  printf '\n%s\n' "$chunk" >> "$build"
}

_dev_context_ours() { # $1 = CLAUDE.local.md
  [ -f "$1" ] || return 1
  local first
  first="$(head -n 1 "$1" 2>/dev/null || true)"
  case "$first" in
    "${DEV_CONTEXT_MARK}"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Append one pack file onto $1. A missing file is skipped. An unreadable one (cloud placeholder)
# prints one ai-sync line and a placeholder. Past DEV_CONTEXT_MAX, keep the head and say so.
_dev_context_append() {
  local dest="$1" label="$2" src="$3"
  [ -f "$src" ] || return 0
  local one n
  one="$(mktemp)"
  if ! cat "$src" > "$one" 2>/dev/null; then
    rm -f "$one"
    echo "ai-sync: dev-context: cannot read $label"
    printf '%s\n' "(could not be read)" >> "$dest"
    return 0
  fi
  n="$(wc -c < "$one" | tr -d ' ')"
  if [ "${n:-0}" -gt "$DEV_CONTEXT_MAX" ]; then
    echo "ai-sync: dev-context: $label truncated to $DEV_CONTEXT_MAX bytes"
    head -c "$DEV_CONTEXT_MAX" "$one" >> "$dest"
    printf '\n\n(truncated)\n' >> "$dest"
  else
    cat "$one" >> "$dest"
    # Command substitution strips a trailing newline, so an empty result means the
    # file already ended with one (or was empty). A non-empty result needs a newline.
    if [ -n "${n:-}" ] && [ "$n" -gt 0 ] && [ -n "$(tail -c 1 "$one")" ]; then
      printf '\n' >> "$dest"
    fi
  fi
  rm -f "$one"
}

# _apply_dev_context <project-dir> <true|false dry-run>
# Writes CLAUDE.local.md from the matching pack. Never fails the caller.
_apply_dev_context() {
  local target="$1" dry_run="$2"
  local scope="" croot="" dir localfile build label="" source=""
  scope="$(_dev_context_scope "$target" 2>/dev/null)" || scope=""
  localfile="$target/CLAUDE.local.md"
  dir=""
  # The code root's .ai-root/dev-context/ (when it holds a pack file).
  if [ -n "$scope" ]; then
    croot="$(_code_root "$target" 2>/dev/null)" || croot=""
    if [ -n "$croot" ]; then
      dir="$croot/.ai-root/dev-context"
      label=".ai-root/dev-context"
      source="../.ai-root/dev-context/ (the code root's .ai-root repo) — not in this project's git."
    fi
  fi
  if [ -z "$dir" ] || { [ ! -f "$dir/rules.md" ] && [ ! -f "$dir/settings.json" ]; }; then
    if _dev_context_ours "$localfile"; then
      if [ "$dry_run" = true ]; then
        _say "  [remove] CLAUDE.local.md (dev-context)"
      else
        rm -f "$localfile"
      fi
    fi
    return 0
  fi
  if [ -f "$localfile" ] && ! _dev_context_ours "$localfile"; then
    echo "ai-sync: dev-context $scope — CLAUDE.local.md is not ours, left untouched"
    return 0
  fi
  if [ "$dry_run" = true ]; then
    _say "  [write]  CLAUDE.local.md (dev-context $scope)"
    return 0
  fi
  # Built outside the work tree: a leftover (killed hook, failed mv) must never get committed.
  rm -f "$target"/.dev-context.tmp.* 2>/dev/null || true
  build="$(mktemp "${TMPDIR:-/tmp}/ai-dev-context.XXXXXX" 2>/dev/null)" || return 0
  {
    printf '%s %s -->\n' "$DEV_CONTEXT_MARK" "$scope"
    printf '%s\n' "# Dev context — $scope" "" \
      "Development rules for this code root (label from .ai-root/environment.json, else work or personal). Source: $source" \
      "Edit rules.md there. No credentials in that folder; this file is rewritten on sync." ""
  } > "$build"
  if [ -f "$dir/settings.json" ]; then
    printf '%s\n' "## Settings" "" >> "$build"
    _dev_context_append "$build" "$label/settings.json" "$dir/settings.json"
    printf '\n' >> "$build"
  fi
  if [ -f "$dir/rules.md" ]; then
    printf '%s\n' "## Rules" "" >> "$build"
    _dev_context_append "$build" "$label/rules.md" "$dir/rules.md"
  fi
  _keep_factory_section "$build" "$localfile"
  if [ -f "$localfile" ] && cmp -s "$build" "$localfile"; then
    rm -f "$build"
  else
    mv -f "$build" "$localfile"
  fi
  if [ "$SYNC_QUIET" = true ]; then
    echo "ai-sync: dev-context $scope — read CLAUDE.local.md and follow it (development rules for this root; gitignored)."
  else
    _say "ai-sync: dev-context $scope"
  fi
  return 0
}
