[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$ExpectedGitRoot,
    [string]$DesignPath,
    [string]$PlanPath,
    [string]$ExpectedDesignHash,
    [string]$ExpectedPlanHash,
    [string]$ExpectedProfileHash,
    [string]$ExpectedCatalogHash
)

$ErrorActionPreference = 'Stop'
$reasons = New-Object 'System.Collections.Generic.List[string]'
$projectId = $null
$projectType = $null
$defaultReview = $null
$escalationTriggers = @()
$profileSchemaVersion = $null
$riskPolicyVersion = $null
$deliveryTarget = $null
$releaseIntent = $null
$reviewPolicy = $null
$effectiveFromFreshRun = $null

function Add-Reason {
    param([Parameter(Mandatory = $true)][string]$Code)
    if (-not $reasons.Contains($Code)) { [void]$reasons.Add($Code) }
}

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [System.IO.Path]::GetFullPath($Path) } catch { return $null }
}

function Test-Within {
    param([string]$Candidate, [string]$Root)
    if ([string]::IsNullOrWhiteSpace($Candidate) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $candidateFull = (Resolve-FullPath $Candidate).TrimEnd('\')
    $rootFull = (Resolve-FullPath $Root).TrimEnd('\')
    return $candidateFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $candidateFull.StartsWith($rootFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$MissingCode, [Parameter(Mandatory = $true)][string]$InvalidCode)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Reason $MissingCode; return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-Reason $InvalidCode; return $null }
}

function Get-PropertyValue {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ExcludedPath {
    param([string]$Path)
    return $Path -match '(?i)(^|[\\/])(pytest|tmp|temp|legacy|recovery)([\\/]|$)'
}

function Test-RelativeSafePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $false }
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    return $true
}

function Add-IdentityBlock {
    param([Parameter(Mandatory = $true)][string]$Detail)
    Add-Reason 'BLOCKED_IDENTITY'
    Add-Reason $Detail
}

function Add-PolicyBlock {
    param([Parameter(Mandatory = $true)][string]$Detail)
    Add-Reason 'BLOCKED_POLICY'
    Add-Reason $Detail
}

function Test-Hash {
    param([string]$Path, [string]$Expected, [string]$Detail)
    if ([string]::IsNullOrWhiteSpace($Expected)) { return }
    if ($Expected -notmatch '^[0-9A-Fa-f]{64}$') { Add-IdentityBlock -Detail $Detail; return }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-IdentityBlock -Detail $Detail; return }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) { Add-IdentityBlock -Detail $Detail }
}

function Write-ResultAndExit {
    param([Parameter(Mandatory = $true)][bool]$Success)
    $payload = [ordered]@{
        verdict = if ($Success) { 'READY' } else { 'BLOCKED' }
        reason_codes = @($reasons)
        project_id = $projectId
        project_type = $projectType
        profile_schema_version = $profileSchemaVersion
        risk_policy_version = $riskPolicyVersion
        default_review = $defaultReview
        escalation_triggers = @($escalationTriggers)
        delivery_target = $deliveryTarget
        release_intent = $releaseIntent
        review_policy = $reviewPolicy
        effective_from_fresh_run = $effectiveFromFreshRun
    }
    $payload | ConvertTo-Json -Depth 20
    if ($Success) { exit 0 } else { exit 1 }
}

$rootFull = Resolve-FullPath $ProjectRoot
if ($null -eq $rootFull -or -not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    Add-IdentityBlock -Detail 'PROJECT_ROOT_INVALID'
    Write-ResultAndExit -Success $false
}
$xDriveRoot = 'X' + ':\'
if ([System.IO.Path]::GetPathRoot($rootFull) -ine $xDriveRoot) {
    Add-IdentityBlock -Detail 'PROJECT_ROOT_NOT_X_DRIVE'
}

$profileFull = Resolve-FullPath $ProfilePath
$catalogFull = Resolve-FullPath $CatalogPath
if ($null -eq $profileFull -or -not (Test-Within -Candidate $profileFull -Root $rootFull)) { Add-IdentityBlock -Detail 'PROFILE_PATH_OUTSIDE_PROJECT' }
if ($null -eq $catalogFull -or -not (Test-Within -Candidate $catalogFull -Root $rootFull)) { Add-IdentityBlock -Detail 'CATALOG_PATH_OUTSIDE_PROJECT' }
if ($null -eq $profileFull -or -not (Test-Path -LiteralPath $profileFull -PathType Leaf)) { Add-Reason 'PROFILE_MISSING' }
if ($null -eq $catalogFull -or -not (Test-Path -LiteralPath $catalogFull -PathType Leaf)) { Add-Reason 'CATALOG_MISSING' }
if ($reasons.Count -gt 0) { Write-ResultAndExit -Success $false }

$profile = Read-Json -Path $profileFull -MissingCode 'PROFILE_MISSING' -InvalidCode 'PROFILE_INVALID'
$catalog = Read-Json -Path $catalogFull -MissingCode 'CATALOG_MISSING' -InvalidCode 'CATALOG_INVALID'
$profileSchemaPath = Join-Path $rootFull 'schemas\project-governance-profile-v1.schema.json'
$catalogSchemaPath = Join-Path $rootFull 'schemas\project-governance-catalog-v1.schema.json'
$riskPolicyPath = Join-Path $rootFull 'config\lightweight-governance\risk-policy.json'
$profileSchema = Read-Json -Path $profileSchemaPath -MissingCode 'PROFILE_SCHEMA_MISSING' -InvalidCode 'PROFILE_SCHEMA_INVALID'
$catalogSchema = Read-Json -Path $catalogSchemaPath -MissingCode 'CATALOG_SCHEMA_MISSING' -InvalidCode 'CATALOG_SCHEMA_INVALID'
$riskPolicy = Read-Json -Path $riskPolicyPath -MissingCode 'RISK_POLICY_MISSING' -InvalidCode 'RISK_POLICY_INVALID'
if ($null -ne $riskPolicy) { $escalationTriggers = @($riskPolicy.hardTriggers | ForEach-Object { [string]$_.id }) }
if ($null -eq $profile -or $null -eq $catalog) { Write-ResultAndExit -Success $false }

$profileSchemaVersion = [string](Get-PropertyValue -Object $profile -Name 'schemaVersion')
if ($profileSchemaVersion -eq '1.1') {
    $profileSchemaPath = Join-Path $rootFull 'schemas\project-governance-profile-v1.1.schema.json'
    $riskPolicyPath = Join-Path $rootFull 'config\lightweight-governance\risk-policy-v2.json'
    $profileSchema = Read-Json -Path $profileSchemaPath -MissingCode 'PROFILE_SCHEMA_MISSING' -InvalidCode 'PROFILE_SCHEMA_INVALID'
    $riskPolicy = Read-Json -Path $riskPolicyPath -MissingCode 'RISK_POLICY_MISSING' -InvalidCode 'RISK_POLICY_INVALID'
}

$projectId = [string](Get-PropertyValue -Object $profile -Name 'projectId')
$projectType = [string](Get-PropertyValue -Object $profile -Name 'projectType')
$defaultReview = [string](Get-PropertyValue -Object $profile -Name 'defaultReview')
$riskPolicyVersion = [string](Get-PropertyValue -Object $riskPolicy -Name 'schemaVersion')
$deliveryTarget = [string](Get-PropertyValue -Object $profile -Name 'deliveryTarget')
$releaseIntent = [string](Get-PropertyValue -Object $profile -Name 'releaseIntent')
$reviewPolicy = [string](Get-PropertyValue -Object $profile -Name 'reviewPolicy')
$effectiveFromFreshRun = Get-PropertyValue -Object $profile -Name 'effectiveFromFreshRun'

if ($profileSchemaVersion -notin @('1.0', '1.1')) { Add-PolicyBlock -Detail 'PROFILE_SCHEMA_VERSION_UNSUPPORTED' }
if ([string](Get-PropertyValue -Object $catalog -Name 'schemaVersion') -ne '1.0') { Add-PolicyBlock -Detail 'CATALOG_SCHEMA_VERSION_UNSUPPORTED' }
$expectedSchemaIdPattern = if ($profileSchemaVersion -eq '1.1') { 'project-governance-profile-v1\.1' } else { 'project-governance-profile-v1\.schema' }
if ($null -eq $profileSchema -or [string](Get-PropertyValue -Object $profileSchema -Name '$id') -notmatch $expectedSchemaIdPattern) { Add-PolicyBlock -Detail 'PROFILE_SCHEMA_INVALID' }
if ($null -eq $catalogSchema -or [string](Get-PropertyValue -Object $catalogSchema -Name '$id') -notmatch 'project-governance-catalog-v1') { Add-PolicyBlock -Detail 'CATALOG_SCHEMA_INVALID' }
if ($null -eq $riskPolicy -or ($profileSchemaVersion -eq '1.1' -and $riskPolicyVersion -ne '2.0') -or ($profileSchemaVersion -eq '1.0' -and $riskPolicyVersion -ne '1.0')) { Add-PolicyBlock -Detail 'RISK_POLICY_INVALID' }

$requiredFields = @($profileSchema.required)
foreach ($field in $requiredFields) {
    if ($null -eq $profile.PSObject.Properties[$field]) { Add-PolicyBlock -Detail 'PROFILE_REQUIRED_FIELD_MISSING'; break }
}
$allowedProfileFields = @($profileSchema.properties.PSObject.Properties | ForEach-Object { $_.Name })
foreach ($property in @($profile.PSObject.Properties)) {
    if ($allowedProfileFields -notcontains $property.Name) { Add-PolicyBlock -Detail 'PROFILE_UNKNOWN_FIELD'; break }
}

$entries = @($catalog.projects)
$ids = @($entries | ForEach-Object { [string]$_.projectId })
if ($ids.Count -ne (@($ids | Sort-Object -Unique).Count)) { Add-IdentityBlock -Detail 'PROJECT_ID_DUPLICATE' }
$entry = $entries | Where-Object { [string]$_.projectId -eq $projectId } | Select-Object -First 1
if ($null -eq $entry) {
    Add-IdentityBlock -Detail 'PROJECT_NOT_REGISTERED'
}
else {
    $entryProfilePath = Resolve-FullPath (Join-Path $rootFull ([string]$entry.profilePath))
    if ($null -eq $entryProfilePath -or -not $entryProfilePath.Equals($profileFull, [System.StringComparison]::OrdinalIgnoreCase)) { Add-IdentityBlock -Detail 'PROFILE_PATH_MISMATCH' }
    if ([string]$entry.projectType -ne $projectType) { Add-IdentityBlock -Detail 'PROJECT_TYPE_MISMATCH' }
    if ([string]$entry.profileSchemaVersion -ne $profileSchemaVersion) { Add-PolicyBlock -Detail 'PROFILE_SCHEMA_VERSION_UNSUPPORTED' }
    if ([string]$entry.defaultPriority -ne 'lightweight_first' -or [string]$catalog.defaultPriority -ne 'lightweight_first' -or [string]$profile.defaultPriority -ne 'lightweight_first') { Add-PolicyBlock -Detail 'DEFAULT_PRIORITY_MISMATCH' }
    if ([string]$entry.defaultReview -ne 'disabled' -or [string]$catalog.defaultReview -ne 'disabled' -or $defaultReview -ne 'disabled') { Add-PolicyBlock -Detail 'DEFAULT_REVIEW_MISMATCH' }
    if ([string]$entry.activeRunMigration -ne 'next_fresh_run' -or [string]$profile.activeRunMigration -ne 'next_fresh_run') { Add-PolicyBlock -Detail 'ACTIVE_RUN_MIGRATION_INVALID' }

    if ($profileSchemaVersion -eq '1.1') {
        if ($effectiveFromFreshRun -ne $true) { Add-PolicyBlock -Detail 'FRESH_RUN_EFFECTIVE_REQUIRED' }
        $matrixRow = @($riskPolicy.deliveryMatrix | Where-Object { [string]$_.deliveryTarget -eq $deliveryTarget }) | Select-Object -First 1
        $combination = "$deliveryTarget+$releaseIntent"
        if ($null -eq $matrixRow -or @($riskPolicy.invalidCombinations) -contains $combination) {
            Add-PolicyBlock -Detail 'V1_1_DELIVERY_INTENT_INVALID'
        }
        elseif ([string]$matrixRow.reviewPolicy -eq 'NONE_OR_OPTIONAL') {
            if (@('NONE', 'OPTIONAL') -notcontains $reviewPolicy) { Add-PolicyBlock -Detail 'V1_1_REVIEW_POLICY_INVALID' }
        }
        elseif ([string]$matrixRow.reviewPolicy -ne $reviewPolicy) {
            Add-PolicyBlock -Detail 'V1_1_REVIEW_POLICY_INVALID'
        }
    }

    $profileGitRoot = [string]$profile.gitRoot
    $entryGitRoot = [string]$entry.gitRoot
    if (-not $profileGitRoot.Equals($entryGitRoot, [System.StringComparison]::OrdinalIgnoreCase)) { Add-IdentityBlock -Detail 'GIT_ROOT_MISMATCH' }
    $identityRoot = if ([string]::IsNullOrWhiteSpace($ExpectedGitRoot)) { $rootFull } else { $ExpectedGitRoot }
    if (-not $profileGitRoot.Equals([string]$identityRoot, [System.StringComparison]::OrdinalIgnoreCase)) { Add-IdentityBlock -Detail 'GIT_ROOT_MISMATCH' }
    if ($profileGitRoot -notmatch '^[Xx]:[\\/].+' -or -not [bool]$profile.gitRootVerified) { Add-IdentityBlock -Detail 'PROJECT_GIT_ROOT_INVALID' }
    if ((Test-ExcludedPath -Path $profileGitRoot) -or (Test-ExcludedPath -Path $entryGitRoot)) { Add-IdentityBlock -Detail 'PROJECT_PATH_EXCLUDED' }

    foreach ($path in @($profile.allowedWritePaths)) {
        if (-not (Test-RelativeSafePath -Path ([string]$path)) -or [string]$path -match '(?i)(^|[\\/])\.git([\\/]|$)') { Add-IdentityBlock -Detail 'PATH_OUTSIDE_PROJECT'; break }
    }
    foreach ($path in @($profile.protectedPaths)) {
        if (-not (Test-RelativeSafePath -Path ([string]$path))) { Add-IdentityBlock -Detail 'PATH_OUTSIDE_PROJECT'; break }
    }
    if (@($profile.protectedPaths | ForEach-Object { [string]$_ }) -notcontains '.git') { Add-PolicyBlock -Detail 'PROTECTED_GIT_PATH_MISSING' }
    if ([bool]$profile.containsBusinessContent -or [bool]$profile.containsPersonalData -or [bool]$profile.containsSecrets) { Add-PolicyBlock -Detail 'PROFILE_SENSITIVE_CONTENT' }
}

if (-not [string]::IsNullOrWhiteSpace($DesignPath)) {
    $designFull = Resolve-FullPath $DesignPath
    if ($null -eq $designFull -or -not (Test-Within -Candidate $designFull -Root $rootFull)) { Add-IdentityBlock -Detail 'DESIGN_PATH_OUTSIDE_PROJECT' }
    else { Test-Hash -Path $designFull -Expected $ExpectedDesignHash -Detail 'DESIGN_HASH_MISMATCH' }
}
elseif (-not [string]::IsNullOrWhiteSpace($ExpectedDesignHash)) { Add-IdentityBlock -Detail 'DESIGN_HASH_INPUT_MISSING' }
if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
    $planFull = Resolve-FullPath $PlanPath
    if ($null -eq $planFull -or -not (Test-Within -Candidate $planFull -Root $rootFull)) { Add-IdentityBlock -Detail 'PLAN_PATH_OUTSIDE_PROJECT' }
    else { Test-Hash -Path $planFull -Expected $ExpectedPlanHash -Detail 'PLAN_HASH_MISMATCH' }
}
elseif (-not [string]::IsNullOrWhiteSpace($ExpectedPlanHash)) { Add-IdentityBlock -Detail 'PLAN_HASH_INPUT_MISSING' }
Test-Hash -Path $profileFull -Expected $ExpectedProfileHash -Detail 'PROFILE_HASH_MISMATCH'
Test-Hash -Path $catalogFull -Expected $ExpectedCatalogHash -Detail 'CATALOG_HASH_MISMATCH'

Write-ResultAndExit -Success ($reasons.Count -eq 0)
