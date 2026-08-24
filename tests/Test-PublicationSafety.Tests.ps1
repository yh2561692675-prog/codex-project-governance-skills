[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'scripts/Test-PublicationSafety.ps1'
$outputRoot = Join-Path $root '99_Temp/T07-publication-safety-test'

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Expected publication safety scanner at $scriptPath"
}

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}

& $scriptPath -ScanHistory -OutputPath $outputRoot
if ($LASTEXITCODE -ne 0) {
    throw "Publication safety scanner exited with $LASTEXITCODE"
}

$resultPath = Join-Path $outputRoot 'publication-safety.json'
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "Expected machine-readable result at $resultPath"
}

$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($result.SECRET_FINDINGS -ne 0) { throw 'Expected SECRET_FINDINGS=0' }
if ($result.PII_FINDINGS -ne 0) { throw 'Expected PII_FINDINGS=0' }
if ($result.LICENSE_CONFLICTS -ne 0) { throw 'Expected LICENSE_CONFLICTS=0' }
if ($result.SUPPLY_CHAIN -ne 'PASS') { throw 'Expected SUPPLY_CHAIN=PASS' }
if ($result.HISTORY_SCANNED -ne $true) { throw 'Expected HISTORY_SCANNED=true' }

Write-Output 'TEST_PUBLICATION_SAFETY=PASS'
