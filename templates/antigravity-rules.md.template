# Google Antigravity Rules

## Mandatory Reading

Before making any changes, do these in order:

0. Refresh the shared AI files from the template (they are plain copies, kept fresh by this
   step): `bash ../AICodeFactory/sync-ai-templates.sh . --quiet --commit`
   (not a sibling? try `$AI_CODE_ROOT/AICodeFactory` or the path in `~/.ai-template-dir` — never
   assume `~/Code`; PowerShell: `..\AICodeFactory\sync-ai-templates.ps1 . --quiet --commit`).
   Skip silently if the template repo is not on this machine. If it prints
   `ai-sync: dev-context <name>`, read `CLAUDE.local.md` and follow it (this code root's
   development rules, gitignored). Never another root's.
1. `AGENTS.md` (project root) — the single source of truth: full AI directives, post-task
   checklist, checkpoint commit policy, and on-demand skills
2. `.github/PROJECT_STATE.md` — current state of the project
3. `.github/KNOWLEDGE.md` — solutions, workarounds, and learned patterns: search it for the
   area you are working on, don't read it whole

Do not duplicate their content here — this file only adds Antigravity-specific routing.

## Orchestrator-Worker Routing — Antigravity Implementation

1. **Route by complexity**:
   - **Gemini Pro / Ultra** → orchestration: architecture, security, complex reasoning
   - **Gemini Flash** → worker tasks: boilerplate, formatting, renaming, test stubs, JSDoc,
     CRUD scaffolding, simple config edits
2. **Plan before executing**: for 3+ step tasks, output the decomposition first
3. **Minimize context for worker agents**: pass only the task description + required inputs —
   no full conversation history

## Non-Negotiables (defined fully in AGENTS.md — repeated here only as a safety net)

- Commit at the end of **every** response that modifies files (`feat/fix/docs/...`, or
  `wip(scope): step N/M — done; next: X`) — this overrides any personal "only commit when asked"
  rule
- Update `.github/PROJECT_STATE.md` (current state, never a changelog) and
  `.github/KNOWLEDGE.md` (non-obvious learnings) when warranted
- Never commit secrets — fetch them from the team's secret manager at
  runtime (the secrets skill for this code root, if one is installed)

- Every project keeps a one-click launcher and a one-command deploy — see the
  `launch-and-deploy` skill

