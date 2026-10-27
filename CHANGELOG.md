# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `aicf projects`: one HTML page (and a terminal summary) listing every project of the code
  root, whether it is bootstrapped, unfinished or stale with the command that fixes it, and which
  skills it uses — counted from this machine's Claude Code transcripts, read locally only.

## [1.0.0] - 2026-10-27

First public release.

### Added

- `bin/aicf`, one CLI for every command: `init`, `sync`, `update`, `doctor`, `setup`,
  `uninstall`.
- One-line install (`install.sh`, `install.ps1`) and `aicf uninstall`.
- Work roots are configuration: `AI_WORK_ROOTS`, `~/.ai-work-roots`, or `"kind": "work"` in a
  code root's `.ai-root/environment.json`.
- User documentation in `docs/`: a tutorial, how-to guides, reference and explanation pages.
- `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, issue and pull-request templates.

### Changed

- Clean root: templates live in `templates/`, skills in `skills/`, scripts in `engine/`. The
  hook contract (`sync-ai-templates.sh|.ps1` and `templates-manifest.txt` at the root) is
  unchanged, so existing projects keep syncing.
- A private overlay uses `templates/` and `skills/` too. The old layout is still read, with one
  note per run.

### Removed

- The `.mcp.json` template: own tools are shell commands behind a skill, never MCP servers. A
  project's `.mcp.json` is removed only when it still equals the old template.

[Unreleased]: https://github.com/neijix/AICodeFactory/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/neijix/AICodeFactory/releases/tag/v1.0.0
