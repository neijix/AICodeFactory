# Sharded review — reviewers for recall, the architect for precision

Phase 6 and every lite-path review. One reviewer reading a whole diff skims its end; several
`reviewer` agents on a cheap model each read it cold and over-report, then you verify every
finding at its source and only confirmed ones become fix rows.

## 1. Surface and shard count

Changed lines = the first two columns of `git diff --numstat -M -C <Base>` summed, plus the
line count of each untracked new file (`git status --porcelain`, `??`). A move counts only
what it changed.

| Changed lines | Reviewers |
|---|---|
| ≤ 300 | 2 — the floor |
| 301 – 800 | 3 |
| 801 – 1500 | 4 |
| 1501 – 2500 | 5 |
| > 2500 | 6 — the cap |

- **The last reviewer is always cross-cutting**: it owns no slice — the anchor covered as a
  whole, and contracts between files of different slices. The others are slices.
- A **slice** is whole files, each with its tests and paired twin (`.sh` with its `.ps1`),
  balanced by changed lines; a file is never split.
- **Fewer files than slice reviewers** → each file is its own slice and the extra reviewers
  are **second readers**, dealt to the largest files first: same slice, same brief, not told
  the other exists.
- Spawn all of them in one message, `subagent_type: "reviewer"`, `model` the configured model
  for step review (default `haiku`). When `review-prefilter` is `mlx` and the local-model offload
  skill's health check answers, that free pass runs first; these reviewers still run and the session still triages.
  Never for a work environment or a security review. Each
  brief: the anchor (plan path, or the lite plan pasted verbatim), the `Base:` commit, and its
  slice (the file list) or "you are the cross-cutting reviewer" — never a summary of the diff,
  never another reviewer's findings.
- **Fallback**: a reviewer that ends with no report (turn cap) is resumed once
  (`SendMessage`: "budget is up — report now, `(timeboxed)`"); one that errors, or still has
  no report, is re-spawned once on `model: "sonnet"` with the same brief, and after a spawn
  error every later reviewer of the session goes straight to Sonnet. Name each fallback and
  each `(timeboxed)` report in the summary; a slice nobody reviewed is reported as not run.

## 2. Triage (you — never a reviewer)

1. Merge duplicates (keep the better-cited one), renumber `F1..Fn`.
2. A finding with no `file:line`, no anchor citation where its tag needs one, or no concrete
   failure scenario → dismissed without further thought.
3. Verify each survivor at its source: open the `file:line`, trace the trigger through the
   code, open the anchor line. **Dismiss what you cannot positively confirm** — a wrongly
   confirmed false positive breaks working code now; a wrongly dismissed real issue
   resurfaces.
4. One verdict per finding, one-line reason:
   - `fix — <action>` → a fix row (fix loop); a `bug` fix starts with the failing test;
   - built differently from the plan and the code is right → `fix — amend the plan: <what>`,
     the plan lines rewritten: plan and code never silently disagree (lite path: `dismiss —
     divergence accepted: <why>`);
   - `defer — <question>` when the answer is the user's (scope, visible behavior, a
     trade-off); ask it before the fix loop.
5. Rubber-stamping every finding is as wrong as dismissing them all.

## 3. Once per reviewed state

Applying the review's own `fix` verdicts does not re-run it: the fix executes what a reviewer
asked for. Re-run it — scoped to the files that changed — only when the fix loop changed code
the review never read (a new subtask, a converger row) or the plan itself changed.

Report in Phase 8: `<K> reviewers — <surface> lines` (fallbacks, timeboxed ones), then each
finding with its tag, citation and verdict. A clean review is a result too: "2 reviewers,
0 findings".
