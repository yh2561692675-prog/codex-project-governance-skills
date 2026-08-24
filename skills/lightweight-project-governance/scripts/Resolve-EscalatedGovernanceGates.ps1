[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath
)

$ErrorActionPreference = 'Stop'
$reasonCodes = New-Object 'System.Collections.Generic.List[string]'
$blockingReasons = New-Object 'System.Collections.Generic.List[string]'
$requiredApprovals = New-Object 'System.Collections.Generic.List[string]'
$owners = New-Object 'System.Collections.Generic.List[string]'
$requiredEvidence = New-Object 'System.Collections.Generic.List[string]'
$releaseCriteria = New-Object 'System.Collections.Generic.List[string]'
$recoveryEntry = New-Object 'System.Collections.Generic.List[string]'
$requiredGates = New-Object 'System.Collections.Generic.List[string]'
$skippedGates = New-Object 'System.Collections.Generic.List[string]'

function Add-Unique {
    param($List, [string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) { [void]$List.Add($Value) }
}

function Add-Reason {
    param([string]$Code, [bool]$Blocking = $false)
    Add-Unique -List $reasonCodes -Value $Code
    if ($Blocking) { Add-Unique -List $blockingReasons -Value $Code }
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ArrayValue {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value | ForEach-Object { $_ })
}

function Test-BooleanSignal {
    param($Signals, [string]$Name)
    $value = Get-PropertyValue -Object $Signals -Name $Name
    return $value -is [bool] -and $value
}

function Normalize-Trigger {
    param([string]$Value)
    $normalized = ([string]$Value).Trim().ToLowerInvariant().Replace('-', '_').Replace(' ', '_')
    switch ($normalized) {
        'formal_data' { return 'formal_data' }
        'formal_fact' { return 'formal_data' }
        'acceptedfact' { return 'accepted_fact' }
        'accepted_fact' { return 'accepted_fact' }
        'accepted_fact_data' { return 'accepted_fact' }
        'formal_recommendation' { return 'formal_recommendation' }
        'personal_or_student_data' { return 'personal_or_student_data' }
        'personal_student_data' { return 'personal_or_student_data' }
        'production_or_publication' { return 'production_or_publication' }
        'production_publication' { return 'production_or_publication' }
        'public_release' { return 'production_or_publication' }
        'production' { return 'production_or_publication' }
        'paid_or_external_account' { return 'paid_or_external_account' }
        'paid_external' { return 'paid_or_external_account' }
        'paid_account' { return 'paid_or_external_account' }
        'account_permission' { return 'paid_or_external_account' }
        default { return $null }
    }
}

function Finish {
    param([bool]$Success, [string]$Verdict, [string]$QualificationReview, [string]$ProjectId, [string[]]$AffectedScope)
    $result = [ordered]@{
        schema_version = 1
        valid = $Success
        verdict = $Verdict
        project_id = $ProjectId
        required_approvals = @($requiredApprovals)
        provided_approvals = @($providedApprovals)
        owners = @($owners)
        required_evidence = @($requiredEvidence)
        evidence = @($requiredEvidence)
        provided_evidence = @($providedEvidence)
        release_criteria = @($releaseCriteria)
        recovery_entry = @($recoveryEntry)
        required_gates = @($requiredGates)
        skipped_gates = @($skippedGates)
        qualification_review = $QualificationReview
        reason_codes = @($reasonCodes)
        affected_scope = @($AffectedScope)
        escalation_blocked = $blockingReasons.Count -gt 0
    }
    $result | ConvertTo-Json -Depth 30
    if ($Success) { exit 0 } else { exit 1 }
}

$inputFull = $InputPath
if (-not (Test-Path -LiteralPath $inputFull -PathType Leaf)) {
    Add-Reason -Code 'INPUT_MISSING' -Blocking $true
    Finish -Success $false -Verdict 'BLOCKED_ESCALATION' -QualificationReview 'not_required' -ProjectId '' -AffectedScope @()
}
$source = $null
try { $source = Get-Content -LiteralPath $inputFull -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Add-Reason -Code 'INPUT_INVALID_JSON' -Blocking $true }
if ($null -eq $source) { Finish -Success $false -Verdict 'BLOCKED_ESCALATION' -QualificationReview 'not_required' -ProjectId '' -AffectedScope @() }
if ([int](Get-PropertyValue -Object $source -Name 'schema_version') -ne 1) { Add-Reason -Code 'SCHEMA_VERSION_UNSUPPORTED' -Blocking $true }

$projectId = [string](Get-PropertyValue -Object $source -Name 'project_id')
$activity = [string](Get-PropertyValue -Object $source -Name 'activity')
$affectedScope = @((Get-ArrayValue (Get-PropertyValue -Object $source -Name 'changed_paths')) | ForEach-Object { [string]$_ })
$providedApprovals = @((Get-ArrayValue (Get-PropertyValue -Object $source -Name 'approvals')) | ForEach-Object { ([string]$_).ToUpperInvariant() })
$providedEvidence = @((Get-ArrayValue (Get-PropertyValue -Object $source -Name 'evidence')) | ForEach-Object { ([string]$_).ToUpperInvariant() })
$signals = Get-PropertyValue -Object $source -Name 'signals'
$qualification = Get-PropertyValue -Object $source -Name 'qualification'

$canonicalTriggers = New-Object 'System.Collections.Generic.List[string]'
foreach ($rawTrigger in (Get-ArrayValue (Get-PropertyValue -Object $source -Name 'hard_triggers'))) {
    $canonical = Normalize-Trigger -Value ([string]$rawTrigger)
    if ($null -eq $canonical) { Add-Reason -Code 'UNKNOWN_HARD_TRIGGER' -Blocking $true }
    else { Add-Unique -List $canonicalTriggers -Value $canonical }
}
$signalTriggers = @{
    formal_data = 'formal_data'
    accepted_fact = 'accepted_fact'
    formal_recommendation = 'formal_recommendation'
    personal_or_student_data = 'personal_or_student_data'
    production_or_publication = 'production_or_publication'
    paid_or_external_account = 'paid_or_external_account'
}
foreach ($signalName in $signalTriggers.Keys) {
    if (Test-BooleanSignal -Signals $signals -Name $signalName) { Add-Unique -List $canonicalTriggers -Value $signalTriggers[$signalName] }
}
if ($activity -eq 'formal_fact') { Add-Unique -List $canonicalTriggers -Value 'accepted_fact' }
if ($activity -eq 'formal_recommendation') { Add-Unique -List $canonicalTriggers -Value 'formal_recommendation' }
if ($activity -eq 'personal_student_data') { Add-Unique -List $canonicalTriggers -Value 'personal_or_student_data' }
if ($activity -eq 'production_publication') { Add-Unique -List $canonicalTriggers -Value 'production_or_publication' }
if ($activity -eq 'paid_external') { Add-Unique -List $canonicalTriggers -Value 'paid_or_external_account' }
if (Test-BooleanSignal -Signals $signals -Name 'unknown') { Add-Reason -Code 'UNKNOWN_ESCALATION_SIGNAL' -Blocking $true }
if (Test-BooleanSignal -Signals $signals -Name 'conflict') { Add-Reason -Code 'ESCALATION_CONFLICT' -Blocking $true }

$triggerPolicies = [ordered]@{
    formal_data = [ordered]@{
        reason = 'HARD_TRIGGER_FORMAL_DATA'
        approvals = @('BUSINESS_OWNER', 'COMPLIANCE_OWNER')
        owners = @('BUSINESS_OWNER', 'COMPLIANCE_OWNER')
        evidence = @('SOURCE_REGISTER', 'FACT_VERIFICATION', 'DATA_PROVENANCE')
        criteria = @('FORMAL_DATA_SOURCE_REVIEW', 'HUMAN_ACCEPTANCE', 'FORMAL_RELEASE_APPROVAL')
        recovery = @('FORMAL_DATA_ROLLBACK')
    }
    accepted_fact = [ordered]@{
        reason = 'HARD_TRIGGER_ACCEPTED_FACT'
        approvals = @('BUSINESS_OWNER', 'SOURCE_OWNER')
        owners = @('BUSINESS_OWNER', 'SOURCE_OWNER')
        evidence = @('SOURCE_REGISTER', 'FACT_VERIFICATION')
        criteria = @('ACCEPTED_FACT_VERIFICATION', 'FORMAL_RELEASE_APPROVAL')
        recovery = @('ACCEPTED_FACT_ROLLBACK')
    }
    formal_recommendation = [ordered]@{
        reason = 'HARD_TRIGGER_FORMAL_RECOMMENDATION'
        approvals = @('BUSINESS_OWNER', 'COMPLIANCE_OWNER', 'RECOMMENDATION_REVIEWER')
        owners = @('BUSINESS_OWNER', 'COMPLIANCE_OWNER', 'RECOMMENDATION_REVIEWER')
        evidence = @('SOURCE_TRACE', 'RECOMMENDATION_CRITERIA', 'HUMAN_REVIEW')
        criteria = @('HUMAN_RECOMMENDATION_REVIEW', 'USER_FINAL_APPROVAL')
        recovery = @('RECOMMENDATION_ROLLBACK')
    }
    personal_or_student_data = [ordered]@{
        reason = 'HARD_TRIGGER_PERSONAL_OR_STUDENT_DATA'
        approvals = @('DATA_PROTECTION_OWNER', 'COMPLIANCE_OWNER')
        owners = @('DATA_PROTECTION_OWNER', 'COMPLIANCE_OWNER')
        evidence = @('AUTHORIZED_DATA_SCOPE', 'DATA_MINIMIZATION', 'ACCESS_LOG')
        criteria = @('PROTECTED_DATA_APPROVAL', 'ACCESS_REVIEW')
        recovery = @('PROTECTED_DATA_DELETE_OR_REVOKE')
    }
    production_or_publication = [ordered]@{
        reason = 'HARD_TRIGGER_PRODUCTION_OR_PUBLICATION'
        approvals = @('RELEASE_OWNER', 'BUSINESS_OWNER', 'COMPLIANCE_OWNER')
        owners = @('RELEASE_OWNER', 'BUSINESS_OWNER', 'COMPLIANCE_OWNER')
        evidence = @('RELEASE_CHECKLIST', 'ROLLBACK_PLAN', 'OBSERVABILITY')
        criteria = @('RELEASE_APPROVAL', 'ROLLBACK_READY')
        recovery = @('RELEASE_ROLLBACK')
    }
    paid_or_external_account = [ordered]@{
        reason = 'HARD_TRIGGER_PAID_OR_EXTERNAL_ACCOUNT'
        approvals = @('ACCOUNT_OWNER', 'USER_EXTERNAL_ACTION_APPROVER')
        owners = @('ACCOUNT_OWNER', 'USER_EXTERNAL_ACTION_APPROVER')
        evidence = @('ACCOUNT_AUTHORIZATION', 'PAYMENT_APPROVAL')
        criteria = @('EXTERNAL_ACTION_APPROVAL', 'PAYMENT_REVERSIBILITY')
        recovery = @('ACCOUNT_REVOKE_OR_REFUND')
    }
}

$qualificationReview = 'not_required'
foreach ($field in @('legal', 'license', 'account_permission', 'designated_role')) {
    if (Test-BooleanSignal -Signals $qualification -Name $field) { $qualificationReview = 'required' }
}
if ($qualificationReview -eq 'required') {
    Add-Reason -Code 'QUALIFICATION_REVIEW_REQUIRED'
    Add-Unique -List $requiredApprovals -Value 'QUALIFICATION_OWNER'
    Add-Unique -List $owners -Value 'QUALIFICATION_OWNER'
    Add-Unique -List $requiredEvidence -Value 'QUALIFICATION_BASIS'
    Add-Unique -List $releaseCriteria -Value 'QUALIFICATION_REVIEW_COMPLETE'
    Add-Unique -List $recoveryEntry -Value 'QUALIFICATION_REVIEW_REVOKE'
    Add-Unique -List $requiredGates -Value 'qualification_review'
    if ($providedApprovals -notcontains 'QUALIFICATION_OWNER') { Add-Reason -Code 'ESCALATION_APPROVAL_MISSING' -Blocking $true }
    if ($providedEvidence -notcontains 'QUALIFICATION_BASIS') { Add-Reason -Code 'ESCALATION_EVIDENCE_MISSING' -Blocking $true }
}
else { Add-Unique -List $skippedGates -Value 'qualification_review' }

if ($canonicalTriggers.Count -eq 0 -and $blockingReasons.Count -eq 0) {
    Add-Unique -List $owners -Value 'PROJECT_DEVELOPER'
    Add-Unique -List $requiredEvidence -Value 'ENGINEERING_TESTS'
    Add-Unique -List $releaseCriteria -Value 'AUTOMATED_TESTS_PASS'
    Add-Unique -List $recoveryEntry -Value 'REVERT_LOCAL_CHANGE'
    Add-Unique -List $requiredGates -Value 'automatic_development'
    Add-Unique -List $requiredGates -Value 'automated_candidate'
    Add-Unique -List $skippedGates -Value 'business_owner_review'
    Add-Unique -List $skippedGates -Value 'compliance_review'
    Add-Unique -List $skippedGates -Value 'second_reviewer'
}
else {
    Add-Unique -List $requiredGates -Value 'escalated_review'
    Add-Unique -List $requiredGates -Value 'user_final_review'
    foreach ($trigger in @('formal_data', 'accepted_fact', 'formal_recommendation', 'personal_or_student_data', 'production_or_publication', 'paid_or_external_account')) {
        if ($canonicalTriggers -contains $trigger) {
            $policy = $triggerPolicies[$trigger]
            Add-Reason -Code ([string]$policy.reason)
            foreach ($value in @($policy.approvals)) { Add-Unique -List $requiredApprovals -Value $value }
            foreach ($value in @($policy.owners)) { Add-Unique -List $owners -Value $value }
            foreach ($value in @($policy.evidence)) { Add-Unique -List $requiredEvidence -Value $value }
            foreach ($value in @($policy.criteria)) { Add-Unique -List $releaseCriteria -Value $value }
            foreach ($value in @($policy.recovery)) { Add-Unique -List $recoveryEntry -Value $value }
        }
    }
    foreach ($approval in @($requiredApprovals)) { if ($providedApprovals -notcontains $approval) { Add-Reason -Code 'ESCALATION_APPROVAL_MISSING' -Blocking $true; break } }
    foreach ($evidenceItem in @($requiredEvidence)) { if ($providedEvidence -notcontains $evidenceItem) { Add-Reason -Code 'ESCALATION_EVIDENCE_MISSING' -Blocking $true; break } }
}

if ($canonicalTriggers.Count -eq 0 -and $qualificationReview -eq 'not_required' -and $blockingReasons.Count -eq 0) {
    Finish -Success $true -Verdict 'LIGHTWEIGHT_ALLOWED' -QualificationReview $qualificationReview -ProjectId $projectId -AffectedScope $affectedScope
}
if ($blockingReasons.Count -gt 0) {
    Finish -Success $false -Verdict 'BLOCKED_ESCALATION' -QualificationReview $qualificationReview -ProjectId $projectId -AffectedScope $affectedScope
}
Finish -Success $true -Verdict 'ESCALATED_READY' -QualificationReview $qualificationReview -ProjectId $projectId -AffectedScope $affectedScope
