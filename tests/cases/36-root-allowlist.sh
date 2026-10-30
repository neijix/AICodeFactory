# shellcheck shell=bash
# Sourced by tests/run-tests.sh ($T): the public root stays the product's. Twin: 36-root-allowlist.ps1.
echo "--- 36. the repo root holds only the product's entries"
# The target root of the public layout, the dev tooling beside it, and the dogfood copies: the first
# path component of every [POINTERS] and [LIVING_DOCS] destination of the manifest.
allowed36=" README.md LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md .editorconfig .gitignore .gitattributes"
allowed36="$allowed36 install.sh install.ps1 config.bat sync-ai-templates.sh sync-ai-templates.ps1 templates-manifest.txt"
allowed36="$allowed36 bin engine templates skills examples docs tests .github .githooks .code-health.json "
for d in $(sed -n '/^\[POINTERS\]/,/^\[SHARED_HOOKS\]/p' "$T/templates-manifest.txt" | grep '|' | cut -d'|' -f2 | cut -d/ -f1 | tr -d '\r'); do
  allowed36="$allowed36$d "
done
bad36=""
for e in $(git -C "$T" ls-files | cut -d/ -f1 | tr -d '\r' | sort -u); do
  case "$allowed36" in *" $e "*) ;; *) bad36="$bad36 $e" ;; esac
done
[ -z "$bad36" ] || fail "unexpected tracked entries at the repo root (move them, or extend the public layout):$bad36"
