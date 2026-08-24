[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')" }
}

function Assert-Contains {
    param([object[]]$Values, [string]$Expected, [string]$Message)
    Assert-True (@($Values | ForEach-Object { [string]$_ }) -contains $Expected) "$Message (missing '$Expected')"
}

function Read-Json {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON: $Path"
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Json {
    param([string]$Path, $Object)
    $Object | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-CanonicalHash {
    param($Object, [string]$ExcludedProperty)
    $ordered = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -ne $ExcludedProperty) { $ordered[$property.Name] = $property.Value }
    }
    $json = $ordered | ConvertTo-Json -Depth 40 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-', '')).ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-Package {
    param([string]$InputPath, [string]$OutputPath, [string]$Decision = '', [string]$P14AdapterPath = '')
    if (-not [string]::IsNullOrWhiteSpace($Decision) -and -not [string]::IsNullOrWhiteSpace($P14AdapterPath)) {
        $raw = @(& $scriptPath -InputPath $InputPath -OutputPath $OutputPath -Decision $Decision -P14AdapterPath $P14AdapterPath 2>&1)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Decision)) {
        $raw = @(& $scriptPath -InputPath $InputPath -OutputPath $OutputPath -Decision $Decision 2>&1)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($P14AdapterPath)) {
        $raw = @(& $scriptPath -InputPath $InputPath -OutputPath $OutputPath -P14AdapterPath $P14AdapterPath 2>&1)
    }
    else {
        $raw = @(& $scriptPath -InputPath $InputPath -OutputPath $OutputPath 2>&1)
    }
    $exitCode = $LASTEXITCODE
    $json = $null
    if ($raw.Count -gt 0) {
        try { $json = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json; Raw = $raw }
}

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $PSScriptRoot 'New-FinalUserReviewPackage.ps1'
$fixtureBase = Join-Path $root 'outputs\skill-packaging\lightweight-governance-v1_2\T05\test-fixtures'
$fixtureDir = Join-Path $fixtureBase ('run-' + [guid]::NewGuid().ToString('N'))

try {
    Assert-True (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'final review package resolver must exist'
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

    $candidatePath = Join-Path $fixtureDir 'candidate.json'
    $candidate = [ordered]@{
        schema_version = 1
        candidate_id = 'candidate-t05-fixture'
        created_at_utc = '2026-08-21T00:00:00Z'
        state = 'CANDIDATE_AUTOMATED'
        project = [ordered]@{ project_id = 'fixture-content-media'; root = $root }
        identity = [ordered]@{ worktree = $root; branch = 'fixture-t05'; head = ('A' * 40); dirty = $true }
        planning = [ordered]@{ design_path = 'docs/design.md'; plan_path = 'docs/plan.md'; design_hash = ('1' * 64); plan_hash = ('2' * 64) }
        changed_paths = @('skills/lightweight-project-governance/scripts/example.ps1', 'tests/example.Tests.ps1')
        tests = @([ordered]@{ command = 'powershell.exe -File tests\example.Tests.ps1'; exit_code = 0 }, [ordered]@{ command = 'powershell.exe -File tests\smoke.Tests.ps1'; exit_code = 0 })
        artifacts = @()
        risk_tier = 'CANDIDATE'
        rollback = 'Restore the prior candidate manifest and rerun affected checks.'
    }
    $candidate.candidate_sha256 = Get-CanonicalHash -Object ([pscustomobject]$candidate) -ExcludedProperty 'candidate_sha256'
    Write-Json -Path $candidatePath -Object $candidate

    $impactPath = Join-Path $fixtureDir 'impact.json'
    $impact = [ordered]@{
        schema_version = 1
        candidate_manifest_path = $candidatePath
        candidate_sha256 = $candidate.candidate_sha256
        changed_paths = @($candidate.changed_paths)
        affected_paths = @('skills/lightweight-project-governance/scripts/example.ps1')
        affected_tests = @('tests/example.Tests.ps1')
        invalidated_evidence = @('candidate-evidence')
        retained_evidence = @('unrelated-evidence')
        expanded = $false
        reason_codes = @('MAPPED_CHANGE')
    }
    $impact.impact_sha256 = Get-CanonicalHash -Object ([pscustomobject]$impact) -ExcludedProperty 'impact_sha256'
    Write-Json -Path $impactPath -Object $impact

    $inputPath = Join-Path $fixtureDir 'review-input.json'
    $p14MissingPath = Join-Path $fixtureDir 'p14-adapter-missing.json'
    $reviewInput = [ordered]@{
        schema_version = 1
        review_mode = 'single_user'
        candidate_manifest_path = $candidatePath
        impact_manifest_path = $impactPath
        known_failures = @('P14 adapter is not available in this fixture.')
        risk_notes = @('Candidate tier requires a user decision before release.')
        pending_decisions = @('Select exactly one fixed decision option.')
        rollback = 'Restore the prior candidate and rerun the affected review scope.'
        p14_adapter_path = $p14MissingPath
    }
    Write-Json -Path $inputPath -Object $reviewInput

    $outputPath = Join-Path $fixtureDir 'review-package.json'
    $valid = Invoke-Package -InputPath $inputPath -OutputPath $outputPath
    Assert-Equal $valid.ExitCode 0 'valid review package must exit 0'
    Assert-True ($null -ne $valid.Json.package) 'valid invocation must return package'
    $package = Read-Json -Path $outputPath
    Assert-Equal $package.review_mode 'single_user' 'single user review mode'
    Assert-Equal $package.candidate.candidate_sha256 $candidate.candidate_sha256 'candidate hash binding'
    Assert-Equal $package.impact.impact_sha256 $impact.impact_sha256 'impact hash binding'
    Assert-Contains @($package.changed_paths) 'skills/lightweight-project-governance/scripts/example.ps1' 'changed path summary'
    Assert-Contains @($package.tests) 'tests/example.Tests.ps1' 'test summary'
    Assert-Contains @($package.known_failures) 'P14 adapter is not available in this fixture.' 'known failure summary'
    Assert-Equal $package.risk_tier 'CANDIDATE' 'risk tier summary'
    Assert-Equal $package.rollback $reviewInput.rollback 'rollback summary'
    Assert-Equal $package.user_decision '' 'user decision must be blank by default'
    Assert-Equal $package.user_conclusion '' 'user conclusion must be blank'
    Assert-Contains @($package.decision_options) '通过' 'pass decision option'
    Assert-Contains @($package.decision_options) '需修改' 'change decision option'
    Assert-Contains @($package.decision_options) '不通过' 'reject decision option'
    Assert-Equal $package.p14.status 'SIMPLIFIED_NO_P14' 'P14 unavailable simplification'
    Assert-Equal $package.review_package_sha256 (Get-CanonicalHash -Object $package -ExcludedProperty 'review_package_sha256') 'package hash reproducibility'
    Write-Output 'PASS single_review_hash_and_blank_user_fields'

    $again = Invoke-Package -InputPath $inputPath -OutputPath $outputPath
    Assert-Equal $again.ExitCode 1 'review package must be create-only'
    Assert-Contains @($again.Json.reason_codes) 'OUTPUT_EXISTS' 'review package create-only reason'
    Write-Output 'PASS review_package_create_only'

    $revisionPath = Join-Path $fixtureDir 'review-package-revision.json'
    $revision = Invoke-Package -InputPath $inputPath -OutputPath $revisionPath -Decision '需修改'
    Assert-Equal $revision.ExitCode 0 '需修改 decision must exit 0'
    $revisionPackage = Read-Json -Path $revisionPath
    Assert-Equal $revisionPackage.user_decision '需修改' 'revision decision'
    Assert-Contains @($revisionPackage.revision_scope.affected_paths) 'skills/lightweight-project-governance/scripts/example.ps1' 'revision affected scope'
    Assert-Contains @($revisionPackage.revision_scope.affected_tests) 'tests/example.Tests.ps1' 'revision affected tests'
    Assert-Equal $revisionPackage.user_conclusion '' 'revision user conclusion remains blank'
    Write-Output 'PASS revision_returns_only_affected_scope'

    foreach ($decision in @('通过', '不通过')) {
        $decisionPath = Join-Path $fixtureDir ('review-package-' + $decision + '.json')
        $decisionResult = Invoke-Package -InputPath $inputPath -OutputPath $decisionPath -Decision $decision
        Assert-Equal $decisionResult.ExitCode 0 "$decision decision must exit 0"
        $decisionPackage = Read-Json -Path $decisionPath
        Assert-Equal $decisionPackage.user_decision $decision "$decision decision binding"
        Assert-Equal @($decisionPackage.revision_scope.affected_paths).Count 0 "$decision must not return revision scope"
        Assert-Equal $decisionPackage.user_conclusion '' "$decision user conclusion remains blank"
    }
    Write-Output 'PASS fixed_decision_options'

    $invalidPath = Join-Path $fixtureDir 'review-package-invalid.json'
    $invalid = Invoke-Package -InputPath $inputPath -OutputPath $invalidPath -Decision '自动通过'
    Assert-Equal $invalid.ExitCode 1 'invalid decision must exit 1'
    Assert-Contains @($invalid.Json.reason_codes) 'INVALID_DECISION' 'invalid decision reason'
    Write-Output 'PASS invalid_decision_fail_closed'

    $adapterPath = Join-Path $fixtureDir 'p14-adapter.json'
    Write-Json -Path $adapterPath -Object ([ordered]@{ schema_version = 1; adapter = 'P14-ReviewPackage' })
    $adapterOut = Join-Path $fixtureDir 'review-package-p14.json'
    $adapterResult = Invoke-Package -InputPath $inputPath -OutputPath $adapterOut -P14AdapterPath $adapterPath
    Assert-Equal $adapterResult.ExitCode 0 'available P14 adapter must remain optional'
    Assert-Equal (Read-Json $adapterOut).p14.status 'P14_ADAPTER_AVAILABLE' 'P14 adapter status'
    Write-Output 'PASS optional_p14_adapter'

    $safeCandidatePath = Join-Path $fixtureDir 'safe-local-candidate.json'
    $safeCandidate = [ordered]@{}
    foreach ($property in $candidate.GetEnumerator()) { $safeCandidate[$property.Key] = $property.Value }
    $safeCandidate.state = 'LOCAL_CANDIDATE_READY'
    $safeCandidate.identity = [ordered]@{ worktree = $root; branch = 'fixture-t05'; head = ('A' * 40); source_head = ('A' * 40); dirty = $true; dirty_fingerprint = ('D' * 64) }
    $safeCandidate.governance = [ordered]@{ mode = 'LOCAL_AUTONOMOUS'; terminal_state = 'LOCAL_CANDIDATE_READY'; required_review = $false; delivery_target = 'ENGINEERING_ONLY'; release_intent = 'NONE'; review_policy = 'NONE'; policy_hash = ('P' * 64); profile_schema_hash = ('S' * 64); layers = @([ordered]@{ name = 'formal_release'; status = 'NOT_APPLICABLE'; applicability_reason = 'releaseIntent=NONE' }) }
    $safeCandidate.candidate_sha256 = Get-CanonicalHash -Object ([pscustomobject]$safeCandidate) -ExcludedProperty 'candidate_sha256'
    Write-Json -Path $safeCandidatePath -Object $safeCandidate
    $safeImpactPath = Join-Path $fixtureDir 'safe-local-impact.json'
    $safeImpact = [ordered]@{ schema_version = 1; candidate_manifest_path = $safeCandidatePath; candidate_sha256 = $safeCandidate.candidate_sha256; changed_paths = @($candidate.changed_paths); affected_paths = @(); affected_tests = @(); invalidated_evidence = @(); retained_evidence = @('engineering'); expanded = $false; reason_codes = @() }
    $safeImpact.impact_sha256 = Get-CanonicalHash -Object ([pscustomobject]$safeImpact) -ExcludedProperty 'impact_sha256'
    Write-Json -Path $safeImpactPath -Object $safeImpact
    $safeInputPath = Join-Path $fixtureDir 'safe-local-review-input.json'
    $safeInput = [ordered]@{ schema_version = 1; review_mode = 'single_user'; review_requested = $false; policy_hash = ('P' * 64); candidate_manifest_path = $safeCandidatePath; impact_manifest_path = $safeImpactPath; rollback = 'Restore the local candidate.' }
    Write-Json -Path $safeInputPath -Object $safeInput
    $safeOutput = Join-Path $fixtureDir 'safe-local-review-package.json'
    $safeResult = Invoke-Package -InputPath $safeInputPath -OutputPath $safeOutput
    Assert-Equal $safeResult.ExitCode 1 'safe local candidate without review request must not create a review package'
    Assert-Contains @($safeResult.Json.reason_codes) 'REVIEW_NOT_REQUIRED' 'safe local review skip reason'
    Write-Output 'PASS safe_local_review_not_required'

    $safeInput.review_requested = $true
    Write-Json -Path $safeInputPath -Object $safeInput
    $optionalOutput = Join-Path $fixtureDir 'optional-review-package.json'
    $optionalResult = Invoke-Package -InputPath $safeInputPath -OutputPath $optionalOutput
    Assert-Equal $optionalResult.ExitCode 0 'optional review must be creatable when explicitly requested'
    Assert-Equal (Read-Json $optionalOutput).governance.required_review $false 'optional review package must retain non-required state'
    Write-Output 'PASS optional_review_requested'

    Write-Output 'FINAL_USER_REVIEW_PACKAGE_TESTS=PASS'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    Write-Output 'FINAL_USER_REVIEW_PACKAGE_TESTS=FAIL'
    exit 1
}
