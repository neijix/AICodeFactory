# Dot-sourced by tests/run-tests.ps1 inside case 30 (IG, $IGH, $R30, $F30): install-global -WorkRoot
# and the overlay-aware auto-bootstrap instructions.
# -WorkRoot / --work-root: appended to ~/.ai-work-roots once (any case), one line per run.
$wf30 = Join-Path $IGH '.ai-work-roots'
$out = Out-Text (IG -WorkRoot Office)
if ($LASTEXITCODE -ne 0) { Fail "install-global -WorkRoot failed: $out" }
if ((Count-Match $out '^Recorded a work root: .*\.ai-work-roots \+= Office$') -ne 1) { Fail "-WorkRoot must say what it recorded: $out" }
$out = Out-Text (IG --work-root=office)
if ($LASTEXITCODE -ne 0) { Fail "a second --work-root failed: $out" }
if ((Count-Match $out '^Work root already recorded: office \(.*\.ai-work-roots\)$') -ne 1) { Fail "a listed work root must say so: $out" }
if ([IO.File]::ReadAllText($wf30) -cne "Office`n") { Fail "--work-root must append once: $([IO.File]::ReadAllText($wf30))" }
$out = Out-Text (IG --work-root)
if ($LASTEXITCODE -eq 0) { Fail "--work-root needs a value: $out" }
Remove-Item -LiteralPath $wf30 -Force
# The auto-bootstrap instructions are overlay-aware: the overlay's .append reaches both copies.
New-Item -ItemType Directory -Force -Path "$R30/ova/templates/global" | Out-Null
[IO.File]::WriteAllText("$R30/ova/templates/global/ai-autobootstrap.instructions.md.append", "OVA-FRAGMENT`n")
$base30 = [IO.File]::ReadAllBytes("$F30/templates/global/ai-autobootstrap.instructions.md")
$p30 = "$IGH/AppData/Code/User/prompts/ai-autobootstrap.instructions.md"; $cp30 = "$IGH/.copilot/copilot-instructions.md"
$env:AI_TEMPLATE_OVERLAY_DIR = "$R30/ova"
try { $out = Out-Text (IG); $rc = $LASTEXITCODE } finally { $env:AI_TEMPLATE_OVERLAY_DIR = 'none' }
if ($rc -ne 0) { Fail "install-global with an overlay failed: $out" }
$want30 = [byte[]]($base30 + [Text.Encoding]::UTF8.GetBytes("OVA-FRAGMENT`n"))
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($p30)) -cne [Convert]::ToBase64String($want30)) { Fail "the VS Code instructions must be the base plus the overlay fragment" }
if ((Get-Content -LiteralPath $cp30)[-1] -cne 'OVA-FRAGMENT') { Fail "the Copilot CLI block must carry the overlay fragment" }
$out = Out-Text (IG)
if ($LASTEXITCODE -ne 0) { Fail "install-global without an overlay failed: $out" }
if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($p30)) -cne [Convert]::ToBase64String($base30)) { Fail "no overlay must give the base file" }
if ([IO.File]::ReadAllText($cp30) -match 'OVA-FRAGMENT') { Fail "the Copilot CLI block must drop a fragment that is gone" }
