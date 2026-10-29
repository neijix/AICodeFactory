# aicf.ps1 - the AICodeFactory command line: one entry point for the factory's scripts.
# Every argument after the command is passed through verbatim; `aicf <command> --help` prints
# that command's own help. Bash twin: bin/aicf.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Usage = @'
Usage: aicf <command> [options]

Commands:
  init <name> [--tracked]   create a sibling project, git-init it and install the AI files
  sync [<dir>] [options]    refresh one project's AI files from the templates (default: .)
  update [options] [<name>] refresh every sibling project (a preview unless --yes)
  doctor [--yes | --json]   check this machine and its code root; --yes fixes what it can
  setup [options]           set this machine up: global skills, hook, markers, profiles
  uninstall [--yes]         undo setup on this machine (a preview unless --yes)
  projects [--open]         page: which projects are bootstrapped, which skills each one uses
  config [--no-open]        settings page: code roots, personal skills, extra skill folders, scan
  help                      print this text
  --version                 print the version

`aicf <command> --help` prints that command's options.
'@

if ($args.Count -eq 0) { Write-Output $Usage; exit 0 }
$cmd = [string]$args[0]
$rest = @($args | Select-Object -Skip 1)
$script = switch -CaseSensitive ($cmd) {
  'init'   { Join-Path $Root 'engine/new-project.ps1' }
  'sync'   { Join-Path $Root 'sync-ai-templates.ps1' }
  'update' { Join-Path $Root 'engine/update-projects.ps1' }
  'doctor' { Join-Path $Root 'engine/doctor.ps1' }
  'setup'  { Join-Path $Root 'engine/install-global.ps1' }
  'uninstall' { Join-Path $Root 'engine/uninstall.ps1' }
  default  { '' }
}
$pages = @{ 'projects' = 'engine/projects-page.py'; 'config' = 'engine/config-ui.py' }
if ($pages.Keys -ccontains $cmd) {   # case-sensitive, like the switch above
  # Python, not PowerShell: these pages read JSON and transcripts. Same lookup as the engine's.
  $page = Join-Path $Root $pages[$cmd]
  foreach ($py in @('python3', 'python')) {
    if (-not (Get-Command $py -CommandType Application -ErrorAction SilentlyContinue)) { continue }
    # The Windows Store stub exits non-zero; its stderr is a terminating error under 5.1 + Stop.
    try { & $py -c 'import sys' 2>$null | Out-Null } catch { continue }
    if ($LASTEXITCODE -eq 0) { & $py $page @rest; exit $LASTEXITCODE }
  }
  if (Get-Command uv -ErrorAction SilentlyContinue) { & uv run -q --no-project python $page @rest; exit $LASTEXITCODE }
  $host.UI.WriteErrorLine("aicf: $cmd needs Python 3.9 or later (python3, python or uv) on PATH")
  exit 1
}
if (-not $script) {
  if ($cmd -cin @('help', '-h', '--help')) { Write-Output $Usage; exit 0 }
  if ($cmd -cin @('--version', 'version')) { Write-Output ([IO.File]::ReadAllText((Join-Path $Root 'engine/VERSION')).Trim()); exit 0 }
  $host.UI.WriteErrorLine("aicf: unknown command: $cmd")
  $host.UI.WriteErrorLine($Usage)
  exit 2
}
# A child process: each script reads its own arguments (and hands Windows PowerShell 5.1 over
# to pwsh itself), exactly as when it is run directly.
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $script @rest
exit $LASTEXITCODE
