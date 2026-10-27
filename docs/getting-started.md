# Getting started

In about ten minutes you install AICodeFactory, create a project, see two different agents read
the same rules, then change a rule and watch it reach the project. The commands are for macOS
and Linux; on Windows read [Windows](how-to/windows.md) first.

You need `git` and `bash`. `uv` (or `python3`) is optional. The examples use `~/Code` as the
folder that holds your projects; any folder works.

## 1. Install

Clone the factory into your code folder and set the machine up:

<!-- runnable -->
```bash
mkdir -p ~/Code
git clone https://github.com/neijix/AICodeFactory.git ~/Code/AICodeFactory
~/Code/AICodeFactory/bin/aicf setup
```

`aicf setup` links each shared skill into every tool's skills folder, writes the global files,
and ends with a summary:

```text
  [link]   ~/.claude/skills/bootstrap-ai -> ~/Code/AICodeFactory/skills/bootstrap-ai
  ...
Recorded this machine's template dir: ~/.ai-template-dir -> ~/Code/AICodeFactory
  registered AI_TEMPLATE_DIR: ~/.claude/settings.json
  registered AI_CODE_ROOT: ~/.claude/settings.json
  registered global SessionStart hook: ~/.claude/settings.json
Installed global customizations to:
  ...
Next: reload VS Code and Cursor (Developer: Reload Window). Claude Code / Gemini pick up
new skills in any new session.
```

Nothing else on the machine changes. `aicf uninstall` takes all of it back
([uninstall](how-to/uninstall.md)).

## 2. Create a project

<!-- runnable -->
```bash
~/Code/AICodeFactory/bin/aicf init hello-ai
```

```text
Creating ~/Code/hello-ai ...
ai-sync: private AI docs kept in a local hidden repo only — install-global --ai-context-remote <url> shares them between machines
  [create] CLAUDE.md
  [create] .github/copilot-instructions.md
  ...
  [create] AGENTS.md
  [create] .github/PROJECT_STATE.md
  [create] .github/KNOWLEDGE.md
  [create] .env.example
  [modify] .git/info/exclude
  [modify] .gitignore (add 2 line(s))
  [create] .git/hooks/pre-commit
ai-sync: private AI docs committed (.github/KNOWLEDGE.md .github/PROJECT_STATE.md AGENTS.md)
Mechanical bootstrap done: AI files copied, git init, first commit.
Next: open '~/Code/hello-ai' in your AI tool (Claude Code, Copilot, ...) so it can scan the code and finish filling in the project details.
Done: ~/Code/hello-ai
```

When the `claude` command is installed, `aicf init` also starts it once to fill in the
project's docs; otherwise your agent does it on the first session.

Look at what you got:

<!-- runnable -->
```bash
cd ~/Code/hello-ai
ls -A
git log --oneline
```

```text
.antigravity  .claude  .env.example  .gemini  .git  .github  .gitignore  AGENTS.md  CLAUDE.md
fa79188 docs: bootstrap project documentation
```

`AGENTS.md` holds the rules. `CLAUDE.md`, `.github/copilot-instructions.md`,
`.gemini/settings.json` and `.antigravity/rules.md` are small pointer files that send each tool
to it. The project is in **private** mode: the first commit holds only `.gitignore` and
`.env.example`, and your AI docs are versioned in a hidden repo inside `.git`, so the code repo
can go public without them. Prefer one repo for everything? Use `aicf init hello-ai --tracked`
([the modes](how-to/team-and-private-docs.md)).

## 3. Open it in two agents

Open `~/Code/hello-ai` in Claude Code, then in a second agent: Codex, Copilot, Cursor or Gemini
CLI. On the first session the agent sees the unfilled `AGENTS.md` and runs the `bootstrap-ai`
skill, which asks what the project is for and fills the docs in. Then ask both:

> Which file holds this project's rules, and what is step 1 of its session start?

Both answer `AGENTS.md`, and both quote the same step: refresh the shared AI files by running
the factory's `sync-ai-templates` script. Claude Code reads `AGENTS.md` through the
`@AGENTS.md` import in `CLAUDE.md`; the others read it directly. One set of rules, every tool.

## 4. Change a rule and watch it arrive

Personal rules belong in an **overlay**, a second folder next to the factory that the factory
layers on top of its own templates. Create one with a single extra line for `CLAUDE.md`:

<!-- runnable -->
```bash
mkdir -p ~/Code/AICodeFactory-private/templates
echo '- Answer in short sentences.' >> ~/Code/AICodeFactory-private/templates/CLAUDE.md.template.append
```

Now start a new Claude Code session in `hello-ai`. Its session-start hook runs this command,
which you can also run yourself to see what happens:

<!-- runnable -->
```bash
cd ~/Code/hello-ai
bash ~/Code/AICodeFactory/sync-ai-templates.sh . --quiet --commit --pull --agents --skills
tail -n 1 CLAUDE.md
```

```text
ai-sync: refreshed CLAUDE.md from AICodeFactory+AICodeFactory-private
- Answer in short sentences.
```

The same happens in every project on the machine, each at its next session start, with no
command to remember. A change to a template inside the factory travels the same way, and on
your other machines once you push it: the hook fast-forwards the factory first.

## Next

- [How the sync works](explanation/how-sync-works.md): why copies and why at session start.
- [Keep your own rules in a private overlay](how-to/private-overlay.md), as a real git repo.
- [Add a skill](how-to/add-a-skill.md).
- [Bootstrap an existing repo](how-to/update-projects.md#one-project):
  `aicf update <name>` for a folder next to the factory.
