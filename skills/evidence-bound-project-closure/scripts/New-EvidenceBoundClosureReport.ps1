[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-ObjectValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Add-UniqueReason {
    param([Parameter(Mandatory = $true)]$List, [Parameter(Mandatory = $true)][string]$Code)
    if (-not $List.Contains($Code)) { [void]$List.Add($Code) }
}

function Write-V11ReportAndExit {
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines, [Parameter(Mandatory = $true)][bool]$Success, [Parameter(Mandatory = $true)][string]$OutputPath)
    [IO.File]::WriteAllText($OutputPath, ($Lines -join [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    $Result | ConvertTo-Json -Depth 30 -Compress
    if (-not $Success) { exit 1 }
    exit 0
}

function Get-ManifestValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ''
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return [string]$property.Value
}

function Require-ManifestValue {
    param($Object, [string]$Name)
    $value = Get-ManifestValue -Object $Object -Name $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Manifest requires identity.$Name."
    }
    return $value
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "Refusing to overwrite an existing report: $OutputPath"
}
$outputParent = Split-Path -Parent $OutputPath
if ([string]::IsNullOrWhiteSpace($outputParent) -or -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    throw "Output directory must already exist: $outputParent"
}

$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$manifest = [IO.File]::ReadAllText($ManifestPath, $strictUtf8) | ConvertFrom-Json
if ($null -eq $manifest.identity -or $null -eq $manifest.engineering -or $null -eq $manifest.installer) {
    throw 'Manifest requires identity, engineering, and installer objects.'
}

$isV11 = $null -ne $manifest.PSObject.Properties['delivery_target']
if ($isV11) {
    $v11Reasons = New-Object 'System.Collections.Generic.List[string]'
    $v11Layers = New-Object 'System.Collections.Generic.List[object]'
    $deliveryTarget = [string](Get-ObjectValue -Object $manifest -Name 'delivery_target')
    $releaseIntent = [string](Get-ObjectValue -Object $manifest -Name 'release_intent')
    $reviewPolicy = [string](Get-ObjectValue -Object $manifest -Name 'review_policy')
    $resolver = Get-ObjectValue -Object $manifest -Name 'resolver'
    $terminalState = [string](Get-ObjectValue -Object $resolver -Name 'terminal_state')
    $preflightStatus = [string](Get-ObjectValue -Object $manifest -Name 'preflight_status' -Default 'UNKNOWN')
    $planningStatus = [string](Get-ObjectValue -Object $manifest -Name 'planning_status' -Default 'PENDING')
    $engineeringInput = [string](Get-ObjectValue -Object $manifest.engineering -Name 'status' -Default 'PENDING')
    $engineeringExitCode = [string](Get-ObjectValue -Object $manifest.engineering -Name 'exit_code' -Default '-1')
    $engineeringStatus = if ($engineeringInput -eq 'PASS' -and $engineeringExitCode -eq '0') { 'PASS' } else { 'BLOCKED' }
    $installationStatus = [string](Get-ObjectValue -Object $manifest -Name 'installation_status' -Default 'NOT_APPLICABLE')
    $realUseStatus = [string](Get-ObjectValue -Object $manifest -Name 'real_use_status' -Default 'NOT_APPLICABLE')
    $humanAcceptanceStatus = [string](Get-ObjectValue -Object $manifest -Name 'human_acceptance_status' -Default 'NOT_APPLICABLE')
    $formalDataStatus = [string](Get-ObjectValue -Object $manifest -Name 'formal_data_status' -Default 'NOT_APPLICABLE')
    $rollbackStatus = [string](Get-ObjectValue -Object $manifest -Name 'rollback_rehearsal_status' -Default 'PENDING')
    $layerMap = @{}
    foreach ($layer in @((Get-ObjectValue -Object $resolver -Name 'layers'))) {
        if ($null -ne $layer) { $layerMap[[string](Get-ObjectValue -Object $layer -Name 'name')] = $layer; [void]$v11Layers.Add($layer) }
    }
    if ($preflightStatus -ne 'READY') { Add-UniqueReason -List $v11Reasons -Code 'BLOCKED_PREFLIGHT_COMPLETION' }
    if ([string]::IsNullOrWhiteSpace($terminalState)) { Add-UniqueReason -List $v11Reasons -Code 'RESOLVER_TERMINAL_STATE_MISSING' }
    $riskCodes = @((Get-ObjectValue -Object $resolver -Name 'risk_codes') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($riskCodes.Count -gt 0 -and $layerMap.ContainsKey('formal_data') -and [string](Get-ObjectValue -Object $layerMap['formal_data'] -Name 'status') -eq 'NOT_APPLICABLE') { Add-UniqueReason -List $v11Reasons -Code 'RISK_NA_CONFLICT' }
    switch ($deliveryTarget) {
        'ENGINEERING_ONLY' {
            if ($terminalState -ne 'LOCAL_CANDIDATE_READY') { Add-UniqueReason -List $v11Reasons -Code 'TERMINAL_STATE_MISMATCH' }
            $installationStatus = 'NOT_APPLICABLE'; $realUseStatus = 'NOT_APPLICABLE'; $humanAcceptanceStatus = 'NOT_APPLICABLE'; $formalDataStatus = 'NOT_APPLICABLE'
            if ($layerMap.ContainsKey('formal_release')) { $formalReleaseStatus = [string](Get-ObjectValue -Object $layerMap['formal_release'] -Name 'status') } else { $formalReleaseStatus = 'NOT_APPLICABLE' }
            if ($formalReleaseStatus -ne 'NOT_APPLICABLE') { Add-UniqueReason -List $v11Reasons -Code 'FORMAL_RELEASE_APPLICABILITY_INVALID' }
        }
        'LOCAL_USABLE' {
            if ($terminalState -notin @('LOCAL_USABLE_READY', 'OPTIONAL_REVIEW_AVAILABLE')) { Add-UniqueReason -List $v11Reasons -Code 'TERMINAL_STATE_MISMATCH' }
            if ($installationStatus -ne 'PASS' -or [string](Get-ObjectValue -Object $manifest -Name 'local_smoke_status' -Default 'PENDING') -ne 'PASS') { Add-UniqueReason -List $v11Reasons -Code 'LOCAL_USABLE_EVIDENCE_REQUIRED' }
            $realUseStatus = 'NOT_APPLICABLE'; $humanAcceptanceStatus = 'NOT_APPLICABLE'; $formalDataStatus = 'NOT_APPLICABLE'; $formalReleaseStatus = 'NOT_APPLICABLE'
        }
        'INTERNAL_REVIEW' {
            if ($terminalState -ne 'USER_FINAL_REVIEW') { Add-UniqueReason -List $v11Reasons -Code 'TERMINAL_STATE_MISMATCH' }
            $installationStatus = 'NOT_APPLICABLE'; $realUseStatus = 'NOT_APPLICABLE'; $formalDataStatus = 'NOT_APPLICABLE'; $formalReleaseStatus = 'NOT_APPLICABLE'
        }
        'FORMAL_RELEASE' {
            if ($terminalState -ne 'READY_FOR_USER_RELEASE_DECISION') { Add-UniqueReason -List $v11Reasons -Code 'TERMINAL_STATE_MISMATCH' }
            $formalReleaseStatus = 'READY_FOR_USER_DECISION'
            foreach ($status in @($planningStatus, $engineeringStatus, $installationStatus, $realUseStatus, $humanAcceptanceStatus, $formalDataStatus, $rollbackStatus)) { if ($status -ne 'PASS') { Add-UniqueReason -List $v11Reasons -Code 'FORMAL_RELEASE_GATE_MISSING'; break } }
        }
        default { Add-UniqueReason -List $v11Reasons -Code 'DELIVERY_TARGET_INVALID'; $formalReleaseStatus = 'NO_GO' }
    }
    if ($planningStatus -ne 'PASS') { Add-UniqueReason -List $v11Reasons -Code 'PLANNING_NOT_PASS' }
    if ($engineeringStatus -ne 'PASS') { Add-UniqueReason -List $v11Reasons -Code 'ENGINEERING_NOT_PASS' }
    $success = $v11Reasons.Count -eq 0
    $overall = if ($success) { switch ($deliveryTarget) { 'ENGINEERING_ONLY' { 'LOCAL_CANDIDATE_READY' } 'LOCAL_USABLE' { if ($reviewPolicy -eq 'OPTIONAL') { 'OPTIONAL_REVIEW_AVAILABLE' } else { 'LOCAL_USABLE_READY' } } 'INTERNAL_REVIEW' { 'USER_FINAL_REVIEW' } 'FORMAL_RELEASE' { 'READY_FOR_USER_RELEASE_DECISION' } default { 'BLOCKED' } } } else { 'BLOCKED' }
    $formalReleaseStatus = if ($deliveryTarget -eq 'ENGINEERING_ONLY' -or $deliveryTarget -eq 'LOCAL_USABLE' -or $deliveryTarget -eq 'INTERNAL_REVIEW') { 'NOT_APPLICABLE' } else { $formalReleaseStatus }
    $project = Require-ManifestValue -Object $manifest.identity -Name 'project'
    $task = Require-ManifestValue -Object $manifest.identity -Name 'task'
    $worktree = Require-ManifestValue -Object $manifest.identity -Name 'worktree'
    $branch = Require-ManifestValue -Object $manifest.identity -Name 'branch'
    $commit = Require-ManifestValue -Object $manifest.identity -Name 'commit'
    $lines = @(
        '# Evidence-Bound Project Closure Report V1.1', '',
        "Current verdict: $overall", '',
        '## Identity and source binding', '',
        "- Project: $project", "- Task: $task", "- Worktree: $worktree", "- Branch: $branch", "- Current commit: $commit", '',
        '## Evidence layers', '',
        '| Layer | Status | Applicability reason |', '| --- | --- | --- |',
        "| Planning | $planningStatus | delivery target and current plan |", "| Engineering | $engineeringStatus | command exit $engineeringExitCode |", "| Installation | $installationStatus | delivery target bound |", "| Real use | $realUseStatus | delivery target bound |", "| Human acceptance | $humanAcceptanceStatus | review policy bound |", "| Formal data | $formalDataStatus | release intent bound |", "| Rollback rehearsal | $rollbackStatus | candidate rollback evidence |", "| Formal release | $formalReleaseStatus | release intent bound; never inferred from tests |", '',
        '## Blockers and reason codes', '', "- $($v11Reasons -join '; ')", '',
        '## Cleanup round one', '', 'Repair only authorized work, rerun its verification, and regenerate a new report at a new path.', '',
        '## Second blocker review', '', 'Recheck each remaining blocker once; preserve external, human, formal-data, destructive, and release blockers.', '',
        '## Final user review package', '', 'Bind candidate, source HEAD, policy hash, evidence paths, reason codes, and rollback entry.', '',
        '## User-only actions', '', 'Merge, tag, formal release, formal data, human acceptance, and external actions remain user decisions.'
    )
    $result = [ordered]@{ overall_verdict = $overall; planning_status = $planningStatus; engineering_status = $engineeringStatus; installation_status = $installationStatus; real_use_status = $realUseStatus; human_acceptance_status = $humanAcceptanceStatus; formal_release_status = $formalReleaseStatus; layer_applicability = $v11Layers.ToArray(); reason_codes = $v11Reasons.ToArray(); report_path = $OutputPath }
    if ($v11Reasons.Count -gt 0) { Write-V11ReportAndExit -Result $result -Lines $lines -Success $false -OutputPath $OutputPath }
    Write-V11ReportAndExit -Result $result -Lines $lines -Success $true -OutputPath $OutputPath
}

$project = Require-ManifestValue -Object $manifest.identity -Name 'project'
$task = Require-ManifestValue -Object $manifest.identity -Name 'task'
$worktree = Require-ManifestValue -Object $manifest.identity -Name 'worktree'
$branch = Require-ManifestValue -Object $manifest.identity -Name 'branch'
$commit = Require-ManifestValue -Object $manifest.identity -Name 'commit'
$installerSourceCommit = Get-ManifestValue -Object $manifest.installer -Name 'source_commit'

$planningStatus = Get-ManifestValue -Object $manifest -Name 'planning_status' -Default 'PENDING'
$engineeringInput = Get-ManifestValue -Object $manifest.engineering -Name 'status' -Default 'PENDING'
$engineeringExitCode = Get-ManifestValue -Object $manifest.engineering -Name 'exit_code' -Default '-1'
$engineeringStatus = 'FAILED'
if ($engineeringInput -eq 'PASS' -and $engineeringExitCode -eq '0') { $engineeringStatus = 'PASS' }

$installationStatus = Get-ManifestValue -Object $manifest -Name 'installation_status' -Default 'PENDING'
if ([string]::IsNullOrWhiteSpace($installerSourceCommit)) {
    $installationStatus = 'BLOCKED_SOURCE_UNVERIFIED'
}
elseif ($installerSourceCommit -ne $commit) {
    $installationStatus = 'BLOCKED_SOURCE_MISMATCH'
}

$realUseStatus = Get-ManifestValue -Object $manifest -Name 'real_use_status' -Default 'PENDING'
$humanAcceptanceStatus = Get-ManifestValue -Object $manifest -Name 'human_acceptance_status' -Default 'PENDING'
$formalDataStatus = Get-ManifestValue -Object $manifest -Name 'formal_data_status' -Default 'NO_GO'
$rollbackStatus = Get-ManifestValue -Object $manifest -Name 'rollback_rehearsal_status' -Default 'PENDING'

$allFormalGatesPass = (
    $planningStatus -eq 'PASS' -and
    $engineeringStatus -eq 'PASS' -and
    $installationStatus -eq 'PASS' -and
    $realUseStatus -eq 'PASS' -and
    $humanAcceptanceStatus -eq 'PASS' -and
    $formalDataStatus -eq 'PASS' -and
    $rollbackStatus -eq 'PASS'
)
$formalReleaseStatus = 'NO_GO'
if ($allFormalGatesPass) { $formalReleaseStatus = 'READY_FOR_USER_DECISION' }

$overallVerdict = 'COMPLETED_WITH_BLOCKERS / FORMAL_RELEASE_NO_GO'
if ($engineeringStatus -ne 'PASS') { $overallVerdict = 'ENGINEERING_NOT_COMPLETE / FORMAL_RELEASE_NO_GO' }
if ($formalReleaseStatus -eq 'READY_FOR_USER_DECISION') { $overallVerdict = 'EVIDENCE_COMPLETE / USER_RELEASE_DECISION_REQUIRED' }

$reasonCodes = New-Object System.Collections.Generic.List[string]
if ($planningStatus -ne 'PASS') { [void]$reasonCodes.Add('PLANNING_NOT_PASS') }
if ($engineeringStatus -ne 'PASS') { [void]$reasonCodes.Add('ENGINEERING_NOT_PASS') }
if ($installationStatus -ne 'PASS') { [void]$reasonCodes.Add($installationStatus) }
if ($realUseStatus -ne 'PASS') { [void]$reasonCodes.Add('REAL_USE_NOT_PASS') }
if ($humanAcceptanceStatus -ne 'PASS') { [void]$reasonCodes.Add('HUMAN_ACCEPTANCE_NOT_PASS') }
if ($formalDataStatus -ne 'PASS') { [void]$reasonCodes.Add('FORMAL_DATA_NOT_PASS') }
if ($rollbackStatus -ne 'PASS') { [void]$reasonCodes.Add('ROLLBACK_REHEARSAL_NOT_PASS') }
if ($reasonCodes.Count -eq 0) { [void]$reasonCodes.Add('USER_RELEASE_DECISION_REQUIRED') }

$engineeringCommand = Get-ManifestValue -Object $manifest.engineering -Name 'command' -Default 'Not recorded'
$engineeringLog = Get-ManifestValue -Object $manifest.engineering -Name 'log_path' -Default 'Not recorded'
$installerPath = Get-ManifestValue -Object $manifest.installer -Name 'path' -Default 'Not recorded'
$installerHash = Get-ManifestValue -Object $manifest.installer -Name 'sha256' -Default 'Not recorded'

$lines = @(
    '# Evidence-Bound Project Closure Report',
    '',
    "**Current verdict:** $overallVerdict",
    '',
    '## Identity and source binding',
    '',
    "- Project: $project",
    "- Task: $task",
    "- Worktree: $worktree",
    "- Branch: $branch",
    "- Current commit: $commit",
    "- Installer: $installerPath",
    "- Installer source commit: $installerSourceCommit",
    "- Installer SHA-256: $installerHash",
    '',
    '## Evidence layers',
    '',
    '| Layer | Status | Bound evidence |',
    '| --- | --- | --- |',
    "| Planning | $planningStatus | Current approved design and itemized plan |",
    "| Engineering | $engineeringStatus | `$engineeringCommand` (exit $engineeringExitCode); $engineeringLog |",
    "| Installation | $installationStatus | $installerPath; source $installerSourceCommit vs current $commit |",
    "| Real use | $realUseStatus | Recorded real-use run, not fixture-only evidence |",
    "| Human acceptance | $humanAcceptanceStatus | Required named/manual sign-off |",
    "| Formal data | $formalDataStatus | Authorization and data provenance |",
    "| Rollback rehearsal | $rollbackStatus | Rehearsal evidence bound to this candidate |",
    "| Formal release | $formalReleaseStatus | Never inferred from a passing test or candidate |",
    '',
    '## Blockers and reason codes',
    '',
    "- $($reasonCodes -join '; ')",
    '',
    '## Cleanup round one',
    '',
    'For each non-PASS layer, repair only work already authorized by the itemized plan; rerun its verification, update the manifest with the resulting exit code and immutable evidence location, then regenerate a new report at a new path.',
    '',
    '## Second blocker review',
    '',
    'Recheck every remaining blocker once after its stated dependency changes. Preserve external, human, formal-data, destructive, or release blockers with their required input and recovery entry; do not retry unchanged failures or convert them into a PASS.',
    '',
    '## Final user review package',
    '',
    '- Project, task, worktree, branch, current commit, and change summary',
    '- Design/plan readiness result, verification commands, exit codes, logs, and known failures',
    '- Candidate and installer paths, hashes, source-commit binding, and rollback evidence',
    '- Per-layer status, remaining blockers, risks, and recovery entry',
    '',
    '## User-only actions',
    '',
    '- Decide on mainline merge, formal tag, formal release, or promotion of a candidate.',
    '- Approve required human acceptance, formal-data use, and external/public actions.',
    '- Authorize destructive recovery, migration, or changes outside the approved project scope.'
)

Set-Content -LiteralPath $OutputPath -Value ($lines -join [Environment]::NewLine) -Encoding utf8 -NoNewline

[pscustomobject]@{
    overall_verdict = $overallVerdict
    planning_status = $planningStatus
    engineering_status = $engineeringStatus
    installation_status = $installationStatus
    real_use_status = $realUseStatus
    human_acceptance_status = $humanAcceptanceStatus
    formal_release_status = $formalReleaseStatus
    report_path = (Resolve-Path -LiteralPath $OutputPath).Path
    reason_codes = @($reasonCodes)
} | ConvertTo-Json -Compress
