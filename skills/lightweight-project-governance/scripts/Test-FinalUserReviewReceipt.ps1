[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$ReceiptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$reasonCodes = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason { param([string]$Code); if (-not $reasonCodes.Contains($Code)) { [void]$reasonCodes.Add($Code) } }
function Get-FullPath { param([string]$Path); if ([string]::IsNullOrWhiteSpace($Path)) { return $null }; try { return [IO.Path]::GetFullPath($Path) } catch { return $null } }
function Get-PropertyValue { param($Object, [string]$Name); if ($null -eq $Object) { return $null }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property) { return $null }; return $property.Value }
function Get-CanonicalHash { param($Object, [string]$ExcludedProperty); $ordered=[ordered]@{}; foreach($property in $Object.PSObject.Properties){if($property.Name -ne $ExcludedProperty){$ordered[$property.Name]=$property.Value}}; $json=$ordered|ConvertTo-Json -Depth 50 -Compress; $sha=[Security.Cryptography.SHA256]::Create(); try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','')).ToUpperInvariant()}finally{$sha.Dispose()} }
function Write-CreateOnly { param([string]$Path,[string]$Content);$directory=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $directory -PathType Container)){New-Item -ItemType Directory -Path $directory -Force|Out-Null};$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$bytes=[Text.Encoding]::UTF8.GetBytes($Content);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()} }
function Finish {
    param([bool]$Success, [string]$PackageHash, [string]$ReceiptHash)
    $result=[ordered]@{schema_version=1;valid=$Success;reason_codes=@($reasonCodes);package_sha256=$PackageHash;receipt_sha256=$ReceiptHash}
    if ($null -ne $outputFull -and -not (Test-Path -LiteralPath $outputFull)) {
        try { Write-CreateOnly -Path $outputFull -Content ($result|ConvertTo-Json -Depth 20) } catch { Add-Reason 'OUTPUT_CREATE_FAILED';$result.valid=$false;$result.reason_codes=@($reasonCodes) }
    }
    $result|ConvertTo-Json -Depth 20
    if ($result.valid) { exit 0 } else { exit 1 }
}

$packageFull=Get-FullPath $PackagePath;$receiptFull=Get-FullPath $ReceiptPath;$outputFull=Get-FullPath $OutputPath
if($null -eq $packageFull){Add-Reason 'PACKAGE_PATH_INVALID'}
if($null -eq $receiptFull){Add-Reason 'RECEIPT_PATH_INVALID'}
if($null -eq $outputFull){Add-Reason 'OUTPUT_PATH_INVALID'}
if($null -ne $outputFull -and (Test-Path -LiteralPath $outputFull)){Add-Reason 'OUTPUT_EXISTS'}
if($reasonCodes.Count -gt 0){$result=[ordered]@{schema_version=1;valid=$false;reason_codes=@($reasonCodes);package_sha256='';receipt_sha256=''};$result|ConvertTo-Json -Depth 20;exit 1}
if(-not(Test-Path -LiteralPath $packageFull -PathType Leaf)){Add-Reason 'PACKAGE_MISSING'}
if(-not(Test-Path -LiteralPath $receiptFull -PathType Leaf)){Add-Reason 'RECEIPT_MISSING'}
$package=$null;$receipt=$null
if($reasonCodes.Count -eq 0){try{$package=Get-Content -LiteralPath $packageFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'PACKAGE_INVALID_JSON'};try{$receipt=Get-Content -LiteralPath $receiptFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'RECEIPT_INVALID_JSON'}}
if($null -eq $package -and $reasonCodes.Count -eq 0){Add-Reason 'PACKAGE_INVALID'}
if($null -eq $receipt -and $reasonCodes.Count -eq 0){Add-Reason 'RECEIPT_INVALID'}
$packageHash='';$receiptHash=''
if($null -ne $package){$packageHash=Get-CanonicalHash -Object $package -ExcludedProperty 'review_package_sha256';$declaredPackageHash=[string](Get-PropertyValue $package 'review_package_sha256');if($declaredPackageHash -notmatch '^[0-9A-Fa-f]{64}$' -or $declaredPackageHash.ToUpperInvariant() -ne $packageHash){Add-Reason 'PACKAGE_HASH_MISMATCH'}}
if($null -ne $receipt){$receiptHash=Get-CanonicalHash -Object $receipt -ExcludedProperty 'receipt_sha256';$declaredReceiptHash=[string](Get-PropertyValue $receipt 'receipt_sha256');if($declaredReceiptHash -notmatch '^[0-9A-Fa-f]{64}$' -or $declaredReceiptHash.ToUpperInvariant() -ne $receiptHash){Add-Reason 'RECEIPT_HASH_MISMATCH'}}
if($null -ne $receipt -and $null -ne $package){if([string](Get-PropertyValue $receipt 'package_sha256').ToUpperInvariant() -ne [string](Get-PropertyValue $package 'review_package_sha256').ToUpperInvariant()){Add-Reason 'RECEIPT_PACKAGE_HASH_MISMATCH'};if([string](Get-PropertyValue $receipt 'review_package_id') -ne [string](Get-PropertyValue $package 'review_package_id')){Add-Reason 'RECEIPT_PACKAGE_ID_MISMATCH'}}
if($reasonCodes.Count -eq 0){Add-Reason 'BIDIRECTIONAL_HASH_VERIFIED'}
Finish -Success ($reasonCodes.Count -eq 1 -and $reasonCodes.Contains('BIDIRECTIONAL_HASH_VERIFIED')) -PackageHash $packageHash -ReceiptHash $receiptHash
