[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-StringArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { [string]$_ })
}

function Add-Unique {
    param([System.Collections.Generic.List[string]]$List, [string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        [void]$List.Add($Value)
    }
}

function Read-Adapter {
    param([string]$AdapterType)
    $adapterFile = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'adapters\lightweight-governance') ($AdapterType + '.json')
    if (-not (Test-Path -LiteralPath $adapterFile -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $adapterFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-CreateOnly {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

function Write-Failure {
    param([string]$Code, [string]$Message)
    $failure = [ordered]@{
        schema_version = 1
        valid = $false
        mode = 'blocked'
        migration_suggestion = [ordered]@{ recommended_adapter = $null; actions = @() }
        candidate_profile = $null
        diff = [ordered]@{ preserved_hard_gates = @(); preserved_historical_evidence = @(); manual_mapping_required = @($Code); removed_count = 0 }
        error = [ordered]@{ code = $Code; message = $Message }
    }
    $failure | ConvertTo-Json -Depth 30
    exit 1
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    Write-Failure -Code 'INPUT_MISSING' -Message 'The source profile does not exist.'
}
if ([System.IO.Path]::GetFullPath($InputPath).Equals([System.IO.Path]::GetFullPath($OutputPath), [StringComparison]::OrdinalIgnoreCase)) {
    Write-Failure -Code 'SOURCE_OUTPUT_COLLISION' -Message 'The converter requires a separate output path.'
}

$source = $null
try { $source = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Failure -Code 'INPUT_INVALID_JSON' -Message 'The source profile is not valid JSON.' }
if ($null -eq $source) { Write-Failure -Code 'INPUT_INVALID_JSON' -Message 'The source profile is empty.' }

$knownFields = @('schema_version', 'project_id', 'adapter_type', 'hard_gates', 'historical_evidence', 'legacy_mode')
$manualMapping = New-Object 'System.Collections.Generic.List[string]'
foreach ($property in $source.PSObject.Properties) {
    if ($knownFields -notcontains $property.Name) { Add-Unique -List $manualMapping -Value $property.Name }
}

$schemaValue = Get-PropertyValue -Object $source -Name 'schema_version'
$isModernShape = $null -ne $schemaValue -and [int]$schemaValue -eq 1
$mode = if ($isModernShape) { 'migration_suggestion' } else { 'legacy_fallback' }
$adapterType = ([string](Get-PropertyValue -Object $source -Name 'adapter_type')).Trim().ToLowerInvariant()
$supportedAdapterTypes = @('high-impact-data', 'content-media', 'infrastructure-tooling')
if ($mode -eq 'legacy_fallback') {
    $adapterType = 'legacy'
}
elseif ($supportedAdapterTypes -notcontains $adapterType) {
    if (-not [string]::IsNullOrWhiteSpace($adapterType)) { Add-Unique -List $manualMapping -Value 'adapter_type' }
    $adapterType = 'legacy'
}

$hardGates = New-Object 'System.Collections.Generic.List[string]'
foreach ($gate in (Get-StringArray (Get-PropertyValue -Object $source -Name 'hard_gates'))) { Add-Unique -List $hardGates -Value $gate }
$historicalEvidence = New-Object 'System.Collections.Generic.List[string]'
foreach ($reference in (Get-StringArray (Get-PropertyValue -Object $source -Name 'historical_evidence'))) { Add-Unique -List $historicalEvidence -Value $reference }

$adapter = if ($adapterType -eq 'legacy') { $null } else { Read-Adapter -AdapterType $adapterType }
$defaultReview = if ($null -ne $adapter) { $adapter.default_final_review } else { [ordered]@{ required = $true; decision_values = @('通过', '需修改', '不通过'); human_fields = @('decision', 'reviewer', 'notes') } }
$triggers = if ($null -ne $adapter) { $adapter.triggers } else { [ordered]@{ data = @(); media = @(); permissions = @() } }
$tests = if ($null -ne $adapter) { $adapter.tests } else { [ordered]@{ commands = @(); required_cases = @('legacy_review') } }
$rollback = if ($null -ne $adapter) { $adapter.rollback } else { [ordered]@{ strategy = 'Continue with the source legacy governance profile.'; steps = @('Keep the source profile unchanged.', 'Discard the migration candidate.', 'Re-enter the legacy review path.') } }

$actions = New-Object 'System.Collections.Generic.List[string]'
Add-Unique -List $actions -Value 'review_migration_suggestion'
Add-Unique -List $actions -Value 'preserve_hard_gates'
Add-Unique -List $actions -Value 'preserve_historical_evidence'
if ($manualMapping.Count -gt 0) { Add-Unique -List $actions -Value 'review_unknown_fields' }
if ($mode -eq 'legacy_fallback') { Add-Unique -List $actions -Value 'keep_legacy_fallback_until_manual_mapping' }

$candidateProfile = [ordered]@{
    adapter_type = $adapterType
    default_final_review = $defaultReview
    triggers = $triggers
    tests = $tests
    rollback = $rollback
    hard_gates = @($hardGates)
    historical_evidence = @($historicalEvidence)
    manual_mapping_required = @($manualMapping)
}
$diff = [ordered]@{
    preserved_hard_gates = @($hardGates)
    preserved_historical_evidence = @($historicalEvidence)
    manual_mapping_required = @($manualMapping)
    added_fields = @('default_final_review', 'triggers', 'tests', 'rollback')
    removed_fields = @()
    removed_count = 0
}
$result = [ordered]@{
    schema_version = 1
    valid = $true
    mode = $mode
    migration_suggestion = [ordered]@{
        recommended_adapter = if ($adapterType -eq 'legacy') { $null } else { $adapterType }
        actions = @($actions)
        fallback = 'legacy'
    }
    candidate_profile = $candidateProfile
    diff = $diff
}

try { Write-CreateOnly -Path $OutputPath -Content ($result | ConvertTo-Json -Depth 30) }
catch { Write-Failure -Code 'OUTPUT_CREATE_FAILED' -Message 'The converter could not create the requested output.' }

$result | ConvertTo-Json -Depth 30
exit 0
