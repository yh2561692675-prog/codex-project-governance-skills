[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$implementation = Join-Path $PSScriptRoot 'Test-LongRunExecutionProfile.ps1'
if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    Write-Error 'RED: Test-LongRunExecutionProfile.ps1 is missing.'
    exit 1
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected=[$Expected] Actual=[$Actual]" }
}

function Assert-Contains {
    param([object[]]$Actual, [string]$Expected, [string]$Message)
    if ($Actual -notcontains $Expected) { throw "$Message Missing=[$Expected] Actual=[$($Actual -join ',')]" }
}

function Invoke-Validator {
    param([string]$Path)
    $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $implementation -ProfilePath $Path 2>&1
    $code = $LASTEXITCODE
    $lines = @($raw | ForEach-Object { [string]$_ })
    $start = -1
    $end = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($start -lt 0 -and $lines[$i].TrimStart().StartsWith('{')) { $start = $i }
        if ($lines[$i].TrimEnd().EndsWith('}')) { $end = $i }
    }
    if ($start -ge 0 -and $end -ge $start) { $parsed = (($lines[$start..$end] -join [Environment]::NewLine) | ConvertFrom-Json) } else { $parsed = $null }
    return [pscustomobject]@{ Code = $code; Json = $parsed; Raw = @($raw) }
}

function New-ValidProfile {
    param([string]$ProjectRoot, [string]$Path)
    $longRun = Join-Path $ProjectRoot '.codex\long-run'
    New-Item -ItemType Directory -Path $longRun -Force | Out-Null
    $profile = [ordered]@{
        schemaVersion = '1.0'
        projectId = 'fixture-project'
        projectRoot = $ProjectRoot
        designPath = 'docs\future-development\design.md'
        planPath = 'docs\future-development\plan.md'
        allowedWritePaths = @('src', 'tests')
        protectedPaths = @('.git', '.codex\x-drive\project-profile.json')
        runtimeRoot = (Join-Path $ProjectRoot 'runtime')
        evidenceRoot = (Join-Path $ProjectRoot 'evidence')
        sharedResources = @('fixture-port')
        defaultVerificationCommands = @('pwsh -File tests.ps1')
        humanGates = @('formal-release')
        modelPolicy = [ordered]@{
            design = [ordered]@{ model = 'gpt-5.6-sol'; reasoning = 'high' }
            implementation = [ordered]@{ model = 'gpt-5.6-luna'; reasoning = 'xhigh' }
        }
        maxEffectiveRetries = 2
        unfinishedCleanupRounds = 2
        unknownFixtureField = 'preserve-me'
    }
    $profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

$base = [System.IO.Path]::GetFullPath('X:\Projects\01_Active\15_项目开发治理Skills\99_Temp\long-run-v1_1\T04')
$fixture = Join-Path $base ('profile-' + [guid]::NewGuid().ToString('N'))
$profilePath = Join-Path $fixture '.codex\long-run\execution-profile.json'
$nonX = $null
New-ValidProfile -ProjectRoot $fixture -Path $profilePath
try {
    $valid = Invoke-Validator -Path $profilePath
    Assert-Equal $valid.Code 0 'Valid profile must exit zero.'
    Assert-Equal $valid.Json.valid $true 'Valid profile must be accepted.'
    Assert-Equal $valid.Json.normalized_profile.projectId 'fixture-project' 'Project ID must normalize.'
    Assert-Equal $valid.Json.normalized_profile.unknownFixtureField 'preserve-me' 'Unknown fields must be retained.'

    $modelBad = Join-Path $fixture 'model-bad.json'
    $model = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    $model.modelPolicy.implementation.model = 'gpt-5.6-sol'
    $model | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $modelBad -Encoding utf8
    $badModelResult = Invoke-Validator -Path $modelBad
    Assert-Equal $badModelResult.Code 1 'Bad implementation model must fail.'
    Assert-Contains @($badModelResult.Json.reason_codes) 'MODEL_POLICY_BLOCKED' 'Bad model reason code.'

    $missing = Join-Path $fixture 'missing.json'
    $missingObject = [ordered]@{ schemaVersion = '1.0'; projectId = 'missing-fields' } | ConvertTo-Json
    Set-Content -LiteralPath $missing -Value $missingObject -Encoding utf8
    $missingResult = Invoke-Validator -Path $missing
    Assert-Equal $missingResult.Code 1 'Missing fields must fail.'
    Assert-Contains @($missingResult.Json.reason_codes) 'PROFILE_FIELD_MISSING' 'Missing field reason code.'

    $traversal = Join-Path $fixture 'traversal.json'
    $traversalObject = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    $traversalObject.allowedWritePaths = @('..\outside')
    $traversalObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $traversal -Encoding utf8
    $traversalResult = Invoke-Validator -Path $traversal
    Assert-Equal $traversalResult.Code 1 'Traversal paths must fail.'
    Assert-Contains @($traversalResult.Json.reason_codes) 'PATH_OUTSIDE_PROJECT_ROOT' 'Traversal reason code.'

    $invalid = Join-Path $fixture 'invalid.json'
    Set-Content -LiteralPath $invalid -Value '{ invalid json' -Encoding utf8
    $invalidResult = Invoke-Validator -Path $invalid
    Assert-Equal $invalidResult.Code 1 'Invalid JSON must fail.'
    Assert-Contains @($invalidResult.Json.reason_codes) 'INVALID_JSON' 'Invalid JSON reason code.'

    $nonX = Join-Path 'E:\iwen-codex\codex-study\.codex-tmp\preflight' ('profile-nonx-' + [guid]::NewGuid().ToString('N'))
    $nonXProfile = Join-Path $nonX '.codex\long-run\execution-profile.json'
    New-ValidProfile -ProjectRoot $nonX -Path $nonXProfile
    $nonXResult = Invoke-Validator -Path $nonXProfile
    Assert-Equal $nonXResult.Code 1 'Non-X profile must fail.'
    Assert-Contains @($nonXResult.Json.reason_codes) 'NOT_X_DRIVE' 'Non-X reason code.'

    Write-Output 'TEST_LONG_RUN_EXECUTION_PROFILE=PASS'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
    if ($nonX -and (Test-Path -LiteralPath $nonX)) { Remove-Item -LiteralPath $nonX -Recurse -Force }
}
