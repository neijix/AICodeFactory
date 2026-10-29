# Factory config — brain, personal layer, one environment per code root

The brain is this checkout. A personal overlay holds `factory.json` (identity, taste, skill
overrides, default step choices). Each code root holds `.ai-root/environment.json` (label, kind
`personal` or `work`, which skills are on, which agent runs each step). A project still owns its
own living docs. D3SKHAND Settings → Brain only runs `engine/factory-env.py`. The engine
reads the files at session start, so an agent that never opens D3SKHAND follows the same rules.

No `factory.json` and no `environment.json`, and nothing turned off: the sync writes nothing.
Existing tests stay valid. When the files go away, the next run takes back what it wrote.

## Command

`python <brain>/engine/factory-env.py <command>` (package `engine/factory_env`, one
implementation). A script, not `python -m`: `-m` puts the caller's folder first on `sys.path`,
and a project with its own `engine/` package would shadow the brain's. Not a C# tool: the
session-start hook runs before .NET is required anywhere. stdout is the result. stderr is
`ERROR: what failed — what to do`. Exit 0, 1, or 2. Unit tests: `tests/test_factory_env.py`.

`aicf config` (`engine/config_ui`) is the brain's own page over the same calls (`view`,
`set_layer`). `get --json`, `set` (stdin `{layer, root, values}`), `apply PROJECT`, `skills-current`,
`skills-begin`, `skills-finish`, `skill-keep`, `skill-stamp`, `merge-rebase`, `unsynced`,
`brain-set`, `overlay-dirs`. `set` checks only the keys it changes and keeps every other key as
written (a newer brain on another machine may know more keys). It may commit the one file it
wrote when that repo is otherwise clean. It never pushes.

## What a project is told

Claude: `skillOverrides` in the project's gitignored `.claude/settings.local.json` gets
`"<name>": "off"` for each skill off. The names the last run wrote are read back from the
`Skills off …` line of the Factory section; only those are taken back. Any other entry, or a
value the user changed, stays. A file that is not a JSON object, or one git tracks (a team's),
is left untouched. The `skills off` line is printed again only on a change, or every time
outside Claude Code (`CLAUDECODE` / `CLAUDE_PROJECT_DIR` unset); inside it, `skillOverrides`
already hides the skill.

Every agent: a marked section in gitignored `CLAUDE.local.md`
(`<!-- ai-templates: factory -->` … `factory-end`). It names skills that are off, the step
table, a one-line warning when design is configured for Claude and this agent is not Claude,
and the MLX prefilter sentence only when that step's agent is `mlx`.

Work (`kind: work`) never runs MLX. A hand-edited file is clamped at read time too.

## Skills

Brain skills are on everywhere. Personal-overlay skills are on in a personal environment and
off at work unless `skills.on` names them. Work-overlay skills are on only at work. A project
exported as `skill/<name>/SKILL.md` stays off until an environment turns it on. The environment
wins over the personal file.

## Not losing a push or a pull

- A skill install records a content hash under `~/.ai-skills-stamp`. A matching stamp skips the
  refresh, including the retired-skill prune. A killed install leaves `.ai-skills-stamp.running`
  and the next run says `ai-sync: previous skill install did not finish`. The stamp covers the
  overlay found the engine's way (variable, `~/.ai-template-overlay-dir`, `<brain>-private`);
  a retired name counts only when the copy there is ours (its origin names a source).
- An installed copy's `.ai-template-origin` keeps the source path on line 1 and a content hash
  on line 2. Comparisons use line 1 only. A copy that differs from the source (compared first,
  so Python starts only then) and from the recorded hash is kept, with one warning.
  `__pycache__` is not content: a script run from the copy is not an edit.
- A hidden-repo rebase that conflicts only in `config.local/*.json` is merged three ways by
  top-level key: a key changed on one side takes that side, a deletion included. A key both
  sides changed differently, any other conflicted file, or an error aborts the rebase as before
  and writes `.git/ai-context/sync-conflict.json` (files, keys, the ref). Every session start
  repeats the line until a pull goes through, which deletes the marker. Doctor and D3SKHAND see
  it too.
- Doctor `--json` adds `unsynced` after `projects`: ahead, behind, dirty, a conflict, or an
  installed skill copy whose origin names this brain and which is neither shipped nor in
  `RETIRED`. Check-only still writes nothing.

The employer's API specs are still in published history. The README says the purge is pending.
Do not rewrite that history from this change.
