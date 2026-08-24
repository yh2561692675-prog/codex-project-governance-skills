[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$reasons = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason {
    param([Parameter(Mandatory = $true)][string]$Code)
    if (-not $reasons.Contains($Code)) { [void]$reasons.Add($Code) }
}

function Get-Value {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Resolve-LocalPath {
    param([string]$Path, [string]$Base)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
        return [IO.Path]::GetFullPath((Join-Path $Base $Path))
    }
    catch { return $null }
}

function Read-Json {
    param([string]$Path)
    try {
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        return [IO.File]::ReadAllText($Path, $strictUtf8) | ConvertFrom-Json
    }
    catch { Add-Reason 'JSON_INVALID'; return $null }
}

function Finish {
    param([bool]$Valid)
    $result = [ordered]@{ schema_version = 1; valid = $Valid; reason_codes = @($reasons); manifest_path = $ManifestPath }
    $result | ConvertTo-Json -Depth 30 -Compress
    if (-not $Valid) { exit 1 }
    exit 0
}

$manifestFull = Resolve-LocalPath -Path $ManifestPath -Base (Get-Location).Path
if ($null -eq $manifestFull -or -not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { Add-Reason 'MANIFEST_MISSING'; Finish -Valid $false }
$manifest = Read-Json -Path $manifestFull
if ($null -eq $manifest) { Finish -Valid $false }
$base = Split-Path -Parent $manifestFull
$serialized = $manifest | ConvertTo-Json -Depth 60 -Compress
if ($serialized -match '\{\{[^}]+\}\}') { Add-Reason 'TEMPLATE_VARIABLE_REMAINS' }

$preflight = [string](Get-Value -Object $manifest -Name 'preflight_status')
$terminal = [string](Get-Value -Object $manifest -Name 'terminal_state')
$previousTerminal = [string](Get-Value -Object $manifest -Name 'previous_terminal_state')
if ($preflight -eq 'BLOCKED' -and $terminal -ne 'BLOCKED') { Add-Reason 'BLOCKED_PREFLIGHT_COMPLETION' }
if ($previousTerminal -eq 'BLOCKED' -and $terminal -notin @('', 'BLOCKED')) { Add-Reason 'TERMINAL_REVIVAL_BLOCKED' }

$candidateMeta = Get-Value -Object $manifest -Name 'candidate'
$candidatePath = Resolve-LocalPath -Path ([string](Get-Value -Object $candidateMeta -Name 'path')) -Base $base
if ($null -eq $candidatePath -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
    Add-Reason 'CANDIDATE_REFERENCE_MISSING'
}
else {
    $candidate = Read-Json -Path $candidatePath
    $expectedCandidateHash = [string](Get-Value -Object $candidateMeta -Name 'sha256')
    if ($expectedCandidateHash -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $expectedCandidateHash.ToUpperInvariant()) { Add-Reason 'CANDIDATE_HASH_MISMATCH' }
    $candidateIdentity = Get-Value -Object $candidate -Name 'identity'
    $candidateSourceHead = [string](Get-Value -Object $candidateMeta -Name 'source_head')
    $actualSourceHead = [string](Get-Value -Object $candidateIdentity -Name 'source_head')
    $actualHead = [string](Get-Value -Object $candidateIdentity -Name 'head')
    if (-not [string]::IsNullOrWhiteSpace($candidateSourceHead) -and $candidateSourceHead -ne $actualSourceHead) { Add-Reason 'SOURCE_HEAD_DRIFT' }
    if (-not [string]::IsNullOrWhiteSpace($actualSourceHead) -and $actualSourceHead -ne $actualHead) { Add-Reason 'SOURCE_HEAD_DRIFT' }
}

$policyMeta = Get-Value -Object $manifest -Name 'policy'
$policyPath = Resolve-LocalPath -Path ([string](Get-Value -Object $policyMeta -Name 'path')) -Base $base
if ($null -eq $policyPath -or -not (Test-Path -LiteralPath $policyPath -PathType Leaf)) { Add-Reason 'POLICY_REFERENCE_MISSING' }
else {
    $expectedPolicyHash = [string](Get-Value -Object $policyMeta -Name 'sha256')
    if ($expectedPolicyHash -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $expectedPolicyHash.ToUpperInvariant()) { Add-Reason 'POLICY_HASH_MISMATCH' }
}

foreach ($reference in @((Get-Value -Object $manifest -Name 'required_references'))) {
    $referencePath = Resolve-LocalPath -Path ([string]$reference) -Base $base
    if ($null -eq $referencePath -or -not (Test-Path -LiteralPath $referencePath -PathType Leaf)) { Add-Reason 'REQUIRED_REFERENCE_MISSING' }
}

$target = [string](Get-Value -Object $manifest -Name 'delivery_target')
$formalReleaseStatus = [string](Get-Value -Object $manifest -Name 'formal_release_status')
if ($target -eq 'FORMAL_RELEASE' -and $formalReleaseStatus -ne 'READY_FOR_USER_DECISION') { Add-Reason 'FORMAL_RELEASE_GATE_MISSING' }

Finish -Valid ($reasons.Count -eq 0)
