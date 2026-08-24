param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'New-EvidenceBoundClosureReport.ps1')
)

$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('evidence-bound-closure-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $mismatchManifest = Join-Path $tempRoot 'mismatch-manifest.json'
    $mismatchReport = Join-Path $tempRoot 'mismatch-report.md'
    @'
{
  "identity": { "project": "Demo", "task": "T08", "worktree": "X:/Projects/Demo/01_Workspace", "branch": "codex/demo", "commit": "abc123" },
  "planning_status": "PASS",
  "engineering": { "status": "PASS", "command": "pwsh ./test.ps1", "exit_code": 0, "log_path": "outputs/test.log" },
  "installation_status": "PASS",
  "installer": { "path": "outputs/Demo.exe", "source_commit": "def456", "sha256": "012345" },
  "real_use_status": "PENDING",
  "human_acceptance_status": "PENDING",
  "formal_data_status": "NO_GO",
  "rollback_rehearsal_status": "PENDING"
}
'@ | Set-Content -LiteralPath $mismatchManifest -Encoding utf8

    $raw = & $ScriptPath -ManifestPath $mismatchManifest -OutputPath $mismatchReport
    $result = $raw | ConvertFrom-Json
    Assert-Equal $result.overall_verdict 'COMPLETED_WITH_BLOCKERS / FORMAL_RELEASE_NO_GO' 'Mismatch must not become release-ready.'
    Assert-Equal $result.installation_status 'BLOCKED_SOURCE_MISMATCH' 'Installer source commit must bind to current identity.'
    Assert-Equal $result.formal_release_status 'NO_GO' 'Pending human/real-use gates must block formal release.'
    $report = Get-Content -LiteralPath $mismatchReport -Raw
    Assert-True ($report -match 'abc123') 'Report must include the current commit.'
    Assert-True ($report -match 'def456') 'Report must include the installer source commit.'
    Assert-True ($report -match 'Cleanup round one') 'Report must define cleanup round one.'
    Assert-True ($report -match 'Final user review package') 'Report must contain the final review package.'

    $overwriteExit = 0
    try { & $ScriptPath -ManifestPath $mismatchManifest -OutputPath $mismatchReport | Out-Null } catch { $overwriteExit = 1 }
    Assert-Equal $overwriteExit 1 'Existing report must never be overwritten.'

    $alignedManifest = Join-Path $tempRoot 'aligned-manifest.json'
    $alignedReport = Join-Path $tempRoot 'aligned-report.md'
    @'
{
  "identity": { "project": "Demo", "task": "T08", "worktree": "X:/Projects/Demo/01_Workspace", "branch": "codex/demo", "commit": "abc123" },
  "planning_status": "PASS",
  "engineering": { "status": "PASS", "command": "pwsh ./test.ps1", "exit_code": 0, "log_path": "outputs/test.log" },
  "installation_status": "PASS",
  "installer": { "path": "outputs/Demo.exe", "source_commit": "abc123", "sha256": "012345" },
  "real_use_status": "PENDING",
  "human_acceptance_status": "PENDING",
  "formal_data_status": "NO_GO",
  "rollback_rehearsal_status": "PENDING"
}
'@ | Set-Content -LiteralPath $alignedManifest -Encoding utf8
    $alignedRaw = & $ScriptPath -ManifestPath $alignedManifest -OutputPath $alignedReport
    $aligned = $alignedRaw | ConvertFrom-Json
    Assert-Equal $aligned.installation_status 'PASS' 'Aligned installer should preserve its installation result.'
    Assert-Equal $aligned.formal_release_status 'NO_GO' 'Aligned source is not a substitute for human and formal gates.'
    Assert-Equal $aligned.overall_verdict 'COMPLETED_WITH_BLOCKERS / FORMAL_RELEASE_NO_GO' 'Missing real-use and human evidence must remain visible.'

    function Invoke-ClosureShell {
        param([string]$Shell, [string]$ManifestPath, [string]$OutputPath)
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # Negative fixtures intentionally return non-zero. Native stderr must
            # be captured as test data instead of terminating this harness before
            # the expected fail-closed assertion runs.
            $ErrorActionPreference = 'Continue'
            $raw = @(& $Shell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -ManifestPath $ManifestPath -OutputPath $OutputPath 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        $json = $null
        if ($raw.Count -gt 0) {
            try { $json = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json } catch { }
        }
        return [pscustomobject]@{ ExitCode = $exitCode; Json = $json }
    }

    $safeManifest = Join-Path $tempRoot 'safe-local-v1.1.json'
    @'
{
  "identity": { "project": "Demo", "task": "T05-safe", "worktree": "X:/Projects/Demo/01_Workspace", "branch": "codex/demo", "commit": "abc123" },
  "planning_status": "PASS",
  "engineering": { "status": "PASS", "command": "pwsh ./test.ps1", "exit_code": 0, "log_path": "outputs/test.log" },
  "installer": { "path": "", "source_commit": "", "sha256": "" },
  "delivery_target": "ENGINEERING_ONLY",
  "release_intent": "NONE",
  "review_policy": "NONE",
  "resolver": { "governance_mode": "LOCAL_AUTONOMOUS", "terminal_state": "LOCAL_CANDIDATE_READY", "required_review": false, "risk_codes": [], "layers": [
    { "name": "formal_release", "status": "NOT_APPLICABLE", "applicability_reason": "releaseIntent=NONE" }
  ] },
  "preflight_status": "READY",
  "installation_status": "NOT_APPLICABLE",
  "real_use_status": "NOT_APPLICABLE",
  "human_acceptance_status": "NOT_APPLICABLE",
  "formal_data_status": "NOT_APPLICABLE",
  "rollback_rehearsal_status": "PASS"
}
'@ | Set-Content -LiteralPath $safeManifest -Encoding utf8
    $safeReport51 = Join-Path $tempRoot 'safe-local-ps51.md'
    $safeReport7 = Join-Path $tempRoot 'safe-local-ps7.md'
    $safe51 = Invoke-ClosureShell -Shell 'powershell.exe' -ManifestPath $safeManifest -OutputPath $safeReport51
    $safe7 = Invoke-ClosureShell -Shell 'pwsh' -ManifestPath $safeManifest -OutputPath $safeReport7
    Assert-Equal $safe51.ExitCode 0 'Safe local PowerShell 5.1 closure must exit 0'
    Assert-Equal $safe7.ExitCode 0 'Safe local PowerShell 7 closure must exit 0'
    Assert-Equal $safe51.Json.overall_verdict 'LOCAL_CANDIDATE_READY' 'Safe local terminal state'
    Assert-Equal $safe51.Json.formal_release_status 'NOT_APPLICABLE' 'Safe local formal release N/A'
    Assert-Equal $safe51.Json.overall_verdict $safe7.Json.overall_verdict 'Cross-shell terminal state must match'
    Write-Output 'PASS safe_local_na_and_cross_shell'

    $localMissingManifest = Join-Path $tempRoot 'local-usable-missing.json'
    $localMissingObject = Get-Content -LiteralPath $safeManifest -Raw | ConvertFrom-Json
    $localMissingObject.identity.task = 'T05-local-missing'
    $localMissingObject.delivery_target = 'LOCAL_USABLE'
    $localMissingObject.resolver.terminal_state = 'BLOCKED'
    $localMissingObject.installation_status = 'PENDING'
    $localMissingObject | Add-Member -NotePropertyName local_smoke_status -NotePropertyValue 'PENDING'
    $localMissingObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $localMissingManifest -Encoding utf8
    $localMissingReport = Join-Path $tempRoot 'local-usable-missing.md'
    $localMissing = Invoke-ClosureShell -Shell 'powershell.exe' -ManifestPath $localMissingManifest -OutputPath $localMissingReport
    Assert-True ($localMissing.ExitCode -ne 0) 'Local-usable missing installation/smoke must fail closed'
    Write-Output 'PASS local_usable_missing_evidence_blocked'

    $riskNaManifest = Join-Path $tempRoot 'risk-na-conflict.json'
    $riskNaObject = Get-Content -LiteralPath $safeManifest -Raw | ConvertFrom-Json
    $riskNaObject.identity.task = 'T05-risk-na'
    $riskNaObject.resolver.risk_codes = @('HARD_TRIGGER_FORMAL_DATA')
    $riskNaObject.resolver.layers = @([ordered]@{ name = 'formal_data'; status = 'NOT_APPLICABLE'; applicability_reason = 'releaseIntent=NONE' })
    $riskNaObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $riskNaManifest -Encoding utf8
    $riskNaReport = Join-Path $tempRoot 'risk-na-conflict.md'
    $riskNa = Invoke-ClosureShell -Shell 'powershell.exe' -ManifestPath $riskNaManifest -OutputPath $riskNaReport
    Assert-True ($riskNa.ExitCode -ne 0) 'Risk trigger with N/A formal data must fail closed'
    Write-Output 'PASS risk_na_conflict_blocked'

    $blockedManifest = Join-Path $tempRoot 'blocked-preflight.json'
    $blockedObject = Get-Content -LiteralPath $safeManifest -Raw | ConvertFrom-Json
    $blockedObject.identity.task = 'T05-blocked'
    $blockedObject.preflight_status = 'BLOCKED'
    $blockedObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $blockedManifest -Encoding utf8
    $blockedReport = Join-Path $tempRoot 'blocked-preflight.md'
    $blocked = Invoke-ClosureShell -Shell 'powershell.exe' -ManifestPath $blockedManifest -OutputPath $blockedReport
    Assert-True ($blocked.ExitCode -ne 0) 'Blocked preflight must not produce a completion declaration'
    Write-Output 'PASS blocked_preflight_completion_blocked'

    $formalMissingManifest = Join-Path $tempRoot 'formal-release-missing.json'
    $formalMissingObject = Get-Content -LiteralPath $safeManifest -Raw | ConvertFrom-Json
    $formalMissingObject.identity.task = 'T05-formal'
    $formalMissingObject.delivery_target = 'FORMAL_RELEASE'
    $formalMissingObject.release_intent = 'INTENDED'
    $formalMissingObject.review_policy = 'REQUIRED'
    $formalMissingObject.resolver.terminal_state = 'READY_FOR_USER_RELEASE_DECISION'
    $formalMissingObject.installation_status = 'PENDING'
    $formalMissingObject.real_use_status = 'PENDING'
    $formalMissingObject.human_acceptance_status = 'PENDING'
    $formalMissingObject.formal_data_status = 'PENDING'
    $formalMissingObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $formalMissingManifest -Encoding utf8
    $formalMissingReport = Join-Path $tempRoot 'formal-release-missing.md'
    $formalMissing = Invoke-ClosureShell -Shell 'powershell.exe' -ManifestPath $formalMissingManifest -OutputPath $formalMissingReport
    Assert-True ($formalMissing.ExitCode -ne 0) 'Formal release missing gates must fail closed'
    Write-Output 'PASS formal_release_missing_gates_blocked'

    Write-Output 'TEST_EVIDENCE_BOUND_PROJECT_CLOSURE=PASS'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
