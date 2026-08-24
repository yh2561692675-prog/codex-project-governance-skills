[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$PolicyPath
)

$ErrorActionPreference = 'Stop'
$reasonCodes = New-Object 'System.Collections.Generic.List[string]'
$requiredEvidence = New-Object 'System.Collections.Generic.List[string]'
$requiredGates = New-Object 'System.Collections.Generic.List[string]'
$skippedGates = New-Object 'System.Collections.Generic.List[string]'
$layers = New-Object 'System.Collections.Generic.List[object]'

function Add-Unique {
    param([Parameter(Mandatory = $true)]$List, [Parameter(Mandatory = $true)][string]$Value)
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) { [void]$List.Add($Value) }
}

function Get-Property {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$MissingCode, [Parameter(Mandatory = $true)][string]$InvalidCode)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Unique -List $reasonCodes -Value $MissingCode; return $null }
    try {
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        return [System.IO.File]::ReadAllText($Path, $strictUtf8) | ConvertFrom-Json
    }
    catch { Add-Unique -List $reasonCodes -Value $InvalidCode; return $null }
}

function Test-True {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    $value = Get-Property -Object $Object -Name $Name
    return $value -is [bool] -and $value
}

function Get-EvidenceStatus {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if (Test-True -Object $Object -Name $Name) { return 'PASS' }
    return 'BLOCKED'
}

function Add-Layer {
    param([string]$Name, [string]$Status, [string]$Reason)
    [void]$layers.Add([ordered]@{ name = $Name; status = $Status; applicability_reason = $Reason })
}

function Finish {
    param([bool]$Success, [string]$TerminalState, [string]$GovernanceMode, [bool]$RequiredReview, [string]$ProjectId, [string]$Target, [string]$Release, [string]$Review)
    $result = [ordered]@{
        schema_version = 1
        valid = $Success
        project_id = $ProjectId
        governance_mode = $GovernanceMode
        terminal_state = $TerminalState
        required_review = $RequiredReview
        delivery_target = $Target
        release_intent = $Release
        review_policy = $Review
        required_evidence = $requiredEvidence.ToArray()
        required_gates = $requiredGates.ToArray()
        skipped_gates = $skippedGates.ToArray()
        layers = $layers.ToArray()
        reason_codes = $reasonCodes.ToArray()
    }
    $result | ConvertTo-Json -Depth 30
    if ($Success) { exit 0 } else { exit 1 }
}

$input = Read-Json -Path $InputPath -MissingCode 'INPUT_MISSING' -InvalidCode 'INPUT_INVALID'
$policy = Read-Json -Path $PolicyPath -MissingCode 'POLICY_MISSING' -InvalidCode 'POLICY_INVALID'
$projectId = [string](Get-Property -Object $input -Name 'project_id')
$target = [string](Get-Property -Object $input -Name 'delivery_target')
$releaseIntent = [string](Get-Property -Object $input -Name 'release_intent')
$reviewPolicy = [string](Get-Property -Object $input -Name 'review_policy')
$identity = Get-Property -Object (Get-Property -Object $input -Name 'risk') -Name 'identity_preflight'
if ($null -eq $input -or $null -eq $policy) { Add-Unique -List $requiredGates -Value 'risk_resolution'; Add-Unique -List $requiredGates -Value 'user_decision'; Finish -Success $false -TerminalState 'BLOCKED' -GovernanceMode 'BLOCKED' -RequiredReview $true -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy }

if ([int](Get-Property -Object $input -Name 'schema_version') -ne 1) { Add-Unique -List $reasonCodes -Value 'INPUT_SCHEMA_UNSUPPORTED' }
if ([string](Get-Property -Object $policy -Name 'schemaVersion') -ne '2.0') { Add-Unique -List $reasonCodes -Value 'POLICY_VERSION_UNSUPPORTED' }
$matrixRow = @($policy.deliveryMatrix | Where-Object { [string]$_.deliveryTarget -eq $target }) | Select-Object -First 1
$combination = "$target+$releaseIntent"
if ($null -eq $matrixRow -or @($policy.invalidCombinations) -contains $combination) { Add-Unique -List $reasonCodes -Value 'V1_1_DELIVERY_INTENT_INVALID' }
elseif ([string]$matrixRow.releaseIntent -ne $releaseIntent) { Add-Unique -List $reasonCodes -Value 'V1_1_DELIVERY_INTENT_INVALID' }
elseif ([string]$matrixRow.reviewPolicy -eq 'NONE_OR_OPTIONAL') {
    if (@('NONE', 'OPTIONAL') -notcontains $reviewPolicy) { Add-Unique -List $reasonCodes -Value 'V1_1_REVIEW_POLICY_INVALID' }
}
elseif ([string]$matrixRow.reviewPolicy -ne $reviewPolicy) { Add-Unique -List $reasonCodes -Value 'V1_1_REVIEW_POLICY_INVALID' }
if ((Get-Property -Object $input -Name 'effective_from_fresh_run') -ne $true) { Add-Unique -List $reasonCodes -Value 'FRESH_RUN_EFFECTIVE_REQUIRED' }

$evidence = Get-Property -Object $input -Name 'evidence'
$baseEvidence = [ordered]@{ plan = 'PLAN_EVIDENCE_REQUIRED'; engineering = 'ENGINEERING_EVIDENCE_REQUIRED'; candidate_identity = 'CANDIDATE_IDENTITY_REQUIRED'; rollback = 'ROLLBACK_EVIDENCE_REQUIRED' }
foreach ($name in $baseEvidence.Keys) {
    Add-Unique -List $requiredEvidence -Value $name
    if (-not (Test-True -Object $evidence -Name $name)) { Add-Unique -List $reasonCodes -Value $baseEvidence[$name] }
}
$risk = Get-Property -Object $input -Name 'risk'
$hardTriggers = @((Get-Property -Object $risk -Name 'hard_triggers') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$knownTriggers = @($policy.hardTriggers | ForEach-Object { [string]$_.id })
$hardRisk = $false
if ($identity -ne 'READY') { Add-Unique -List $reasonCodes -Value 'IDENTITY_OR_PREFLIGHT_BLOCKED' }
if (Test-True -Object $risk -Name 'shared_resource_conflict') { Add-Unique -List $reasonCodes -Value 'SHARED_RESOURCE_CONFLICT' }
if (Test-True -Object $risk -Name 'destructive_action') { Add-Unique -List $reasonCodes -Value 'DESTRUCTIVE_ACTION_BLOCKED' }
if (Test-True -Object $risk -Name 'unknown') { Add-Unique -List $reasonCodes -Value 'RISK_UNKNOWN' }
foreach ($trigger in $hardTriggers) {
    if ($knownTriggers -notcontains $trigger) { Add-Unique -List $reasonCodes -Value 'RISK_UNKNOWN' }
    else { $hardRisk = $true; Add-Unique -List $reasonCodes -Value ('HARD_TRIGGER_' + $trigger.ToUpperInvariant()) }
}

if ($target -eq 'LOCAL_USABLE') {
    Add-Unique -List $requiredEvidence -Value 'installation'
    Add-Unique -List $requiredEvidence -Value 'local_smoke'
    if (-not (Test-True -Object $evidence -Name 'installation')) { Add-Unique -List $reasonCodes -Value 'INSTALLATION_EVIDENCE_REQUIRED' }
    if (-not (Test-True -Object $evidence -Name 'local_smoke')) { Add-Unique -List $reasonCodes -Value 'LOCAL_SMOKE_EVIDENCE_REQUIRED' }
}
if ($target -eq 'INTERNAL_REVIEW' -or $target -eq 'FORMAL_RELEASE') {
    Add-Unique -List $requiredEvidence -Value 'user_final_review'
    Add-Unique -List $requiredGates -Value 'user_final_review'
    if (-not (Test-True -Object $evidence -Name 'user_final_review')) { Add-Unique -List $reasonCodes -Value 'USER_FINAL_REVIEW_REQUIRED' }
}
if ($target -eq 'FORMAL_RELEASE') {
    foreach ($name in @('installation', 'local_smoke', 'real_use', 'human_acceptance', 'formal_data')) {
        Add-Unique -List $requiredEvidence -Value $name
        if (-not (Test-True -Object $evidence -Name $name)) { Add-Unique -List $reasonCodes -Value (($name.ToUpperInvariant()) + '_EVIDENCE_REQUIRED') }
    }
}

Add-Layer -Name 'engineering' -Status (Get-EvidenceStatus -Object $evidence -Name 'engineering') -Reason ''
if ($target -eq 'ENGINEERING_ONLY') {
    Add-Layer -Name 'installation' -Status 'NOT_APPLICABLE' -Reason 'deliveryTarget=ENGINEERING_ONLY; installation is outside the requested delivery.'
    Add-Layer -Name 'real_use' -Status 'NOT_APPLICABLE' -Reason 'deliveryTarget=ENGINEERING_ONLY; real use is outside the requested delivery.'
    Add-Layer -Name 'human_acceptance' -Status 'NOT_APPLICABLE' -Reason 'reviewPolicy=NONE; human acceptance is outside the requested delivery.'
    Add-Layer -Name 'formal_data' -Status 'NOT_APPLICABLE' -Reason 'releaseIntent=NONE; formal data is outside the requested delivery.'
    Add-Layer -Name 'formal_release' -Status 'NOT_APPLICABLE' -Reason 'releaseIntent=NONE; formal release is outside the requested delivery.'
}
elseif ($target -eq 'LOCAL_USABLE') {
    Add-Layer -Name 'installation' -Status (Get-EvidenceStatus -Object $evidence -Name 'installation') -Reason ''
    Add-Layer -Name 'real_use' -Status 'NOT_APPLICABLE' -Reason 'deliveryTarget=LOCAL_USABLE; formal real-use evidence is outside local usability scope.'
    Add-Layer -Name 'human_acceptance' -Status 'NOT_APPLICABLE' -Reason 'reviewPolicy does not require formal human acceptance for local usability.'
    Add-Layer -Name 'formal_data' -Status 'NOT_APPLICABLE' -Reason 'releaseIntent=NONE; formal data is outside the requested delivery.'
    Add-Layer -Name 'formal_release' -Status 'NOT_APPLICABLE' -Reason 'releaseIntent=NONE; formal release is outside the requested delivery.'
}
elseif ($target -eq 'INTERNAL_REVIEW') {
    Add-Layer -Name 'installation' -Status 'NOT_APPLICABLE' -Reason 'deliveryTarget=INTERNAL_REVIEW; installation is not part of this review package.'
    Add-Layer -Name 'real_use' -Status 'NOT_APPLICABLE' -Reason 'deliveryTarget=INTERNAL_REVIEW; real use is not part of this review package.'
    Add-Layer -Name 'human_acceptance' -Status (Get-EvidenceStatus -Object $evidence -Name 'user_final_review') -Reason ''
    Add-Layer -Name 'formal_data' -Status 'NOT_APPLICABLE' -Reason 'releaseIntent=NONE; formal data is outside the requested delivery.'
    Add-Layer -Name 'formal_release' -Status 'NOT_APPLICABLE' -Reason 'releaseIntent=NONE; formal release is outside the requested delivery.'
}
else {
    foreach ($name in @('installation', 'real_use', 'human_acceptance', 'formal_data', 'formal_release')) {
        Add-Layer -Name $name -Status (Get-EvidenceStatus -Object $evidence -Name $name) -Reason ''
    }
}

if ($reasonCodes.Count -gt 0 -and -not $hardRisk) {
    Add-Unique -List $requiredGates -Value 'risk_resolution'
    Finish -Success $false -TerminalState 'BLOCKED' -GovernanceMode 'BLOCKED' -RequiredReview $true -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy
}
if ($hardRisk) {
    Add-Unique -List $requiredGates -Value 'escalated_review'
    Add-Unique -List $requiredGates -Value 'user_final_review'
    Finish -Success $true -TerminalState 'ESCALATED_REVIEW' -GovernanceMode 'ESCALATED' -RequiredReview $true -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy
}

switch ($target) {
    'ENGINEERING_ONLY' {
        Add-Unique -List $reasonCodes -Value 'DELIVERY_TARGET_ENGINEERING_ONLY'
        Add-Unique -List $skippedGates -Value 'user_final_review'
        Finish -Success $true -TerminalState 'LOCAL_CANDIDATE_READY' -GovernanceMode 'LOCAL_AUTONOMOUS' -RequiredReview $false -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy
    }
    'LOCAL_USABLE' {
        if ($reviewPolicy -eq 'OPTIONAL') {
            Add-Unique -List $reasonCodes -Value 'OPTIONAL_REVIEW_AVAILABLE'
            Finish -Success $true -TerminalState 'OPTIONAL_REVIEW_AVAILABLE' -GovernanceMode 'LOCAL_AUTONOMOUS' -RequiredReview $false -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy
        }
        Add-Unique -List $reasonCodes -Value 'DELIVERY_TARGET_LOCAL_USABLE'
        Finish -Success $true -TerminalState 'LOCAL_USABLE_READY' -GovernanceMode 'LOCAL_AUTONOMOUS' -RequiredReview $false -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy
    }
    'INTERNAL_REVIEW' { Finish -Success $true -TerminalState 'USER_FINAL_REVIEW' -GovernanceMode 'USER_REVIEW' -RequiredReview $true -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy }
    'FORMAL_RELEASE' { Finish -Success $true -TerminalState 'READY_FOR_USER_RELEASE_DECISION' -GovernanceMode 'USER_REVIEW' -RequiredReview $true -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy }
    default { Add-Unique -List $reasonCodes -Value 'V1_1_DELIVERY_INTENT_INVALID'; Finish -Success $false -TerminalState 'BLOCKED' -GovernanceMode 'BLOCKED' -RequiredReview $true -ProjectId $projectId -Target $target -Release $releaseIntent -Review $reviewPolicy }
}
