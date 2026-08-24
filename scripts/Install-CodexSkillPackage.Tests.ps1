[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$implementation = Join-Path $PSScriptRoot 'Install-CodexSkillPackage.ps1'
$projectContainerName = '15_' + [regex]::Unescape('\u9879\u76ee\u5f00\u53d1\u6cbb\u7406') + 'Skills'
$tempBase = [System.IO.Path]::GetFullPath((Join-Path (Join-Path 'X:\Projects\01_Active' $projectContainerName) '99_Temp\preflight-reader-utf8-ps51-ps7\installer-tests'))
New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
$fixtureRoot = Join-Path $tempBase ([guid]::NewGuid().ToString('N'))
$fixtureFull = [System.IO.Path]::GetFullPath($fixtureRoot)
$hostExecutable = (Get-Process -Id $PID).Path
$nl = [Environment]::NewLine

function Assert-Equal {
    param([AllowNull()]$Actual, [AllowNull()]$Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected=[$Expected] Actual=[$Actual]" }
}
function Assert-True {
    param([bool]$Actual, [string]$Message)
    if (-not $Actual) { throw $Message }
}

function Write-Utf8Text {
    param([string]$Path, [string]$Value)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Manifest {
    param([string]$Root)
    @(
        Get-ChildItem -LiteralPath $Root -File -Recurse |
            ForEach-Object {
                [pscustomobject]@{
                    Relative = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\','/')
                    Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            } |
            Sort-Object Relative
    )
}

function Invoke-Installer {
    param([string]$Source, [string]$Installed, [string]$Evidence)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = @(& $hostExecutable -NoProfile -ExecutionPolicy Bypass -File $implementation -SourceSkillPath $Source -InstalledSkillPath $Installed -EvidencePath $Evidence 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    [pscustomobject]@{ Code = $code; Raw = @($raw | ForEach-Object { [string]$_ }) }
}

if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    Write-Error 'RED: Install-CodexSkillPackage.ps1 is missing.'
    exit 1
}
if (-not $fixtureFull.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe fixture path: $fixtureFull"
}

try {
    $source = Join-Path $fixtureRoot 'source\example-skill'
    $installed = Join-Path $fixtureRoot 'installed\example-skill'
    $evidence = Join-Path $fixtureRoot 'evidence\run-1'
    Write-Utf8Text -Path (Join-Path $source 'SKILL.md') -Value ('---' + $nl + 'name: example-skill' + $nl + 'description: fixture' + $nl + '---' + $nl)
    Write-Utf8Text -Path (Join-Path $source 'scripts\run.ps1') -Value ("Write-Output 'new'" + $nl)
    Write-Utf8Text -Path (Join-Path $source 'references\contract.md') -Value ('# Contract' + $nl)
    Write-Utf8Text -Path (Join-Path $installed 'SKILL.md') -Value ('---' + $nl + 'name: example-skill' + $nl + 'description: old fixture' + $nl + '---' + $nl)
    Write-Utf8Text -Path (Join-Path $installed 'scripts\run.ps1') -Value ("Write-Output 'old'" + $nl)
    Write-Utf8Text -Path (Join-Path $installed 'legacy.txt') -Value ('old-only' + $nl)

    $result = Invoke-Installer -Source $source -Installed $installed -Evidence $evidence
    Assert-Equal $result.Code 0 "Fixture installation must pass. Raw=$($result.Raw -join ' | ')"
    foreach ($name in @('source-manifest.json','installed-before-manifest.json','installed-after-manifest.json','source-package.zip','installed-before-backup.zip','result.json')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $evidence $name) -PathType Leaf) "Evidence file missing: $name"
    }
    $sourceManifest = Get-Manifest -Root $source
    $installedManifest = Get-Manifest -Root $installed
    Assert-Equal (($sourceManifest | ConvertTo-Json -Depth 5) -join '') (($installedManifest | ConvertTo-Json -Depth 5) -join '') 'Installed tree must exactly match source.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $installed 'legacy.txt'))) 'Old-only file must not leak into the new package.'
    $receipt = [System.IO.File]::ReadAllText((Join-Path $evidence 'result.json'), (New-Object System.Text.UTF8Encoding($false,$true))) | ConvertFrom-Json
    Assert-Equal $receipt.install_status 'PASS' 'Receipt install status.'
    Assert-Equal $receipt.source_install_parity 'PASS' 'Receipt parity status.'
    Assert-True (Test-Path -LiteralPath $receipt.rollback_directory -PathType Container) 'Recoverable rollback directory is required.'

    $repeat = Invoke-Installer -Source $source -Installed $installed -Evidence $evidence
    Assert-Equal $repeat.Code 1 'Existing evidence path must fail create-only.'

    $wrongSource = Join-Path $fixtureRoot 'source\wrong-skill'
    $wrongInstalled = Join-Path $fixtureRoot 'installed\wrong-skill'
    $wrongEvidence = Join-Path $fixtureRoot 'evidence\run-wrong'
    Write-Utf8Text -Path (Join-Path $wrongSource 'SKILL.md') -Value ('---' + $nl + 'name: wrong-skill' + $nl + 'description: fixture' + $nl + '---' + $nl)
    Write-Utf8Text -Path (Join-Path $wrongInstalled 'SKILL.md') -Value ('---' + $nl + 'name: different-skill' + $nl + 'description: fixture' + $nl + '---' + $nl)
    $wrong = Invoke-Installer -Source $wrongSource -Installed $wrongInstalled -Evidence $wrongEvidence
    Assert-Equal $wrong.Code 1 'Mismatched installed identity must block.'
    Assert-True (Test-Path -LiteralPath (Join-Path $wrongInstalled 'SKILL.md') -PathType Leaf) 'Identity blocker must preserve target.'

    Write-Output 'TEST_CODEX_SKILL_PACKAGE_INSTALLER=PASS'
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
}
