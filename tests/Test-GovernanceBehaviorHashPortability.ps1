[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

function Write-CrLfUtf8File {
    param([string]$Path)
    $utf8Strict = New-Object Text.UTF8Encoding($false, $true)
    $utf8 = New-Object Text.UTF8Encoding($false)
    $text = [IO.File]::ReadAllText($Path, $utf8Strict)
    $crLf = (($text -replace "`r`n", "`n") -replace "`r", "`n") -replace "`n", "`r`n"
    [IO.File]::WriteAllText($Path, $crLf, $utf8)
}

$root = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path $root ("99_Temp\tests\behavior-hash-portability-" + [guid]::NewGuid().ToString('N'))
$candidateRoot = Join-Path $tempRoot 'candidate'
$baselineRoot = Join-Path $tempRoot 'baseline'
$outputRoot = Join-Path $tempRoot 'output'

try {
    [IO.Directory]::CreateDirectory($candidateRoot) | Out-Null
    [IO.Directory]::CreateDirectory($baselineRoot) | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'evaluations\fixtures') -Destination (Join-Path $candidateRoot 'evaluations\fixtures') -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'evaluations\expected') -Destination (Join-Path $candidateRoot 'evaluations\expected') -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'evaluations\candidate') -Destination (Join-Path $candidateRoot 'evaluations\candidate') -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'evaluations\baseline\results.json') -Destination (Join-Path $baselineRoot 'results.json')

    @(
        (Join-Path $candidateRoot 'evaluations\fixtures\scenarios.json'),
        (Join-Path $candidateRoot 'evaluations\candidate\results.json'),
        (Join-Path $baselineRoot 'results.json')
    ) | ForEach-Object { Write-CrLfUtf8File -Path $_ }

    $script = Join-Path $root 'scripts\Invoke-GovernanceBehaviorEvaluation.ps1'
    $raw = @(& $script -Baseline $baselineRoot -Candidate $candidateRoot -OutputPath $outputRoot 2>&1)
    $exitCode = $LASTEXITCODE
    Assert-True ($exitCode -eq 0) "CRLF-equivalent inputs must pass the behavior evaluation. Output: $($raw -join ' ')"
    Assert-True (($raw -join [Environment]::NewLine).Contains('BEHAVIOR_EVALUATION=PASS')) 'Evaluator must report a passing portable contract.'
    Assert-True (Test-Path -LiteralPath (Join-Path $outputRoot 'behavior-summary.json') -PathType Leaf) 'Evaluator must emit the behavior summary.'
    Write-Output 'GOVERNANCE_BEHAVIOR_HASH_PORTABILITY=PASS'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { [IO.Directory]::Delete($tempRoot, $true) }
}
