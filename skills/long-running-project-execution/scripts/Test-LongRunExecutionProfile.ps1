[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'
$hardReasons = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason {
    param([string]$Code)
    if (-not $hardReasons.Contains($Code)) { [void]$hardReasons.Add($Code) }
}

function Get-Field {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Resolve-AbsolutePath {
    param([string]$Value, [string]$ProjectRoot)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        $candidate = if ([System.IO.Path]::IsPathRooted($Value)) { $Value } else { Join-Path $ProjectRoot $Value }
        return [System.IO.Path]::GetFullPath($candidate)
    }
    catch { return $null }
}

function Test-Within {
    param([string]$Candidate, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\')
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $candidateFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Write-ResultAndExit {
    param([bool]$Valid, [object]$Profile, [string]$ProjectRoot, [string]$ProfileFullPath)
    $result = [ordered]@{
        schema_version = 1
        valid = $Valid
        reason_codes = @($hardReasons)
        profile_path = $ProfileFullPath
        project_root = $ProjectRoot
        normalized_profile = $Profile
    }
    $result | ConvertTo-Json -Depth 16
    if ($Valid) { exit 0 } else { exit 1 }
}

try {
    $profileFullPath = [System.IO.Path]::GetFullPath($ProfilePath)
}
catch {
    Add-Reason 'PROFILE_PATH_INVALID'
    Write-ResultAndExit -Valid $false -Profile $null -ProjectRoot $null -ProfileFullPath $ProfilePath
}

if (-not (Test-Path -LiteralPath $profileFullPath -PathType Leaf)) {
    Add-Reason 'PROFILE_MISSING'
    Write-ResultAndExit -Valid $false -Profile $null -ProjectRoot $null -ProfileFullPath $profileFullPath
}

try {
    $profile = Get-Content -LiteralPath $profileFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
    Add-Reason 'INVALID_JSON'
    Write-ResultAndExit -Valid $false -Profile $null -ProjectRoot $null -ProfileFullPath $profileFullPath
}

$profileDirectory = Split-Path -Parent $profileFullPath
$defaultProjectRoot = Split-Path -Parent (Split-Path -Parent $profileDirectory)
$projectRootValue = Get-Field $profile 'projectRoot'
if ([string]::IsNullOrWhiteSpace([string]$projectRootValue)) { $projectRootValue = $defaultProjectRoot }
$projectRoot = Resolve-AbsolutePath -Value ([string]$projectRootValue) -ProjectRoot $defaultProjectRoot
if ($null -eq $projectRoot) {
    Add-Reason 'PROJECT_ROOT_INVALID'
    Write-ResultAndExit -Valid $false -Profile $profile -ProjectRoot $null -ProfileFullPath $profileFullPath
}

$xDriveRoot = 'X' + ':\'
if ([System.IO.Path]::GetPathRoot($projectRoot) -ine $xDriveRoot) { Add-Reason 'NOT_X_DRIVE' }

$requiredFields = @('schemaVersion','projectId','designPath','planPath','allowedWritePaths','protectedPaths','runtimeRoot','evidenceRoot','sharedResources','defaultVerificationCommands','humanGates','modelPolicy','maxEffectiveRetries','unfinishedCleanupRounds')
foreach ($field in $requiredFields) {
    $value = Get-Field $profile $field
    if ($null -eq $value -or ([string]$value -eq '')) { Add-Reason 'PROFILE_FIELD_MISSING' }
}

if (([string](Get-Field $profile 'schemaVersion')) -ne '1.0') { Add-Reason 'SCHEMA_VERSION_UNSUPPORTED' }
if ([string]::IsNullOrWhiteSpace([string](Get-Field $profile 'projectId'))) { Add-Reason 'PROJECT_ID_INVALID' }

$pathFields = @('designPath','planPath','runtimeRoot','evidenceRoot')
foreach ($field in $pathFields) {
    $value = [string](Get-Field $profile $field)
    $resolved = Resolve-AbsolutePath -Value $value -ProjectRoot $projectRoot
    if ($null -eq $resolved -or -not (Test-Within -Candidate $resolved -Root $projectRoot)) { Add-Reason 'PATH_OUTSIDE_PROJECT_ROOT' }
    elseif ([System.IO.Path]::GetPathRoot($resolved) -ine $xDriveRoot) { Add-Reason 'NOT_X_DRIVE' }
}

foreach ($field in @('allowedWritePaths','protectedPaths')) {
    $values = Get-Field $profile $field
    if ($values -is [string] -or $null -eq $values) { $values = @($values) }
    foreach ($value in @($values)) {
        $resolved = Resolve-AbsolutePath -Value ([string]$value) -ProjectRoot $projectRoot
        if ($null -eq $resolved -or -not (Test-Within -Candidate $resolved -Root $projectRoot)) { Add-Reason 'PATH_OUTSIDE_PROJECT_ROOT' }
    }
}

$policy = Get-Field $profile 'modelPolicy'
$designPolicy = Get-Field $policy 'design'
$implementationPolicy = Get-Field $policy 'implementation'
if (([string](Get-Field $designPolicy 'model') -ne 'gpt-5.6-sol') -or ([string](Get-Field $designPolicy 'reasoning') -ne 'high') -or ([string](Get-Field $implementationPolicy 'model') -ne 'gpt-5.6-luna') -or ([string](Get-Field $implementationPolicy 'reasoning') -ne 'xhigh')) {
    Add-Reason 'MODEL_POLICY_BLOCKED'
}

if ([int](Get-Field $profile 'maxEffectiveRetries') -ne 2) { Add-Reason 'RETRY_POLICY_INVALID' }
if ([int](Get-Field $profile 'unfinishedCleanupRounds') -ne 2) { Add-Reason 'CLEANUP_ROUNDS_INVALID' }

$normalized = [ordered]@{}
foreach ($property in $profile.PSObject.Properties) { $normalized[$property.Name] = $property.Value }
$normalized['projectRoot'] = $projectRoot
$normalized['profilePath'] = $profileFullPath
$normalized['normalizedPathFields'] = [ordered]@{}
foreach ($field in $pathFields) { $normalized['normalizedPathFields'][$field] = Resolve-AbsolutePath -Value ([string](Get-Field $profile $field)) -ProjectRoot $projectRoot }
$normalized['normalizedAllowedWritePaths'] = @((Get-Field $profile 'allowedWritePaths') | ForEach-Object { Resolve-AbsolutePath -Value ([string]$_) -ProjectRoot $projectRoot })
$normalized['normalizedProtectedPaths'] = @((Get-Field $profile 'protectedPaths') | ForEach-Object { Resolve-AbsolutePath -Value ([string]$_) -ProjectRoot $projectRoot })

Write-ResultAndExit -Valid ($hardReasons.Count -eq 0) -Profile $normalized -ProjectRoot $projectRoot -ProfileFullPath $profileFullPath
