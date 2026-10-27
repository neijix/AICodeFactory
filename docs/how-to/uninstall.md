# Uninstall

`aicf uninstall` removes what `aicf setup` put on the machine, and never touches a project.
Projects keep their AI files as plain files; remove those by hand if you want them gone.

## 1. Undo the machine setup

```bash
~/Code/AICodeFactory/bin/aicf uninstall          # preview: lists what would go
~/Code/AICodeFactory/bin/aicf uninstall --yes    # do it
```

On Windows: `bin\aicf.ps1 uninstall`, then `-Yes`.

It removes:

- the skill folders this checkout installed in every tool's skills folder (skills from other
  sources stay);
- the global hook and the `AI_TEMPLATE_DIR`, `AI_CODE_ROOT`, `AI_TEMPLATE_OVERLAY_DIR` keys in
  `~/.claude/settings.json` and in each Claude profile's settings (every other key stays);
- the Copilot CLI block in `~/.copilot/copilot-instructions.md`, the VS Code
  `ai-autobootstrap.instructions.md` prompt file and `~/.gemini/commands/bootstrap-ai.toml`;
- the `claude` profile block in your shell profiles;
- `~/.ai-template-dir`, `~/.ai-template-overlay-dir`, `~/.ai-work-roots`, `~/.claude-profiles`,
  `~/.ai-skills-stamp`, and the folders setup created that are now empty.

It keeps every project, each code root's `.ai-root` and `.ai-context-remote`, and the checkout
itself. [Full list](../reference/cli.md#aicf-uninstall).

## 2. Delete the checkout

```bash
rm -rf ~/Code/AICodeFactory
```

From then on a Claude Code session in a project prints one line and carries on:

```text
ai-sync: AICodeFactory not found - shared AI files not refreshed. Run its install-global once on this machine, or set AI_TEMPLATE_DIR.
```

## 3. Clean a project (optional)

To remove the AI files from one project, delete the pointer files, and the living docs too if
you do not want them ([which is which](../reference/project-files.md)). In a tracked
project, untrack them in the same commit:

```bash
cd ~/Code/my-project
git rm -r --cached --ignore-unmatch -q CLAUDE.md .claude .gemini .antigravity \
  .github/copilot-instructions.md .github/agents/quick-tasks.agent.md
rm -rf CLAUDE.md CLAUDE.local.md .claude .gemini .antigravity \
  .github/copilot-instructions.md .github/agents/quick-tasks.agent.md
git commit -m "chore: remove AI tool files"     # tracked mode only
```

`.claude/settings.local.json` goes with `.claude`: keep a copy if you added your own settings.

Then remove what the engine wrote outside the manifest:

- the block from `# ai-templates: <mode>` to `# ai-templates: end` in `.git/info/exclude`;
- the lines under `# ai-templates: local-only` in `.gitignore` (shared mode);
- `.git/hooks/pre-commit`, if its second line is `# ai-templates: managed git hook`;
- in a private or team project, `.git/ai-context`: the history of your AI docs (the files
  themselves are in the work tree). Delete it only when you no longer want that history.
