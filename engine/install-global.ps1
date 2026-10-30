# Installs the global AI customizations (skills, auto-bootstrap instruction) into your user
# profile for every tool, and removes the MCP servers older versions registered (no MCP server
# anywhere). Run once per machine; afterwards the session-start sync (`sync-ai-templates.ps1
# --skills`, run by every project's SessionStart hook) keeps the skill folders fresh. Re-run only
# after editing ai-autobootstrap.instructions.md.
#
# Claude Code also gets one global SessionStart hook in ~\.claude\settings.json
# (templates\global\claude-global-hook.json, merged by Install-ClaudeGlobalHook: other keys and
# hooks kept, never duplicated). It runs `sync-ai-templates.sh --global-hook`, a no-op unless the
# project sits in a code root and its own .claude\settings.json lacks the sync hook — a fresh
# clone of a private project, whose layer C is not there yet. There is no global Stop hook: the
# project's own Stop hook takes over once layer C exists.
#
# Usage: aicf setup [-Copy] [-Overlay <dir>] [-AppsConfigDir <dir>] [-AiContextRemote <url>|<root>=<url>]
#                             [-ClaudeProfile <root>[=<config-dir>|none],...] [-ClaudeEnv <root>=<NAME>=<value>,...]
#                             [-WorkRoot <name>|<path>,...]
#   -Copy            install skills as plain copies instead of symlinks. Already the default on
#                    Windows (symlinks need Developer Mode); on macOS/Linux symlinks stay the default.
#   -Overlay <dir>   layer a second (typically private) template repo on top of this one - see the
#                    "Overlay" paragraph in sync-ai-templates.ps1. Records its absolute path in
#                    ~\.ai-template-overlay-dir and as AI_TEMPLATE_OVERLAY_DIR in
#                    ~\.claude\settings.json so every session-start sync layers it. Without it, an
#                    overlay already configured on this machine is left untouched.
#   -AppsConfigDir <dir>
#                    where this machine keeps the owner's personal app settings (one subfolder per
#                    app, e.g. a synced "AppsSync" folder): written to ~\.apps-config-dir, read by
#                    every app that follows the apps-config skill. Without it an existing record is kept.
#   -AiContextRemote <url> | <root>=<url>
#                    a code root's private git remote (one branch per project, plus _root for the
#                    root's own config) that carries the owner's private AI docs between machines
#                    for projects switched with `sync-ai-templates.ps1 -PrivateLayer`: written to
#                    <root>\.ai-context-remote. <root>=<url> when the part before the first = is an
#                    existing folder; else the URL is for the root holding this repo, refused when
#                    that root is a work root (name it). A github.com URL is refused for a work
#                    root. `none` keeps the docs in each project's local hidden repo only.
#                    ~\.ai-context-remote is no longer written (the engine still reads it outside
#                    a work root).
#   -WorkRoot <name>|<path>
#                    mark a code root as a work root, whose private AI docs never reach a personal
#                    remote: appended to ~\.ai-work-roots (one per line) unless already listed. A
#                    name without / matches that folder anywhere in a path (any case); an absolute
#                    path matches that folder and below. $env:AI_WORK_ROOTS (';' between entries;
#                    none = no work roots) replaces the file; a root whose
#                    .ai-root\environment.json has the label work is one as well. Repeatable.
#   -ClaudeProfile <root>[=<config-dir>|none]
#                    define that code root's Claude Code profile (below): writes and commits
#                    <root>\.ai-root\claude-profile.json — its config dir (default: the one it
#                    has, else ~/.claude-<root name, lower case>), or none to remove it. Repeatable.
#   -ClaudeEnv <root>=<NAME>=<value>
#                    an environment variable of that profile's sessions (e.g. the work gateway's
#                    ANTHROPIC_BASE_URL); an empty value removes it. Refused when it looks like a
#                    secret (the file is committed): an apiKeyHelper or /login. Repeatable.
#                    Both are engine\claude-profile-define.py, run before anything else is
#                    written; the profiles are then installed in the same run.
#   (--copy / --overlay <dir> / --apps-config-dir <dir> / --ai-context-remote <url> /
#   --claude-profile <arg> / --claude-env <arg> / --work-root <arg> spellings are accepted too.)
#
# Claude Code profiles: every code root (this one and its siblings) whose .ai-root holds
# claude-profile.json gets its own config dir, ~/.claude-profiles records it, and a managed
# `claude` function in the shell profiles picks it by folder (Install-ClaudeProfiles in the
# engine) — e.g. the work account beside the personal one, both at once.
#
# Root repo: for the root holding this repo and the one -AiContextRemote names, a missing
# <root>\.ai-root is cloned from branch _root of that root's remote (bounded; a failure is one
# line and the install carries on). An existing .ai-root is left alone.

[CmdletBinding(PositionalBinding = $false)]
param([switch]$Copy, [string]$Overlay, [string]$AppsConfigDir, [string]$AiContextRemote, [string[]]$ClaudeProfile, [string[]]$ClaudeEnv, [string[]]$WorkRoot, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

# Windows PowerShell 5.1 (all a fresh Windows has) cannot run this script: hand over to pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  $fwd = @(foreach ($k in $PSBoundParameters.Keys) { $v = $PSBoundParameters[$k]; if ($k -eq 'Rest') { $v } elseif ($k -in 'ClaudeProfile', 'ClaudeEnv') { foreach ($x in $v) { '--claude-' + $k.Substring(6).ToLower(); $x } } elseif ($k -eq 'WorkRoot') { foreach ($x in $v) { '--work-root'; $x } } elseif ($v -is [switch]) { if ($v) { "-$k" } } else { "-$k"; $v } })
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Write-Host "Error: this script needs PowerShell 7 (this is Windows PowerShell $($PSVersionTable.PSVersion)). Install it with ``winget install --id Microsoft.PowerShell -e``, open a new terminal and run it again."; exit 1 }
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd; exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSScriptRoot   # the template repo (this file is in engine\)
$claudeDefine = @()
foreach ($a in $ClaudeProfile) { $claudeDefine += @('--profile', $a) }
foreach ($a in $ClaudeEnv) { $claudeDefine += @('--env', $a) }
$workRoots = @($WorkRoot | Where-Object { $null -ne $_ })

# --copy / --overlay <dir> spellings (the bash twin's), on top of the native -Copy / -Overlay.
for ($i = 0; $i -lt $Rest.Count; $i++) {
  switch -Regex ($Rest[$i]) {
    '^(-h|--help)$' {
      foreach ($line in @(Get-Content -LiteralPath $PSCommandPath)) { if ($line -notmatch '^#') { break }; $line -replace '^# ?', '' }
      exit 0
    }
    '^--copy$'    { $Copy = $true; break }
    '^--overlay$' {
      if ($i + 1 -ge $Rest.Count) { $host.UI.WriteErrorLine('--overlay needs a directory: aicf setup --overlay <dir>'); exit 2 }
      $i++; $Overlay = $Rest[$i]; break
    }
    '^--apps-config-dir$' {
      if ($i + 1 -ge $Rest.Count) { $host.UI.WriteErrorLine('--apps-config-dir needs a directory: aicf setup --apps-config-dir <dir>'); exit 2 }
      $i++; $AppsConfigDir = $Rest[$i]; break
    }
    '^--ai-context-remote$' {
      if ($i + 1 -ge $Rest.Count) { $host.UI.WriteErrorLine('--ai-context-remote needs a git URL (or none): aicf setup --ai-context-remote <url>'); exit 2 }
      $i++; $AiContextRemote = $Rest[$i]; break
    }
    '^--claude-(profile|env)$' {
      if ($i + 1 -ge $Rest.Count) { $host.UI.WriteErrorLine("$($Rest[$i]) needs a value: --claude-profile <root>[=<config-dir>|none] / --claude-env <root>=<NAME>=<value>"); exit 2 }
      $claudeDefine += @("--$($Matches[1])", $Rest[$i + 1]); $i++; break
    }
    '^--claude-(profile|env)=(.*)$' { $claudeDefine += @("--$($Matches[1])", $Matches[2]); break }
    '^--work-root$' {
      if ($i + 1 -ge $Rest.Count) { $host.UI.WriteErrorLine('Error: --work-root needs a folder name or an absolute path'); exit 2 }
      $i++; $workRoots += $Rest[$i]; break
    }
    '^--work-root=(.*)$' { $workRoots += $Matches[1]; break }
    default       { $host.UI.WriteErrorLine("Unknown option: $($Rest[$i]) (usage: aicf setup [-Copy] [-Overlay <dir>] [-AppsConfigDir <dir>] [-AiContextRemote <url>|<root>=<url>] [-ClaudeProfile <root>[=<config-dir>|none]] [-ClaudeEnv <root>=<NAME>=<value>] [-WorkRoot <name>|<path>])"); exit 2 }
  }
}
foreach ($w in $workRoots) {
  if (-not $w.Trim()) { $host.UI.WriteErrorLine('Error: --work-root needs a folder name or an absolute path'); exit 2 }
}

# Personal app settings folder (apps-config skill): must exist; recorded on disk further down.
$appsConfigPath = ''
if ($AppsConfigDir) {
  if (-not (Test-Path -LiteralPath $AppsConfigDir -PathType Container)) {
    $host.UI.WriteErrorLine("Apps config directory not found: $AppsConfigDir - create it (or let your sync client download it) first.")
    exit 2
  }
  $appsConfigPath = (Resolve-Path -LiteralPath $AppsConfigDir).Path
}

# Overlay repo: must exist; published to the engine BEFORE it is dot-sourced, so the skills refresh
# in this very run already layers the overlay's skills. Recorded on disk further down.
$overlayPath = ''
if ($Overlay) {
  if (-not (Test-Path -LiteralPath $Overlay -PathType Container)) {
    $host.UI.WriteErrorLine("Overlay directory not found: $Overlay")
    $host.UI.WriteErrorLine('Clone your private overlay repo first, then re-run: aicf setup -Overlay <path-to-that-clone>')
    exit 2
  }
  $overlayPath = (Resolve-Path -LiteralPath $Overlay).Path
  $env:AI_TEMPLATE_OVERLAY_DIR = $overlayPath
}
$src = Join-Path $scriptDir 'engine'
# The code root is simply the folder holding this repo — F:\Code on the Windows boxes, ~/Code on
# macOS, D:\Dev anywhere else. Never assume $env:USERPROFILE\Code: it is wrong on any machine
# whose projects live off the home volume. Sibling program repos (your own
# tools) hang off this, and it is published to agents as $AI_CODE_ROOT below.
$codeRoot = Split-Path -Parent $scriptDir

if ($Copy) { $env:AI_SKILLS_MODE = 'copy' }
. (Join-Path $scriptDir 'sync-ai-templates.ps1')

# -AiContextRemote: checked before anything is written.
$rootRemote = $null
if ($AiContextRemote) {
  $rootRemote = Resolve-RootRemote $AiContextRemote $codeRoot
  if ($null -eq $rootRemote) { exit 2 }
}
# -ClaudeProfile / -ClaudeEnv: every argument checked now; each root's profile file is written and
# committed once its .ai-root is cloned (below), and Install-ClaudeProfiles installs it.
if ($claudeDefine.Count -gt 0) {
  $py = @()
  foreach ($c in 'python3', 'python') {
    if (-not (Get-Command $c -CommandType Application -ErrorAction SilentlyContinue)) { continue }
    try { & $c -c 'import sys' 2>$null | Out-Null } catch { continue }
    if ($LASTEXITCODE -eq 0) { $py = @($c); break }
  }
  if ($py.Count -eq 0 -and (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue)) { $py = @('uv', 'run', '--quiet', '--no-project') }
  if ($py.Count -eq 0) { $host.UI.WriteErrorLine('-ClaudeProfile / -ClaudeEnv need python3 (or uv)'); exit 2 }
  $pyArgs = @()
  if ($py.Count -gt 1) { $pyArgs += $py[1..($py.Count - 1)] }
  $pyArgs += Join-Path $src 'claude-profile-define.py'
  & $py[0] @pyArgs --check @claudeDefine
  if ($LASTEXITCODE -ne 0) { exit 2 }
}

# Detect VS Code user folder (Windows uses %APPDATA%)
$base = $env:APPDATA
if (-not $base) { throw 'APPDATA not set. On macOS/Linux use bin/aicf setup instead.' }

$destDir = Join-Path $base 'Code\User\prompts'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# Overlay-aware like every manifest entry: the base file wins, else the overlay's, then its .append.
$bootstrapFile = Join-Path $destDir 'ai-autobootstrap.instructions.md'
Write-OverlayLayoutNote
[IO.File]::WriteAllBytes($bootstrapFile, (Get-RenderedBytes 'templates/global/ai-autobootstrap.instructions.md'))

# Personal skills — SKILL.md / Agent Skills format (agentskills.io open standard) read by
# Copilot CLI (~/.copilot/skills/ and the standard ~/.agents/skills/), Claude Code
# (~/.claude/skills/), Cursor 2.4+ (~/.cursor/skills/), Google Antigravity
# (~/.gemini/config/skills/), and Codex (~/.agents/skills/). Every folder under
# skills\ is installed — no list to maintain. Plain copies on Windows (no
# Developer Mode needed); the session-start sync refreshes them whenever the template changes.
foreach ($root in $SkillRoots) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
Sync-GlobalSkills

# Gemini CLI uses a different format (TOML custom command) — delegate to the same
# SKILL.md instead of duplicating its content, so there's still one source of truth.
$geminiCmdDest = Join-Path $env:USERPROFILE '.gemini\commands'
New-Item -ItemType Directory -Force -Path $geminiCmdDest | Out-Null
$skillPath = ($scriptDir + '\skills\bootstrap-ai\SKILL.md') -replace '\\', '/'
@"
description = "Bootstrap or refresh this project's AI instructions from my canonical template."
prompt = """
Read and follow the instructions in $skillPath
exactly, then execute them for the current project. If that path doesn't exist, clone
https://github.com/neijix/AICodeFactory.git into a temp dir first and use
SKILL.md from there instead.
"""
"@ | Set-Content (Join-Path $geminiCmdDest 'bootstrap-ai.toml')

# GitHub Copilot CLI (the "Copilot CLI" harness in VS Code's Agents window) is a
# separate tool from the Copilot Chat extension above - it reads its own config
# from ~/.copilot/, not from VS Code's User folder. Wire it up too.
$copilotHome = Join-Path $env:USERPROFILE '.copilot'
New-Item -ItemType Directory -Force -Path $copilotHome | Out-Null

# Global instructions: same auto-bootstrap rules, minus the VS Code-only YAML
# frontmatter (Copilot CLI's personal instructions file is plain Markdown).
$copilotInstructionsDest = Join-Path $copilotHome 'copilot-instructions.md'
$marker = 'Global AI Behavior — Auto-Bootstrap Every Project'
$sourceLines = Get-Content $bootstrapFile   # the rendered copy (overlay included)
$dashCount = 0
$bodyLines = foreach ($line in $sourceLines) {
  if ($line -eq '---' -and $dashCount -lt 2) { $dashCount++; continue }
  if ($dashCount -lt 2) { continue }
  $line
}
$bootstrapBody = ($bodyLines -join "`n").TrimEnd() + "`n"
# Refresh the managed auto-bootstrap block on every install so edits to
# ai-autobootstrap.instructions.md actually propagate. Keep any user text
# that appears *before* the managed H1; replace from that H1 through EOF.
if ((Test-Path $copilotInstructionsDest) -and (Select-String -Path $copilotInstructionsDest -SimpleMatch $marker -Quiet)) {
  $text = Get-Content -Raw $copilotInstructionsDest
  $idx = $text.IndexOf($marker)
  $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $idx - 1))
  $prefix = if ($lineStart -ge 0) { $text.Substring(0, $lineStart + 1) } else { '' }
  if ($prefix.EndsWith("`n`n")) { $prefix = $prefix.Substring(0, $prefix.Length - 1) }
  Set-Content -Path $copilotInstructionsDest -Value ($prefix + $bootstrapBody) -NoNewline
  Write-Host "Refreshed managed auto-bootstrap block: $copilotInstructionsDest"
} elseif (Test-Path $copilotInstructionsDest) {
  Add-Content -Path $copilotInstructionsDest -Value ("`n" + $bootstrapBody)
  Write-Host "Appended auto-bootstrap rules to existing: $copilotInstructionsDest"
} else {
  Set-Content -Path $copilotInstructionsDest -Value $bootstrapBody -NoNewline
  Write-Host "Installed global Copilot CLI instructions: $copilotInstructionsDest"
}

# Machine-local marker: where this repo lives on THIS machine. The SessionStart hook reads it as
# its last-resort candidate, so a project under a second root (e.g. F:\WorkCode\proj beside
# F:\Code\AICodeFactory) still finds the templates. It lives in the user profile, outside every
# repo, so it is never committed and never travels between machines — which is the whole point.
# Written LF-terminated with no BOM: the hook `cat`s it from Git Bash.
$markerPath = Join-Path $env:USERPROFILE '.ai-template-dir'
[IO.File]::WriteAllText($markerPath, "$scriptDir`n")
Write-Host "Recorded this machine's template dir: $markerPath -> $scriptDir"

# Same idea for the overlay (only when -Overlay was given: an existing marker is never touched).
# The engine reads this file as its second candidate, after AI_TEMPLATE_OVERLAY_DIR.
if ($overlayPath) {
  $overlayMarkerPath = Join-Path $env:USERPROFILE '.ai-template-overlay-dir'
  [IO.File]::WriteAllText($overlayMarkerPath, "$overlayPath`n")
  Write-Host "Recorded this machine's overlay dir: $overlayMarkerPath -> $overlayPath"
}
# The owner's personal app settings (apps-config skill): also in the user profile, never in a repo,
# so a friend who clones an app gets its local defaults and nothing personal. LF, no BOM.
$appsMarkerPath = Join-Path $env:USERPROFILE '.apps-config-dir'
if ($appsConfigPath) {
  [IO.File]::WriteAllText($appsMarkerPath, "$appsConfigPath`n")
  Write-Host "Recorded this machine's apps config dir: $appsMarkerPath -> $appsConfigPath"
}
# Where a root's private AI docs travel between machines (sync-ai-templates.ps1 -PrivateLayer):
# <root>\.ai-context-remote, outside every project repo.
Write-RootRemote $rootRemote
# Work roots (engine\work-roots.ps1): each -WorkRoot entry goes to ~\.ai-work-roots (LF, no BOM),
# once - an entry already listed (same text, any case, spaces trimmed) is not added again.
$workFile = Join-Path $HOME '.ai-work-roots'
foreach ($w in $workRoots) {
  $w = $w.Trim()
  $have = @(if (Test-Path -LiteralPath $workFile -PathType Leaf) { [IO.File]::ReadAllLines($workFile) | ForEach-Object { $_.Trim() } })
  if ($have -contains $w) { Write-Host "Work root already recorded: $w ($workFile)"; continue }
  $pre = ''
  if ((Test-Path -LiteralPath $workFile -PathType Leaf) -and (Get-Item -LiteralPath $workFile).Length -gt 0) {
    [byte[]]$b = [IO.File]::ReadAllBytes($workFile); if ($b[$b.Length - 1] -ne 10) { $pre = "`n" }
  }
  [IO.File]::AppendAllText($workFile, "$pre$w`n")
  Write-Host "Recorded a work root: $workFile += $w"
}
# The root repo (.ai-root: registry, dev-context, private terms) of each known root, when missing.
Reset-NetBudget
Copy-AiRoot $codeRoot
if ($null -ne $rootRemote -and -not (Test-SamePath $rootRemote.Dir $codeRoot)) { Copy-AiRoot $rootRemote.Dir }
if ($claudeDefine.Count -gt 0) {
  & $py[0] @pyArgs --code-root $codeRoot @claudeDefine
  if ($LASTEXITCODE -ne 0) { exit 2 }
}

# No MCP server anywhere (endpoint-security tools flag them): own tools (`mlx-local`,
# `d3skwebscout`, `bw-auto`) are shell commands agents run through their shell tool, behind skills
# from your overlay. Earlier versions of this script registered `mlx-local` and the third-party
# `bitwarden` server in every harness, and `d3skwebscout` was registered by hand: delete those
# stale entries, keeping a `<file>.bak` of each file it changes. A file without those entries is
# never rewritten, so re-running is a no-op.
$mlxDir = Join-Path $codeRoot 'MLX_Local'
if ((Test-Path $mlxDir) -and -not (Get-Command mlx-local -ErrorAction SilentlyContinue) -and
    -not (Test-Path (Join-Path $HOME '.local/bin/mlx-local'))) {
  Write-Host "NOTE: mlx-local is not on PATH - run $mlxDir/start.command once (it links ~/.local/bin/mlx-local)."
}
function Read-JsonConfig($path) {
  try {
    $raw = Get-Content $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    $data = $raw | ConvertFrom-Json -AsHashtable
  } catch { Write-Host "  skipped (unparseable JSON): $path"; return $null }
  if ($data -isnot [System.Collections.IDictionary]) { Write-Host "  skipped (JSON root not an object): $path"; return $null }
  return $data
}

function Upsert-ConfigEntry($path, $key, $name, $entry, $create) {
  if (-not (Test-Path $path)) {
    if (-not $create) { return }
    $parent = Split-Path -Parent $path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $data = @{}
  } else {
    $data = Read-JsonConfig $path
    if ($null -eq $data) { return }
  }
  if (-not $data.ContainsKey($key) -or $null -eq $data[$key]) { $data[$key] = @{} }
  $prev = $null
  if ($data[$key].ContainsKey($name)) { $prev = $data[$key][$name] }
  # Match the bash twin: leave the file untouched when the entry is already correct, so re-running
  # this script does not rewrite the user's own config files.
  if ($null -ne $prev -and
      (($prev | ConvertTo-Json -Depth 20 -Compress) -eq ($entry | ConvertTo-Json -Depth 20 -Compress))) {
    Write-Host "  $name up to date: $path"
    return
  }
  $data[$key][$name] = $entry
  ($data | ConvertTo-Json -Depth 20) | Set-Content -Path $path -Encoding utf8
  if ($null -ne $prev) { Write-Host "  refreshed $name`: $path" }
  else { Write-Host "  registered $name`: $path" }
}

$staleMcp = @('mlx-local', 'd3skwebscout', 'bitwarden')
function Remove-StaleMcpEntries($path) {
  if (-not (Test-Path $path)) { return }
  $data = Read-JsonConfig $path
  if ($null -eq $data) { return }
  # Top-level "mcpServers" (Claude, Cursor, Gemini, Copilot CLI) / "servers" (VS Code), plus
  # Claude Code's local-scope entries under projects.<path>.mcpServers in ~/.claude.json.
  $containers = @($data['mcpServers'], $data['servers'])
  if ($data['projects'] -is [System.Collections.IDictionary]) {
    foreach ($proj in $data['projects'].Values) {
      if ($proj -is [System.Collections.IDictionary]) { $containers += , $proj['mcpServers'] }
    }
  }
  $removed = @()
  foreach ($cont in $containers) {
    if ($cont -isnot [System.Collections.IDictionary]) { continue }
    foreach ($name in $staleMcp) {
      if ($cont.Contains($name)) { $cont.Remove($name); $removed += $name }
    }
  }
  if ($removed.Count -eq 0) { return }
  Copy-Item -LiteralPath $path -Destination "$path.bak" -Force
  ($data | ConvertTo-Json -Depth 50) | Set-Content -Path $path -Encoding utf8
  Write-Host "  removed stale MCP $((($removed | Sort-Object -Unique) -join ', ')): $path (backup: $path.bak)"
}

foreach ($cfg in @(
    (Join-Path $base 'Code\User\mcp.json'),
    (Join-Path $copilotHome 'mcp-config.json'),
    (Join-Path $env:USERPROFILE '.cursor\mcp.json'),
    (Join-Path $env:USERPROFILE '.claude.json'),
    (Join-Path $env:USERPROFILE '.gemini\antigravity\mcp_config.json'),
    (Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json'),
    (Join-Path $env:USERPROFILE '.gemini\settings.json'))) {
  Remove-StaleMcpEntries $cfg
}

# Machine-local paths, published to agents as env vars. This is Claude Code's USER settings file
# (~/.claude/settings.json) — outside every repo, so these absolute paths never get committed and
# never travel to another machine. AI_TEMPLATE_DIR is the hook's first candidate; AI_CODE_ROOT is
# what skills use instead of a hardcoded ~/Code when they reach for a sibling program repo.
$claudeSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
Upsert-ConfigEntry $claudeSettings 'env' 'AI_TEMPLATE_DIR' $scriptDir $true
Upsert-ConfigEntry $claudeSettings 'env' 'AI_CODE_ROOT' $codeRoot $true
# AI_TEMPLATE_OVERLAY_DIR is the engine's first overlay candidate; only written when -Overlay was
# given, so re-running without it keeps whatever this machine already had.
if ($overlayPath) { Upsert-ConfigEntry $claudeSettings 'env' 'AI_TEMPLATE_OVERLAY_DIR' $overlayPath $true }
# The global SessionStart hook (see the header): a fresh clone of a private project has no
# .claude\settings.json yet, so only this one can restore its private layer at session start.
Install-ClaudeGlobalHook $claudeSettings
# Claude Code profiles (a code root's .ai-root\claude-profile.json, read after the clone above): a
# separate config dir per declaring root, chosen by the `claude` PowerShell function. See the
# engine's Install-ClaudeProfiles; the second refresh only fills the profiles' skills dirs.
Install-ClaudeProfiles $codeRoot
Sync-GlobalSkills

$skillList = (Get-ChildItem -Path (Join-Path $scriptDir 'skills') -Directory | ForEach-Object { $_.Name }) -join ','
Write-Host "Installed global customizations to:"
Write-Host "  $destDir\ai-autobootstrap.instructions.md  (VS Code / Copilot auto-bootstrap trigger)"
Write-Host "  ~\.agents\skills\{$skillList}  (open-standard shared dir - Copilot CLI, Codex)"
Write-Host "  ~\.copilot\skills\{...}  (Copilot)   ~\.claude\skills\{...}  (Claude Code)"
Write-Host "  ~\.cursor\skills\{...}  (Cursor)     ~\.gemini\config\skills\{...}  (Google Antigravity)"
if ($SkillMode -eq 'link') {
  Write-Host "  (symlinks into skills\ - edits there apply everywhere immediately)"
} else {
  Write-Host "  (plain copies - refreshed by every project's session-start sync, or re-run this script)"
}
Write-Host "  $geminiCmdDest\bootstrap-ai.toml  (Gemini CLI - type /bootstrap-ai)"
Write-Host "  $copilotInstructionsDest  (Copilot CLI / VS Code Agents window)"
Write-Host "  stale mlx-local / d3skwebscout / bitwarden MCP entries removed from VS Code / Copilot CLI / Cursor / Claude / Gemini configs (no MCP server anywhere)"
# $OverlayDir comes from the dot-sourced engine: the overlay it actually resolved this run (the one
# just given, or one already configured on this machine), or '' when there is none.
if ($OverlayDir) { Write-Host "  overlay: $OverlayDir  (layered on every sync; skills above include its skills\)" }
else { Write-Host "  overlay: none  (add one with aicf setup -Overlay <dir>)" }
if ((Test-Path -LiteralPath $appsMarkerPath) -and (Get-Content -LiteralPath $appsMarkerPath -TotalCount 1)) {
  Write-Host "  apps config: $(Get-Content -LiteralPath $appsMarkerPath -TotalCount 1)  (personal app settings, apps-config skill)"
} else { Write-Host "  apps config: none  (aicf setup -AppsConfigDir <dir> to keep app settings in one folder)" }
Write-Host "  ~\.claude\settings.json  (global SessionStart hook: sync-ai-templates.sh --global-hook)"
$profRec = Join-Path $HOME '.claude-profiles'
if ((Test-Path -LiteralPath $profRec) -and (Get-Content -LiteralPath $profRec -TotalCount 1)) {
  Write-Host "  Claude Code profiles: $((Get-Content -LiteralPath $profRec | ForEach-Object { ($_ -split "`t", 2)[1] }) -join ' ')  (``claude`` in a root with a profile uses it - open a new terminal)"
} else { Write-Host "  Claude Code profiles: none  (aicf setup -ClaudeProfile <root> to give a code root its own)" }
$aicMarkerPath = Join-Path $codeRoot '.ai-context-remote'
if ((Test-Path -LiteralPath $aicMarkerPath) -and (Get-Content -LiteralPath $aicMarkerPath -TotalCount 1)) {
  Write-Host "  private AI docs remote of $codeRoot`: $(Get-Content -LiteralPath $aicMarkerPath -TotalCount 1)  (projects switched with -PrivateLayer)"
} else { Write-Host "  private AI docs remote of $codeRoot`: none  (aicf setup -AiContextRemote <url> to share them between machines)" }
Write-Host ""
Write-Host "Next: reload VS Code and Cursor (Developer: Reload Window). Claude Code / Gemini pick up"
Write-Host "new skills in any new session."
Write-Host "Ensure these VS Code user settings are enabled:"
Write-Host '  "chat.promptFiles": true'
Write-Host '  "github.copilot.chat.codeGeneration.useInstructionFiles": true'
