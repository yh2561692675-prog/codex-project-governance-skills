[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$resolver = Join-Path $PSScriptRoot 'Resolve-LocalAutonomyPolicy.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) {
    Write-Error 'RED: Resolve-LocalAutonomyPolicy.ps1 is missing.'
    exit 1
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory = $true)][string]$Message)
    if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')" }
}

function Assert-Contains {
    param([object[]]$Values, [Parameter(Mandatory = $true)][string]$Expected, [Parameter(Mandatory = $true)][string]$Message)
    $strings = @($Values | ForEach-Object { [string]$_ })
    if ($strings -notcontains $Expected) { throw "ASSERTION_FAILED: $Message (missing '$Expected')" }
}

function Write-JsonFixture {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    $json = $Value | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function New-Input {
    param(
        [string]$Target = 'ENGINEERING_ONLY',
        [string]$Release = 'NONE',
        [string]$Review = 'NONE',
        [bool]$Installation = $false,
        [bool]$LocalSmoke = $false,
        [bool]$UserReview = $false,
        [string[]]$HardTriggers = @(),
        [bool]$IdentityBlocked = $false,
        [bool]$Conflict = $false,
        [bool]$Destructive = $false,
        [bool]$UnknownRisk = $false
    )
    $identityStatus = if ($IdentityBlocked) { 'BLOCKED' } else { 'READY' }
    return [ordered]@{
        schema_version = 1
        project_id = 'fixture-autonomous-local'
        delivery_target = $Target
        release_intent = $Release
        review_policy = $Review
        effective_from_fresh_run = $true
        risk = [ordered]@{
            identity_preflight = $identityStatus
            shared_resource_conflict = $Conflict
            destructive_action = $Destructive
            unknown = $UnknownRisk
            hard_triggers = @($HardTriggers)
        }
        evidence = [ordered]@{
            plan = $true
            engineering = $true
            candidate_identity = $true
            rollback = $true
            installation = $Installation
            local_smoke = $LocalSmoke
            user_final_review = $UserReview
            real_use = $false
            human_acceptance = $false
            formal_data = $false
        }
    }
}

function Invoke-Resolver {
    param([Parameter(Mandatory = $true)]$InputObject, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$PolicyPath)
    $inputPath = Join-Path $Root ([guid]::NewGuid().ToString('N') + '.json')
    Write-JsonFixture -Path $inputPath -Value $InputObject
    $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver -InputPath $inputPath -PolicyPath $PolicyPath 2>&1)
    $exitCode = $LASTEXITCODE
    $json = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json }
}

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$policyPath = Join-Path $root 'config\lightweight-governance\risk-policy-v2.json'
$tempRoot = Join-Path 'X:\Projects\01_Active\15_项目开发治理Skills\99_Temp\autonomous-local-v1_3' ('T03-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $safeEngineering = Invoke-Resolver -InputObject (New-Input) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $safeEngineering.ExitCode 0 'Safe engineering-only must exit 0'
    Assert-Equal $safeEngineering.Json.terminal_state 'LOCAL_CANDIDATE_READY' 'Safe engineering-only terminal state'
    Assert-Equal $safeEngineering.Json.required_review $false 'Safe engineering-only must not require review'
    $releaseLayer = @($safeEngineering.Json.layers | Where-Object { $_.name -eq 'formal_release' })[0]
    Assert-Equal $releaseLayer.status 'NOT_APPLICABLE' 'Formal release must be N/A for engineering-only'
    if ([string]::IsNullOrWhiteSpace([string]$releaseLayer.applicability_reason)) { throw 'Engineering-only N/A reason must not be empty.' }
    Write-Output 'PASS engineering_only_local_candidate'

    $localMissing = Invoke-Resolver -InputObject (New-Input -Target 'LOCAL_USABLE') -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $localMissing.ExitCode 1 'Local-usable without installation must fail closed'
    Assert-Equal $localMissing.Json.terminal_state 'BLOCKED' 'Local-usable without installation must block'
    Assert-Contains @($localMissing.Json.reason_codes) 'INSTALLATION_EVIDENCE_REQUIRED' 'Missing installation reason'
    Write-Output 'PASS local_usable_missing_evidence_blocked'

    $localReady = Invoke-Resolver -InputObject (New-Input -Target 'LOCAL_USABLE' -Installation $true -LocalSmoke $true) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $localReady.ExitCode 0 'Local-usable with installation and smoke must exit 0'
    Assert-Equal $localReady.Json.terminal_state 'LOCAL_USABLE_READY' 'Local-usable terminal state'
    Write-Output 'PASS local_usable_ready'

    $optional = Invoke-Resolver -InputObject (New-Input -Target 'LOCAL_USABLE' -Review 'OPTIONAL' -Installation $true -LocalSmoke $true) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $optional.ExitCode 0 'Optional review local task must exit 0'
    Assert-Equal $optional.Json.terminal_state 'OPTIONAL_REVIEW_AVAILABLE' 'Optional review terminal state'
    Assert-Equal $optional.Json.required_review $false 'Optional review must not be required'
    Write-Output 'PASS optional_review_available'

    $internal = Invoke-Resolver -InputObject (New-Input -Target 'INTERNAL_REVIEW' -Review 'REQUIRED' -UserReview $true) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $internal.ExitCode 0 'Internal review task with receipt must exit 0'
    Assert-Equal $internal.Json.terminal_state 'USER_FINAL_REVIEW' 'Internal review terminal state'
    Assert-Equal $internal.Json.required_review $true 'Internal review must require review'
    Write-Output 'PASS required_user_review'

    $invalid = Invoke-Resolver -InputObject (New-Input -Target 'FORMAL_RELEASE' -Release 'NONE' -Review 'NONE') -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $invalid.ExitCode 1 'Invalid formal release combination must fail'
    Assert-Contains @($invalid.Json.reason_codes) 'V1_1_DELIVERY_INTENT_INVALID' 'Invalid intent reason'
    Write-Output 'PASS invalid_intent_blocked'

    $hard = Invoke-Resolver -InputObject (New-Input -HardTriggers @('formal_data')) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $hard.ExitCode 0 'Hard trigger must produce an escalation result'
    Assert-Equal $hard.Json.terminal_state 'ESCALATED_REVIEW' 'Hard trigger must escalate'
    Assert-Equal $hard.Json.required_review $true 'Hard trigger must require review'
    Write-Output 'PASS hard_trigger_escalated'

    $conflict = Invoke-Resolver -InputObject (New-Input -Conflict $true) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $conflict.ExitCode 1 'Shared resource conflict must block local autonomy'
    Assert-Equal $conflict.Json.terminal_state 'BLOCKED' 'Shared resource conflict terminal state'
    Assert-Contains @($conflict.Json.reason_codes) 'SHARED_RESOURCE_CONFLICT' 'Conflict reason'
    Write-Output 'PASS shared_conflict_blocked'

    $destructive = Invoke-Resolver -InputObject (New-Input -Destructive $true) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $destructive.ExitCode 1 'Destructive action must block local autonomy'
    Assert-Contains @($destructive.Json.reason_codes) 'DESTRUCTIVE_ACTION_BLOCKED' 'Destructive reason'
    Write-Output 'PASS destructive_action_blocked'

    $unknown = Invoke-Resolver -InputObject (New-Input -UnknownRisk $true) -Root $tempRoot -PolicyPath $policyPath
    Assert-Equal $unknown.ExitCode 1 'Unknown risk must block local autonomy'
    Assert-Contains @($unknown.Json.reason_codes) 'RISK_UNKNOWN' 'Unknown risk reason'
    Write-Output 'PASS unknown_risk_blocked'

    Write-Output 'LOCAL_AUTONOMY_POLICY_TESTS=PASS'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    Write-Output 'LOCAL_AUTONOMY_POLICY_TESTS=FAIL'
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
