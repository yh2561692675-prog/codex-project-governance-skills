[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Decision = '',
    [string]$P14AdapterPath = ''
)

$ErrorActionPreference = 'Stop'
$reasonCodes = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason {
    param([string]$Code)
    if (-not $reasonCodes.Contains($Code)) { [void]$reasonCodes.Add($Code) }
}

function Add-Unique {
    param($List, [string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) { [void]$List.Add($Value) }
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

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-CanonicalHash {
    param($Object, [string]$ExcludedProperty)
    $ordered = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -ne $ExcludedProperty) { $ordered[$property.Name] = $property.Value }
    }
    $json = $ordered | ConvertTo-Json -Depth 50 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-', '')).ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-ArrayValue {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Get-TestLabel {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $match = [regex]::Match($Command, '(?i)(?:^|[\s"''])(?<path>(?:[^\s"'']+[\\/])*tests[\\/][^\s"'']+\.ps1)(?:$|[\s"''])')
    if ($match.Success) { return $match.Groups['path'].Value.Replace('\', '/') }
    return $Command
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
    param([bool]$Success, $Package)
    $result = [ordered]@{ schema_version = 1; valid = $Success; reason_codes = @($reasonCodes); package = $Package }
    $result | ConvertTo-Json -Depth 50
    if ($Success) { exit 0 } else { exit 1 }
}

$inputFull = Get-FullPath $InputPath
$outputFull = Get-FullPath $OutputPath
if ($null -eq $inputFull) { Add-Reason 'INPUT_PATH_INVALID' }
if ($null -eq $outputFull) { Add-Reason 'OUTPUT_PATH_INVALID' }
if ($null -ne $outputFull -and (Test-Path -LiteralPath $outputFull)) { Add-Reason 'OUTPUT_EXISTS' }
if ($reasonCodes.Count -gt 0) { Finish -Success $false -Package $null }

$source = $null
try { $source = Get-Content -LiteralPath $inputFull -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Add-Reason 'INPUT_INVALID_JSON' }
if ($null -eq $source) { Finish -Success $false -Package $null }

$reviewMode = [string](Get-PropertyValue $source 'review_mode')
if ([string]::IsNullOrWhiteSpace($reviewMode)) { $reviewMode = 'single_user' }
if ($reviewMode -ne 'single_user') { Add-Reason 'REVIEW_MODE_INVALID' }
$decisionValue = $Decision
if ([string]::IsNullOrWhiteSpace($decisionValue)) { $decisionValue = [string](Get-PropertyValue $source 'user_decision') }
if (@('', '通过', '需修改', '不通过') -notcontains $decisionValue) { Add-Reason 'INVALID_DECISION' }

$candidatePath = Get-FullPath ([string](Get-PropertyValue $source 'candidate_manifest_path'))
$impactPath = Get-FullPath ([string](Get-PropertyValue $source 'impact_manifest_path'))
if ($null -eq $candidatePath -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { Add-Reason 'CANDIDATE_MISSING' }
if ($null -eq $impactPath -or -not (Test-Path -LiteralPath $impactPath -PathType Leaf)) { Add-Reason 'IMPACT_MISSING' }
$candidate = $null
$impact = $null
if ($reasonCodes.Count -eq 0) {
    try { $candidate = Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Reason 'CANDIDATE_INVALID_JSON' }
    try { $impact = Get-Content -LiteralPath $impactPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Reason 'IMPACT_INVALID_JSON' }
}
if ($null -eq $candidate -and $reasonCodes.Count -eq 0) { Add-Reason 'CANDIDATE_INVALID' }
if ($null -eq $impact -and $reasonCodes.Count -eq 0) { Add-Reason 'IMPACT_INVALID' }

$candidateHash = [string](Get-PropertyValue $candidate 'candidate_sha256')
$impactHash = [string](Get-PropertyValue $impact 'impact_sha256')
if ($candidateHash -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-CanonicalHash -Object $candidate -ExcludedProperty 'candidate_sha256') -ne $candidateHash.ToUpperInvariant()) { Add-Reason 'CANDIDATE_HASH_MISMATCH' }
if ($impactHash -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-CanonicalHash -Object $impact -ExcludedProperty 'impact_sha256') -ne $impactHash.ToUpperInvariant()) { Add-Reason 'IMPACT_HASH_MISMATCH' }
if ([string](Get-PropertyValue $impact 'candidate_sha256') -ne $candidateHash) { Add-Reason 'IMPACT_CANDIDATE_HASH_MISMATCH' }

$candidateGovernance = Get-PropertyValue $candidate 'governance'
$reviewRequested = [bool](Get-PropertyValue $source 'review_requested')
$candidateRequiredReview = $true
if ($null -ne $candidateGovernance) {
    $candidateRequiredReview = [bool](Get-PropertyValue $candidateGovernance 'required_review')
    if (-not $candidateRequiredReview -and -not $reviewRequested -and [string]::IsNullOrWhiteSpace($Decision) -and [string]::IsNullOrWhiteSpace([string](Get-PropertyValue $source 'user_decision'))) { Add-Reason 'REVIEW_NOT_REQUIRED' }
    $declaredPolicyHash = [string](Get-PropertyValue $source 'policy_hash')
    $candidatePolicyHash = [string](Get-PropertyValue $candidateGovernance 'policy_hash')
    if (-not [string]::IsNullOrWhiteSpace($declaredPolicyHash) -and $declaredPolicyHash.ToUpperInvariant() -ne $candidatePolicyHash.ToUpperInvariant()) { Add-Reason 'POLICY_HASH_MISMATCH' }
    $candidateIdentity = Get-PropertyValue $candidate 'identity'
    $candidateHead = [string](Get-PropertyValue $candidateIdentity 'head')
    $sourceHead = [string](Get-PropertyValue $candidateIdentity 'source_head')
    if (-not [string]::IsNullOrWhiteSpace($sourceHead) -and $sourceHead -ne $candidateHead) { Add-Reason 'CANDIDATE_SOURCE_HEAD_MISMATCH' }
}

$candidateProject = Get-PropertyValue $candidate 'project'
$projectRoot = Get-FullPath ([string](Get-PropertyValue $candidateProject 'root'))
if ($null -eq $projectRoot) { Add-Reason 'PROJECT_ROOT_INVALID' }
if ($null -ne $projectRoot -and $null -ne $candidatePath -and -not (Test-Within $candidatePath $projectRoot)) { Add-Reason 'CANDIDATE_OUTSIDE_PROJECT_ROOT' }
if ($null -ne $projectRoot -and $null -ne $impactPath -and -not (Test-Within $impactPath $projectRoot)) { Add-Reason 'IMPACT_OUTSIDE_PROJECT_ROOT' }
if ($null -ne $projectRoot -and $null -ne $outputFull -and -not (Test-Within $outputFull $projectRoot)) { Add-Reason 'OUTPUT_OUTSIDE_PROJECT_ROOT' }

if ($reasonCodes.Count -gt 0) { Finish -Success $false -Package $null }

$p14Path = $P14AdapterPath
if ([string]::IsNullOrWhiteSpace($p14Path)) { $p14Path = [string](Get-PropertyValue $source 'p14_adapter_path') }
$p14 = [ordered]@{ status = 'SIMPLIFIED_NO_P14'; path = ''; reason_codes = @('P14_ADAPTER_UNAVAILABLE') }
if (-not [string]::IsNullOrWhiteSpace($p14Path)) {
    $p14Full = Get-FullPath $p14Path
    if ($null -ne $p14Full -and (Test-Path -LiteralPath $p14Full -PathType Leaf)) {
        try {
            $null = Get-Content -LiteralPath $p14Full -Raw -Encoding UTF8 | ConvertFrom-Json
            $p14 = [ordered]@{ status = 'P14_ADAPTER_AVAILABLE'; path = $p14Full; reason_codes = @() }
        }
        catch { $p14 = [ordered]@{ status = 'SIMPLIFIED_NO_P14'; path = $p14Full; reason_codes = @('P14_ADAPTER_INVALID') } }
    }
}

$candidateTests = New-Object 'System.Collections.Generic.List[string]'
foreach ($test in (Get-ArrayValue (Get-PropertyValue $candidate 'tests'))) {
    $label = Get-TestLabel -Command ([string](Get-PropertyValue $test 'command'))
    Add-Unique -List $candidateTests -Value $label
}
$changedPaths = @(Get-ArrayValue (Get-PropertyValue $candidate 'changed_paths'))
$affectedPaths = @(Get-ArrayValue (Get-PropertyValue $impact 'affected_paths'))
$affectedTests = @(Get-ArrayValue (Get-PropertyValue $impact 'affected_tests'))
$invalidatedEvidence = @(Get-ArrayValue (Get-PropertyValue $impact 'invalidated_evidence'))
$retainedEvidence = @(Get-ArrayValue (Get-PropertyValue $impact 'retained_evidence'))
$knownFailures = @(Get-ArrayValue (Get-PropertyValue $source 'known_failures'))
$riskNotes = @(Get-ArrayValue (Get-PropertyValue $source 'risk_notes'))
$pendingDecisions = @(Get-ArrayValue (Get-PropertyValue $source 'pending_decisions'))
$rollback = [string](Get-PropertyValue $source 'rollback')
if ([string]::IsNullOrWhiteSpace($rollback)) { $rollback = [string](Get-PropertyValue $candidate 'rollback') }

$revisionScope = [ordered]@{ affected_paths = @(); affected_tests = @(); invalidated_evidence = @(); reason_codes = @() }
if ($decisionValue -eq '需修改') {
    $revisionScope = [ordered]@{ affected_paths = $affectedPaths; affected_tests = $affectedTests; invalidated_evidence = $invalidatedEvidence; reason_codes = @(Get-ArrayValue (Get-PropertyValue $impact 'reason_codes')) }
}

$governanceSummary = [ordered]@{
    required_review = $candidateRequiredReview
    review_requested = $reviewRequested
    delivery_target = if ($null -ne $candidateGovernance) { [string](Get-PropertyValue $candidateGovernance 'delivery_target') } else { '' }
    terminal_state = if ($null -ne $candidateGovernance) { [string](Get-PropertyValue $candidateGovernance 'terminal_state') } else { 'LEGACY_V1_2' }
    policy_hash = if ($null -ne $candidateGovernance) { [string](Get-PropertyValue $candidateGovernance 'policy_hash') } else { '' }
}

$package = [ordered]@{
    schema_version = 1
    review_package_id = [guid]::NewGuid().ToString('N')
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    review_mode = $reviewMode
    project = [ordered]@{ project_id = [string](Get-PropertyValue $candidateProject 'project_id'); root = $projectRoot }
    candidate = [ordered]@{ path = $candidatePath; candidate_sha256 = $candidateHash; project_id = [string](Get-PropertyValue $candidateProject 'project_id'); identity = (Get-PropertyValue $candidate 'identity'); planning = (Get-PropertyValue $candidate 'planning'); risk_tier = [string](Get-PropertyValue $candidate 'risk_tier') }
    impact = [ordered]@{ path = $impactPath; impact_sha256 = $impactHash; candidate_sha256 = $candidateHash; affected_paths = $affectedPaths; affected_tests = $affectedTests; invalidated_evidence = $invalidatedEvidence; retained_evidence = $retainedEvidence; expanded = [bool](Get-PropertyValue $impact 'expanded'); reason_codes = @(Get-ArrayValue (Get-PropertyValue $impact 'reason_codes')) }
    changed_paths = $changedPaths
    tests = @($candidateTests)
    risk_tier = [string](Get-PropertyValue $candidate 'risk_tier')
    governance = $governanceSummary
    risk_notes = $riskNotes
    known_failures = $knownFailures
    rollback = $rollback
    pending_decisions = $pendingDecisions
    decision_options = @('通过', '需修改', '不通过')
    user_decision = $decisionValue
    user_conclusion = ''
    reviewer = ''
    revision_scope = $revisionScope
    p14 = $p14
}
$package.review_package_sha256 = Get-CanonicalHash -Object ([pscustomobject]$package) -ExcludedProperty 'review_package_sha256'
try { Write-CreateOnly -Path $outputFull -Content ($package | ConvertTo-Json -Depth 50) }
catch { Add-Reason 'OUTPUT_CREATE_FAILED'; Finish -Success $false -Package $null }
Finish -Success $true -Package ([pscustomobject]$package)
