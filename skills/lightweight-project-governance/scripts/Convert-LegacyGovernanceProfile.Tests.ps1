[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-Contains {
    param([object[]]$Values, [string]$Expected, [string]$Message)
    Assert-True (@($Values | ForEach-Object { [string]$_ }) -contains $Expected) "$Message (missing '$Expected')"
}

function Write-Json {
    param([string]$Path, $Object)
    $Object | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-Converter {
    param([string]$InputPath, [string]$OutputPath)
    $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -InputPath $InputPath -OutputPath $OutputPath 2>&1)
    $exitCode = $LASTEXITCODE
    $json = $null
    if ($raw.Count -gt 0) {
        try { $json = (($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json } catch { }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json; Raw = $raw }
}

function New-ConverterInput {
    param([string]$Name, [hashtable]$Values)
    $path = Join-Path $fixtureDir ($Name + '.json')
    Write-Json -Path $path -Object $Values
    return $path
}

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$scriptPath = Join-Path $PSScriptRoot 'Convert-LegacyGovernanceProfile.ps1'
$adapterDir = Join-Path $root 'adapters\lightweight-governance'
$adapterIntegrationAvailable = Test-Path -LiteralPath $adapterDir -PathType Container
$fixtureBase = Join-Path ([System.IO.Path]::GetTempPath()) 'codex-lightweight-governance-tests'
$fixtureDir = Join-Path $fixtureBase ('run-' + [guid]::NewGuid().ToString('N'))
$fixtureFull = [System.IO.Path]::GetFullPath($fixtureDir)
$fixtureBaseFull = [System.IO.Path]::GetFullPath($fixtureBase).TrimEnd('\')
if (-not $fixtureFull.StartsWith($fixtureBaseFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe fixture path: $fixtureFull"
}

$testExitCode = 0

try {
    Assert-True (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'converter must exist'
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

    if ($adapterIntegrationAvailable) {
        $adapterNames = @('high-impact-data', 'content-media', 'infrastructure-tooling')
        foreach ($adapterName in $adapterNames) {
        $adapterPath = Join-Path $adapterDir ($adapterName + '.json')
        Assert-True (Test-Path -LiteralPath $adapterPath -PathType Leaf) "$adapterName adapter must exist"
        $adapterRaw = Get-Content -LiteralPath $adapterPath -Raw -Encoding UTF8
        $adapter = $adapterRaw | ConvertFrom-Json
        Assert-Equal $adapter.schema_version 1 "$adapterName schema version"
        Assert-Equal $adapter.default_final_review.required $true "$adapterName default final review"
        Assert-True (@($adapter.default_final_review.decision_values).Count -ge 3) "$adapterName review decisions"
        Assert-True ($null -ne $adapter.triggers.data) "$adapterName data triggers"
        Assert-True ($null -ne $adapter.triggers.media) "$adapterName media triggers"
        Assert-True ($null -ne $adapter.triggers.permissions) "$adapterName permission triggers"
        Assert-True (@($adapter.tests.required_cases).Count -gt 0) "$adapterName test cases"
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$adapter.rollback.strategy)) "$adapterName rollback strategy"
        Assert-True (@($adapter.rollback.steps).Count -gt 0) "$adapterName rollback steps"
        Assert-True ($adapterRaw -notmatch '(?i)(project_root|project_path|business_path|candidate_id|candidate_hash|commit_sha|branch|head|X:\\|[A-Za-z]:\\\\)') "$adapterName has no business path or candidate identity"
            Write-Output "PASS adapter_contract_$adapterName"
        }
        Write-Output 'ADAPTER_INTEGRATION=PASS'
    }
    else {
        Write-Output 'ADAPTER_INTEGRATION_NOT_APPLICABLE'
    }

    $migrationValues = [ordered]@{
        schema_version = 1
        project_id = 'fixture-legacy-project'
        adapter_type = 'high-impact-data'
        hard_gates = @('FORMAL_DATA_REVIEW', 'CUSTOM_BUSINESS_GATE')
        historical_evidence = @('legacy-evidence-ref-001', 'legacy-evidence-ref-002')
        legacy_mode = $true
        mystery_trigger = 'manual-mapping-needed'
    }
    $migrationInput = New-ConverterInput -Name 'legacy-high-impact-data' -Values $migrationValues
    $migrationOutput = Join-Path $fixtureDir 'migration-output.json'
    $beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $migrationInput).Hash
    $migration = Invoke-Converter -InputPath $migrationInput -OutputPath $migrationOutput
    Assert-Equal $migration.ExitCode 0 'migration suggestion exits 0'
    Assert-True (Test-Path -LiteralPath $migrationOutput -PathType Leaf) 'migration output exists'
    $output = Get-Content -LiteralPath $migrationOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $output.mode 'migration_suggestion' 'migration mode'
    Assert-Equal $output.candidate_profile.adapter_type 'high-impact-data' 'candidate adapter type'
    Assert-Equal @($output.candidate_profile.hard_gates).Count 2 'candidate hard gates count'
    Assert-Contains @($output.candidate_profile.hard_gates) 'FORMAL_DATA_REVIEW' 'hard gate preserved'
    Assert-Contains @($output.candidate_profile.historical_evidence) 'legacy-evidence-ref-001' 'historical evidence preserved'
    Assert-Contains @($output.diff.preserved_hard_gates) 'CUSTOM_BUSINESS_GATE' 'diff preserves custom hard gate'
    Assert-Contains @($output.diff.preserved_historical_evidence) 'legacy-evidence-ref-002' 'diff preserves historical evidence'
    Assert-Contains @($output.diff.manual_mapping_required) 'mystery_trigger' 'unknown field requires manual mapping'
    Assert-Equal $output.diff.removed_count 0 'migration removes nothing'
    Assert-True ($output.PSObject.Properties.Name -notcontains 'source_path') 'output does not expose source path'
    Assert-True ($output.PSObject.Properties.Name -notcontains 'candidate_id') 'output does not emit candidate identity'
    Assert-True (($output | ConvertTo-Json -Depth 30) -notmatch '(?i)(project_root|branch|head|commit_sha)') 'output has no checkout identity'
    $afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $migrationInput).Hash
    Assert-Equal $afterHash $beforeHash 'converter does not modify source input'
    Write-Output 'PASS migration_suggestion_preserves_gates_and_history'

    $legacyValues = [ordered]@{
        project_id = 'fixture-legacy-fallback'
        hard_gates = @('LEGACY_HARD_GATE')
        historical_evidence = @('legacy-fallback-evidence')
        old_custom_policy = 'manual-review'
    }
    $legacyInput = New-ConverterInput -Name 'legacy-fallback' -Values $legacyValues
    $legacyOutput = Join-Path $fixtureDir 'legacy-fallback-output.json'
    $legacy = Invoke-Converter -InputPath $legacyInput -OutputPath $legacyOutput
    Assert-Equal $legacy.ExitCode 0 'legacy fallback exits 0'
    $legacyResult = Get-Content -LiteralPath $legacyOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $legacyResult.mode 'legacy_fallback' 'legacy fallback mode'
    Assert-Equal $legacyResult.candidate_profile.adapter_type 'legacy' 'legacy adapter fallback'
    Assert-Contains @($legacyResult.candidate_profile.hard_gates) 'LEGACY_HARD_GATE' 'legacy hard gate preserved'
    Assert-Contains @($legacyResult.diff.preserved_historical_evidence) 'legacy-fallback-evidence' 'legacy history preserved'
    Assert-Contains @($legacyResult.diff.manual_mapping_required) 'old_custom_policy' 'legacy unknown field mapped manually'
    Assert-Equal $legacyResult.diff.removed_count 0 'legacy fallback removes nothing'
    Write-Output 'PASS legacy_fallback_preserves_history'

    Write-Output 'CONVERT_LEGACY_GOVERNANCE_PROFILE_TESTS=PASS'
}
catch {
    Write-Error $_.Exception.Message
    Write-Output 'CONVERT_LEGACY_GOVERNANCE_PROFILE_TESTS=FAIL'
    $testExitCode = 1
}
finally {
    if (Test-Path -LiteralPath $fixtureFull) {
        $resolved = [System.IO.Path]::GetFullPath($fixtureFull)
        if (-not $resolved.StartsWith($fixtureBaseFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

exit $testExitCode
