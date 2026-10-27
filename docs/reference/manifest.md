# Manifest reference

`templates-manifest.txt`, at the root of the factory, is the only list of which template
becomes which project file. The engine, `aicf init`, `aicf update` and the tests all read it;
nothing else hardcodes the list.

## Format

Plain text. A line starting with `#` is a comment, a blank line is ignored, a `[SECTION]` line
starts a section, and every other line is an entry with fields separated by `|`. Paths use `/`
on every platform.

| Section | Entry | What the sync does |
|---|---|---|
| `[POINTERS]` | `<src>|<dest>` | Renders `<src>` (with the overlay applied) and copies it to `<dest>` whenever they differ. Identical in every project. |
| `[LIVING_DOCS]` | `<src>|<dest>` | Creates `<dest>` once, with `[PROJECT_NAME]` replaced by the project folder name. Never overwritten afterwards. |
| `[SHARED_HOOKS]` | `<src>|<hook-name>` | Installs `<src>` as `<git-common-dir>/hooks/<hook-name>` in every mode but tracked; never tracked by git. A hook that lacks the `# ai-templates: managed git hook` line is left alone. Removed again when the project goes back to tracked. |
| `[OBSOLETE]` | `<path>` or `<path>|<reference>` | Removes `<path>` from the project. With a reference file, only while the project's copy is byte-identical to it; a customized copy is kept and reported. A symbolic link is always removed. |

`<src>` is relative to the factory root (`templates/...`); `<dest>` and `<path>` are relative to
the project root.

The current entries, and who owns each resulting file, are listed in
[project files](project-files.md).

## Rules for a new entry

- A file every project should get unchanged, refreshed by every sync → `[POINTERS]`. Agents
  must never hand-edit it in a project: the next sync replaces it.
- A file each project fills in and keeps → `[LIVING_DOCS]`. Template changes reach only the
  projects created afterwards.
- Renaming or dropping a pointer → keep the old destination under `[OBSOLETE]` with a reference
  copy of its last content, so the sync removes untouched copies and keeps customized ones.
- No symbolic links, anywhere a project receives files: they break on Windows without Developer
  Mode and on checkouts with `core.symlinks=false`.

## The overlay manifest

An overlay may hold `overlay-manifest.txt` in the same format. Its entries are added to the
factory's, and an entry with the same destination as a factory entry replaces it. See the
[overlay reference](overlay.md).
