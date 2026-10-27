# Sourced by tests/run-tests.ps1 after case 32 (DR, $C31, $F31, $rc31, New-Repo): doctor on unfilled
# living docs, missing generic AGENTS.md sections and projects with no git remote.
Write-Host "--- 33. doctor: unfilled living docs, missing generic AGENTS.md sections, no git remote"
# Case 32's machine, now set up: three bootstrapped projects beside bare31.
# good33: filled from the template; quoted, fenced, link and [NEEDS HUMAN INPUT] brackets are not placeholders.
$tpl33 = [IO.File]::ReadAllText("$F31/templates/AGENTS.md.template")
New-Repo "$C31/good33"; New-Item -ItemType Directory -Force -Path "$C31/good33/.github" | Out-Null
[IO.File]::WriteAllText("$C31/good33/AGENTS.md", (($tpl33 -replace '(?m)^<!-- BOOTSTRAP_PENDING -->\r?\n', '') -replace '\[[^\]]*\]', 'x'))
[IO.File]::WriteAllText("$C31/good33/.github/PROJECT_STATE.md", "# PROJECT STATE — good33`n`nFilled.`n")
[IO.File]::WriteAllText("$C31/good33/.github/KNOWLEDGE.md", (@('# KNOWLEDGE BASE — good33', '', '### `[FRAMEWORK]` stays quoted',
  '- [NEEDS HUMAN INPUT]', '- see [the docs](https://example.invalid) and [[other-note]]', '```text', '[PROJECT_NAME]',
  '- [What it does]', '```') -join "`n") + "`n")
git -C "$C31/good33" remote add origin https://example.invalid/good33.git
# pend33: the template as the sync writes it, BOOTSTRAP_PENDING still there.
New-Repo "$C31/pend33"
[IO.File]::WriteAllText("$C31/pend33/AGENTS.md", $tpl33.Replace('[PROJECT_NAME]', 'pend33'))
git -C "$C31/pend33" remote add origin https://example.invalid/pend33.git
# old33: an older template, never filled, no generic sections, no remote.
New-Repo "$C31/old33"; New-Item -ItemType Directory -Force -Path "$C31/old33/.github" | Out-Null
[IO.File]::WriteAllText("$C31/old33/AGENTS.md", "# old33 - Rules`n`n## Project Purpose`n- [Primary business or technical goal]`n")
[IO.File]::WriteAllText("$C31/old33/.github/PROJECT_STATE.md", "# PROJECT STATE — old33`n`n- ``src/`` — [what it does]`n")
[IO.File]::WriteAllText("$C31/old33/.github/KNOWLEDGE.md", "# KNOWLEDGE BASE - [PROJECT NAME]`n")
$out = DR $F31
if ($rc31 -ne 1 -or
    $out -notmatch '(?m)^TODO  2 project\(s\) with living docs still holding template placeholders: old33 \(AGENTS\.md PROJECT_STATE\.md KNOWLEDGE\.md\), pend33 \(AGENTS\.md\)\r?$' -or
    $out -notmatch '(?m)^TODO  1 project\(s\) whose AGENTS\.md misses generic sections: old33\r?$' -or
    $out -notmatch '(?m)^TODO  1 project\(s\) with no git remote: old33\r?$') {
  Fail "unfilled docs, missing sections and no remote are TODO lines naming exactly those projects (rc=$rc31): $out"
}
$script:DrStdoutOnly = $true
$out = DR $F31 --json
$script:DrStdoutOnly = $false
try { $j = $out | ConvertFrom-Json } catch { Fail "doctor --json must print valid JSON (rc=$rc31): $out" }
$p33 = @{}; foreach ($x in $j.projects) { $p33[$x.name] = $x }
$o33 = $p33['old33']
if ($rc31 -ne 1 -or $p33['good33'].remote -ne $true -or @($p33['good33'].placeholder_docs).Count -ne 0 -or @($p33['good33'].missing_headings).Count -ne 0 -or
    (@($p33['pend33'].placeholder_docs) -join ',') -ne 'AGENTS.md' -or @($p33['pend33'].missing_headings).Count -ne 0 -or
    $o33.remote -isnot [bool] -or $o33.remote -or (@($o33.placeholder_docs) -join ',') -ne 'AGENTS.md,.github/PROJECT_STATE.md,.github/KNOWLEDGE.md' -or
    @($o33.missing_headings | Where-Object { $_.StartsWith('## ') }).Count -ne 2 -or
    $p33['bare31'].remote -or @($p33['bare31'].placeholder_docs).Count -ne 0 -or @($p33['bare31'].missing_headings).Count -ne 0 -or
    @($j.checks | Where-Object { $_.status -eq 'TODO' -and $_.what -match 'old33' }).Count -ne 3) {
  Fail "doctor --json carries remote, placeholder_docs and missing_headings per project (rc=$rc31): $out"
}
