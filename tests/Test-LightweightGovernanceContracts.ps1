[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw "ASSERTION_FAILED: $Message"
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "JSON file is missing: $Path"
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "JSON_INVALID: $Path :: $($_.Exception.Message)"
    }
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Context
    )
    $property = $Object.PSObject.Properties[$Name]
    Assert-True ($null -ne $property) "PROFILE_REQUIRED_FIELD_MISSING: $Context.$Name"
    return $property.Value
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][object[]]$Values,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )
    Assert-True (@($Values | ForEach-Object { [string]$_ }) -contains $Expected) "$Context does not contain $Expected"
}

function Assert-Reason {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )
    Assert-True ($Reason -eq $Expected) "$Context expected reason code $Expected but got $Reason"
}

function Test-ExcludedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return $Path -match '(?i)(^|[\\/])(pytest|tmp|temp|legacy|recovery)([\\/]|$)'
}

function Test-SensitiveProfile {
    param([Parameter(Mandatory = $true)]$Profile)
    $sensitiveNames = @('businessContent', 'personalData', 'studentData', 'secrets', 'credentials', 'apiKey', 'privateData')
    foreach ($name in $sensitiveNames) {
        $property = $Profile.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value) {
            if ($property.Value -is [bool] -and $property.Value -eq $false) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$property.Value)) { continue }
            return $true
        }
    }
    return $false
}

$root = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $root 'config\lightweight-governance\projects.json'
$riskPolicyPath = Join-Path $root 'config\lightweight-governance\risk-policy.json'
$profileSchemaPath = Join-Path $root 'schemas\project-governance-profile-v1.schema.json'
$catalogSchemaPath = Join-Path $root 'schemas\project-governance-catalog-v1.schema.json'
$fixturesRoot = Join-Path $root 'tests\fixtures\lightweight-governance'

try {
    $catalog = Read-JsonFile -Path $catalogPath
    $riskPolicy = Read-JsonFile -Path $riskPolicyPath
    $profileSchema = Read-JsonFile -Path $profileSchemaPath
    $catalogSchema = Read-JsonFile -Path $catalogSchemaPath

    Assert-True ([string]$catalog.schemaVersion -eq '1.0') 'catalog schemaVersion must be 1.0'
    Assert-True ([string]$catalog.defaultPriority -eq 'lightweight_first') 'catalog defaultPriority must be lightweight_first'
    Assert-True ([string]$catalog.defaultReview -eq 'disabled') 'qualification/default review must be disabled'
    Assert-True ([string]$catalog.unknownRisk -eq 'escalate') 'unknown risk must fail closed by escalation'
    Assert-True (@($catalog.projects).Count -eq 3) 'catalog must contain the three anonymous project types'

    $projectIds = @($catalog.projects | ForEach-Object { [string]$_.projectId })
    Assert-True ($projectIds.Count -eq (@($projectIds | Sort-Object -Unique).Count)) 'catalog projectId values must be unique'
    foreach ($entry in @($catalog.projects)) {
        $entryContext = "catalog.projects[$([string]$entry.projectId)]"
        $profilePath = [string](Get-RequiredProperty -Object $entry -Name 'profilePath' -Context $entryContext)
        $gitRoot = [string](Get-RequiredProperty -Object $entry -Name 'gitRoot' -Context $entryContext)
        Assert-True ($gitRoot -match '^[Xx]:[\\/]') "$entryContext.gitRoot must be X-drive rooted"
        Assert-True ([bool]$entry.gitRootVerified) "$entryContext.gitRootVerified must be true"
        Assert-True (-not (Test-ExcludedPath -Path $gitRoot)) "$entryContext.gitRoot may not be temporary/legacy/recovery"
        $profile = Read-JsonFile -Path (Join-Path $root $profilePath)
        Assert-True ([string]$profile.schemaVersion -eq '1.0') "$entryContext profile schemaVersion must be 1.0"
        Assert-True ([string]$profile.projectId -eq [string]$entry.projectId) "$entryContext profile projectId must match catalog"
        Assert-True ([string]$profile.projectType -eq [string]$entry.projectType) "$entryContext profile projectType must match catalog"
        Assert-True ([string]$profile.defaultPriority -eq 'lightweight_first') "$entryContext profile defaultPriority must be lightweight_first"
        Assert-True ([string]$profile.defaultReview -eq 'disabled') "$entryContext profile defaultReview must be disabled"
        Assert-True ([bool]$profile.containsBusinessContent -eq $false) "$entryContext profile may not contain business content"
        Assert-True ([bool]$profile.containsPersonalData -eq $false) "$entryContext profile may not contain personal data"
        Assert-True ([bool]$profile.containsSecrets -eq $false) "$entryContext profile may not contain secrets"
    }
    Write-Output 'PASS catalog_valid_unique_profiles'

    $requiredProfileFields = @('schemaVersion', 'projectId', 'projectType', 'gitRoot', 'gitRootVerified', 'defaultPriority', 'defaultReview', 'allowedWritePaths', 'protectedPaths', 'containsBusinessContent', 'containsPersonalData', 'containsSecrets')
    Assert-Contains -Values @($profileSchema.required) -Expected 'projectId' -Context 'profile schema required fields'
    foreach ($field in $requiredProfileFields) {
        Assert-Contains -Values @($profileSchema.required) -Expected $field -Context 'profile schema required fields'
    }
    Assert-True ([string]$profileSchema.properties.schemaVersion.const -eq '1.0') 'profile schema must pin schemaVersion 1.0'
    Assert-True (@($profileSchema.properties.projectType.enum).Count -eq 3) 'profile schema must define three project types'
    Assert-True ([bool]$profileSchema.additionalProperties -eq $false) 'profile schema must reject unknown fields'

    Assert-Contains -Values @($catalogSchema.required) -Expected 'projects' -Context 'catalog schema required fields'
    Assert-True ([string]$catalogSchema.properties.defaultPriority.const -eq 'lightweight_first') 'catalog schema must pin lightweight_first'
    Assert-True ([bool]$catalogSchema.additionalProperties -eq $false) 'catalog schema must reject unknown fields'
    Write-Output 'PASS schemas_required_and_closed'

    $phases = @($riskPolicy.stages | ForEach-Object { [string]$_.id })
    foreach ($phase in @('DEVELOP_AUTONOMOUS', 'CANDIDATE_AUTOMATED', 'USER_FINAL_REVIEW', 'ESCALATED_REVIEW')) {
        Assert-Contains -Values $phases -Expected $phase -Context 'risk policy stages'
    }
    Assert-True ([string]$riskPolicy.defaultPriority -eq 'lightweight_first') 'risk policy defaultPriority must be lightweight_first'
    Assert-True ([string]$riskPolicy.qualificationReviewDefault -eq 'not_required') 'qualification review must be disabled by default'
    Assert-True ([string]$riskPolicy.unknownRiskAction -eq 'escalate') 'risk policy unknownRiskAction must escalate'
    foreach ($reason in @('PROFILE_MISSING', 'PROFILE_REQUIRED_FIELD_MISSING', 'PROFILE_SENSITIVE_CONTENT', 'PROFILE_SCHEMA_VERSION_UNSUPPORTED', 'PROJECT_ID_DUPLICATE', 'PROJECT_PATH_EXCLUDED', 'RISK_UNKNOWN')) {
        Assert-Contains -Values @($riskPolicy.reasonCodes) -Expected $reason -Context 'risk policy stable reason codes'
    }
    foreach ($trigger in @('formal_data', 'personal_or_student_data', 'secrets', 'formal_recommendation', 'production_or_publication', 'paid_or_external_account')) {
        Assert-Contains -Values @($riskPolicy.hardTriggers.id) -Expected $trigger -Context 'risk policy hard triggers'
    }
    Write-Output 'PASS risk_policy_stages_triggers_and_reason_codes'

    $duplicate = Read-JsonFile -Path (Join-Path $fixturesRoot 'catalog-duplicate-project-id.json')
    $duplicateIds = @($duplicate.projects | ForEach-Object { [string]$_.projectId })
    Assert-True ($duplicateIds.Count -ne (@($duplicateIds | Sort-Object -Unique).Count) ) 'duplicate fixture must contain duplicate IDs'
    Assert-Reason -Reason ([string]$duplicate.expectedReasonCode) -Expected 'PROJECT_ID_DUPLICATE' -Context 'duplicate fixture'
    Write-Output 'PASS duplicate_project_id_rejected'

    $excluded = Read-JsonFile -Path (Join-Path $fixturesRoot 'catalog-excluded-path.json')
    Assert-True (Test-ExcludedPath -Path ([string]$excluded.gitRoot)) 'temporary/legacy fixture path must be excluded'
    Assert-Reason -Reason ([string]$excluded.expectedReasonCode) -Expected 'PROJECT_PATH_EXCLUDED' -Context 'excluded path fixture'
    Write-Output 'PASS temporary_pytest_legacy_paths_rejected'

    $missing = Join-Path $fixturesRoot 'missing-profile.json'
    Assert-True (-not (Test-Path -LiteralPath $missing -PathType Leaf)) 'missing profile fixture must remain missing'
    $missingManifest = Read-JsonFile -Path (Join-Path $fixturesRoot 'catalog-missing-profile.json')
    Assert-Reason -Reason ([string]$missingManifest.expectedReasonCode) -Expected 'PROFILE_MISSING' -Context 'missing profile fixture'
    Write-Output 'PASS missing_profile_rejected'

    $missingField = Read-JsonFile -Path (Join-Path $fixturesRoot 'profile-missing-field.json')
    Assert-True ($null -eq $missingField.projectType) 'missing-field fixture must omit projectType'
    Assert-Reason -Reason ([string]$missingField.expectedReasonCode) -Expected 'PROFILE_REQUIRED_FIELD_MISSING' -Context 'missing field fixture'
    Write-Output 'PASS missing_profile_field_rejected'

    $sensitive = Read-JsonFile -Path (Join-Path $fixturesRoot 'profile-sensitive-content.json')
    Assert-True (Test-SensitiveProfile -Profile $sensitive) 'sensitive fixture must contain a forbidden content marker'
    Assert-Reason -Reason ([string]$sensitive.expectedReasonCode) -Expected 'PROFILE_SENSITIVE_CONTENT' -Context 'sensitive fixture'
    Write-Output 'PASS_sensitive_profile_rejected'

    $unknownVersion = Read-JsonFile -Path (Join-Path $fixturesRoot 'profile-unknown-version.json')
    Assert-True ([string]$unknownVersion.schemaVersion -ne '1.0') 'unknown-version fixture must not be schema version 1.0'
    Assert-Reason -Reason ([string]$unknownVersion.expectedReasonCode) -Expected 'PROFILE_SCHEMA_VERSION_UNSUPPORTED' -Context 'unknown version fixture'
    Write-Output 'PASS unknown_profile_version_rejected'

    $unknownRisk = Read-JsonFile -Path (Join-Path $fixturesRoot 'risk-unknown.json')
    Assert-Reason -Reason ([string]$unknownRisk.expectedReasonCode) -Expected 'RISK_UNKNOWN' -Context 'unknown risk fixture'
    Write-Output 'PASS unknown_risk_fails_closed'

    Write-Output 'LIGHTWEIGHT_GOVERNANCE_CONTRACTS=PASS'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    Write-Output 'LIGHTWEIGHT_GOVERNANCE_CONTRACTS=FAIL'
    exit 1
}
