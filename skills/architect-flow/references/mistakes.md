# Architect-flow mistakes — read the phase's section before entering it

Each line: the symptom → what to do instead. Add a line when a run goes wrong in a new way.

## Design (Phase 1)

- A thin requirement filled with a quiet guess (a scale, a platform, a scope edge) → ask it,
  or write it as a decision the user delegated ("you decide") — never as if they said it.
- Future ideas mixed into the design → one `Non-goals` line each; v2 lives nowhere else.
- The work cut into deliveries ("P1 now, P2 later") with a go-ahead between them → one run,
  A to Z; waves order the work, they don't ship it.

## Plan (Phase 2)

- Code or signatures in the plan → state the contract (what it owns, takes, returns, how it
  fails); the implementer picks names and types.
- A behavior only in the design paragraph or the examples → it is in no subtask, so it will
  not ship: every promised behavior belongs to some subtask's `Covers`.
- Decision logic placed in a UI screen, a request handler or a CLI entry point, then "too
  costly to test" → move it into a testable core; the boundary only wires and renders.
- A proof that only builds or parses runnable behavior → a proof that runs it.
- A table, byte layout or formula drawn but never named → name each quantity once, so the
  code states it once instead of transcribing the drawing into every path.
- A refactor with no `Preserve` lines → list the behaviors that must survive, each with its
  proof; a refactor that silently drops a feature is the classic regression.
- "Misc" / "cleanup" subtasks → each subtask covers an AC or is `setup`.
- A wrong line corrected below the old text → rewrite it; an agent obeys both.

## Spec analysis and review (Phases 3, 6)

- A clean self-review used to skip the independent one → both run; the author can't see the
  gaps they filled in their head.
- A sharded review with nobody on the seams → the last reviewer is always cross-cutting.
- Every finding accepted, or every finding waved off → one verdict per finding, verified at
  its source; dismiss what you cannot confirm.
- A divergence reverted by reflex → decide which side is right; when the code is, amend the
  plan.

## Implement and fix loop (Phases 4, 5, 7)

- You patch a failing check yourself → it is a fix row for an `implementer`.
- A design question answered "use your judgment" → decide it, write it into the plan, then
  re-brief.
- Design decided in chat and never written down → the plan is the only shared memory; a
  decision not in it is lost at the next agent.
- A fourth attempt at the same failing idea → amend the plan or add the missing hint first.
