[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$reasonCodes = New-Object 'System.Collections.Generic.List[string]'

function Add-Reason { param([string]$Code); if (-not $reasonCodes.Contains($Code)) { [void]$reasonCodes.Add($Code) } }
function Get-FullPath { param([string]$Path); if ([string]::IsNullOrWhiteSpace($Path)) { return $null }; try { return [IO.Path]::GetFullPath($Path) } catch { return $null } }
function Test-Within { param([string]$Path, [string]$Root); $p=Get-FullPath $Path; $r=Get-FullPath $Root; if($null -eq $p -or $null -eq $r){return $false};$p=$p.TrimEnd('\');$r=$r.TrimEnd('\');return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase) }
function Get-PropertyValue { param($Object,[string]$Name); if($null -eq $Object){return $null};$p=$Object.PSObject.Properties[$Name];if($null -eq $p){return $null};return $p.Value }
function Get-CanonicalHash { param($Object);$ordered=[ordered]@{};foreach($p in $Object.PSObject.Properties){if($p.Name -ne 'candidate_sha256'){$ordered[$p.Name]=$p.Value}};$json=$ordered|ConvertTo-Json -Depth 40 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','')).ToUpperInvariant()}finally{$sha.Dispose()} }
function Write-CreateOnly { param([string]$Path,[string]$Content);$dir=Split-Path -Parent $Path;if(-not (Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$bytes=[Text.Encoding]::UTF8.GetBytes($Content);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()} }
function Finish { param([bool]$Success,$Impact);$result=[ordered]@{schema_version=1;valid=$Success;reason_codes=@($reasonCodes);impact=$Impact};$result|ConvertTo-Json -Depth 40;if($Success){exit 0}else{exit 1} }
function Add-Unique { param($List,[string]$Value);if(-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)){[void]$List.Add($Value)} }
function Test-PathMatch { param([string]$Path,[string]$Prefix);$normalized=$Path.Replace('\','/');$prefixNormalized=$Prefix.Replace('\','/');return $normalized.StartsWith($prefixNormalized,[StringComparison]::OrdinalIgnoreCase) }

$inputFull=Get-FullPath $InputPath;$outputFull=Get-FullPath $OutputPath
if($null -eq $inputFull){Add-Reason 'INPUT_PATH_INVALID'}
if($null -eq $outputFull){Add-Reason 'OUTPUT_PATH_INVALID'}
if (($null -ne $outputFull) -and (Test-Path -LiteralPath $outputFull)) { Add-Reason 'OUTPUT_EXISTS' }
if($reasonCodes.Count -gt 0){Finish $false $null}
$source=$null;try{$source=Get-Content -LiteralPath $inputFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'INPUT_INVALID_JSON'}
if($null -eq $source){Finish $false $null}
$candidatePath=Get-FullPath ([string](Get-PropertyValue $source 'candidate_manifest_path'))
if($null -eq $candidatePath){Add-Reason 'CANDIDATE_PATH_INVALID'}
if($null -ne $candidatePath -and -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)){Add-Reason 'CANDIDATE_MISSING'}
$candidate=$null;if($reasonCodes.Count -eq 0){try{$candidate=Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'CANDIDATE_INVALID_JSON'}}
if($null -eq $candidate -and $reasonCodes.Count -eq 0){Add-Reason 'CANDIDATE_INVALID'}
$root=Get-FullPath ([string](Get-PropertyValue (Get-PropertyValue $candidate 'project') 'root'))
if($null -eq $root){Add-Reason 'PROJECT_ROOT_INVALID'}
if($null -ne $root -and $null -ne $candidatePath -and -not (Test-Within $candidatePath $root)){Add-Reason 'CANDIDATE_OUTSIDE_PROJECT_ROOT'}
$expectedHash=[string](Get-PropertyValue $source 'candidate_sha256');$actualHash=[string](Get-PropertyValue $candidate 'candidate_sha256')
if($actualHash -notmatch '^[0-9a-fA-F]{64}$' -or $expectedHash.ToUpperInvariant() -ne $actualHash.ToUpperInvariant() -or (Get-CanonicalHash $candidate) -ne $actualHash.ToUpperInvariant()){Add-Reason 'CANDIDATE_HASH_MISMATCH'}
if($reasonCodes.Count -gt 0){Finish $false $null}

$changedPaths=@((Get-PropertyValue $source 'changed_paths')|ForEach-Object{[string]$_})
$mappings=@((Get-PropertyValue $source 'test_mappings'))
$evidenceRefs=@((Get-PropertyValue $source 'evidence_references'))
$configDependencies=@((Get-PropertyValue $source 'configuration_dependencies'))
$affectedPaths=New-Object 'System.Collections.Generic.List[string]';$affectedTests=New-Object 'System.Collections.Generic.List[string]';$invalidEvidence=New-Object 'System.Collections.Generic.List[string]';$retainedEvidence=New-Object 'System.Collections.Generic.List[string]';$expanded=$false
$configurationChange=$false;$proofFound=$false
foreach($path in $changedPaths){
    Add-Unique $affectedPaths $path
    if($path -match '(^|[\\/])(config|schemas)([\\/]|$)' -or $path -like '.codex/*' -or $path -like '.codex\*'){$configurationChange=$true}
    foreach($dependency in $configDependencies){$prefix=[string](Get-PropertyValue $dependency 'path_prefix');if(-not [string]::IsNullOrWhiteSpace($prefix) -and (Test-PathMatch $path $prefix)){$configurationChange=$true}}
    foreach($mapping in $mappings){$prefix=[string](Get-PropertyValue $mapping 'path_prefix');if(-not [string]::IsNullOrWhiteSpace($prefix) -and (Test-PathMatch $path $prefix)){$proofFound=$true;foreach($test in @((Get-PropertyValue $mapping 'tests'))){Add-Unique $affectedTests ([string]$test)};foreach($evidence in @((Get-PropertyValue $mapping 'evidence'))){Add-Unique $invalidEvidence ([string]$evidence)}}}
    foreach($reference in $evidenceRefs){$depends=@((Get-PropertyValue $reference 'depends_on')|ForEach-Object{[string]$_});if($depends -contains $path){$proofFound=$true;Add-Unique $invalidEvidence ([string](Get-PropertyValue $reference 'id'))}}
}
if($configurationChange){$expanded=$true;Add-Reason 'CONFIG_OR_SCHEMA_CHANGE';foreach($mapping in $mappings){foreach($test in @((Get-PropertyValue $mapping 'tests'))){Add-Unique $affectedTests ([string]$test)}};foreach($reference in $evidenceRefs){Add-Unique $invalidEvidence ([string](Get-PropertyValue $reference 'id'))}}
elseif(-not $proofFound){
    $onlyDocumentation=$true;foreach($path in $changedPaths){if($path -notmatch '(^|[\\/])docs([\\/]|$)'){$onlyDocumentation=$false}}
    if($onlyDocumentation){Add-Reason 'NO_AFFECTED_EVIDENCE_INVALIDATION'}else{$expanded=$true;Add-Reason 'AFFECTED_PATH_UNMAPPED'}
}
foreach($reference in $evidenceRefs){$id=[string](Get-PropertyValue $reference 'id');if($invalidEvidence -notcontains $id){Add-Unique $retainedEvidence $id}}
if($invalidEvidence.Count -eq 0 -and -not ($reasonCodes -contains 'CONFIG_OR_SCHEMA_CHANGE')){Add-Reason 'NO_AFFECTED_EVIDENCE_INVALIDATION'}

$impact=[ordered]@{schema_version=1;candidate_manifest_path=$candidatePath;candidate_sha256=$actualHash;changed_paths=@($changedPaths);affected_paths=@($affectedPaths);affected_tests=@($affectedTests);invalidated_evidence=@($invalidEvidence);retained_evidence=@($retainedEvidence);expanded=$expanded;reason_codes=@($reasonCodes)}
$impactHash=[Security.Cryptography.SHA256]::Create();try{$canon=[ordered]@{};foreach($p in $impact.Keys){if($p -ne 'impact_sha256'){$canon[$p]=$impact[$p]}};$impact.impact_sha256=([BitConverter]::ToString($impactHash.ComputeHash([Text.Encoding]::UTF8.GetBytes(($canon|ConvertTo-Json -Depth 40 -Compress)))).Replace('-','')).ToUpperInvariant()}finally{$impactHash.Dispose()}
try{Write-CreateOnly -Path $outputFull -Content ($impact|ConvertTo-Json -Depth 40)}catch{Add-Reason 'OUTPUT_CREATE_FAILED';Finish $false $null}
Finish $true ([pscustomobject]$impact)
