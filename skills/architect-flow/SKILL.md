---
name: architect-flow
description: "Use when the user says build / ship / deliver / implement / livre-moi a feature spanning several files or ~200+ LOC, or runs /architect: design questions with the user, then one independent agent per step — planner, spec-analyst, implementers (parallel waves, on the owner's chosen target), converger, reviewer (sharded on a large diff), verifier — with a committed plan file and a bounded fix loop. Not for one-file fixes or pure research."
---

# Architect flow

You are the architect: you design with the user, brief one independent agent per step, check
what each one hands back, and commit. Every step after the design runs in a fresh context with
a single role — no agent judges its own work, and the plan file is the only thing they share.

## When to invoke

Use this flow when:
- The user says **build / ship / deliver / implement / livre-moi** a feature.
- The user invokes `/architect` explicitly.
- The change is expected to touch **more than ~3 files** or **more than ~200 LOC**.
- The requirements have ambiguity that would change the outcome.

Skip it for a one-line fix, a typo or a rename in one file (just do it, then hand the diff to
the `reviewer` if it is more than a few lines), and for pure research (`Explore` agent). A
change of 2-4 files that still deserves a plan takes the **lite path** below.

**One run, A to Z.** A product, a feature or a refactor ships whole in one run: the waves
order the work, they are not deliveries. Never cut the plan into "P1 now, P2 later" and stop
for a go-ahead between them — the only stops are the gates below and a question whose answer
changes the outcome. Before each phase, read its section of
[`references/mistakes.md`](references/mistakes.md): the classic ways each phase goes wrong.

## The roles

| Phase | Who | Writes | Gate |
|---|---|---|---|
| 1 Design | **you** — only the main conversation can talk to the user | — | user agrees with the design paragraph |
| 2 Plan | `planner` | `docs/plans/<slug>.md` | plan saved (committed when tracked) |
| 3 Spec analysis | `spec-analyst` | nothing (report) | `READY` |
| 4 Implement | `implementer` × N on the subtask target, a `P` wave in parallel; the local-model offload skill for `offload` rows | the subtask's `Files` | each report `DONE`, diff matches |
| 5 Converge | `converger` | nothing (rows for you to append) | `CONVERGED` |
| 6 Review | `reviewer` × 2-6 on the configured model for step review (default haiku), then your triage | nothing (report) | no confirmed blocking finding |
| 7 Test & verify | `verifier` | nothing (report) | `DONE` |
| 8 Finish | **you** | plan status, docs, commits | — |

Their briefs are the agent files (`.claude/agents/<role>.md`, copied into every project). Spawn
them with the harness's agent tool (Claude Code: `Agent`, `subagent_type: "<role>"`). A role
missing from the list (the project hasn't synced since it was added) → `general-purpose` with
*"Read `.claude/agents/<role>.md` and act exactly as it says"*. No agent tool at all (Codex,
Gemini CLI…) → play each role yourself in a separate pass from that file, re-reading the plan
and the diff rather than trusting your memory, and say in Phase 8 that the steps were not
independent.

You never write feature code yourself: a fix is a new subtask for an `implementer`. A brief is
a contract, not a conversation: the plan path, the subtask number (or the diff base), and
nothing the agent file already says. Never forward an agent's opinion as fact to the next one
— each reads the repo.

## Phase 1 — Design (you, with the user)

Read the code first: `git log --oneline -10`, `git status`, the files the user named or that
obviously match the feature area. Then identify the **materially ambiguous** decisions — the
ones where a different choice produces a different feature. Per the **Asking** rule of
AGENTS.md (cite rules by name — their numbers vary per project): ask only when the answer
changes the outcome, one targeted question with a recommended default, 3 questions at most,
through the harness's question tool if it has one. Typical categories: scope boundary, API
shape, naming (the **Rough names are intent** rule: propose 2-3 idiomatic names), error and
edge behavior.

Confirm the resolved design in one paragraph: *"I'll build X with shape Y, handling edge cases
Z. Non-goals: W."* — that paragraph is the planner's input.

## Phase 2 — Plan (`planner`)

Brief: the design paragraph, the slug, the files you read. The planner writes
`docs/plans/<slug>.md` — a `Base:` commit in its header, examples, `AC<n>` criteria each with
its proof command, and a subtask table with `Files`, `Covers`, `After`, `P` and `Target`
columns (the exact shape is in its agent file). Settle its **Open questions** with the user,
have it amend the plan, then commit it: `docs(plan): <feature>` — unless
`git check-ignore -q docs/plans/<slug>.md` says it is ignored (private, team or shared
project): there the hidden-repo sync versions it, and `git add -f` would leak the AI layer
into the code repo; never force it. Every later brief passes the plan path; agents diff
against its `Base:`. When the design changes later, the affected lines are rewritten, never
corrected below the old text — an agent would obey both.

## Phase 3 — Spec analysis (`spec-analyst`)

Brief: the plan path. It returns coverage, ambiguity, rule-conflict and parallel-safety
findings with severities. `FIX` → fix the plan at the source (or re-brief the planner), commit,
re-run — 3 rounds at most, then take the remaining findings to the user. A conflict with an `AGENTS.md` rule is always CRITICAL: change the plan,
never water down the rule — changing a rule is a separate decision for the user. Skip this
phase only for a plan of one or two subtasks.

## Phase 4 — Implement (`implementer`, in waves)

**Who implements** an `implementer` row is the owner's choice. `workflow.implement` in
`factory.json` or the environment is the default agent and model for this step.
`AI_SUBTASK_TARGET`, when set in the shell or the Claude settings `env`, still wins:

| Value | The row goes to |
|---|---|
| unset, empty, `subagent` | an `implementer` agent (its own model, Sonnet) |
| `subagent:<model>` | an `implementer` agent with `model: <model>` |
| `helpers` | the host app's helper-delegation command (a skill installed on this machine documents it), the brief saying *"act exactly as `.claude/agents/implementer.md` says"* plus the plan path and row; its report is untrusted — the wave gates below are what count |
| `self` | you, playing the `implementer` file in a separate pass |

`helpers` and `self` run a wave's rows one by one. `helpers` works only inside a host that
offers helper delegation: probe it first as its skill says; no such skill, a failed probe, or
any other value → one line saying so, then the default.

A wave is every `todo` subtask whose `After` is done. Its `P` rows go out **in one message,
one `implementer` each**, so they run concurrently; a row without `P` runs alone. Before a
wave, re-check that its `P` rows share no path in `Files` — if they do, run them one by one.

Implementers share one working tree (worktrees are out — AGENTS.md **Git** rule), so in a
wave each one runs only the checks scoped to its own files; the whole-tree gates are yours,
after the wave:
1. `git status --porcelain` (it shows new untracked files; `git diff --stat` doesn't): every
   changed path must belong to some row's `Files`. A path nobody claimed, or a `BLOCKED` /
   `PARTIAL` report → settle it (with the user if it is a design question) before going on.
2. Run the area's tests and the `code-health` check once on the wave's result; a failure is a
   fix subtask (fix loop), not something you patch yourself.
3. Set the rows `done` in the plan and commit them with their changes:
   `feat(scope): <subtask>` — one commit per subtask when they are separable.

`offload` rows: run them yourself through the local-model offload skill, if one is installed,
and gate the output with parse/lint/test before accepting it. No such skill, or its health check
fails → say once *"local offload unavailable, staying local"* and hand those rows to an
`implementer`.

## Phase 5 — Converge (`converger`)

Brief: the plan path. `GAPS` → append its rows to the plan's `## Convergence` table, commit,
run Phase 4 for them, converge again until `CONVERGED`. Each `GAPS` verdict counts as one
fix-loop iteration.

## Phase 6 — Review (`reviewer`)

Brief: the plan path and its `Base:` commit as the diff base. Always 2 reviewers at least,
scaled on the changed lines, the last one cross-cutting, on the configured model for step
review (default haiku). When step `review-prefilter` is `mlx` and the local-model offload
skill's health check answers, run that free pass first; the reviewers still run and you still
triage. Never on a work environment and never for a security review. You triage every finding
([`references/review.md`](references/review.md)). Confirmed blocking findings (correctness,
security, a broken rule, a `code-health` failure, untested behavior, an uncovered AC or
`Preserve` line) → fix loop. Non-blocking ones go into the plan's final note and the report to the user; don't
loop on them. For a large or risky diff
the user may also run `/code-review` — it complements the reviewer, it doesn't replace it.

## Phase 7 — Test & verify (`verifier`)

Brief: the plan path and its `Base:` commit — the acceptance criteria plus any claim you will
make ("X now does Y", "Z is covered by test T") are what it checks, and "run the full tier"
(the end of a feature is when slow tests run — `test-tiers` skill). It finds and runs the
project's gate itself (`./check.sh --full` first, else the documented test commands) and the real
behavior, and reports PASS / FAIL / UNVERIFIED per claim. Any FAIL → fix loop. UNVERIFIED
claims (GUI, network, no harness) don't loop: they go to the user in Phase 8 with the reason.
No test harness at all → tell the user *"No test harness detected — recommend adding one
before this feature ships"* and don't invent a command.

## Lite path (2-4 files)

Same roles, less paper: no plan file, no spec analysis, no converger.
1. **Design + plan in the conversation**: the design paragraph, the ACs with their proof
   commands, the subtask list with `Files` — one message; the user's explicit yes is the gate
   (with a plan-mode tool, the plan goes through it).
2. **Implement** as Phase 4 — the brief carries the plan text verbatim instead of a path;
   commit each subtask.
3. **Review** as Phase 6 with the plan pasted verbatim into each brief (2 reviewers on a small
   diff), then **verify** as Phase 7. Fix loop and guardrails unchanged.

The plan grows past 4 files or wants open questions parked → switch to the full flow: the
planner writes the plan file from what is already settled.

## Fix loop

An implementer stops after 3 distinct fixes for one failing check (`PARTIAL`, attempts
listed): read them before re-briefing — a fourth try of the same idea is not a fix row; amend
the plan or add the missing hint first.

Bounded to **3 iterations** in total: each `GAPS`, `CHANGES REQUESTED` or FAIL verdict that
sends you back counts as one. Each iteration: add the fix as a row of the `## Convergence`
table (findings or failing output just below it), commit, run Phase 4 for it, then re-run
**every** gate from Phase 5 on — a fix can break what an earlier gate accepted.

After 3 iterations without a clean pass, **stop and hand it to the user** with the current
diff, the remaining findings or failures, and your best guess at the root cause. Never extend
the loop yourself: the user may know about a flaky test, an intended inversion, a missing
dependency.

## Phase 8 — Finish (you)

Set the plan's `Status:` to `done` and note skipped phases and open non-blocking findings in
it. Update `.github/PROJECT_STATE.md` (or its `docs/state/` detail) if architecture, commands,
env vars or capabilities changed, and `.github/KNOWLEDGE.md` if something non-obvious was
solved. Final commit: `feat(scope): <feature>`. Tell the user in a few lines: what was
delivered, each gate's verdict (or why it was skipped), the non-blocking findings left, the
final commit hash.

## Guardrails

- **Never** use destructive git commands (hard reset, force push, history rewrites) inside the
  flow without explicit user approval — even if a finding suggests one.
- **Never** let an agent grade its own output: the implementer is never its own reviewer,
  converger or verifier, and neither are you.
- **Never** invent a test command that doesn't exist in the project.
- **Never** loop more than 3 times. Hand back to the user.
- **Never** hand judgment work (design, naming, security-sensitive choices) to a local-model offload.
- **Always** commit at each checkpoint (plan when tracked, each wave, each fix). A crashed session must be
  resumable from `git log --oneline` + `git diff HEAD` + the plan's status column.
