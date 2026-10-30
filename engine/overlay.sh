# shellcheck shell=bash
# The overlay: its layout, its effective templates, and the overlay per sync target. Sourced by
# sync-ai-templates.sh once OVERLAY_DIR is known; kept here so the engine script stays under its
# code-health record.
#
# Layout: templates/<src> (+ .append) and skills/, like this repo. The old layout — <src> at the
# overlay's root, vscode-global/<file> and vscode-global/skills/ — is still read, after the new
# paths, with one note per run (_overlay_layout_note).

OVERLAY_MANIFEST_FILE="${OVERLAY_DIR:+$OVERLAY_DIR/overlay-manifest.txt}"
OVERLAY_SKILLS_SRC=""
if [ -n "$OVERLAY_DIR" ]; then
  OVERLAY_SKILLS_SRC="$OVERLAY_DIR/skills"
  [ -d "$OVERLAY_SKILLS_SRC" ] || [ ! -d "$OVERLAY_DIR/vscode-global/skills" ] ||
    OVERLAY_SKILLS_SRC="$OVERLAY_DIR/vscode-global/skills"
fi
# Where skills come from, first source wins on a name clash: this repo first — it takes precedence
# over every overlay, which only adds skills.
SKILL_SRCS=("$SKILLS_SRC")
[ -n "$OVERLAY_SKILLS_SRC" ] && [ -d "$OVERLAY_SKILLS_SRC" ] && SKILL_SRCS+=("$OVERLAY_SKILLS_SRC")

# _overlay_layout_note — once per run, one line when the overlay still holds old-layout paths.
OVERLAY_LAYOUT_NOTED=false
_overlay_layout_note() {
  [ -n "$OVERLAY_DIR" ] && [ "$OVERLAY_LAYOUT_NOTED" = false ] || return 0
  OVERLAY_LAYOUT_NOTED=true
  local old find=find
  [ -x /usr/bin/find ] && find=/usr/bin/find     # not Windows' find.exe, when PATH puts it first
  old="$(cd "$OVERLAY_DIR" 2>/dev/null && "$find" . \( -path ./templates -o -path ./skills -o -path ./.git \) -prune \
    -o -path ./vscode-global -prune -print -o \( -name '*.template' -o -name '*.template.append' \) -print 2>/dev/null |
    sed 's|^\./||' | LC_ALL=C sort | awk 'NR <= 3 { printf "%s%s", (NR > 1 ? ", " : ""), $0 } END { if (NR > 3) printf ", …" }')" || old=""
  [ -z "$old" ] || echo "ai-sync: overlay uses the old layout ($old) — move it to templates/ and skills/"
}

# _tpl_old <rel> — the old overlay layout's spelling of a template path.
_tpl_old() {
  case "$1" in
    templates/global/*) printf 'vscode-global/%s' "${1#templates/global/}" ;;
    templates/*) printf '%s' "${1#templates/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# _tpl <rel> — effective template path: the base's file when it has one (this repo takes
# precedence: an overlay adds files and .append fragments, it never replaces a base file), else
# the overlay's (new layout, then old). An old overlay-manifest entry naming a base template
# without its templates/ prefix still finds it.
_tpl() {
  local old
  if [ -f "$TEMPLATE_DIR/$1" ]; then printf '%s' "$TEMPLATE_DIR/$1"; return 0; fi
  if [ -f "$TEMPLATE_DIR/templates/$1" ]; then printf '%s' "$TEMPLATE_DIR/templates/$1"; return 0; fi
  if [ -n "$TPL_OVERLAY" ]; then
    old="$(_tpl_old "$1")"
    if [ -f "$TPL_OVERLAY/$1" ]; then printf '%s' "$TPL_OVERLAY/$1"; return 0; fi
    if [ -f "$TPL_OVERLAY/$old" ]; then printf '%s' "$TPL_OVERLAY/$old"; return 0; fi
  fi
  printf '%s' "$TEMPLATE_DIR/$1"
}

# _render <rel> <out> — write the effective template to <out>, followed by the overlay's
# <rel>.append fragment when there is one (a newline is inserted if the base lacks one).
_render() {
  local rel="$1" out="$2" src frag=""
  src="$(_tpl "$rel")"
  cat "$src" > "$out"
  if [ -n "$TPL_OVERLAY" ]; then
    frag="$TPL_OVERLAY/$rel.append"
    [ -f "$frag" ] || frag="$TPL_OVERLAY/$(_tpl_old "$rel").append"
  fi
  if [ -n "$frag" ] && [ -f "$frag" ]; then
    [ -s "$out" ] && [ -n "$(tail -c1 "$out")" ] && echo >> "$out"
    cat "$frag" >> "$out"
  fi
}

# _overlay_for <target> — the overlay that renders this target (TPL_OVERLAY): none for the template
# repo itself (same physical folder), whose committed copies must never carry overlay content —
# no overlay file, .append fragment or overlay-manifest entry. Skills keep the overlay.
TPL_OVERLAY="$OVERLAY_DIR"
_overlay_for() {
  local want="$OVERLAY_DIR"
  [ "$(cd "$1" 2>/dev/null && pwd -P)" != "$(cd "$TEMPLATE_DIR" && pwd -P)" ] || want=""
  [ -z "$want" ] || _overlay_layout_note
  [ "$want" != "$TPL_OVERLAY" ] || return 0
  TPL_OVERLAY="$want"; POINTER_MAP=(); LIVING_DOCS_MAP=(); OBSOLETE_MAP=(); SHARED_HOOK_MAP=()
  _read_manifest "$MANIFEST_FILE"
  [ -z "$want" ] || [ ! -f "$OVERLAY_MANIFEST_FILE" ] || _read_manifest "$OVERLAY_MANIFEST_FILE"
}
