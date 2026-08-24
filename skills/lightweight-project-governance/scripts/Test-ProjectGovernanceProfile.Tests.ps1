[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory = $true)][string]$Message)
    if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')" }
}

function Assert-Contains {
    param([object[]]$Values, [Parameter(Mandatory = $true)][string]$Expected, [Parameter(Mandatory = $true)][string]$Message)
    $strings = @($Values | ForEach-Object { [string]$_ })
    Assert-True ($strings -contains $Expected) "$Message (missing '$Expected')"
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "JSON file missing: $Path"
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "JSON_INVALID: $Path :: $($_.Exception.Message)" }
}

function Get-Hash {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Invoke-Validator {
    param(
        [Parameter(Mandatory = $true)][string]$ValidatorPath,
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
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ValidatorPath, '-ProfilePath', $ProfilePath, '-CatalogPath', $CatalogPath, '-ProjectRoot', $ProjectRoot)
    if ($ExpectedGitRoot) { $arguments += @('-ExpectedGitRoot', $ExpectedGitRoot) }
    if ($DesignPath) { $arguments += @('-DesignPath', $DesignPath) }
    if ($PlanPath) { $arguments += @('-PlanPath', $PlanPath) }
    if ($ExpectedDesignHash) { $arguments += @('-ExpectedDesignHash', $ExpectedDesignHash) }
    if ($ExpectedPlanHash) { $arguments += @('-ExpectedPlanHash', $ExpectedPlanHash) }
    if ($ExpectedProfileHash) { $arguments += @('-ExpectedProfileHash', $ExpectedProfileHash) }
    if ($ExpectedCatalogHash) { $arguments += @('-ExpectedCatalogHash', $ExpectedCatalogHash) }
    $raw = @(& powershell.exe @arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $json = $null
    if ($raw.Count -gt 0) {
        try { $json = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json; Raw = $raw }
}

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$skillRoot = Join-Path $root 'skills\lightweight-project-governance'
$validatorPath = Join-Path $skillRoot 'scripts\Test-ProjectGovernanceProfile.ps1'
$skillPath = Join-Path $skillRoot 'SKILL.md'
$agentPath = Join-Path $skillRoot 'agents\openai.yaml'
$referencePath = Join-Path $skillRoot 'references\governance-contract.md'
$v11SchemaPath = Join-Path $root 'schemas\project-governance-profile-v1.1.schema.json'
$v2PolicyPath = Join-Path $root 'config\lightweight-governance\risk-policy-v2.json'
$catalogPath = Join-Path $root 'config\lightweight-governance\projects.json'
$fixtureRoot = Join-Path $root 'tests\fixtures\lightweight-governance'
$validCatalog = Read-JsonFile -Path $catalogPath
$validEntry = @($validCatalog.projects)[0]
$validProfilePath = Join-Path $root ([string]$validEntry.profilePath)
$validProfile = Read-JsonFile -Path $validProfilePath
$planningFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs\future-development') -File | Where-Object { $_.Name -like '*V1.2.md' } | Sort-Object Length)
Assert-True ($planningFiles.Count -ge 2) 'V1.2 design and plan files must be present'
$designPath = $planningFiles[0].FullName
$planPath = $planningFiles[1].FullName
$designHash = Get-Hash -Path $designPath
$planHash = Get-Hash -Path $planPath
$profileHash = Get-Hash -Path $validProfilePath
$catalogHash = Get-Hash -Path $catalogPath

try {
    Assert-True (Test-Path -LiteralPath $v11SchemaPath -PathType Leaf) 'V1.1 profile schema must exist'
    Assert-True (Test-Path -LiteralPath $v2PolicyPath -PathType Leaf) 'V2 risk policy must exist'
    $v11Schema = Read-JsonFile -Path $v11SchemaPath
    $v2Policy = Read-JsonFile -Path $v2PolicyPath
    Assert-Equal ([string]$v11Schema.properties.schemaVersion.const) '1.1' 'V1.1 schema must declare schemaVersion 1.1'
    foreach ($field in @('deliveryTarget', 'releaseIntent', 'reviewPolicy', 'effectiveFromFreshRun')) {
        Assert-Contains @($v11Schema.required) $field "V1.1 schema must require $field"
    }
    Assert-Equal ([string]$v2Policy.schemaVersion) '2.0' 'V2 policy must declare schemaVersion 2.0'
    Assert-Equal ([string]$v2Policy.policyId) 'lightweight-governance-risk-policy-v2' 'V2 policy id must be stable'
    Assert-Equal @($v2Policy.deliveryMatrix).Count 4 'V2 policy must expose four delivery target rows'
    $engineering = @($v2Policy.deliveryMatrix | Where-Object { $_.deliveryTarget -eq 'ENGINEERING_ONLY' })[0]
    Assert-Equal ([string]$engineering.releaseIntent) 'NONE' 'Engineering-only release intent must be NONE'
    Assert-Equal ([string]$engineering.reviewPolicy) 'NONE' 'Engineering-only review must be NONE'
    $formal = @($v2Policy.deliveryMatrix | Where-Object { $_.deliveryTarget -eq 'FORMAL_RELEASE' })[0]
    Assert-Equal ([string]$formal.releaseIntent) 'INTENDED' 'Formal release intent must be INTENDED'
    Assert-Equal ([string]$formal.reviewPolicy) 'REQUIRED' 'Formal release review must be REQUIRED'
    Assert-Contains @($v2Policy.invalidCombinations) 'ENGINEERING_ONLY+INTENDED' 'Engineering-only intended release must be rejected'
    Assert-Contains @($v2Policy.invalidCombinations) 'FORMAL_RELEASE+NONE' 'Formal release without intent must be rejected'
    Write-Output 'PASS v11_intent_matrix_contract'

    Assert-True (Test-Path -LiteralPath $skillPath -PathType Leaf) 'SKILL.md must exist'
    Assert-True (Test-Path -LiteralPath $agentPath -PathType Leaf) 'agents/openai.yaml must exist'
    Assert-True (Test-Path -LiteralPath $referencePath -PathType Leaf) 'governance-contract.md must exist'
    Assert-True ((Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8) -match '(?m)^name:\s*lightweight-project-governance\s*$') 'Skill name must be discoverable'
    Assert-True ((Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8) -match '(?i)does not publish|不自动发布|formal release') 'Skill must not claim automatic publication'
    $agentText = Get-Content -LiteralPath $agentPath -Raw -Encoding UTF8
    Assert-True ($agentText -match '(?m)^interface:\s*$' -and $agentText -match 'display_name:' -and $agentText -match 'default_prompt:') 'openai.yaml interface metadata is incomplete'
    $referenceText = Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8
    foreach ($phase in @('DEVELOP_AUTONOMOUS', 'CANDIDATE_AUTOMATED', 'USER_FINAL_REVIEW', 'ESCALATED_REVIEW')) {
        Assert-True ($referenceText.Contains($phase)) "governance reference missing phase $phase"
    }
    Assert-True ($referenceText -match '(?i)fail-closed') 'governance reference must document fail-closed boundaries'
    Write-Output 'PASS skill_structure_and_discoverability'

    $valid = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $validProfilePath -CatalogPath $catalogPath -ProjectRoot $root -ExpectedGitRoot ([string]$validProfile.gitRoot) -DesignPath $designPath -PlanPath $planPath -ExpectedDesignHash $designHash -ExpectedPlanHash $planHash -ExpectedProfileHash $profileHash -ExpectedCatalogHash $catalogHash
    Assert-Equal $valid.ExitCode 0 'Valid profile validator invocation must exit 0'
    Assert-True ($null -ne $valid.Json) 'Valid profile must return JSON'
    Assert-Equal $valid.Json.verdict 'READY' 'Valid profile must be READY'
    Assert-Equal @($valid.Json.reason_codes).Count 0 'Valid profile must have no reason codes'
    Assert-Equal $valid.Json.project_id ([string]$validProfile.projectId) 'Valid project_id must be returned'
    Assert-Equal $valid.Json.project_type ([string]$validProfile.projectType) 'Valid project_type must be returned'
    Assert-Equal $valid.Json.default_review 'disabled' 'Valid default_review must be disabled'
    Assert-True (@($valid.Json.escalation_triggers).Count -ge 1) 'Valid result must expose escalation triggers'
    Write-Output 'PASS valid_profile_returns_unique_strategy'

    $profileDrift = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $validProfilePath -CatalogPath $catalogPath -ProjectRoot $root -ExpectedGitRoot ([string]$validProfile.gitRoot) -ExpectedProfileHash ('0' * 64)
    Assert-Equal $profileDrift.ExitCode 1 'Profile hash drift must exit 1'
    Assert-Equal $profileDrift.Json.verdict 'BLOCKED' 'Profile hash drift must block'
    Assert-Contains @($profileDrift.Json.reason_codes) 'BLOCKED_IDENTITY' 'Profile hash drift identity code'
    Assert-Contains @($profileDrift.Json.reason_codes) 'PROFILE_HASH_MISMATCH' 'Profile hash drift detail code'
    Write-Output 'PASS profile_hash_drift_blocked'

    $catalogDrift = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $validProfilePath -CatalogPath $catalogPath -ProjectRoot $root -ExpectedGitRoot ([string]$validProfile.gitRoot) -ExpectedCatalogHash ('0' * 64)
    Assert-Equal $catalogDrift.ExitCode 1 'Catalog hash drift must exit 1'
    Assert-Contains @($catalogDrift.Json.reason_codes) 'BLOCKED_IDENTITY' 'Catalog hash drift identity code'
    Assert-Contains @($catalogDrift.Json.reason_codes) 'CATALOG_HASH_MISMATCH' 'Catalog hash drift detail code'
    Write-Output 'PASS catalog_hash_drift_blocked'

    $planDrift = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $validProfilePath -CatalogPath $catalogPath -ProjectRoot $root -ExpectedGitRoot ([string]$validProfile.gitRoot) -DesignPath $designPath -PlanPath $planPath -ExpectedDesignHash ('F' * 64) -ExpectedPlanHash $planHash
    Assert-Equal $planDrift.ExitCode 1 'Planning hash drift must exit 1'
    Assert-Contains @($planDrift.Json.reason_codes) 'BLOCKED_IDENTITY' 'Planning hash drift identity code'
    Assert-Contains @($planDrift.Json.reason_codes) 'DESIGN_HASH_MISMATCH' 'Planning hash drift detail code'
    Write-Output 'PASS planning_hash_drift_blocked'

    $gitMismatch = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $validProfilePath -CatalogPath $catalogPath -ProjectRoot $root -ExpectedGitRoot $root
    Assert-Equal $gitMismatch.ExitCode 1 'Git root mismatch must exit 1'
    Assert-Equal $gitMismatch.Json.verdict 'BLOCKED' 'Git root mismatch must block'
    Assert-Contains @($gitMismatch.Json.reason_codes) 'BLOCKED_IDENTITY' 'Git root mismatch identity code'
    Assert-Contains @($gitMismatch.Json.reason_codes) 'GIT_ROOT_MISMATCH' 'Git root mismatch detail code'
    Write-Output 'PASS git_root_mismatch_blocked'

    $unknownProfile = Join-Path $fixtureRoot 'profile-unknown-project.json'
    $unknown = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $unknownProfile -CatalogPath $catalogPath -ProjectRoot $root -ExpectedGitRoot ([string](Read-JsonFile -Path $unknownProfile).gitRoot)
    Assert-Equal $unknown.ExitCode 1 'Unknown project must exit 1'
    Assert-Equal $unknown.Json.verdict 'BLOCKED' 'Unknown project must block'
    Assert-Contains @($unknown.Json.reason_codes) 'BLOCKED_IDENTITY' 'Unknown project identity code'
    Assert-Contains @($unknown.Json.reason_codes) 'PROJECT_NOT_REGISTERED' 'Unknown project detail code'
    Write-Output 'PASS unknown_project_blocked'

    $crossCatalog = Join-Path $fixtureRoot 'catalog-cross-path.json'
    $crossProfile = Join-Path $fixtureRoot 'profile-cross-path.json'
    $crossProfileObject = Read-JsonFile -Path $crossProfile
    $cross = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $crossProfile -CatalogPath $crossCatalog -ProjectRoot $root -ExpectedGitRoot ([string]$crossProfileObject.gitRoot)
    Assert-Equal $cross.ExitCode 1 'Cross-project path must exit 1'
    Assert-Equal $cross.Json.verdict 'BLOCKED' 'Cross-project path must block'
    Assert-Contains @($cross.Json.reason_codes) 'BLOCKED_IDENTITY' 'Cross-project path identity code'
    Assert-Contains @($cross.Json.reason_codes) 'PATH_OUTSIDE_PROJECT' 'Cross-project path detail code'
    Write-Output 'PASS cross_project_path_blocked'

    $policyCatalog = Join-Path $fixtureRoot 'catalog-policy-drift.json'
    $policyProfile = Join-Path $fixtureRoot 'profile-policy-drift.json'
    $policyProfileObject = Read-JsonFile -Path $policyProfile
    $policy = Invoke-Validator -ValidatorPath $validatorPath -ProfilePath $policyProfile -CatalogPath $policyCatalog -ProjectRoot $root -ExpectedGitRoot ([string]$policyProfileObject.gitRoot)
    Assert-Equal $policy.ExitCode 1 'Policy version drift must exit 1'
    Assert-Equal $policy.Json.verdict 'BLOCKED' 'Policy version drift must block'
    Assert-Contains @($policy.Json.reason_codes) 'BLOCKED_POLICY' 'Policy version code'
    Assert-Contains @($policy.Json.reason_codes) 'PROFILE_SCHEMA_VERSION_UNSUPPORTED' 'Policy version detail code'
    Write-Output 'PASS policy_version_drift_blocked'

    Write-Output 'PROJECT_GOVERNANCE_PROFILE_TESTS=PASS'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    Write-Output 'PROJECT_GOVERNANCE_PROFILE_TESTS=FAIL'
    exit 1
}
