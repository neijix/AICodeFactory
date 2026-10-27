---
name: review-sweep
description: "Use when the user asks for a deep, thorough or multi-pass review of finished work — a branch, the unpushed commits or the uncommitted changes — before a merge, a PR or a release (\"passe une review complète\", \"sweep this branch\", \"review everything before I merge\"), or when an agent wants an unattended review-and-fix pass (`auto`). A budget of cheap read-only reviewer agents cut into waves; after each wave the session triages every finding, fixes the confirmed ones, verifies and checkpoints, so the next wave reviews the fixed state. Code and docs in the same sweep. Not for a one-file diff (one `reviewer` is enough) nor for work still being built (architect-flow has its own review)."
---

# Review sweep

Depth comes from **waves**: each wave is a fresh set of `reviewer` agents reading the branch
as it is *now*, after the earlier waves' fixes. Cheap reviewers over-report (recall); you
verify every finding at its source (precision); only confirmed findings change anything.

## 1. Scope (one line before any spawn)

- **Source**: the current branch. **Base**: the ref the user gave, else
  `git merge-base HEAD "$(git symbolic-ref --short refs/remotes/origin/HEAD)"`, else
  `origin/master` / `origin/main`; on the default branch itself that is the unpushed work. No
  base found → ask (unattended: stop, "pass a base ref").
- **Review set**: `git diff --name-only -M -C <base>` plus
  `git ls-files --others --exclude-standard` — committed, uncommitted and untracked work.
  Nothing in it → say so and stop.
- **Anchor** (what the branch is for — coverage and divergence are measured against it): the
  user's intent statement, else a plan in `docs/plans/` the commits name, else
  `git log <base>..HEAD` pasted verbatim. None → the sweep still runs, without coverage and
  divergence, and the report says so.
- **Measure**: changed lines, as the shared review protocol
  [`../architect-flow/references/review.md`](../architect-flow/references/review.md) §1
  counts them (`review.md` below).
- **Tree state**: `git status --porcelain` empty → **clean**: each wave's fixes are committed.
  Not empty → **dirty**: the user's pending work is reviewed too, but a sweep commit would
  mix it in, so fixes stay in the working tree and each wave is snapshotted instead (§3).

Announce: base, scope, anchor, budget (and the measure it came from), wave cut, tree state,
and `unattended` with each default taken.

## 2. Budget and waves

The **budget** `N` is the total number of reviewers for the whole run. The user's number wins
either way. Else:

| Changed lines | `N` |
|---|---|
| ≤ 800 | 2 |
| 801 – 2500 | 4 |
| 2501 – 6000 | 6 |
| 6001 – 13000 | 8 |
| > 13000 | 10 |

At most **8 reviewers run at once**: `N` is cut into waves of 8, the remainder last (10 →
8 + 2; 20 → 8 + 8 + 4). A clean wave does not refund the budget — the run ends when every
budgeted reviewer has reviewed.

## 3. Each wave

1. **Shard** the current review set per `review.md` §1 (slices of
   whole files, second readers when files run short, the last reviewer cross-cutting).
2. **Spawn** the wave in one message: `subagent_type: "reviewer"`, `model` the configured model
   for step review (default `haiku`), with the
   same fallback (resume once, then Sonnet). When `review-prefilter` is `mlx` and the local-model offload
   skill's health check answers, run that free pass first; these reviewers still run and you still triage. Never on a
   work environment and never for a security review. Each brief: the repo root, the base, "review
   `git diff -M -C <base>` plus the untracked files", the anchor verbatim, its slice, and from
   wave 2 on the **wave log**.
3. **Triage** per `review.md` §2: merge, evidence first, verify at the source, one verdict
   each (`fix`, `dismiss`, `defer`), the severity confirmed or corrected. A finding the wave
   log already holds is dropped unless it brings new evidence — then it re-opens.
4. **Fix** the `fix` verdicts yourself (a `bug` starts with its failing test; a divergence
   where the code is right is `dismiss — accepted`, or `fix — amend <plan>` when a plan file
   is the anchor). A `defer` never blocks the sweep: it waits for the final report.
5. **Verify**: the project's own gate (`./check.sh`, else its documented tests) on a wave
   that touched code; a docs-only wave re-reads each edited section against its finding. Not
   green → fix before the next wave.
6. **Checkpoint**: clean tree → `fix(review): sweep wave <w> — <n> fixes` (only the files the
   fixes touched). Dirty tree → a snapshot outside the repo, nothing staged:

   ```bash
   S="${TMPDIR:-/tmp}/review-sweep-$(basename "$PWD")"; mkdir -p "$S"   # outside the repo
   cp "$(git rev-parse --git-path index)" "$S/sweep.index"
   GIT_INDEX_FILE="$S/sweep.index" git add -A && GIT_INDEX_FILE="$S/sweep.index" git write-tree
   ```

   Take `<T0>` this way before wave 1; after wave `w`, `git diff <T0> <Tw> > $S/wave-<w>.diff`
   is exactly the sweep's fixes.
7. **Log** one line per finding, appended, also mirrored to `$S/log.txt` (it must
   survive a compaction): `wave <w> F<n> [tag|severity] <file:line> — <defect> — <verdict> —
   <reason>`.

## 4. Unattended (`auto`, or no way to ask)

Never ask: no base → stop with "pass a base ref"; no intent → the commit messages; a dirty
tree → the dirty mode above. Defers go into the final report with their question.

## 5. Final report

The scope line as executed (fallbacks to Sonnet, timeboxed reviewers); per wave: reviewers,
findings, verdicts; the **severity tally** of every finding's latest line, with a
recommendation — an unfixed `critical`/`high` → another sweep is warranted, only
`medium`/`low` left → likely not; the totals (fixed, dismissed, deferred — each defer with its
question); the commits or the snapshot paths; any slice no reviewer covered.

## Guardrails

- The reviewers never fix and never verdict; you never skip verifying a finding.
- Only `fix` verdicts change anything. Rubber-stamping is as wrong as dismissing all.
- Never push, force-push, rebase or reset in a sweep; never commit the user's pending work.
