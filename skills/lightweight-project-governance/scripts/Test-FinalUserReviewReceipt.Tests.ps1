[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ASSERTION_FAILED: $Message" } }
function Assert-Equal { param($Actual, $Expected, [string]$Message); if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')" } }
function Assert-Contains { param([object[]]$Values, [string]$Expected, [string]$Message); Assert-True (@($Values | ForEach-Object { [string]$_ }) -contains $Expected) "$Message (missing '$Expected')" }
function Read-Json { param([string]$Path); Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON: $Path"; return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Write-Json { param([string]$Path, $Object); $Object | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Get-CanonicalHash { param($Object, [string]$ExcludedProperty); $ordered=[ordered]@{}; foreach($property in $Object.PSObject.Properties){if($property.Name -ne $ExcludedProperty){$ordered[$property.Name]=$property.Value}}; $json=$ordered|ConvertTo-Json -Depth 40 -Compress; $sha=[Security.Cryptography.SHA256]::Create(); try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','')).ToUpperInvariant()}finally{$sha.Dispose()} }
function Invoke-Receipt { param([string]$PackagePath,[string]$ReceiptPath,[string]$OutputPath);$raw=@(& $scriptPath -PackagePath $PackagePath -ReceiptPath $ReceiptPath -OutputPath $OutputPath 2>&1);$e=$LASTEXITCODE;$j=$null;if($raw.Count -gt 0){try{$j=(($raw|ForEach-Object{[string]$_})-join [Environment]::NewLine)|ConvertFrom-Json}catch{}};return [pscustomobject]@{ExitCode=$e;Json=$j;Raw=$raw} }

$root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot));$scriptPath=Join-Path $PSScriptRoot 'Test-FinalUserReviewReceipt.ps1';$fixtureBase=Join-Path $root 'outputs\skill-packaging\lightweight-governance-v1_2\T05\test-fixtures';$fixtureDir=Join-Path $fixtureBase ('receipt-run-' + [guid]::NewGuid().ToString('N'))
try {
    Assert-True (Test-Path -LiteralPath $scriptPath -PathType Leaf) 'receipt validator must exist'
    New-Item -ItemType Directory -Path $fixtureDir -Force|Out-Null

    $packagePath=Join-Path $fixtureDir 'package.json';$package=[ordered]@{schema_version=1;review_package_id='review-t05-fixture';review_mode='single_user';candidate=[ordered]@{candidate_sha256=('A'*64)};impact=[ordered]@{impact_sha256=('B'*64)};user_decision='';user_conclusion='';decision_options=@('PASS','CHANGE','REJECT')};$package.review_package_sha256=Get-CanonicalHash -Object ([pscustomobject]$package) -ExcludedProperty 'review_package_sha256';Write-Json $packagePath $package
    $receiptPath=Join-Path $fixtureDir 'receipt.json';$receipt=[ordered]@{schema_version=1;receipt_id='receipt-t05-fixture';review_package_path=$packagePath;review_package_id=$package.review_package_id;package_sha256=$package.review_package_sha256;decision='';human_conclusion='';reviewer=''};$receipt.receipt_sha256=Get-CanonicalHash -Object ([pscustomobject]$receipt) -ExcludedProperty 'receipt_sha256';Write-Json $receiptPath $receipt

    $validOut=Join-Path $fixtureDir 'receipt-valid-result.json';$valid=Invoke-Receipt $packagePath $receiptPath $validOut;Assert-Equal $valid.ExitCode 0 'valid receipt must exit 0';Assert-True $valid.Json.valid 'valid receipt verdict';Assert-Contains @($valid.Json.reason_codes) 'BIDIRECTIONAL_HASH_VERIFIED' 'bidirectional hash reason';Assert-Equal $valid.Json.package_sha256 $package.review_package_sha256 'package hash in receipt result';Assert-Equal $valid.Json.receipt_sha256 $receipt.receipt_sha256 'receipt hash in result';Write-Output 'PASS bidirectional_receipt_hash'

    $again=Invoke-Receipt $packagePath $receiptPath $validOut;Assert-Equal $again.ExitCode 1 'receipt result must be create-only';Assert-Contains @($again.Json.reason_codes) 'OUTPUT_EXISTS' 'receipt output create-only reason';Write-Output 'PASS receipt_result_create_only'

    $packageDriftPath=Join-Path $fixtureDir 'package-drift.json';$packageDrift=[ordered]@{};foreach($entry in $package.GetEnumerator()){$packageDrift[$entry.Key]=$entry.Value};$packageDrift.review_mode='changed';Write-Json $packageDriftPath $packageDrift;$driftOut=Join-Path $fixtureDir 'receipt-package-drift-result.json';$drift=Invoke-Receipt $packageDriftPath $receiptPath $driftOut;Assert-Equal $drift.ExitCode 1 'package drift must exit 1';Assert-Contains @($drift.Json.reason_codes) 'PACKAGE_HASH_MISMATCH' 'package drift reason';Write-Output 'PASS package_hash_drift_fail_closed'

    $receiptDriftPath=Join-Path $fixtureDir 'receipt-drift.json';$receiptDrift=[ordered]@{};foreach($entry in $receipt.GetEnumerator()){$receiptDrift[$entry.Key]=$entry.Value};$receiptDrift.decision='通过';Write-Json $receiptDriftPath $receiptDrift;$receiptDriftOut=Join-Path $fixtureDir 'receipt-drift-result.json';$receiptDriftResult=Invoke-Receipt $packagePath $receiptDriftPath $receiptDriftOut;Assert-Equal $receiptDriftResult.ExitCode 1 'receipt drift must exit 1';Assert-Contains @($receiptDriftResult.Json.reason_codes) 'RECEIPT_HASH_MISMATCH' 'receipt drift reason';Write-Output 'PASS receipt_hash_drift_fail_closed'

    Write-Output 'FINAL_USER_REVIEW_RECEIPT_TESTS=PASS';exit 0
} catch {Write-Error $_.Exception.Message;Write-Output 'FINAL_USER_REVIEW_RECEIPT_TESTS=FAIL';exit 1}
