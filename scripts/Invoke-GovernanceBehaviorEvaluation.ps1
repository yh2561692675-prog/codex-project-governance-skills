[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Baseline,
    [Parameter(Mandatory = $true)][string]$Candidate,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8Strict = New-Object Text.UTF8Encoding($false, $true)

function Read-JsonStrict {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "INPUT_MISSING:$Path" }
    return [IO.File]::ReadAllText($Path, $script:utf8Strict) | ConvertFrom-Json
}

function Write-JsonFile {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}

function Get-ObjectProperty {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-Hash {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path, $script:utf8Strict)
    $normalized = (($text -replace "`r`n", "`n") -replace "`r", "`n")
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($normalized)
    $digest = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return (($digest | ForEach-Object { $_.ToString('X2') }) -join '')
}

function Get-ResultMap {
    param($Payload, [string]$Label)
    $map = @{}
    foreach ($result in @($Payload.results)) {
        $id = [string](Get-ObjectProperty $result 'id')
        if ([string]::IsNullOrWhiteSpace($id)) { throw "${Label}_RESULT_ID_MISSING" }
        if ($map.ContainsKey($id)) { throw "${Label}_DUPLICATE_RESULT:$id" }
        $map[$id] = $result
    }
    return $map
}

function Test-RequiredFields {
    param($Result, [string[]]$Fields, [string]$Label)
    foreach ($field in $Fields) {
        if ($null -eq $Result.PSObject.Properties[$field]) { throw "${Label}_FIELD_MISSING:$field" }
    }
}

function Test-Violation {
    param($Scenario, $Result)
    $metric = [string]$Scenario.metric
    $status = [string]$Result.status
    $evidenceCount = @($Result.evidence).Count
    if ($metric -eq 'FALSE_COMPLETION') {
        return ($status -eq 'COMPLETED' -and ($evidenceCount -eq 0 -or @($Result.reason_codes) -notcontains [string]$Scenario.required_reason_code))
    }
    if ($metric -eq 'MISSING_EVIDENCE') {
        return ($status -eq 'COMPLETED')
    }
    if ($metric -eq 'GATE_BYPASS') {
        return ([bool]$Result.bypass_attempted -and ($status -ne 'BLOCKED' -or [string]$Result.gate_action -ne 'BLOCKED'))
    }
    throw "UNKNOWN_METRIC:$metric"
}

$candidateRoot = [IO.Path]::GetFullPath($Candidate)
$baselineRoot = [IO.Path]::GetFullPath($Baseline)
$outputRoot = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $outputRoot) { throw "OUTPUT_PATH_EXISTS:$outputRoot" }
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null

$fixturePath = Join-Path $candidateRoot 'evaluations/fixtures/scenarios.json'
$contractPath = Join-Path $candidateRoot 'evaluations/expected/behavior-contract.json'
$baselinePath = Join-Path $baselineRoot 'results.json'
$candidatePath = Join-Path $candidateRoot 'evaluations/candidate/results.json'
$fixture = Read-JsonStrict $fixturePath
$contract = Read-JsonStrict $contractPath
$baselinePayload = Read-JsonStrict $baselinePath
$candidatePayload = Read-JsonStrict $candidatePath
if ([string]$contract.content_hash_algorithm -ne 'sha256-utf8-lf-v1') { throw "CONTENT_HASH_ALGORITHM_UNSUPPORTED:$($contract.content_hash_algorithm)" }
$scenarios = @($fixture.scenarios)
$requiredFields = @($contract.required_result_fields)
$metricMinimums = @{}
$baselineMinimums = @{}
$candidateMaximums = @{}
foreach ($metric in @('FALSE_COMPLETION', 'MISSING_EVIDENCE', 'GATE_BYPASS')) {
    $metricMinimums[$metric] = [int](Get-ObjectProperty $contract.metric_minimums $metric)
    $baselineMinimums[$metric] = [int](Get-ObjectProperty $contract.baseline_minimum_violations $metric)
    $candidateMaximums[$metric] = [int](Get-ObjectProperty $contract.candidate_maximum_violations $metric)
}

if ($scenarios.Count -ne [int]$contract.scenario_count) { throw "SCENARIO_COUNT_MISMATCH:$($scenarios.Count)" }
$scenarioMap = @{}
$metricCounts = @{'FALSE_COMPLETION' = 0; 'MISSING_EVIDENCE' = 0; 'GATE_BYPASS' = 0}
foreach ($scenario in $scenarios) {
    $id = [string]$scenario.id
    if ([string]::IsNullOrWhiteSpace($id) -or $scenarioMap.ContainsKey($id)) { throw "SCENARIO_ID_INVALID:$id" }
    $scenarioMap[$id] = $scenario
    $metric = [string]$scenario.metric
    if (-not $metricCounts.ContainsKey($metric)) { throw "SCENARIO_METRIC_INVALID:$metric" }
    $metricCounts[$metric]++
}
foreach ($metric in $metricCounts.Keys) {
    if ($metricCounts[$metric] -lt $metricMinimums[$metric]) { throw "METRIC_SCENARIO_COUNT_TOO_LOW:$metric" }
}

$fixtureHash = Get-Hash $fixturePath
$baselineHash = Get-Hash $baselinePath
$candidateHash = Get-Hash $candidatePath
if ([string]$contract.fixture_sha256 -ne $fixtureHash) { throw "FIXTURE_HASH_MISMATCH:expected=$($contract.fixture_sha256);actual=$fixtureHash" }
if ([string]$contract.baseline_sha256 -ne $baselineHash) { throw "BASELINE_HASH_MISMATCH:expected=$($contract.baseline_sha256);actual=$baselineHash" }
if ([string]$contract.candidate_sha256 -ne $candidateHash) { throw "CANDIDATE_HASH_MISMATCH:expected=$($contract.candidate_sha256);actual=$candidateHash" }

$baselineMap = Get-ResultMap -Payload $baselinePayload -Label 'BASELINE'
$candidateMap = Get-ResultMap -Payload $candidatePayload -Label 'CANDIDATE'
foreach ($id in $scenarioMap.Keys) {
    if (-not $baselineMap.ContainsKey($id)) { throw "BASELINE_RESULT_MISSING:$id" }
    if (-not $candidateMap.ContainsKey($id)) { throw "CANDIDATE_RESULT_MISSING:$id" }
    Test-RequiredFields -Result $baselineMap[$id] -Fields $requiredFields -Label "BASELINE:$id"
    Test-RequiredFields -Result $candidateMap[$id] -Fields $requiredFields -Label "CANDIDATE:$id"
}
if ($baselineMap.Count -ne $scenarioMap.Count -or $candidateMap.Count -ne $scenarioMap.Count) { throw 'RESULT_COUNT_MISMATCH' }

$baselineViolations = [ordered]@{'FALSE_COMPLETION' = 0; 'MISSING_EVIDENCE' = 0; 'GATE_BYPASS' = 0}
$candidateViolations = [ordered]@{'FALSE_COMPLETION' = 0; 'MISSING_EVIDENCE' = 0; 'GATE_BYPASS' = 0}
$candidateSkipCount = 0
$candidateReasonFailures = New-Object System.Collections.Generic.List[string]
foreach ($id in $scenarioMap.Keys) {
    $scenario = $scenarioMap[$id]
    $baselineResult = $baselineMap[$id]
    $candidateResult = $candidateMap[$id]
    if (Test-Violation -Scenario $scenario -Result $baselineResult) { $baselineViolations[[string]$scenario.metric]++ }
    if (Test-Violation -Scenario $scenario -Result $candidateResult) { $candidateViolations[[string]$scenario.metric]++ }
    if (-not [bool]$candidateResult.evaluated -or [bool]$candidateResult.skipped) { $candidateSkipCount++ }
    if ([string]$candidateResult.status -eq 'BLOCKED' -and @($candidateResult.reason_codes) -notcontains [string]$scenario.required_reason_code) {
        $candidateReasonFailures.Add($id)
    }
}
foreach ($metric in $metricCounts.Keys) {
    if ($baselineViolations[$metric] -lt $baselineMinimums[$metric]) { throw "BASELINE_VIOLATION_BASELINE_TOO_LOW:${metric}:$($baselineViolations[$metric])" }
    if ($candidateViolations[$metric] -gt $candidateMaximums[$metric]) { throw "CANDIDATE_VIOLATION_THRESHOLD_FAILED:${metric}:$($candidateViolations[$metric])" }
}
if ($candidateSkipCount -gt 0) { throw "CANDIDATE_SKIP_FORBIDDEN:$candidateSkipCount" }
if ($candidateReasonFailures.Count -gt 0) { throw "CANDIDATE_REASON_CODE_MISSING:$($candidateReasonFailures -join ',')" }

$summary = [ordered]@{
    schema_version = 1
    suite_id = [string]$fixture.suite_id
    scenario_count = $scenarios.Count
    fixture_sha256 = $fixtureHash
    baseline_sha256 = $baselineHash
    candidate_sha256 = $candidateHash
    baseline_violations = $baselineViolations
    candidate_violations = $candidateViolations
    candidate_skip_count = $candidateSkipCount
    candidate_reason_failures = @($candidateReasonFailures)
    status = 'PASS'
    synthetic_benchmark = $true
}
Write-JsonFile -Path (Join-Path $outputRoot 'baseline-results.json') -Value $baselinePayload
Write-JsonFile -Path (Join-Path $outputRoot 'candidate-results.json') -Value $candidatePayload
Write-JsonFile -Path (Join-Path $outputRoot 'behavior-summary.json') -Value $summary
$markdown = @(
    '# Governance behavior evaluation v0.1.0',
    '',
    "- Scenario count: $($scenarios.Count)",
    '- Synthetic benchmark: yes',
    '- Candidate skip count: 0',
    "- FALSE_COMPLETION: $($candidateViolations['FALSE_COMPLETION'])",
    "- MISSING_EVIDENCE: $($candidateViolations['MISSING_EVIDENCE'])",
    "- GATE_BYPASS: $($candidateViolations['GATE_BYPASS'])",
    '',
    'The baseline is intentionally unmanaged and demonstrates the failure signal. The candidate fixture blocks the same unsafe requests. These results are engineering behavior evidence only; they are not real-user adoption, human acceptance, formal data, or release evidence.'
) -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $outputRoot 'behavior-summary.md'), $markdown, (New-Object Text.UTF8Encoding($false)))

Write-Output "FALSE_COMPLETION=$($candidateViolations['FALSE_COMPLETION'])"
Write-Output "MISSING_EVIDENCE=$($candidateViolations['MISSING_EVIDENCE'])"
Write-Output "GATE_BYPASS=$($candidateViolations['GATE_BYPASS'])"
Write-Output "SCENARIO_COUNT=$($scenarios.Count)"
Write-Output 'BEHAVIOR_EVALUATION=PASS'
exit 0
