[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$implementation = Join-Path $PSScriptRoot 'Find-ProjectPlanningBaseline.ps1'

if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    Write-Error 'RED: Find-ProjectPlanningBaseline.ps1 is missing.'
    exit 1
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Contains {
    param([object[]]$Actual, [string]$Expected, [string]$Message)
    if ($Actual -notcontains $Expected) {
        throw "$Message Missing=[$Expected] Actual=[$($Actual -join ',')]"
    }
}

$implementationBytes = [System.IO.File]::ReadAllBytes($implementation)
$implementationHasUtf8Bom = $implementationBytes.Length -ge 3 -and
    $implementationBytes[0] -eq 0xEF -and
    $implementationBytes[1] -eq 0xBB -and
    $implementationBytes[2] -eq 0xBF
Assert-Equal $implementationHasUtf8Bom $true 'Discovery implementation must use UTF-8 BOM for Windows PowerShell 5.1 compatibility.'

function Invoke-Discovery {
    param([string]$Root)
    $json = & $implementation -ProjectRoot $Root
    if ($LASTEXITCODE -ne 0) {
        throw "Discovery script exited with $LASTEXITCODE"
    }
    return ($json | ConvertFrom-Json)
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $tempBase ('codex-plan-baseline-test-' + [guid]::NewGuid().ToString('N'))
$fixtureFull = [System.IO.Path]::GetFullPath($fixtureRoot)
if (-not $fixtureFull.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe fixture path: $fixtureFull"
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

    $missing = Invoke-Discovery -Root $fixtureRoot
    Assert-Equal $missing.planning_root_exists $false 'Missing planning root must be reported.'
    Assert-Contains @($missing.reason_codes) 'PLANNING_ROOT_MISSING' 'Missing planning root reason.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixtureRoot 'docs\future-development')) $false 'Discovery must not create the planning root.'

    $planningRoot = Join-Path $fixtureRoot 'docs\future-development'
    New-Item -ItemType Directory -Path $planningRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $planningRoot 'ExampleAgent_Direction_V1.1.md') -Value '# direction' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $planningRoot 'ExampleAgent_DesignDoc_V1.1.md') -Value '# design 1.1' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $planningRoot 'ExampleAgent_DesignDoc_V1.2.md') -Value '# design 1.2' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $planningRoot 'ExampleAgent_ImplementationPlan_V1.1.md') -Value '# plan' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $planningRoot 'ExampleAgent_roadmap.md') -Value '# roadmap' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $planningRoot 'ExampleAgent_AcceptanceWindow_V1.0.md') -Value '# acceptance' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $planningRoot 'notes.txt') -Value 'not markdown' -Encoding utf8

    $found = Invoke-Discovery -Root $fixtureRoot
    Assert-Equal $found.planning_root_exists $true 'Planning root must exist.'
    Assert-Equal @($found.files).Count 6 'Only Markdown planning files must be returned.'
    $categories = @($found.files | ForEach-Object { $_.category })
    Assert-Contains $categories 'Direction' 'Direction category.'
    Assert-Contains $categories 'Design' 'Design category.'
    Assert-Contains $categories 'Plan' 'Plan category.'
    Assert-Contains $categories 'Roadmap' 'Roadmap category.'
    Assert-Contains $categories 'AcceptanceWindow' 'Acceptance-window category.'

    $designs = @($found.files | Where-Object { $_.category -eq 'Design' })
    Assert-Equal $designs[0].version 'V1.2' 'Newest design must sort first.'
    Assert-Equal ([string]::IsNullOrWhiteSpace($designs[0].sha256)) $false 'Every file must have SHA-256.'

    Write-Output 'FIND_PROJECT_PLANNING_BASELINE=PASS'
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

