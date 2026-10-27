# shellcheck shell=bash
# Sourced by tests/run-tests.sh after case 32 (DR, J32, $C32, $F32, mkrepo): doctor on unfilled
# living docs, missing generic AGENTS.md sections and projects with no git remote.
echo "--- 33. doctor: unfilled living docs, missing generic AGENTS.md sections, no git remote"
# Case 32's machine, now set up: three bootstrapped projects beside bare32.
# good33: filled from the template; quoted, fenced, link and [NEEDS HUMAN INPUT] brackets are not placeholders.
mkrepo "$C32/good33"; mkdir -p "$C32/good33/.github"
sed -e '/^<!-- BOOTSTRAP_PENDING -->/d' -e 's/\[[^]]*\]/x/g' "$F32/templates/AGENTS.md.template" > "$C32/good33/AGENTS.md"
printf '# PROJECT STATE — good33\n\nFilled.\n' > "$C32/good33/.github/PROJECT_STATE.md"
printf '%s\n' '# KNOWLEDGE BASE — good33' '' '### `[FRAMEWORK]` stays quoted' '- [NEEDS HUMAN INPUT]' \
  '- see [the docs](https://example.invalid) and [[other-note]]' '```text' '[PROJECT_NAME]' '- [What it does]' '```' \
  > "$C32/good33/.github/KNOWLEDGE.md"
git -C "$C32/good33" remote add origin https://example.invalid/good33.git
# pend33: the template as the sync writes it, BOOTSTRAP_PENDING still there.
mkrepo "$C32/pend33"
sed 's/\[PROJECT_NAME\]/pend33/' "$F32/templates/AGENTS.md.template" > "$C32/pend33/AGENTS.md"
git -C "$C32/pend33" remote add origin https://example.invalid/pend33.git
# old33: an older template, never filled, no generic sections, no remote.
mkrepo "$C32/old33"; mkdir -p "$C32/old33/.github"
printf '%s\n' '# old33 - Rules' '' '## Project Purpose' '- [Primary business or technical goal]' > "$C32/old33/AGENTS.md"
printf '%s\n' '# PROJECT STATE — old33' '' '- `src/` — [what it does]' > "$C32/old33/.github/PROJECT_STATE.md"
printf '%s\n' '# KNOWLEDGE BASE - [PROJECT NAME]' > "$C32/old33/.github/KNOWLEDGE.md"
rc=0; out=$(DR "$F32" 2>&1) || rc=$?
[ "$rc" = 1 ] \
  && printf '%s\n' "$out" | grep -qxF 'TODO  2 project(s) with living docs still holding template placeholders: old33 (AGENTS.md PROJECT_STATE.md KNOWLEDGE.md), pend33 (AGENTS.md)' \
  && printf '%s\n' "$out" | grep -qxF 'TODO  1 project(s) whose AGENTS.md misses generic sections: old33' \
  && printf '%s\n' "$out" | grep -qxF 'TODO  1 project(s) with no git remote: old33' \
  || fail "unfilled docs, missing sections and no remote are TODO lines naming exactly those projects (rc=$rc): $out"
rc=0; out=$(DR "$F32" --json 2>/dev/null) || rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | J32 '
p = {x["name"]: x for x in d["projects"]}
assert p["good33"]["remote"] is True and p["good33"]["placeholder_docs"] == [] and p["good33"]["missing_headings"] == [], p["good33"]
assert p["pend33"]["placeholder_docs"] == ["AGENTS.md"] and p["pend33"]["missing_headings"] == []
o = p["old33"]
assert o["remote"] is False and o["placeholder_docs"] == ["AGENTS.md", ".github/PROJECT_STATE.md", ".github/KNOWLEDGE.md"], o
assert len(o["missing_headings"]) == 2 and all(h.startswith("## ") for h in o["missing_headings"]), o
b = p["bare32"]
assert b["remote"] is False and b["placeholder_docs"] == [] and b["missing_headings"] == []
assert sum(c["status"] == "TODO" and "old33" in c["what"] for c in d["checks"]) == 3
' || fail "doctor --json carries remote, placeholder_docs and missing_headings per project (rc=$rc): $out"
