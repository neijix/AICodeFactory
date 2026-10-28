# doctor.ps1 — PowerShell twin of doctor.sh (identical behavior). One command, safe to run at any
# time, that checks this machine's whole AI setup and, with --yes, puts it right. It holds no logic
# of its own beyond the checks: every fix is the existing scripts (install-global, sync-ai-templates,
# update-projects), run in the right order.
#
# Usage: aicf doctor [--yes] [--clone] [--push] [--copy] | --json   (-Yes / -Clone / -Push / -Copy / -Json too)
#   (no flag)  check only — one line per item, nothing written, no network:
#                OK    as it should be
#                FIX   wrong, and `aicf doctor --yes` puts it right
#                TODO  wrong, and only you can put it right (the line says how)
#                WARN  worth knowing, nothing to fix (unpushed commits, optional tools…)
#   --yes      fix, in this order: fast-forward this repo (+ overlay; re-runs itself when it moved)
#              and the code root's .ai-root, re-run install-global (skills, markers, global hook,
#              Claude env, stale MCP entries), re-sync this repo's pointer copies, switch the
#              projects that miss the private-layer plan (update-projects -Migrate -Yes), refresh
#              every bootstrapped sibling (update-projects -Yes -Pull), then check again
#   --clone    with --yes: also clone your GitHub repos that have no local folder (needs gh)
#   --push     with --yes: also push the sync commits (never done otherwise)
#   --copy     with --yes: install skills as copies (install-global -Copy; Windows always copies)
#   --json     the check-only pass as one JSON document on stdout (schema 1: ok, counts, checks,
#              projects, unsynced) for a UI to read; alone — not with --yes/--clone/--push/--copy (exit 2)
#
# Run it from the main checkout: in a linked worktree --yes refuses (install-global would point
# this machine at the worktree).
# Exit status: 0 when nothing is FIX or TODO (WARN lines allowed), 1 otherwise, 2 on bad usage.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)

# Windows PowerShell 5.1 (all a fresh Windows has) cannot run this script: hand over to pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  $fwd = @(foreach ($k in $PSBoundParameters.Keys) { $v = $PSBoundParameters[$k]; if ($k -eq 'Rest') { $v } elseif ($v -is [switch]) { if ($v) { "-$k" } } else { "-$k"; $v } })
  if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) { Write-Host "Error: this script needs PowerShell 7 (this is Windows PowerShell $($PSVersionTable.PSVersion)). Install it with ``winget install --id Microsoft.PowerShell -e``, open a new terminal and run it again."; exit 1 }
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd; exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

$Yes = $false
$Clone = $false
$Push = $false
$Copy = $false
$Json = $false
$TemplatePulled = $false   # --template-pulled: internal, set by the re-run after this repo moved
$Rerun = @()
foreach ($arg in @($Rest | Where-Object { $null -ne $_ })) {
  switch -Regex ($arg) {
    '^-(-yes|Yes)$' { $Yes = $true; break }
    '^-(-clone|Clone)$' { $Clone = $true; break }
    '^-(-push|Push)$' { $Push = $true; break }
    '^-(-copy|Copy)$' { $Copy = $true; break }
    '^-(-json|Json)$' { $Json = $true; break }
    '^-(-template-pulled|TemplatePulled)$' { $TemplatePulled = $true; break }
    '^(-h|--help|-Help)$' {
      foreach ($line in @(Get-Content -LiteralPath $PSCommandPath)) {
        if ($line -notmatch '^#') { break }
        $line -replace '^# ?', ''
      }
      exit 0
    }
    default { $host.UI.WriteErrorLine("Unknown option: $arg (usage: aicf doctor [--yes] [--clone] [--push] [--copy] | --json)"); exit 2 }
  }
  if ($arg -notmatch '^-(-template-pulled|TemplatePulled)$') { $Rerun += $arg }
}
if ($Json -and ($Yes -or $Clone -or $Push -or $Copy)) {
  $host.UI.WriteErrorLine('Error: --json only reports; it cannot be combined with --yes, --clone, --push or --copy.')
  exit 2
}

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'sync-ai-templates.ps1')   # this file is in engine\

$CodeRoot = Split-Path -Parent $TemplateDir
$VsCodeUser = if ($env:APPDATA) { Join-Path $env:APPDATA 'Code\User' } else { Join-Path $HOME '.config/Code/User' }
$Pwsh = (Get-Process -Id $PID).Path
# A linked worktree has a .git FILE; install-global run from one would repoint this machine at it.
$LinkedWorktree = Test-Path -LiteralPath (Join-Path $TemplateDir '.git') -PathType Leaf

$script:NFix = 0
$script:NTodo = 0
$script:NWarn = 0
$script:NOk = 0
# --json: Write-Row records instead of printing; Write-Section names the group the next rows belong to.
$script:Section = ''
$script:Checks = [System.Collections.Generic.List[object]]::new()
$script:Projects = [System.Collections.Generic.List[object]]::new()

# The "== heading" line, or (--json) the section of the rows that follow.
function Write-Section([string]$Heading) {
  if ($Json) { $script:Section = $Heading } else { Write-Host "== $Heading" }
}

# One report line, counted.
function Write-Row([string]$Status, [string]$What, [string]$Hint = '') {
  if ($Json) {
    $script:Checks.Add([ordered]@{ section = $script:Section; status = $Status; what = $What; hint = $Hint })
  } else {
    Write-Host ('{0,-6}{1}' -f $Status, $What)
    if ($Hint) { Write-Host "      -> $Hint" }
  }
  switch ($Status) {
    'OK' { $script:NOk++ }
    'FIX' { $script:NFix++ }
    'TODO' { $script:NTodo++ }
    'WARN' { $script:NWarn++ }
  }
}

# "a, b, c", at most 8 names then "…".
function Join-Names([string[]]$Names) {
  $list = @($Names)
  if ($list.Count -le 8) { return ($list -join ', ') }
  return (($list[0..7] -join ', ') + ', …')
}

# The interpreter the AGENTS.md refresh would use: a python that runs, else uv's. '' when none.
function Get-DoctorPython {
  foreach ($c in 'python3', 'python') {
    if (-not (Get-Command $c -CommandType Application -ErrorAction SilentlyContinue)) { continue }
    try { & $c -c 'import sys' 2>$null | Out-Null } catch { continue }
    if ($LASTEXITCODE -eq 0) { return $c }
  }
  if (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue) {
    $env:NO_COLOR = '1'
    try { $p = (& uv python find 2>$null | Select-Object -First 1) } catch { $p = '' }
    $p = ("$p" -replace "`e\[[0-9;]*m", '').Trim()
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
  }
  return ''
}

function Read-JsonFile([string]$Path) {
  # @{ Data = hashtable or $null; Err = '' | 'missing' | 'unparseable' | 'not an object' }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @{ Data = $null; Err = 'missing' } }
  try {
    $raw = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{ Data = @{}; Err = '' } }
    $data = $raw | ConvertFrom-Json -AsHashtable
  } catch { return @{ Data = $null; Err = 'unparseable' } }
  if ($data -isnot [System.Collections.IDictionary]) { return @{ Data = $null; Err = 'not an object' } }
  return @{ Data = $data; Err = '' }
}

function Test-Tools {
  Write-Section 'Tools'
  $py = Get-DoctorPython
  if ($py) { Write-Row OK "python ($py)" }
  else { Write-Row TODO 'python not found' 'install Python 3 or uv: the settings merges and the AGENTS.md refresh need it' }
  if (Get-Command uv -ErrorAction SilentlyContinue) { Write-Row OK 'uv' }
  else { Write-Row WARN 'uv not found' 'optional: skills'' scripts prefer uv run (https://docs.astral.sh/uv/)' }
  if (Get-Command dotnet -ErrorAction SilentlyContinue) { Write-Row OK 'dotnet' }
  else { Write-Row WARN 'dotnet not found' 'optional: project tools in C# need the .NET 10 SDK (csharp-tools skill)' }
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Row WARN 'gh not found' 'optional: --clone and the GitHub skills need it'
  } else {
    $ok = $false
    try { & gh auth token 2>$null | Out-Null; $ok = ($LASTEXITCODE -eq 0) } catch { $ok = $false }
    if ($ok) { Write-Row OK 'gh (authenticated)' }
    else { Write-Row WARN 'gh is not authenticated' 'gh auth login (--clone needs it)' }
  }
}

function Test-TemplateRepo {
  Write-Section "$TemplateName ($TemplateDir)"
  if ($LinkedWorktree) {
    Write-Row TODO 'this is a linked git worktree, not the main checkout' 'run doctor from the main checkout: --yes refuses here'
  }
  $dirty = @(Invoke-Git @('-C', $TemplateDir, 'status', '--porcelain') | Where-Object { $_ })
  if ($dirty.Count -gt 0) { Write-Row WARN 'uncommitted changes' 'commit them: --yes does not pull a dirty tree' }
  else { Write-Row OK 'working tree clean' }
  $ahead = Get-AheadCount $TemplateDir
  switch ("$ahead") {
    { $_ -in '', '0' } { break }
    'no-remote' { Write-Row WARN 'no upstream branch' 'other machines cannot get this repo''s changes'; break }
    default { Write-Row WARN "$ahead commit(s) not on origin" "git -C `"$TemplateDir`" push" }
  }
  $markerSet = (Test-Path -LiteralPath $OverlayMarker -PathType Leaf) -and ((Get-Item -LiteralPath $OverlayMarker -Force).Length -gt 0)
  if ($markerSet -and -not $OverlayDir) {
    $want = ([string](Get-Content -LiteralPath $OverlayMarker -TotalCount 1)).Trim()
    Write-Row TODO "overlay $want not found" 'clone it there, or aicf setup -Overlay <dir>'
  } elseif ($OverlayDir) {
    Write-Row OK "overlay $OverlayDir"
  }
  $changed = @(Get-DryRunChanges $TemplateDir)
  if ($changed.Count -eq 0) { Write-Row OK 'pointer copies match their templates' }
  else { Write-Row FIX "pointer copies differ from their templates: $(Join-Names $changed)" }
}

# The project-relative paths a dry-run sync would touch (nothing printed, never an error).
function Get-DryRunChanges([string]$Dir) {
  $script:SyncChanged = @()
  try { Sync-AiTemplates -Target $Dir -DryRun *> $null } catch { }
  return @($script:SyncChanged)
}

function Test-Machine {
  Write-Section 'This machine (install-global)'
  $markerFile = Join-Path $HOME '.ai-template-dir'
  $marker = ''
  if ((Test-Path -LiteralPath $markerFile -PathType Leaf) -and ((Get-Item -LiteralPath $markerFile -Force).Length -gt 0)) {
    $marker = ([string](Get-Content -LiteralPath $markerFile -TotalCount 1)).Trim()
  }
  if ($marker -and (Test-SamePath $marker $TemplateDir)) { Write-Row OK '~/.ai-template-dir' }
  elseif ($marker) { Write-Row FIX "~/.ai-template-dir points at $marker" }
  else { Write-Row FIX '~/.ai-template-dir is missing' }

  $missing = @($SkillRoots | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) } |
    ForEach-Object { $_.Substring($HOME.Length).TrimStart('\', '/') })
  if ($missing.Count -gt 0) { Write-Row FIX "skills folder(s) missing: $(Join-Names $missing)" }
  $prevQuiet = $script:SyncQuiet
  $script:SyncQuiet = $false
  $plan = @(Sync-GlobalSkills -DryRun 6>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^  \[' })
  $script:SyncQuiet = $prevQuiet
  if ($plan.Count -eq 0) { Write-Row OK "global skills up to date ($SkillMode mode)" }
  else { Write-Row FIX "$($plan.Count) global skill folder(s) out of date ($SkillMode mode)" }

  # What install-global writes: the template plus the overlay's .append (the factory self-check
  # above rendered without the overlay).
  $bootstrap = [IO.Path]::GetTempFileName()
  $prevOverlay = $script:TplOverlay
  $script:TplOverlay = $OverlayDir
  [IO.File]::WriteAllBytes($bootstrap, (Get-RenderedBytes 'templates/global/ai-autobootstrap.instructions.md'))
  $script:TplOverlay = $prevOverlay
  if (Test-SameFile $bootstrap (Join-Path $VsCodeUser 'prompts/ai-autobootstrap.instructions.md')) {
    Write-Row OK 'VS Code auto-bootstrap instructions'
  } else {
    Write-Row FIX 'VS Code auto-bootstrap instructions missing or stale'
  }
  # install-global.ps1 writes the skill path with forward slashes.
  $skillPath = ($TemplateDir + '\skills\bootstrap-ai\SKILL.md') -replace '\\', '/'
  $toml = Join-Path $HOME '.gemini/commands/bootstrap-ai.toml'
  $tomlOk = $false
  if (Test-Path -LiteralPath $toml -PathType Leaf) { $tomlOk = [IO.File]::ReadAllText($toml).Contains($skillPath) }
  if ($tomlOk) { Write-Row OK 'Gemini CLI /bootstrap-ai command' }
  else { Write-Row FIX 'Gemini CLI /bootstrap-ai command missing or stale' }

  $settingsFile = Join-Path $HOME '.claude/settings.json'
  $s = Read-JsonFile $settingsFile
  if ($s.Err -in 'unparseable', 'not an object') {
    Write-Row TODO "~/.claude/settings.json is $($s.Err) JSON" 'fix it by hand: Claude Code and install-global cannot read it'
  } else {
    $data = if ($null -ne $s.Data) { $s.Data } else { @{} }
    $envMap = if ($data['env'] -is [System.Collections.IDictionary]) { $data['env'] } else { @{} }
    foreach ($pair in @(@('AI_TEMPLATE_DIR', $TemplateDir), @('AI_CODE_ROOT', $CodeRoot))) {
      $key = $pair[0]
      if ($envMap.Contains($key) -and "$($envMap[$key])" -eq $pair[1]) { Write-Row OK "Claude env $key" }
      elseif (-not $envMap.Contains($key)) { Write-Row FIX "Claude env $key is missing" }
      else { Write-Row FIX "Claude env $key is $($envMap[$key])" }
    }
    Test-GlobalHookEntry $settingsFile
  }

  $copilot = Join-Path $HOME '.copilot/copilot-instructions.md'
  $dashCount = 0
  $bodyLines = foreach ($line in [IO.File]::ReadAllLines($bootstrap)) {
    if ($line.Trim() -eq '---' -and $dashCount -lt 2) { $dashCount++; continue }
    if ($dashCount -lt 2) { continue }
    $line
  }
  $body = ($bodyLines -join "`n").TrimEnd() + "`n"
  Remove-Item -LiteralPath $bootstrap -ErrorAction SilentlyContinue
  $text = ''
  if (Test-Path -LiteralPath $copilot -PathType Leaf) { $text = [IO.File]::ReadAllText($copilot) -replace "`r`n", "`n" }
  # Add-Content (the append case) ends the file with one more newline.
  if ($text.EndsWith($body) -or $text.EndsWith($body + "`n")) { Write-Row OK 'Copilot CLI auto-bootstrap instructions' }
  else { Write-Row FIX 'Copilot CLI auto-bootstrap instructions missing or stale' }

  $stale = @('mlx-local', 'd3skwebscout', 'bitwarden')
  $found = @()
  foreach ($path in @(
      (Join-Path $VsCodeUser 'mcp.json'),
      (Join-Path $HOME '.copilot/mcp-config.json'),
      (Join-Path $HOME '.cursor/mcp.json'),
      (Join-Path $HOME '.claude.json'),
      (Join-Path $HOME '.gemini/antigravity/mcp_config.json'),
      (Join-Path $HOME '.gemini/config/mcp_config.json'),
      (Join-Path $HOME '.gemini/settings.json'))) {
    $d = (Read-JsonFile $path).Data
    if ($null -eq $d) { continue }
    $conts = @($d['mcpServers'], $d['servers'])
    if ($d['projects'] -is [System.Collections.IDictionary]) {
      foreach ($p in $d['projects'].Values) { if ($p -is [System.Collections.IDictionary]) { $conts += , $p['mcpServers'] } }
    }
    $hit = $false
    foreach ($c in $conts) {
      if ($c -isnot [System.Collections.IDictionary]) { continue }
      foreach ($n in $stale) { if ($c.Contains($n)) { $hit = $true } }
    }
    if ($hit) { $found += (Split-Path -Leaf $path) }
  }
  if ($found.Count -gt 0) { Write-Row FIX "stale MCP entries (mlx-local / d3skwebscout / bitwarden) in $($found -join ', ')" }
  else { Write-Row OK 'no stale MCP server entries' }

  $remote = ''
  $remoteFile = Join-Path $CodeRoot '.ai-context-remote'
  if ((Test-Path -LiteralPath $remoteFile -PathType Leaf) -and ((Get-Item -LiteralPath $remoteFile -Force).Length -gt 0)) {
    $remote = ([string](Get-Content -LiteralPath $remoteFile -TotalCount 1)).Trim()
  }
  $air = Join-Path $CodeRoot '.ai-root'
  if (Test-Path -LiteralPath (Join-Path $air '.git')) {
    $airDirty = @(Invoke-Git @('-C', $air, 'status', '--porcelain') | Where-Object { $_ })
    if ($airDirty.Count -gt 0) {
      Write-Row WARN '.ai-root has uncommitted changes' "commit them in $air`: the sync never pulls a dirty registry"
    } else {
      Write-Row OK '.ai-root (project registry)'
    }
  } elseif ($remote -and $remote -ne 'none') {
    Write-Row FIX ".ai-root missing (cloned from $remote)"
  } else {
    Write-Row WARN "no .ai-root and no private AI docs remote for $CodeRoot" `
      'aicf setup -AiContextRemote <url> to carry private AI docs between machines'
  }
}

# The global SessionStart hook: exactly one --global-hook entry, equal to claude-global-hook.json.
function Test-GlobalHookEntry([string]$SettingsFile) {
  $J = [System.Text.Json.Nodes.JsonNode]
  # Assign inside the branch, never `$node = if (...)`: a statement's output is enumerated, and a
  # JsonObject would come back as an array of its key/value pairs.
  $node = $null
  try {
    $entry = $J::Parse([IO.File]::ReadAllText((Join-Path $TemplateDir 'templates/global/claude-global-hook.json')))
    if (Test-Path -LiteralPath $SettingsFile -PathType Leaf) { $node = $J::Parse([IO.File]::ReadAllText($SettingsFile)) }
  } catch { $node = $null }
  $ours = @()
  if ($node -is [System.Text.Json.Nodes.JsonObject] -and $node['hooks'] -is [System.Text.Json.Nodes.JsonObject] -and
      $node['hooks']['SessionStart'] -is [System.Text.Json.Nodes.JsonArray]) {
    foreach ($e in $node['hooks']['SessionStart']) {
      if ($null -ne $e -and $e.ToJsonString().Contains('--global-hook')) { $ours += , $e }
    }
  }
  $same = $false
  if ($ours.Count -eq 1) {
    try { $same = $J::DeepEquals($ours[0], $entry) }
    catch { $same = ($ours[0].ToJsonString() -ceq $entry.ToJsonString()) }
  }
  if ($same) { Write-Row OK 'Claude global SessionStart hook' }
  elseif ($ours.Count -eq 0) { Write-Row FIX 'Claude global SessionStart hook missing' }
  else { Write-Row FIX 'Claude global SessionStart hook stale or duplicated' }
}

# One markdown doc, with fenced blocks skipped and `code spans` removed. Without $Tokens: every
# "[text]" that is not a link. With $Tokens: $true when the doc still holds a template placeholder —
# a <!-- BOOTSTRAP_PENDING --> line, one of $Tokens, or a line that is nothing but a
# "[placeholder]" (older templates' style; [NEEDS HUMAN INPUT] is intentional).
function Find-Placeholders([string]$Text, $Tokens = $null) {
  $check = $null -ne $Tokens
  $fence = $false
  $found = [System.Collections.Generic.List[string]]::new()
  foreach ($raw in ($Text -split "`n")) {
    $l = $raw.TrimEnd("`r")
    if ($check -and $l.StartsWith('<!-- BOOTSTRAP_PENDING -->')) { return $true }
    if ($l -match '^[ \t]*```') { $fence = -not $fence; continue }
    if ($fence) { continue }
    $l = $l -replace '`[^`]*`', ''
    if ($check -and $l -match '^[ \t]*([-*] |[0-9]+\. )?\[[^\] \[][^\]]*[^\] ]\][ \t]*$' -and $l -notmatch 'NEEDS HUMAN INPUT') { return $true }
    foreach ($m in [regex]::Matches($l, '\[[^\]]+\]')) {
      $end = $m.Index + $m.Length
      if ($end -lt $l.Length -and $l[$end] -in '(', '[', ':') { continue }
      if (-not $check) { $found.Add($m.Value) }
      elseif ($Tokens.Contains($m.Value)) { return $true }
    }
  }
  if ($check) { return $false }
  return , $found.ToArray()
}

$script:PlaceholderTokens = $null   # the placeholders of the rendered living-doc templates (built once)
$script:GenericHeadings = $null     # refresh-agents-sections.py's GENERIC_HEADINGS (read once)

# A bootstrapped project's living-doc gaps: Placeholders (living docs still holding a template
# placeholder), Missing (generic AGENTS.md headings it lacks), Remote (has a git remote).
function Get-DocGaps([string]$Dir) {
  if ($null -eq $script:PlaceholderTokens) {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$set.Add('[PROJECT NAME]')
    foreach ($entry in $LivingDocsMap) {
      $src, $rel = $entry -split '\|', 2
      if (-not $rel.EndsWith('.md')) { continue }
      foreach ($t in (Find-Placeholders (Get-RenderedTemplate $src))) { [void]$set.Add($t) }
    }
    $script:PlaceholderTokens = $set
    $py = Get-Content -LiteralPath (Join-Path $TemplateDir 'skills/bootstrap-ai/scripts/refresh-agents-sections.py')
    $in = $false
    $script:GenericHeadings = @(foreach ($line in $py) {
        if ($line -match '^GENERIC_HEADINGS = \[') { $in = $true; continue }
        if ($in -and $line -match '^\]') { $in = $false }
        if ($in -and $line -match '^ *"(.*)",? *$') { $Matches[1] }
      })
  }
  $placeholders = @(foreach ($entry in $LivingDocsMap) {
      $rel = ($entry -split '\|', 2)[1]
      $file = Join-Path $Dir $rel
      if ($rel.EndsWith('.md') -and (Test-Path -LiteralPath $file -PathType Leaf) -and
          (Find-Placeholders ([IO.File]::ReadAllText($file)) $script:PlaceholderTokens)) { $rel }
    })
  $lines = @((Get-Content -LiteralPath (Join-Path $Dir 'AGENTS.md')) | ForEach-Object { $_.TrimEnd("`r") })
  $missing = @($script:GenericHeadings | Where-Object { $lines -cnotcontains $_ })
  $remote = (@(Invoke-Git @('-C', $Dir, 'remote') | Where-Object { $_ }).Count -gt 0)
  return [pscustomobject]@{ Placeholders = $placeholders; Missing = $missing; Remote = $remote }
}

# (--json) One project's record, appended to $script:Projects.
function Add-ProjectRecord([string]$Dir, [string]$Name, [string]$State, [string[]]$Stale, $Gaps) {
  $plan = 'ok'
  if (-not (Test-Conforms $Dir)) { $plan = if ((Get-ExpectedMode $Dir) -eq 'tracked') { 'tracked-mismatch' } else { 'off-plan' } }
  $dirty = (@(Invoke-Git @('-C', $Dir, 'status', '--porcelain') | Where-Object { $_ }).Count -gt 0)
  $ahead = "$(Get-AheadCount $Dir)"
  $unpushed = $null
  if ($ahead -match '^[0-9]+$') { $unpushed = [int]$ahead }
  $over = @()
  foreach ($line in @(Test-ContextBudget -Target $Dir 6>&1 | ForEach-Object { "$_" })) {
    if ($line -match '^ai-sync: context budget: (\S+) is ([0-9]+) KB \(> ') { $over += [ordered]@{ file = $Matches[1]; kb = [int]$Matches[2] } }
  }
  $script:Projects.Add([ordered]@{
      name = $Name; path = $Dir
      bootstrapped = ($State -ne 'not-bootstrapped')
      ai_files = $State
      stale_files = @(if ($State -eq 'stale') { $Stale })
      plan = $plan; dirty = $dirty; unpushed = $unpushed
      over_budget = @($over)
      remote = $Gaps.Remote
      placeholder_docs = @($Gaps.Placeholders)
      missing_headings = @($Gaps.Missing)
    })
}

# (--json) The whole report as one ASCII-only JSON document (non-ASCII as \uXXXX: stdout encoding-proof).
function Write-JsonReport {
  # By name, byte order: the same order as doctor.sh's LC_ALL=C sort.
  $byName = [System.Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($p in $script:Projects) { $byName[$p.name] = $p }
  $report = [ordered]@{
    schema = 1
    template_dir = $TemplateDir
    code_root = $CodeRoot
    ok = ($script:NFix + $script:NTodo -eq 0)
    counts = [ordered]@{ ok = $script:NOk; fix = $script:NFix; todo = $script:NTodo; warn = $script:NWarn }
    checks = @($script:Checks)
    projects = @($byName.Values)
    unsynced = @($script:Unsynced)
  }
  $text = $report | ConvertTo-Json -Depth 6 -Compress
  Write-Output ([regex]::Replace($text, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value }))
}

function Test-Projects {
  Write-Section "Projects in $CodeRoot"
  $misses = @(); $trackedMisses = @(); $stale = @(); $bare = @(); $unpushed = @()
  $unfilled = @(); $headless = @(); $remoteless = @(); $moved = @()
  # A root with neither knows no hidden ai-context repo: a project that moved its AGENTS.md there
  # (deleted from the code repo) cannot get it back on this machine.
  $remoteFile = Join-Path $CodeRoot '.ai-context-remote'
  $rootKnown = (Test-Path -LiteralPath (Join-Path $CodeRoot '.ai-root/.git')) -or
    ((Test-Path -LiteralPath $remoteFile -PathType Leaf) -and ((Get-Item -LiteralPath $remoteFile -Force).Length -gt 0))
  foreach ($dir in @(Get-ConformRepos $CodeRoot)) {
    if (Test-Conforms $dir) { continue }
    if ((Get-ExpectedMode $dir) -eq 'tracked') { $trackedMisses += (Split-Path -Leaf $dir) }
    else { $misses += (Split-Path -Leaf $dir) }
  }
  if ($misses.Count -gt 0) { Write-Row FIX "$($misses.Count) project(s) off the private-layer plan: $(Join-Names $misses)" }
  else { Write-Row OK 'every project on the private-layer plan' }
  if ($trackedMisses.Count -gt 0) {
    Write-Row TODO "registry says tracked, project is not: $(Join-Names $trackedMisses)" 'edit .ai-root/projects/<name>, or switch the project by hand'
  }

  # The overlay is part of the factory, not a project.
  $overlayReal = if ($OverlayDir) { (Resolve-Path -LiteralPath $OverlayDir -ErrorAction SilentlyContinue).Path } else { $null }
  foreach ($d in @(Get-ChildItem -LiteralPath $CodeRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $name = $d.Name
    if ($name -eq $TemplateName -or $name.StartsWith('.') -or $name.EndsWith('.worktrees')) { continue }
    if ($overlayReal -and $d.FullName.TrimEnd('\', '/') -eq $overlayReal.TrimEnd('\', '/')) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) { continue }
    $agents = Get-Item -LiteralPath (Join-Path $d.FullName 'AGENTS.md') -Force -ErrorAction SilentlyContinue
    if ($null -eq $agents -or $agents.PSIsContainer -or $agents.LinkType) {
      if (-not $rootKnown -and @(Invoke-Git @('-C', $d.FullName, 'log', '--diff-filter=D', '--format=%h', '-1', '--', 'AGENTS.md') | Where-Object { $_ }).Count -gt 0) {
        $moved += $name
      } else { $bare += $name }
      if ($Json) {
        $remote = (@(Invoke-Git @('-C', $d.FullName, 'remote') | Where-Object { $_ }).Count -gt 0)
        Add-ProjectRecord $d.FullName $name 'not-bootstrapped' @() ([pscustomobject]@{ Placeholders = @(); Missing = @(); Remote = $remote })
      }
      continue
    }
    $gaps = Get-DocGaps $d.FullName
    if ($gaps.Placeholders.Count -gt 0) { $unfilled += "$name ($(@($gaps.Placeholders | ForEach-Object { Split-Path -Leaf $_ }) -join ' '))" }
    if ($gaps.Missing.Count -gt 0) { $headless += $name }
    if (-not $gaps.Remote) { $remoteless += $name }
    $changed = @(Get-DryRunChanges $d.FullName)
    if ($changed.Count -gt 0) { $stale += $name }
    $ahead = Get-AheadCount $d.FullName
    if ("$ahead" -notin '', '0', 'no-remote', '?') { $unpushed += "$name ($ahead)" }
    if ($Json) { Add-ProjectRecord $d.FullName $name $(if ($changed.Count -gt 0) { 'stale' } else { 'current' }) $changed $gaps }
  }
  if ($stale.Count -gt 0) { Write-Row FIX "$($stale.Count) project(s) with stale AI files: $(Join-Names $stale)" }
  else { Write-Row OK 'every bootstrapped project''s AI files up to date' }
  if ($unfilled.Count -gt 0) {
    Write-Row TODO "$($unfilled.Count) project(s) with living docs still holding template placeholders: $(Join-Names $unfilled)" `
      'run /bootstrap-ai in each: it fills them and drops <!-- BOOTSTRAP_PENDING -->'
  } else { Write-Row OK 'every bootstrapped project''s living docs filled' }
  if ($headless.Count -gt 0) {
    Write-Row TODO "$($headless.Count) project(s) whose AGENTS.md misses generic sections: $(Join-Names $headless)" `
      'run /bootstrap-ai in each: it brings AGENTS.md onto the template (the sync only refreshes sections already there)'
  } else { Write-Row OK 'every bootstrapped project''s AGENTS.md has the generic sections' }
  if ($remoteless.Count -gt 0) {
    Write-Row TODO "$($remoteless.Count) project(s) with no git remote: $(Join-Names $remoteless)" `
      'gh repo create <name> --private --source <dir> --push, or git -C <dir> remote add origin <url>'
  } else { Write-Row OK 'every bootstrapped project has a git remote' }
  if ($moved.Count -gt 0) {
    Write-Row TODO "$($moved.Count) project(s) whose AI files are in a private repo $CodeRoot has no remote for: $(Join-Names $moved)" `
      "aicf setup -AiContextRemote <url> (the one in .ai-context-remote of the root on the machine that moved them), then open a session in each"
  }
  if ($bare.Count -gt 0) {
    Write-Row WARN "$($bare.Count) git repo(s) not bootstrapped: $(Join-Names $bare)" 'aicf update <name> or /bootstrap-ai, if they should be'
  }
  if ($unpushed.Count -gt 0) {
    Write-Row WARN "commits not on their remote: $(Join-Names $unpushed)" 'aicf doctor --yes --push, or push them yourself'
  }
}

function Get-UnsyncedRows {
  $py = Get-FactoryPython
  if (-not $py) { return @() }
  $raw = & $py (Join-Path $TemplateDir 'engine/factory-env.py') unsynced --root $CodeRoot 2>$null
  $code = $LASTEXITCODE
  if ($code -ne 0 -or -not $raw -or "$raw" -eq '[]') { return @() }
  try {
    $parsed = $raw | Out-String | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
  } catch { return @() }
}

function Write-UnsyncedWarnings {
  $script:Unsynced = @(Get-UnsyncedRows)
  if ($Json) { return }
  foreach ($row in $script:Unsynced) {
    Write-Row WARN "$($row.role) $($row.path): $($row.detail)"
  }
}

function Invoke-Checks {
  $script:NFix = 0; $script:NTodo = 0; $script:NWarn = 0; $script:NOk = 0
  $script:Unsynced = @()
  Test-Tools
  Test-TemplateRepo
  Test-Machine
  Test-Projects
  Write-UnsyncedWarnings
  if ($Json) { Write-JsonReport; return }
  Write-Host ''
  if ($script:NFix + $script:NTodo -eq 0) {
    if ($script:NWarn -eq 0) { Write-Host 'All good.' } else { Write-Host "All good ($($script:NWarn) warning(s))." }
  } else {
    Write-Host "$($script:NFix) to fix, $($script:NTodo) for you, $($script:NWarn) warning(s)."
    if ($script:NFix -gt 0 -and -not $Yes) { Write-Host 'Run aicf doctor --yes to fix the FIX lines.' }
  }
}

# One fix step, in its own pwsh: a failure is reported and the next step still runs.
function Invoke-Step([string]$Label, [string]$Script, [string[]]$StepArgs) {
  Write-Host ''
  Write-Host "== $Label"
  $rc = 0
  try {
    & $Pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $TemplateDir $Script) @StepArgs
    $rc = $LASTEXITCODE
  } catch { $rc = 1 }
  if ($rc -ne 0) { Write-Host "STEP FAILED   $Label (exit $rc) — carrying on" }
}

if ($Yes) {
  if ($LinkedWorktree) {
    $host.UI.WriteErrorLine("Error: $TemplateDir is a linked git worktree. Run doctor --yes from the main checkout:")
    $host.UI.WriteErrorLine('install-global would point this machine at the worktree.')
    exit 1
  }
  if (-not $TemplatePulled) {
    Write-Host "== Pull $TemplateName"
    Reset-NetBudget
    Update-TemplateRepo
    if ($script:PullUpdated) {
      Write-Host "PULLED        $TemplateName — re-running with the new version"
      & $Pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @Rerun '--template-pulled'
      exit $LASTEXITCODE
    }
  }
  Reset-NetBudget
  Update-AiRoot $CodeRoot
  $ig = @()
  if ($Copy) { $ig += '--copy' }
  Invoke-Step 'install-global' 'engine/install-global.ps1' $ig
  Invoke-Step "Sync $TemplateName's pointer copies" 'sync-ai-templates.ps1' @($TemplateDir, '--commit')
  Invoke-Step 'Private-layer plan' 'engine/update-projects.ps1' @('-Migrate', '-Yes')
  $up = @('-Yes', '-Pull', '-TemplatePulled')
  if ($Clone) { $up += '-Clone' }
  if ($Push) { $up += '-Push' }
  Invoke-Step 'Projects' 'engine/update-projects.ps1' $up
  Write-Host ''
  Write-Host '== Checking again'
}

Invoke-Checks
if ($script:NFix + $script:NTodo -eq 0) { exit 0 }
exit 1
