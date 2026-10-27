---
name: example-skill
description: "Use when the user asks to add a changelog entry, to note a user-visible change, or before tagging a release in a project that has a CHANGELOG.md. Adds one line under the right Keep a Changelog heading of the Unreleased section. An example overlay skill: copy the folder, rename it, rewrite this text."
---

# example-skill: one changelog line per user-visible change

An overlay skill is a folder with a `SKILL.md`. Its `name` must equal the folder name, and its
`description` says when an agent should load it: agents read only the description until the
task matches, so put the trigger words there.

## Steps

1. Open `CHANGELOG.md`. No such file: say so in one line and stop; do not create one unasked.
2. Find `## [Unreleased]`. Pick the heading that fits the change: `### Added`, `### Changed`,
   `### Deprecated`, `### Removed`, `### Fixed` or `### Security`. Create the heading under
   `## [Unreleased]` when it is missing.
3. Add one line, written for a user, not a developer: what changed and why it matters to them.
   No commit hashes, no file names unless the user types them.
4. Commit it with the change it describes, not on its own.
