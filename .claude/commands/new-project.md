---
description: "Create a brand-new sibling project, fully wired for every AI tool (plain copies of the shared instruction files, self-refreshing at session start), then finish the smart fill."
argument-hint: "<project-name>"
allowed-tools: Bash, Read
---

# New Project

Project name: `$ARGUMENTS`

If no name was given, ask for one before running anything.

When the project goes under a work root, first run any pre-creation check that root's
instructions or work skills prescribe, and let the user decide from what it finds before
creating anything.

Run from this repo's root:

```
bin/aicf init "$ARGUMENTS"
```

This creates `../$ARGUMENTS`, git-inits it, copies every AI-tool pointer file from this repo
(no symlinks — the project re-syncs them from the template at every session start), fills the
living docs
(`AGENTS.md`, `PROJECT_STATE.md`, `KNOWLEDGE.md`), commits, and — if the
`claude` CLI is on `PATH` — runs `/bootstrap-ai` inside the new project to scan the code and
finish the smart fill (only meaningful if the folder already has source code; a truly empty
project just gets the mechanical scaffold and is ready for the smart fill once code exists).

Private by default: the AI files stay out of the code repo (`.git/info/exclude`, the hidden repo
`.git/ai-context`, `mode=private` in the code root's registry); the first commit holds only
`.gitignore` and `.env.example`. Only when the user asks for the AI files to be committed in the
code repo, add `--tracked` after the name.

Report: what was created, whether the AI auto-fill ran, and the path to the new project.
