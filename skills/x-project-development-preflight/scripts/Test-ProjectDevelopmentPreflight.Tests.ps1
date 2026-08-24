[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$implementation = Join-Path $PSScriptRoot 'Test-ProjectDevelopmentPreflight.ps1'

function Decode-Unicode {
    param([Parameter(Mandatory = $true)][string]$Value)
    return [regex]::Unescape($Value)
}

if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    Write-Error 'RED: Test-ProjectDevelopmentPreflight.ps1 is missing.'
    exit 1
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][AllowNull()]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -notcontains $Expected) {
        throw "$Message Missing=[$Expected] Actual=[$($Actual -join ',')]"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][string]$Unexpected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -contains $Unexpected) {
        throw "$Message Unexpected=[$Unexpected] Actual=[$($Actual -join ',')]"
    }
}

function Write-Utf8Json {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [bool]$WithBom = $false
    )

    $json = $Value | ConvertTo-Json -Depth 12
    $encoding = New-Object System.Text.UTF8Encoding($WithBom)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Invoke-PreflightJson {
    param([hashtable]$Arguments)

    $json = & $implementation @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Preflight script exited with $LASTEXITCODE"
    }
    return ($json | ConvertFrom-Json)
}

function Invoke-ProfileCase {
    param([Parameter(Mandatory = $true)][string]$Root)

    return Invoke-PreflightJson -Arguments @{
        ProjectRoot = $Root
        RequireXDrive = $false
        ProjectedWip = 1
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
}

$projectContainerName = '15_' + (Decode-Unicode '\u9879\u76ee\u5f00\u53d1\u6cbb\u7406') + 'Skills'
$tempBase = [System.IO.Path]::GetFullPath((Join-Path (Join-Path 'X:\Projects\01_Active' $projectContainerName) '99_Temp\preflight-reader-utf8-ps51-ps7\tests'))
New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
$fixtureRoot = Join-Path $tempBase ((Decode-Unicode '\u5fd7\u613f\u586b\u62a5AI\u667a\u80fd\u4f53') + '-' + [guid]::NewGuid().ToString('N'))
$fixtureFull = [System.IO.Path]::GetFullPath($fixtureRoot)
if (-not $fixtureFull.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe fixture path: $fixtureFull"
}
$nonXBase = [System.IO.Path]::GetFullPath('E:\iwen-codex\codex-study\.codex-tmp\preflight')
$nonXRoot = Join-Path $nonXBase ('codex-preflight-nonx-' + [guid]::NewGuid().ToString('N'))
$nonXFull = [System.IO.Path]::GetFullPath($nonXRoot)
New-Item -ItemType Directory -Path $nonXFull -Force | Out-Null
if (-not $nonXFull.StartsWith($nonXBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe non-X fixture path: $nonXFull"
}

try {
    $missing = Invoke-PreflightJson -Arguments @{
        ProjectRoot = (Join-Path $fixtureRoot 'missing')
        RequireXDrive = $false
        ProjectedWip = 1
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $missing.verdict 'BLOCKED' 'Missing root must block.'
    Assert-Contains @($missing.reason_codes) 'PROJECT_ROOT_MISSING' 'Missing root reason code.'

    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $nonX = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $nonXRoot
        ProjectedWip = 1
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $nonX.verdict 'BLOCKED' 'Default mode must reject non-X roots.'
    Assert-Contains @($nonX.reason_codes) 'NOT_X_DRIVE' 'Non-X reason code.'

    & git -C $fixtureRoot init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    & git -C $fixtureRoot config user.name 'Codex Fixture' | Out-Null
    & git -C $fixtureRoot config user.email 'fixture@example.invalid' | Out-Null

    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot '.codex\x-drive') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'AGENTS.md'), '# Fixture instructions', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'Enter-XProject.ps1'), '# fixture entry', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'Test-XProjectCompliance.ps1'), '# fixture compliance', (New-Object System.Text.UTF8Encoding($false)))
    $profilePath = Join-Path $fixtureRoot '.codex\x-drive\project-profile.json'
    Write-Utf8Json -Path $profilePath -Value ([ordered]@{
        projectRoot = $fixtureRoot
        mainRepositoryPath = $fixtureRoot
        displayName = Decode-Unicode '\u5fd7\u613f\u586b\u62a5 AI \u667a\u80fd\u4f53'
        testOnly = $true
    })

    & git -C $fixtureRoot add -- 'AGENTS.md' 'Enter-XProject.ps1' 'Test-XProjectCompliance.ps1' '.codex/x-drive/project-profile.json' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
    & git -C $fixtureRoot commit -m 'test: create anonymous preflight fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }

    $unobserved = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $fixtureRoot
        RequireXDrive = $false
        ProjectedWip = 1
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
    }
    Assert-Equal $unobserved.verdict 'READ_ONLY_ONLY' 'Unobserved checks must not become READY.'
    Assert-Contains @($unobserved.reason_codes) 'ENTRY_EXIT_CODE_UNKNOWN' 'Entry evidence reason code.'
    Assert-Contains @($unobserved.reason_codes) 'COMPLIANCE_EXIT_CODE_UNKNOWN' 'Compliance evidence reason code.'

    $ready = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $fixtureRoot
        RequireXDrive = $false
        ProjectedWip = 2
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $ready.verdict 'READY' 'Complete clean fixture must be READY.'
    Assert-Equal $ready.evidence_transferable $false 'Historical evidence must remain non-transferable.'
    Assert-Equal $ready.git.dirty $false 'Committed fixture must be clean.'
    Assert-Equal $ready.project_contract.profile_project_root $fixtureRoot 'camelCase projectRoot must be read.'
    Assert-Equal $ready.project_contract.profile_main_repository_path $fixtureRoot 'camelCase mainRepositoryPath must be read.'

    Write-Utf8Json -Path $profilePath -WithBom $true -Value ([ordered]@{
        projectRoot = $fixtureRoot
        mainRepositoryPath = $fixtureRoot
        displayName = (Decode-Unicode '\u4e2d\u6587') + ' BOM'
    })
    $bom = Invoke-ProfileCase -Root $fixtureRoot
    Assert-Equal $bom.project_contract.profile_valid $true 'UTF-8 BOM profile must be valid.'
    Assert-NotContains @($bom.reason_codes) 'PROJECT_PROFILE_INVALID_UTF8' 'BOM is not invalid UTF-8.'
    Assert-NotContains @($bom.reason_codes) 'PROJECT_PROFILE_INVALID_JSON' 'BOM profile is valid JSON.'

    Write-Utf8Json -Path $profilePath -Value ([ordered]@{
        project_root = $fixtureRoot
        main_repository_path = $fixtureRoot
    })
    $snake = Invoke-ProfileCase -Root $fixtureRoot
    Assert-Equal $snake.project_contract.profile_project_root $fixtureRoot 'snake_case project_root must be read.'
    Assert-Equal $snake.project_contract.profile_main_repository_path $fixtureRoot 'snake_case main_repository_path must be read.'

    Write-Utf8Json -Path $profilePath -Value ([ordered]@{ projectRoot = $fixtureRoot })
    $optionalMissing = Invoke-ProfileCase -Root $fixtureRoot
    Assert-Equal $optionalMissing.project_contract.profile_valid $true 'Missing optional field must keep profile valid.'
    Assert-Equal $optionalMissing.project_contract.profile_main_repository_path $null 'Missing optional main repository path must remain null.'
    Assert-NotContains @($optionalMissing.reason_codes) 'PROJECT_PROFILE_REQUIRED_FIELD_MISSING' 'Optional field absence must not become required-field failure.'

    [System.IO.File]::WriteAllBytes($profilePath, [byte[]](0x7B,0x22,0x70,0x72,0x6F,0x6A,0x65,0x63,0x74,0x52,0x6F,0x6F,0x74,0x22,0x3A,0x22,0xC3,0x28,0x22,0x7D))
    $invalidUtf8 = Invoke-ProfileCase -Root $fixtureRoot
    Assert-Contains @($invalidUtf8.reason_codes) 'PROJECT_PROFILE_INVALID_UTF8' 'Damaged bytes need an encoding-specific reason.'
    Assert-NotContains @($invalidUtf8.reason_codes) 'PROJECT_PROFILE_INVALID_JSON' 'Damaged bytes must not be mislabeled invalid JSON.'

    [System.IO.File]::WriteAllText($profilePath, '{"projectRoot":', (New-Object System.Text.UTF8Encoding($false)))
    $invalidJson = Invoke-ProfileCase -Root $fixtureRoot
    Assert-Contains @($invalidJson.reason_codes) 'PROJECT_PROFILE_INVALID_JSON' 'Valid UTF-8 with invalid JSON needs JSON reason.'
    Assert-NotContains @($invalidJson.reason_codes) 'PROJECT_PROFILE_INVALID_UTF8' 'Valid UTF-8 invalid JSON must not be mislabeled encoding.'

    Write-Utf8Json -Path $profilePath -Value ([ordered]@{ mainRepositoryPath = $fixtureRoot })
    $requiredMissing = Invoke-ProfileCase -Root $fixtureRoot
    Assert-Contains @($requiredMissing.reason_codes) 'PROJECT_PROFILE_REQUIRED_FIELD_MISSING' 'Missing required project root needs field-specific reason.'
    Assert-NotContains @($requiredMissing.reason_codes) 'PROJECT_PROFILE_INVALID_JSON' 'Missing fields are not invalid JSON.'

    Write-Utf8Json -Path $profilePath -Value ([ordered]@{
        projectRoot = $fixtureRoot
        mainRepositoryPath = $fixtureRoot
    })
    & git -C $fixtureRoot add -- '.codex/x-drive/project-profile.json' | Out-Null
    & git -C $fixtureRoot commit -m 'test: restore valid profile fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git restore fixture commit failed' }

    $wipAllowed = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $fixtureRoot
        RequireXDrive = $false
        ProjectedWip = 9
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $wipAllowed.verdict 'READY' 'Global project count must be informational only.'
    Assert-Equal $wipAllowed.isolation.project_count_limit_enforced $false 'Global project count enforcement must stay disabled.'

    $wip99Allowed = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $fixtureRoot
        RequireXDrive = $false
        ProjectedWip = 99
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $wip99Allowed.verdict 'READY' 'Any projected project count must remain informational.'

    $writerBlocked = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $fixtureRoot
        RequireXDrive = $false
        ProjectedWip = 9
        SameWorktreeWriterCount = 1
        SharedResourceConflictCount = 0
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $writerBlocked.verdict 'BLOCKED' 'A second same-worktree writer must block.'
    Assert-Contains @($writerBlocked.reason_codes) 'SAME_WORKTREE_WRITER_PRESENT' 'Same-worktree writer reason code.'

    $resourceBlocked = Invoke-PreflightJson -Arguments @{
        ProjectRoot = $fixtureRoot
        RequireXDrive = $false
        ProjectedWip = 9
        SameWorktreeWriterCount = 0
        SharedResourceConflictCount = 1
        EntryExitCode = 0
        ComplianceExitCode = 0
    }
    Assert-Equal $resourceBlocked.verdict 'BLOCKED' 'Shared resource conflicts must serialize.'
    Assert-Contains @($resourceBlocked.reason_codes) 'SHARED_RESOURCE_CONFLICT' 'Shared resource conflict reason code.'

    Write-Output 'TEST_PROJECT_DEVELOPMENT_PREFLIGHT=PASS'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $fixtureFull) {
        $resolved = [System.IO.Path]::GetFullPath($fixtureFull)
        if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if (Test-Path -LiteralPath $nonXFull) {
        $resolvedNonX = [System.IO.Path]::GetFullPath($nonXFull)
        if (-not $resolvedNonX.StartsWith($nonXBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe non-X cleanup target: $resolvedNonX"
        }
        Remove-Item -LiteralPath $resolvedNonX -Recurse -Force
    }
}
