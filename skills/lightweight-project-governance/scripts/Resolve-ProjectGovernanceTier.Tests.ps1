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
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "JSON fixture missing: $Path"
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "JSON_INVALID: $Path :: $($_.Exception.Message)" }
}

function Invoke-Tier {
    param([Parameter(Mandatory = $true)][string]$ResolverPath, [Parameter(Mandatory = $true)][string]$InputPath, [Parameter(Mandatory = $true)][string]$PolicyPath)
    $raw = @(& $ResolverPath -InputPath $InputPath -PolicyPath $PolicyPath 2>&1)
    $exitCode = $LASTEXITCODE
    $json = $null
    if ($raw.Count -gt 0) {
        try { $json = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json; Raw = $raw }
}

function Assert-Tier {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][string]$Tier,
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [Parameter(Mandatory = $true)][string]$QualificationReview,
        [string[]]$RequiredGates,
        [string[]]$SkippedGates,
        [Parameter(Mandatory = $true)][string]$Context
    )
    Assert-Equal $Result.ExitCode $ExitCode "$Context exit code"
    Assert-True ($null -ne $Result.Json) "$Context must return JSON"
    Assert-Equal $Result.Json.tier $Tier "$Context tier"
    Assert-Contains @($Result.Json.reason_codes) $ReasonCode "$Context reason code"
    Assert-Equal $Result.Json.qualification_review $QualificationReview "$Context qualification review"
    foreach ($gate in @($RequiredGates)) { Assert-Contains @($Result.Json.required_gates) $gate "$Context required gate" }
    foreach ($gate in @($SkippedGates)) { Assert-Contains @($Result.Json.skipped_gates) $gate "$Context skipped gate" }
    Assert-True (@($Result.Json.affected_scope).Count -ge 1) "$Context affected scope"
}

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$resolverPath = Join-Path $PSScriptRoot 'Resolve-ProjectGovernanceTier.ps1'
$referencePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'references\risk-tier-contract.md'
$policyPath = Join-Path $root 'config\lightweight-governance\risk-policy.json'
$fixtureRoot = Join-Path $root 'tests\fixtures\lightweight-governance\risk-tiers'

try {
    Assert-True (Test-Path -LiteralPath $resolverPath -PathType Leaf) 'resolver script must exist'
    Assert-True (Test-Path -LiteralPath $referencePath -PathType Leaf) 'risk-tier-contract.md must exist'
    $reference = Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8
    foreach ($tierName in @('LIGHTWEIGHT', 'CANDIDATE', 'ESCALATED', 'BLOCKED')) { Assert-True ($reference.Contains($tierName)) "reference missing tier $tierName" }
    Assert-True ($reference -match '(?i)hard trigger') 'reference must document hard-trigger precedence'
    Assert-True ($reference -match '(?i)fail-closed') 'reference must document fail-closed unknown/conflict behavior'
    Write-Output 'PASS risk_tier_structure_and_contract'

    $ordinaryCodePath = Join-Path $fixtureRoot 'ordinary-code.json'
    $ordinaryCode = Invoke-Tier -ResolverPath $resolverPath -InputPath $ordinaryCodePath -PolicyPath $policyPath
    Assert-Tier -Result $ordinaryCode -ExitCode 0 -Tier 'LIGHTWEIGHT' -ReasonCode 'ORDINARY_DEVELOPMENT' -QualificationReview 'not_required' -RequiredGates @('automatic_development', 'automated_candidate') -SkippedGates @('qualification_review', 'escalated_review') -Context 'ordinary code'
    Write-Output 'PASS ordinary_code_without_human_gate'

    foreach ($name in @('ordinary-test', 'ordinary-documentation', 'anonymous-fixture')) {
        $result = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot ($name + '.json')) -PolicyPath $policyPath
        Assert-Tier -Result $result -ExitCode 0 -Tier 'LIGHTWEIGHT' -ReasonCode 'ORDINARY_DEVELOPMENT' -QualificationReview 'not_required' -RequiredGates @('automatic_development', 'automated_candidate') -SkippedGates @('qualification_review', 'escalated_review') -Context $name
    }
    Write-Output 'PASS ordinary_test_documentation_fixture'

    foreach ($name in @('personal-content', 'external-research-draft')) {
        $result = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot ($name + '.json')) -PolicyPath $policyPath
        $reason = 'EXTERNAL_DRAFT_SOURCE_ONLY'
        if ($name -eq 'personal-content') { $reason = 'PERSONAL_CONTENT_FINAL_REVIEW' }
        Assert-Tier -Result $result -ExitCode 0 -Tier 'CANDIDATE' -ReasonCode $reason -QualificationReview 'not_required' -RequiredGates @('automatic_development', 'automated_candidate', 'user_final_review') -SkippedGates @('qualification_review', 'escalated_review') -Context $name
    }
    Write-Output 'PASS personal_content_and_external_draft_candidate'

    $formalFact = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'formal-fact.json') -PolicyPath $policyPath
    Assert-Tier -Result $formalFact -ExitCode 0 -Tier 'ESCALATED' -ReasonCode 'HARD_TRIGGER_FORMAL_DATA' -QualificationReview 'not_required' -RequiredGates @('escalated_review', 'source_review', 'user_final_review') -SkippedGates @('qualification_review') -Context 'formal fact'
    Write-Output 'PASS formal_fact_hard_trigger'

    $student = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'personal-student-data.json') -PolicyPath $policyPath
    Assert-Tier -Result $student -ExitCode 0 -Tier 'ESCALATED' -ReasonCode 'HARD_TRIGGER_PERSONAL_OR_STUDENT_DATA' -QualificationReview 'not_required' -RequiredGates @('escalated_review', 'authorized_protected_data') -SkippedGates @() -Context 'personal/student data'
    Write-Output 'PASS personal_student_data_hard_trigger'

    $recommendation = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'formal-recommendation.json') -PolicyPath $policyPath
    Assert-Tier -Result $recommendation -ExitCode 0 -Tier 'ESCALATED' -ReasonCode 'HARD_TRIGGER_FORMAL_RECOMMENDATION' -QualificationReview 'not_required' -RequiredGates @('escalated_review', 'human_recommendation_review', 'user_final_review') -SkippedGates @() -Context 'formal recommendation'
    Write-Output 'PASS formal_recommendation_hard_trigger'

    $publication = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'production-publication.json') -PolicyPath $policyPath
    Assert-Tier -Result $publication -ExitCode 0 -Tier 'ESCALATED' -ReasonCode 'HARD_TRIGGER_PRODUCTION_OR_PUBLICATION' -QualificationReview 'not_required' -RequiredGates @('escalated_review', 'release_approval', 'user_final_review') -SkippedGates @() -Context 'production/publication'
    Write-Output 'PASS production_publication_hard_trigger'

    $qualificationOff = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'qualification-not-required.json') -PolicyPath $policyPath
    Assert-Equal $qualificationOff.Json.qualification_review 'not_required' 'No explicit qualification conditions must stay off'
    Assert-Contains @($qualificationOff.Json.skipped_gates) 'qualification_review' 'Qualification default skip'
    Write-Output 'PASS qualification_default_off'

    $qualificationOn = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'qualification-required.json') -PolicyPath $policyPath
    Assert-Tier -Result $qualificationOn -ExitCode 0 -Tier 'ESCALATED' -ReasonCode 'QUALIFICATION_REVIEW_REQUIRED' -QualificationReview 'required' -RequiredGates @('qualification_review', 'escalated_review') -SkippedGates @() -Context 'qualification required'
    Write-Output 'PASS qualification_explicitly_enabled'

    $unknown = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'unknown-risk.json') -PolicyPath $policyPath
    Assert-Tier -Result $unknown -ExitCode 1 -Tier 'BLOCKED' -ReasonCode 'RISK_UNKNOWN' -QualificationReview 'not_required' -RequiredGates @('risk_resolution', 'user_decision') -SkippedGates @() -Context 'unknown risk'
    Write-Output 'PASS unknown_risk_fail_closed'

    $conflict = Invoke-Tier -ResolverPath $resolverPath -InputPath (Join-Path $fixtureRoot 'conflicting-signals.json') -PolicyPath $policyPath
    Assert-Tier -Result $conflict -ExitCode 1 -Tier 'BLOCKED' -ReasonCode 'RISK_CONFLICT' -QualificationReview 'not_required' -RequiredGates @('risk_resolution', 'user_decision') -SkippedGates @() -Context 'conflicting signals'
    Write-Output 'PASS conflicting_signals_fail_closed'

    $again = Invoke-Tier -ResolverPath $resolverPath -InputPath $ordinaryCodePath -PolicyPath $policyPath
    Assert-Equal (($ordinaryCode.Json | ConvertTo-Json -Depth 20 -Compress)) (($again.Json | ConvertTo-Json -Depth 20 -Compress)) 'Same input must produce stable output'
    Assert-Equal $ordinaryCode.Json.policy_hash ((Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToUpperInvariant()) 'Policy hash must be reproducible'
    Write-Output 'PASS deterministic_output_and_policy_hash'

    Write-Output 'PROJECT_GOVERNANCE_TIER_TESTS=PASS'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    Write-Output 'PROJECT_GOVERNANCE_TIER_TESTS=FAIL'
    exit 1
}
