[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$PolicyPath
)

$ErrorActionPreference = 'Stop'
$reasons = New-Object 'System.Collections.Generic.List[string]'
$requiredGates = New-Object 'System.Collections.Generic.List[string]'
$skippedGates = New-Object 'System.Collections.Generic.List[string]'
$tier = 'BLOCKED'
$qualificationReview = 'not_required'
$affectedScope = New-Object 'System.Collections.Generic.List[string]'

function Add-Unique {
    param([Parameter(Mandatory = $true)]$List, [Parameter(Mandatory = $true)][string]$Value)
    if (-not $List.Contains($Value)) { [void]$List.Add($Value) }
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$MissingCode, [Parameter(Mandatory = $true)][string]$InvalidCode)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Unique -List $reasons -Value $MissingCode; return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-Unique -List $reasons -Value $InvalidCode; return $null }
}

function Get-Property {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-True {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    $value = Get-Property -Object $Object -Name $Name
    return $value -is [bool] -and $value
}

function Write-ResultAndExit {
    param([Parameter(Mandatory = $true)][bool]$Success, [string]$ProjectId, [string]$Activity, [string]$PolicyVersion, [string]$PolicyHash)
    $result = [ordered]@{
        tier = $tier
        required_gates = @($requiredGates)
        skipped_gates = @($skippedGates)
        reason_codes = @($reasons)
        affected_scope = @($affectedScope)
        qualification_review = $qualificationReview
        project_id = $ProjectId
        activity = $Activity
        policy_version = $PolicyVersion
        policy_hash = $PolicyHash
    }
    $result | ConvertTo-Json -Depth 20
    if ($Success) { exit 0 } else { exit 1 }
}

$input = Read-Json -Path $InputPath -MissingCode 'INPUT_MISSING' -InvalidCode 'INPUT_INVALID'
$policy = Read-Json -Path $PolicyPath -MissingCode 'POLICY_MISSING' -InvalidCode 'POLICY_INVALID'
$projectId = [string](Get-Property -Object $input -Name 'project_id')
$activity = [string](Get-Property -Object $input -Name 'activity')
$policyVersion = [string](Get-Property -Object $policy -Name 'schemaVersion')
$policyHash = ''
if (Test-Path -LiteralPath $PolicyPath -PathType Leaf) { $policyHash = (Get-FileHash -LiteralPath $PolicyPath -Algorithm SHA256).Hash.ToUpperInvariant() }

if ($null -eq $input -or $null -eq $policy) {
    Add-Unique -List $requiredGates -Value 'risk_resolution'
    Add-Unique -List $requiredGates -Value 'user_decision'
    Write-ResultAndExit -Success $false -ProjectId $projectId -Activity $activity -PolicyVersion $policyVersion -PolicyHash $policyHash
}

$changedPaths = @((Get-Property -Object $input -Name 'changed_paths') | ForEach-Object { [string]$_ })
if ($changedPaths.Count -eq 0) { Add-Unique -List $affectedScope -Value 'project' } else { foreach ($path in $changedPaths) { Add-Unique -List $affectedScope -Value $path } }

$triggerOrder = @('formal_data', 'personal_or_student_data', 'secrets', 'formal_recommendation', 'production_or_publication', 'paid_or_external_account')
$triggerReason = @{
    formal_data = 'HARD_TRIGGER_FORMAL_DATA'
    personal_or_student_data = 'HARD_TRIGGER_PERSONAL_OR_STUDENT_DATA'
    secrets = 'HARD_TRIGGER_SECRET_OR_CREDENTIAL'
    formal_recommendation = 'HARD_TRIGGER_FORMAL_RECOMMENDATION'
    production_or_publication = 'HARD_TRIGGER_PRODUCTION_OR_PUBLICATION'
    paid_or_external_account = 'HARD_TRIGGER_PAID_OR_EXTERNAL_ACCOUNT'
}
$triggerGates = @{
    formal_data = @('source_review', 'escalated_review', 'user_final_review')
    personal_or_student_data = @('authorized_protected_data', 'escalated_review')
    secrets = @('secret_handling_authorization', 'escalated_review')
    formal_recommendation = @('human_recommendation_review', 'escalated_review', 'user_final_review')
    production_or_publication = @('release_approval', 'escalated_review', 'user_final_review')
    paid_or_external_account = @('user_external_action_approval', 'escalated_review')
}
$policyTriggerIds = @($policy.hardTriggers | ForEach-Object { [string]$_.id })
if ([string]$policy.defaultPriority -ne 'lightweight_first' -or [string]$policy.unknownRiskAction -ne 'escalate') {
    Add-Unique -List $reasons -Value 'BLOCKED_POLICY'
    Add-Unique -List $reasons -Value 'POLICY_DEFAULT_MISMATCH'
}
foreach ($trigger in $triggerOrder) {
    if ($policyTriggerIds -notcontains $trigger) {
        Add-Unique -List $reasons -Value 'BLOCKED_POLICY'
        Add-Unique -List $reasons -Value 'POLICY_TRIGGER_MISSING'
    }
}

$signals = Get-Property -Object $input -Name 'signals'
$explicitTriggers = New-Object 'System.Collections.Generic.List[string]'
foreach ($trigger in @((Get-Property -Object $input -Name 'hard_triggers'))) {
    $triggerValue = [string]$trigger
    if (-not [string]::IsNullOrWhiteSpace($triggerValue)) { Add-Unique -List $explicitTriggers -Value $triggerValue }
}
$signalToTrigger = @{
    formal_data = 'formal_data'
    personal_or_student_data = 'personal_or_student_data'
    secrets = 'secrets'
    formal_recommendation = 'formal_recommendation'
    production_or_publication = 'production_or_publication'
    paid_or_external_account = 'paid_or_external_account'
}
foreach ($key in $signalToTrigger.Keys) {
    if (Test-True -Object $signals -Name $key) { Add-Unique -List $explicitTriggers -Value $signalToTrigger[$key] }
}
$activityTrigger = @{
    formal_fact = 'formal_data'
    personal_student_data = 'personal_or_student_data'
    formal_recommendation = 'formal_recommendation'
    production_publication = 'production_or_publication'
    secret_operation = 'secrets'
    paid_external = 'paid_or_external_account'
}
if ($activityTrigger.ContainsKey($activity)) { Add-Unique -List $explicitTriggers -Value $activityTrigger[$activity] }

foreach ($trigger in @($explicitTriggers)) {
    if ($triggerOrder -notcontains $trigger) {
        Add-Unique -List $reasons -Value 'RISK_UNKNOWN'
    }
}
if ((Test-True -Object $signals -Name 'unknown') -or (Test-True -Object $signals -Name 'conflict')) {
    Add-Unique -List $reasons -Value 'RISK_CONFLICT'
}

$knownActivities = @('ordinary_code', 'ordinary_test', 'ordinary_documentation', 'anonymous_fixture', 'personal_content', 'external_research_draft', 'formal_fact', 'personal_student_data', 'formal_recommendation', 'production_publication', 'secret_operation', 'paid_external')
if ($knownActivities -notcontains $activity -and $explicitTriggers.Count -eq 0) { Add-Unique -List $reasons -Value 'RISK_UNKNOWN' }

$qualification = Get-Property -Object $input -Name 'qualification'
$qualificationFields = @('legal', 'license', 'account_permission', 'designated_role')
$qualificationRequired = $false
foreach ($field in $qualificationFields) { if (Test-True -Object $qualification -Name $field) { $qualificationRequired = $true } }
if ($qualificationRequired) { $qualificationReview = 'required' }

if ($reasons.Count -gt 0) {
    $tier = 'BLOCKED'
    Add-Unique -List $requiredGates -Value 'risk_resolution'
    Add-Unique -List $requiredGates -Value 'user_decision'
    Write-ResultAndExit -Success $false -ProjectId $projectId -Activity $activity -PolicyVersion $policyVersion -PolicyHash $policyHash
}

if ($explicitTriggers.Count -gt 0) {
    $tier = 'ESCALATED'
    Add-Unique -List $requiredGates -Value 'automatic_development'
    Add-Unique -List $requiredGates -Value 'automated_candidate'
    foreach ($trigger in $triggerOrder) {
        if ($explicitTriggers -contains $trigger) {
            Add-Unique -List $reasons -Value $triggerReason[$trigger]
            foreach ($gate in $triggerGates[$trigger]) { Add-Unique -List $requiredGates -Value $gate }
        }
    }
    if ($qualificationRequired) { Add-Unique -List $requiredGates -Value 'qualification_review' } else { Add-Unique -List $skippedGates -Value 'qualification_review' }
    Write-ResultAndExit -Success $true -ProjectId $projectId -Activity $activity -PolicyVersion $policyVersion -PolicyHash $policyHash
}

if ($qualificationRequired) {
    $tier = 'ESCALATED'
    Add-Unique -List $reasons -Value 'QUALIFICATION_REVIEW_REQUIRED'
    Add-Unique -List $requiredGates -Value 'automatic_development'
    Add-Unique -List $requiredGates -Value 'automated_candidate'
    Add-Unique -List $requiredGates -Value 'qualification_review'
    Add-Unique -List $requiredGates -Value 'escalated_review'
    Write-ResultAndExit -Success $true -ProjectId $projectId -Activity $activity -PolicyVersion $policyVersion -PolicyHash $policyHash
}

switch ($activity) {
    'ordinary_code' { $tier = 'LIGHTWEIGHT'; Add-Unique -List $reasons -Value 'ORDINARY_DEVELOPMENT' }
    'ordinary_test' { $tier = 'LIGHTWEIGHT'; Add-Unique -List $reasons -Value 'ORDINARY_DEVELOPMENT' }
    'ordinary_documentation' { $tier = 'LIGHTWEIGHT'; Add-Unique -List $reasons -Value 'ORDINARY_DEVELOPMENT' }
    'anonymous_fixture' { $tier = 'LIGHTWEIGHT'; Add-Unique -List $reasons -Value 'ORDINARY_DEVELOPMENT' }
    'personal_content' { $tier = 'CANDIDATE'; Add-Unique -List $reasons -Value 'PERSONAL_CONTENT_FINAL_REVIEW' }
    'external_research_draft' { $tier = 'CANDIDATE'; Add-Unique -List $reasons -Value 'EXTERNAL_DRAFT_SOURCE_ONLY' }
    default { $tier = 'BLOCKED'; Add-Unique -List $reasons -Value 'RISK_UNKNOWN' }
}

if ($tier -eq 'LIGHTWEIGHT') {
    Add-Unique -List $requiredGates -Value 'automatic_development'
    Add-Unique -List $requiredGates -Value 'automated_candidate'
    Add-Unique -List $skippedGates -Value 'qualification_review'
    Add-Unique -List $skippedGates -Value 'escalated_review'
}
elseif ($tier -eq 'CANDIDATE') {
    Add-Unique -List $requiredGates -Value 'automatic_development'
    Add-Unique -List $requiredGates -Value 'automated_candidate'
    Add-Unique -List $requiredGates -Value 'user_final_review'
    Add-Unique -List $skippedGates -Value 'qualification_review'
    Add-Unique -List $skippedGates -Value 'escalated_review'
}
else {
    Add-Unique -List $requiredGates -Value 'risk_resolution'
    Add-Unique -List $requiredGates -Value 'user_decision'
}

Write-ResultAndExit -Success ($tier -ne 'BLOCKED') -ProjectId $projectId -Activity $activity -PolicyVersion $policyVersion -PolicyHash $policyHash
