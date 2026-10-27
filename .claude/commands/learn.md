---
description: Analyze the conversation for learnings and save them to KNOWLEDGE.md
argument-hint: [optional topic hint]
model: fable
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Learn from Conversation

Analyze this conversation for insights worth preserving in `.github/KNOWLEDGE.md`.

**If a topic hint was provided via `$ARGUMENTS`, focus on capturing that specific learning.**
**If no hint provided, analyze the full conversation for valuable insights.**

## Phase 1: Deep Analysis

Think carefully about what was learned in this conversation:
- What non-obvious patterns or approaches were discovered?
- What gotchas or pitfalls were encountered?
- What architecture or design decisions were made and why?
- What conventions or standards were established?
- What debugging solutions or workarounds were found?
- What tool-specific behavior was discovered (Claude Code, Copilot, Cursor, Cursor Grok, Antigravity, etc.)?

Only capture insights that are **all three** of:
1. **Reusable** — will help in future similar situations
2. **Non-obvious** — not already common knowledge or derivable from reading the code
3. **Project-relevant** — applies to this codebase or workflow

If nothing valuable was learned, say so and stop.

## Phase 2: Categorize and Locate

List the headings of `.github/KNOWLEDGE.md` (`grep -n '^##' .github/KNOWLEDGE.md`) to find the
right area, and grep for the topic to avoid a duplicate entry — update an existing entry
instead of adding a second one.

Headings are **areas** — one per component, subsystem or tool (`## Runner`, `## Login`,
`## CI`) — plus `## Decisions` for technology choices and discarded directions. File the entry
under the area a future agent would grep first; if none fits, propose a new area heading.

**Note:** `AGENTS.md` is the master rulebook — it stays short and stable. Detailed learnings go to
`KNOWLEDGE.md`. One exception: a convention or style preference the user had to correct more than
once becomes a **one-line rule** under `## Taste` in `AGENTS.md` (create the section if missing) —
no rationale there; add a KNOWLEDGE.md entry only if the why is non-obvious.

## Phase 3: Draft the Learning

Format the insight to match the existing style in `KNOWLEDGE.md`:

```markdown
### <exact error text, or a greppable title>
**Context:** <when it happens — tool, command, version>
**Cause:** <the real reason>
**Fix:** <what works — command or change>
**Why:** <why this fix over the obvious one; what was tried and failed>
```

The title is what a future agent will `grep` for: prefer the literal error message.

Include code examples where they clarify the insight. Be concise — one clear entry, not a paragraph dump.

## Phase 4: User Approval (BLOCKING)

Present the proposed change:
1. The insight identified
2. Where it will be saved (area heading in KNOWLEDGE.md)
3. The exact content to add

**Wait for explicit user approval before saving.**

## Phase 5: Save

After approval:
1. Edit `.github/KNOWLEDGE.md` — add the entry under its area heading
2. Confirm: "Saved to KNOWLEDGE.md under [Area] — [title]"
