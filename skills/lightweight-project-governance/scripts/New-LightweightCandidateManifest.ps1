[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$reasonCodes = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason {
    param([Parameter(Mandatory = $true)][string]$Code)
    if (-not $reasonCodes.Contains($Code)) { [void]$reasonCodes.Add($Code) }
}

function Get-FullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { return [IO.Path]::GetFullPath($Path) } catch { return $null }
}

function Test-Within {
    param([string]$Path, [string]$Root)
    $pathFull = Get-FullPath $Path
    $rootFull = Get-FullPath $Root
    if ($null -eq $pathFull -or $null -eq $rootFull) { return $false }
    $pathTrimmed = $pathFull.TrimEnd('\')
    $rootTrimmed = $rootFull.TrimEnd('\')
    return $pathTrimmed.Equals($rootTrimmed, [StringComparison]::OrdinalIgnoreCase) -or $pathTrimmed.StartsWith($rootTrimmed + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    $leftFull = Get-FullPath $Left
    $rightFull = Get-FullPath $Right
    return $null -ne $leftFull -and $null -ne $rightFull -and $leftFull.TrimEnd('\').Equals($rightFull.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-GitValue {
    param([string]$GitRoot, [string[]]$Arguments, [string]$FailureCode)
    $lines = @(& git -C $GitRoot --no-optional-locks @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { Add-Reason $FailureCode; return '' }
    return (($lines | Select-Object -First 1).ToString()).Trim()
}

function Get-CanonicalHash {
    param($Object)
    $ordered = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -ne 'candidate_sha256') { $ordered[$property.Name] = $property.Value }
    }
    $json = $ordered | ConvertTo-Json -Depth 40 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-', '')).ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Write-CreateOnly {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

function Finish {
    param([bool]$Success, $Candidate)
    $result = [ordered]@{
        schema_version = 1
        valid = $Success
        reason_codes = @($reasonCodes)
        candidate = $Candidate
    }
    $result | ConvertTo-Json -Depth 40
    if ($Success) { exit 0 } else { exit 1 }
}

$inputFull = Get-FullPath $InputPath
$outputFull = Get-FullPath $OutputPath
if ($null -eq $inputFull) { Add-Reason 'INPUT_PATH_INVALID' }
if ($null -eq $outputFull) { Add-Reason 'OUTPUT_PATH_INVALID' }
if ($null -ne $outputFull -and (Test-Path -LiteralPath $outputFull)) { Add-Reason 'OUTPUT_EXISTS' }
if ($reasonCodes.Count -gt 0) { Finish -Success $false -Candidate $null }

$source = $null
try { $source = Get-Content -LiteralPath $inputFull -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Add-Reason 'INPUT_INVALID_JSON' }
if ($null -eq $source) { Finish -Success $false -Candidate $null }

$projectId = [string](Get-PropertyValue $source 'project_id')
$declaredRoot = Get-FullPath ([string](Get-PropertyValue $source 'project_root'))
$declaredWorktree = Get-FullPath ([string](Get-PropertyValue $source 'worktree'))
if ([string]::IsNullOrWhiteSpace($projectId)) { Add-Reason 'PROJECT_ID_MISSING' }
if ($null -eq $declaredRoot) { Add-Reason 'PROJECT_ROOT_INVALID' }
if ($null -eq $declaredWorktree) { Add-Reason 'WORKTREE_INVALID' }
if ($null -ne $declaredRoot -and -not (Test-Path -LiteralPath $declaredRoot -PathType Container)) { Add-Reason 'PROJECT_ROOT_MISSING' }
if ($null -ne $declaredRoot -and $null -ne $declaredWorktree -and -not (Test-SamePath $declaredRoot $declaredWorktree)) { Add-Reason 'WORKTREE_ROOT_MISMATCH' }
if ($null -ne $outputFull -and $null -ne $declaredRoot -and -not (Test-Within $outputFull $declaredRoot)) { Add-Reason 'OUTPUT_OUTSIDE_PROJECT_ROOT' }

$designPath = Get-FullPath ([string](Get-PropertyValue $source 'design_path'))
$planPath = Get-FullPath ([string](Get-PropertyValue $source 'plan_path'))
if ($null -eq $designPath -or -not (Test-Path -LiteralPath $designPath -PathType Leaf)) { Add-Reason 'DESIGN_PATH_INVALID' }
if ($null -eq $planPath -or -not (Test-Path -LiteralPath $planPath -PathType Leaf)) { Add-Reason 'PLAN_PATH_INVALID' }
if ($null -ne $declaredRoot -and $null -ne $designPath -and -not (Test-Within $designPath $declaredRoot)) { Add-Reason 'DESIGN_OUTSIDE_PROJECT_ROOT' }
if ($null -ne $declaredRoot -and $null -ne $planPath -and -not (Test-Within $planPath $declaredRoot)) { Add-Reason 'PLAN_OUTSIDE_PROJECT_ROOT' }

$declaredBranch = [string](Get-PropertyValue $source 'branch')
$declaredHead = [string](Get-PropertyValue $source 'head')
$declaredDirty = Get-PropertyValue $source 'dirty'
if ([string]::IsNullOrWhiteSpace($declaredBranch)) { Add-Reason 'GIT_BRANCH_MISSING' }
if ($declaredHead -notmatch '^[0-9a-fA-F]{40}$') { Add-Reason 'GIT_HEAD_INVALID' }
if ($declaredDirty -isnot [bool]) { Add-Reason 'DIRTY_STATE_INVALID' }

$changedPaths = @((Get-PropertyValue $source 'changed_paths') | ForEach-Object { [string]$_ })
if ($changedPaths.Count -eq 0) { Add-Reason 'CHANGED_PATHS_MISSING' }
foreach ($path in $changedPaths) {
    if ([string]::IsNullOrWhiteSpace($path) -or [IO.Path]::IsPathRooted($path) -or $path -match '(^|[\\/])\.\.([\\/]|$)') { Add-Reason 'CHANGED_PATH_OUTSIDE_PROJECT' }
}

$tests = @((Get-PropertyValue $source 'tests'))
if ($tests.Count -eq 0) { Add-Reason 'TESTS_MISSING' }
foreach ($test in $tests) {
    $command = [string](Get-PropertyValue $test 'command')
    $exit = Get-PropertyValue $test 'exit_code'
    if ([string]::IsNullOrWhiteSpace($command)) { Add-Reason 'TEST_COMMAND_MISSING' }
    if ($exit -isnot [int] -and $exit -isnot [long] -and $exit -isnot [double]) { Add-Reason 'TEST_EXIT_CODE_INVALID' }
}

$artifacts = @((Get-PropertyValue $source 'artifacts'))
foreach ($artifact in $artifacts) {
    if ($null -eq $artifact) { continue }
    $artifactPath = [string](Get-PropertyValue $artifact 'path')
    if ([string]::IsNullOrWhiteSpace($artifactPath) -or [IO.Path]::IsPathRooted($artifactPath) -or $artifactPath -match '(^|[\\/])\.\.([\\/]|$)') { Add-Reason 'ARTIFACT_PATH_INVALID' }
    if ($null -ne $declaredRoot -and -not (Test-Within (Join-Path $declaredRoot $artifactPath) $declaredRoot)) { Add-Reason 'ARTIFACT_OUTSIDE_PROJECT_ROOT' }
    $artifactFull = if ($null -ne $declaredRoot -and -not [IO.Path]::IsPathRooted($artifactPath)) { Join-Path $declaredRoot $artifactPath } else { $artifactPath }
    if (-not (Test-Path -LiteralPath $artifactFull -PathType Leaf)) { Add-Reason 'ARTIFACT_MISSING' }
    $expectedHash = [string](Get-PropertyValue $artifact 'sha256')
    if (-not [string]::IsNullOrWhiteSpace($expectedHash) -and (Test-Path -LiteralPath $artifactFull -PathType Leaf)) {
        if ((Get-FileHash -LiteralPath $artifactFull -Algorithm SHA256).Hash.ToUpperInvariant() -ne $expectedHash.ToUpperInvariant()) { Add-Reason 'ARTIFACT_HASH_MISMATCH' }
    }
}

$riskTier = [string](Get-PropertyValue $source 'risk_tier')
if (@('LIGHTWEIGHT', 'CANDIDATE', 'ESCALATED', 'BLOCKED') -notcontains $riskTier) { Add-Reason 'RISK_TIER_INVALID' }
$rollback = [string](Get-PropertyValue $source 'rollback')
if ([string]::IsNullOrWhiteSpace($rollback)) { Add-Reason 'ROLLBACK_MISSING' }
$designHash = [string](Get-PropertyValue $source 'design_hash')
$planHash = [string](Get-PropertyValue $source 'plan_hash')
if ($designHash -notmatch '^[0-9a-fA-F]{64}$' -or $planHash -notmatch '^[0-9a-fA-F]{64}$') { Add-Reason 'PLANNING_HASH_INVALID' }
$policyPath = Get-FullPath ([string](Get-PropertyValue $source 'policy_path'))
$profileSchemaPath = Get-FullPath ([string](Get-PropertyValue $source 'profile_schema_path'))
$policyHash = [string](Get-PropertyValue $source 'policy_hash')
$profileSchemaHash = [string](Get-PropertyValue $source 'profile_schema_hash')
$deliveryTarget = [string](Get-PropertyValue $source 'delivery_target')
$releaseIntent = [string](Get-PropertyValue $source 'release_intent')
$reviewPolicy = [string](Get-PropertyValue $source 'review_policy')
$resolverResult = Get-PropertyValue $source 'resolver_result'
$sourceDirtyFingerprint = [string](Get-PropertyValue $source 'dirty_fingerprint')
if ($null -ne $resolverResult) {
    if ([string]::IsNullOrWhiteSpace([string](Get-PropertyValue $resolverResult 'terminal_state'))) { Add-Reason 'GOVERNANCE_TERMINAL_STATE_MISSING' }
    if ([string]::IsNullOrWhiteSpace($deliveryTarget) -or [string]::IsNullOrWhiteSpace($releaseIntent) -or [string]::IsNullOrWhiteSpace($reviewPolicy)) { Add-Reason 'GOVERNANCE_INTENT_MISSING' }
    if ($policyHash -notmatch '^[0-9a-fA-F]{64}$' -or $null -eq $policyPath -or -not (Test-Path -LiteralPath $policyPath -PathType Leaf) -or -not (Test-Within $policyPath $declaredRoot)) { Add-Reason 'POLICY_PATH_INVALID' }
    if ($profileSchemaHash -notmatch '^[0-9a-fA-F]{64}$' -or $null -eq $profileSchemaPath -or -not (Test-Path -LiteralPath $profileSchemaPath -PathType Leaf) -or -not (Test-Within $profileSchemaPath $declaredRoot)) { Add-Reason 'PROFILE_SCHEMA_PATH_INVALID' }
    if ($null -ne $policyPath -and (Test-Path -LiteralPath $policyPath -PathType Leaf) -and ((Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $policyHash.ToUpperInvariant())) { Add-Reason 'POLICY_HASH_MISMATCH' }
    if ($null -ne $profileSchemaPath -and (Test-Path -LiteralPath $profileSchemaPath -PathType Leaf) -and ((Get-FileHash -LiteralPath $profileSchemaPath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $profileSchemaHash.ToUpperInvariant())) { Add-Reason 'PROFILE_SCHEMA_HASH_MISMATCH' }
    if ($sourceDirtyFingerprint -notmatch '^[0-9a-fA-F]{64}$') { Add-Reason 'DIRTY_FINGERPRINT_INVALID' }
}
if ($reasonCodes.Count -gt 0) { Finish -Success $false -Candidate $null }

$currentRoot = Get-GitValue -GitRoot $declaredRoot -Arguments @('rev-parse', '--show-toplevel') -FailureCode 'GIT_ROOT_UNAVAILABLE'
$currentBranch = Get-GitValue -GitRoot $declaredRoot -Arguments @('branch', '--show-current') -FailureCode 'GIT_BRANCH_UNAVAILABLE'
$currentHead = Get-GitValue -GitRoot $declaredRoot -Arguments @('rev-parse', 'HEAD') -FailureCode 'GIT_HEAD_UNAVAILABLE'
$statusLines = @(& git -C $declaredRoot --no-optional-locks status --porcelain 2>$null)
if ($LASTEXITCODE -ne 0) { Add-Reason 'GIT_STATUS_UNAVAILABLE' }
$currentDirty = $statusLines.Count -gt 0
if (-not (Test-SamePath $declaredRoot $currentRoot)) { Add-Reason 'GIT_ROOT_MISMATCH' }
if (-not (Test-SamePath $declaredRoot $declaredWorktree)) { Add-Reason 'WORKTREE_ROOT_MISMATCH' }
if ($declaredBranch -ne $currentBranch) { Add-Reason 'GIT_BRANCH_MISMATCH' }
if ($declaredHead.ToLowerInvariant() -ne $currentHead.ToLowerInvariant()) { Add-Reason 'GIT_HEAD_MISMATCH' }
if ([bool]$declaredDirty -ne $currentDirty) { Add-Reason 'DIRTY_STATE_MISMATCH' }

$actualDesignHash = (Get-FileHash -LiteralPath $designPath -Algorithm SHA256).Hash.ToUpperInvariant()
$actualPlanHash = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($designHash.ToUpperInvariant() -ne $actualDesignHash -or $planHash.ToUpperInvariant() -ne $actualPlanHash) { Add-Reason 'PLANNING_HASH_MISMATCH' }
if ($reasonCodes.Count -gt 0) { Finish -Success $false -Candidate $null }

$terminalState = if ($null -ne $resolverResult) { [string](Get-PropertyValue $resolverResult 'terminal_state') } else { 'CANDIDATE_AUTOMATED' }
$requiredReview = if ($null -ne $resolverResult) { [bool](Get-PropertyValue $resolverResult 'required_review') } else { $true }
$governance = if ($null -ne $resolverResult) {
    [ordered]@{
        mode = [string](Get-PropertyValue $resolverResult 'governance_mode')
        terminal_state = $terminalState
        required_review = $requiredReview
        delivery_target = $deliveryTarget
        release_intent = $releaseIntent
        review_policy = $reviewPolicy
        policy_hash = $policyHash.ToUpperInvariant()
        profile_schema_hash = $profileSchemaHash.ToUpperInvariant()
        layers = @((Get-PropertyValue $resolverResult 'layers'))
    }
} else { [ordered]@{ mode = 'LEGACY_V1_2'; terminal_state = $terminalState; required_review = $requiredReview; delivery_target = ''; release_intent = ''; review_policy = ''; policy_hash = ''; profile_schema_hash = ''; layers = @() } }
$candidate = [ordered]@{
    schema_version = 1
    candidate_id = [guid]::NewGuid().ToString('N')
    # Keep the timestamp string non-ISO so PowerShell ConvertFrom-Json does not
    # coerce it to DateTime with shell-dependent fractional precision before
    # candidate_sha256 is recomputed by downstream validators.
    created_at_utc = 'utc-' + [DateTime]::UtcNow.Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
    state = $terminalState
    project = [ordered]@{ project_id = $projectId; root = $declaredRoot }
    identity = [ordered]@{ worktree = $declaredWorktree; branch = $currentBranch; head = $currentHead; source_head = $currentHead; dirty = $currentDirty; dirty_fingerprint = $sourceDirtyFingerprint }
    planning = [ordered]@{ design_path = $designPath; plan_path = $planPath; design_hash = $actualDesignHash; plan_hash = $actualPlanHash }
    changed_paths = @($changedPaths)
    tests = @($tests)
    artifacts = @($artifacts)
    risk_tier = $riskTier
    governance = $governance
    rollback = $rollback
}
$candidate.candidate_sha256 = Get-CanonicalHash -Object ([pscustomobject]$candidate)
try {
    Write-CreateOnly -Path $outputFull -Content ($candidate | ConvertTo-Json -Depth 40)
}
catch {
    Add-Reason 'OUTPUT_CREATE_FAILED'
    Finish -Success $false -Candidate $null
}
Finish -Success $true -Candidate ([pscustomobject]$candidate)
