# Example private overlay

A working overlay to copy as the start of your own: one skill and one `AGENTS.md` fragment. An
overlay is a second folder next to the factory whose files win over the factory's, so your
rules and skills stay yours while you keep pulling AICodeFactory.

## Layout

```text
overlay/
├── templates/
│   └── AGENTS.md.template.append      appended to every new project's AGENTS.md
└── skills/
    └── example-skill/SKILL.md         installed into every tool's skill folder
```

| File | What it does |
|---|---|
| `templates/AGENTS.md.template.append` | Adds a `## Personal taste` section to the `AGENTS.md` of every project created from now on. `AGENTS.md` is a living doc: existing projects keep theirs. |
| `skills/example-skill/SKILL.md` | A complete skill (add one changelog line per user-visible change). Rename the folder and its `name`, then rewrite it. |

A file under `templates/` follows the factory's path: `templates/CLAUDE.md.template.append`
reaches every project's `CLAUDE.md` at its next session start, and a full
`templates/<src>.template` replaces the factory's template of that path.

## Use it

```bash
cp -R ~/Code/AICodeFactory/examples/overlay ~/Code/AICodeFactory-private
cd ~/Code/AICodeFactory-private
git init -q && git add -A && git commit -qm "chore: start my overlay"
~/Code/AICodeFactory/bin/aicf setup
```

A sibling named `AICodeFactory-private` is found without configuration; for another path, run
`aicf setup --overlay <dir>`. Push it to a **private** remote if you want it on other machines.

- [Keep your own rules in a private overlay](../../docs/how-to/private-overlay.md): the full how-to.
- [Overlay reference](../../docs/reference/overlay.md): lookup order, every file it may hold.
- [Add a skill](../../docs/how-to/add-a-skill.md): the rules a `SKILL.md` must follow.
