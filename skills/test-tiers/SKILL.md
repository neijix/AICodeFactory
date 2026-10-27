---
name: test-tiers
description: "Use when a project's tests take more than ~5 minutes, the user says the tests are slow, take forever or an hour, before running a whole suite to check one change, in a fix loop that reruns a failing suite, or when setting up ./check.sh or CI for a project with integration, e2e, browser, GPU or network tests. Splits the gate into a fast default tier and ./check.sh --full, with targeted and last-failed runs, parallel workers, CI shards and per-framework markers."
---

# Test tiers

`./check.sh` runs at the end of **every** response. A gate that takes an hour is either skipped
(nothing is checked) or blocks the session for an hour: both are bugs. The default gate stays
**under ~5 minutes**; everything slower moves to a full tier that runs less often, never away.

## What to run when

| Moment | Run |
|---|---|
| Iterating on a change | Only the tests of the code you touched (file, module, `-k`/`-run` filter) |
| Fixing a failing test | That test alone, then last-failed, then the fast tier — never the full tier per attempt |
| End of every response (commit) | `./check.sh` — the fast tier |
| End of a feature, before a release, or a change to shared core (schemas, DB layer, config loader, build) | `./check.sh --full` |
| CI on push | `./check.sh --full`, sharded when it is still long |

A full-tier run is a background job: start it once with the shell tool's maximum timeout, write
its log to a unique file (`/tmp/<project>-full-$$.log` — parallel sessions share `/tmp`), keep
working on something that doesn't touch the code under test, and read the result before calling
the work done. Never start a second copy while one runs, and never rerun it to see whether a
flaky test passes — fix or quarantine the flaky test.

## Split the suite (once per project)

1. **Measure first.** A few tests are usually most of the hour: `pytest --durations=20`,
   `go test -json ./...` (the `Elapsed` field), `cargo nextest run` (it prints slow tests),
   Jest `--verbose`. Typical causes, cheapest fix first: real `sleep`s and timeouts (fake the
   clock), a fresh DB or container per test (one per session, a transaction per test), live
   network calls (recorded fixtures — AGENTS.md **Testing** rule), a serial runner (workers),
   e2e tests repeating what unit tests already prove (delete the duplicate).
2. **Fast tier** = lint, type check, `code-health`, unit tests: no network, no real browser,
   DB server or GPU, no sleeps. **Full tier** = fast tier + integration, e2e, browser, GPU or
   model, large fixtures, performance.
3. **Mark slow tests where they live** — the framework's marker or a folder
   (`tests/unit/` vs `tests/integration/`), never a list of file names inside `check.sh`.
4. **One gate, one flag.** `check.sh` takes `--full` (its `check.ps1` twin the same flag):
   ```sh
   #!/usr/bin/env bash
   set -euo pipefail
   full=0; [ "${1:-}" = "--full" ] && full=1
   # lint, type check, code-health …
   if [ "$full" = 1 ]; then uv run pytest -n auto; else uv run pytest -n auto -m "not slow"; fi
   ```
5. **Write the durations down** in `PROJECT_STATE.md` Key Commands, so the next agent knows
   what it is starting: `./check.sh  # fast tier, ~2 min` and
   `./check.sh --full  # + integration/e2e, ~50 min — CI, end of feature`. Name the full tier
   in the AGENTS.md **Testing** rule and point CI (`.github/workflows/check.yml`) at it.

## Per framework

| Framework | Mark slow | Fast tier | Targeted / last-failed | Parallel / shard |
|---|---|---|---|---|
| pytest | `@pytest.mark.slow`, registered under `markers` in `pyproject.toml` | `-m "not slow"` | `pytest tests/test_x.py -k name`, `--lf` | `-n auto` (pytest-xdist); `--splits N --group i` (pytest-split) |
| Jest | separate `projects` or an `e2e/` path | `--testPathIgnorePatterns e2e` | `--findRelatedTests <files>`, `--onlyFailures` | workers by default; `--shard=i/N` |
| Vitest | separate project or `e2e/` path | `--exclude e2e/**` | `vitest related <files>`, `--changed` | workers by default; `--shard=i/N` |
| Go | `if testing.Short() { t.Skip(…) }` | `go test -short ./...` | `go test ./pkg/x -run TestY` | packages run in parallel; `t.Parallel()` |
| Rust | `#[ignore]` | `cargo test` | `cargo test name` | `cargo nextest run`; full: `-- --include-ignored` |
| .NET (xUnit) | `[Trait("Category", "Slow")]` | `dotnet test --filter "Category!=Slow"` | `--filter "FullyQualifiedName~X"` | parallel by default |
| Pester | `-Tag Slow` | `Invoke-Pester -ExcludeTagFilter Slow` | `Invoke-Pester -Path tests/x.Tests.ps1` | separate jobs in CI |
| Numbered shell suite | — | a case list in the runner | `run-tests.sh <case>…` | one CI job per group |

No marker mechanism fits → two scripts called by `check.sh` (`tests/fast.sh`, `tests/full.sh`),
still behind the one `--full` flag.
