---
name: csharp-tools
description: "Use when writing a new project tool, script or CLI helper (anything past a one-liner), when a task rewrites or substantially changes a paired .sh + .ps1 script, when the user asks to port scripts to C#, or when adding unit tests to shell tooling. Project tools are C# console projects run with `dotnet` on Windows and macOS alike — one source instead of two drifting twins, compiled, unit-tested with xUnit. Covers layout, seams for testing, exit codes, shims and the step-by-step port of an existing pair. Not for Claude Code hook one-liners or the session-start sync, which must run before .NET exists."
---

# C# project tools

One C# source replaces a `.sh` + `.ps1` pair: it compiles (the type checker catches what two
hand-synced scripts drift on), it runs the same on Windows and macOS, and its logic is
unit-tested like any code. Every project moves to it **gradually**: new tools start in C#, an
existing pair is ported the next time a task rewrites it — never a big-bang rewrite.

**Stays shell:** a hook one-liner in `.claude/settings.json`, the session-start sync and any
step that must run on a fresh machine before the SDK is installed, a command the human types
once. Everything else that would be a script is a tool.

## Runner

The **.NET 10 SDK** (`dotnet --list-sdks`): Windows `winget install Microsoft.DotNet.SDK.10`,
macOS `brew install --cask dotnet-sdk`. `doctor` warns when it is missing.

```bash
dotnet run --project tools/<Name> -- <args>     # builds on first use (seconds), then runs
dotnet test tools/                              # every test project of the solution
```

Not `csharp-run`: it is a Windows-only work installer's runner and only discovers tools that
Claude Code plugins ship — a repo's `tools/` projects are invisible to it, and macOS has none.

## Layout

```
tools/
├── Directory.Build.props        # net10.0, Nullable, ImplicitUsings, TreatWarningsAsErrors
├── Tools.slnx                   # every project below
├── <Name>/<Name>.csproj         # Exe: Program.cs only parses args and wires the core
├── <Name>/<Feature>.cs          # the logic, behind small interfaces
└── <Name>.Tests/<Name>.Tests.csproj   # xUnit, references <Name>
```

`dotnet new sln -n Tools -o tools` (writes `Tools.slnx`), `dotnet new console -o
tools/<Name>`, `dotnet new xunit -o tools/<Name>.Tests`, `dotnet sln tools/Tools.slnx add
tools/<Name> tools/<Name>.Tests`, `dotnet add tools/<Name>.Tests reference tools/<Name>`.
Commit the solution, the projects and a `.gitignore` with `bin/` and `obj/`.

## Write it testable

- **Program.cs is wiring only**: parse arguments, build the real implementations, call the
  core, map the result to an exit code. Logic in `Program.cs` is logic without a test.
- **Seams for the outside world**: the file system, processes, environment variables and the
  clock go through small interfaces the tests fake (`TimeProvider` for time; own one-method
  interfaces for the rest — no mocking framework needed).
- **Tests**: unit tests on the core with fakes; a few end-to-end tests that run the built tool
  in a temp directory (`Directory.CreateTempSubdirectory()`), one per command, sad path
  included.

## Conventions

- **Streams**: stdout is the result (machine-readable when another tool reads it), stderr is
  `ERROR: <what failed> — <what to do>`. **Exit codes**: `0` success, `1` failure, `2` usage
  error (unknown flag, missing argument).
- **Paths**: `Path.Combine` / `Path.GetFullPath`, never a hard-coded separator or drive; the
  code root from `AI_CODE_ROOT` or derived from the tool's own location, never `$HOME/Code`.
- **Processes**: `ProcessStartInfo.ArgumentList`, never a command string through a shell — no
  quoting bugs, no injection. Set `UseShellExecute = false`, read both streams.
- **Files**: write UTF-8 without BOM and `\n` line endings unless the format needs otherwise.
- **Same bar as the scripts**: loud actionable errors, no secrets in output, no network call
  without a timeout.

## Porting a `.sh` + `.ps1` pair

1. **Pin today's behavior**: the project's existing tests for that script, else new
   end-to-end tests run against the current script — they are the spec.
2. **Port** into `tools/<Name>` with unit tests for the logic; same flags, same output, same
   exit codes. No behavior change in the port commit — a change is its own commit after.
3. **Shims** so callers keep working: the pair shrinks to one line each —
   `exec dotnet run --project "$(dirname "$0")/tools/<Name>" -- "$@"` /
   `dotnet run --project "$PSScriptRoot/tools/<Name>" -- @args; exit $LASTEXITCODE` — and the
   pinned tests pass through them.
4. **Gate**: `dotnet test tools/` joins the project's check (`./check.sh`, CI). CI runs on
   `windows-latest` and `macos-latest` with `actions/setup-dotnet` (`dotnet-version: 10.0.x`).
5. **Later**, once callers and docs name the tool directly, delete the shims.

Inventory what is left to port: `git ls-files '*.sh' '*.ps1'`.
