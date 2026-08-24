[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$TaskId,
    [Parameter(Mandatory=$true)][string]$Command,
    [int]$ExitCode=[int]::MinValue,
    [Parameter(Mandatory=$true)][string]$EvidencePath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop';$reasons=New-Object 'System.Collections.Generic.List[string]'
function Add-Reason{param([string]$Code);if(-not$reasons.Contains($Code)){[void]$reasons.Add($Code)}}
function Resolve-Full{param([string]$Path);try{return [IO.Path]::GetFullPath($Path)}catch{return $null}}
function Within{param([string]$Path,[string]$Root);if($null-eq$Path-or$null-eq$Root){return$false};$p=(Resolve-Full $Path).TrimEnd('\');$r=(Resolve-Full $Root).TrimEnd('\');return$p.Equals($r,[StringComparison]::OrdinalIgnoreCase)-or$p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)}
function Hash-Text{param([string]$Text);$sha=[Security.Cryptography.SHA256]::Create();try{return([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','')).ToUpperInvariant()}finally{$sha.Dispose()}}
function WithinSafe {
    param([string]$Path,[string]$Root)
    if ($null -eq $Path -or $null -eq $Root) { return $false }
    $p = (Resolve-Full $Path).TrimEnd('\'); $r = (Resolve-Full $Root).TrimEnd('\')
    return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Hash-CanonicalObject{param($Object);$ordered=[ordered]@{};foreach($p in $Object.PSObject.Properties){if($p.Name-ne'checkpoint_sha256'){$ordered[$p.Name]=$p.Value}};return Hash-Text (($ordered|ConvertTo-Json -Depth 20 -Compress))}
function Write-ResultAndExit{param([bool]$Valid,$Checkpoint);$result=[ordered]@{schema_version=1;valid=$Valid;reason_codes=@($reasons);checkpoint=$Checkpoint};$result|ConvertTo-Json -Depth 20;if($Valid){exit 0}else{exit 1}}
function Write-CreateOnly{param([string]$Path,[string]$Content);$dir=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$s=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$b=[Text.Encoding]::UTF8.GetBytes($Content);$s.Write($b,0,$b.Length)}finally{$s.Dispose()}}
$manifestFull=Resolve-Full $ManifestPath;$outputFull=Resolve-Full $OutputPath;$evidenceFull=Resolve-Full $EvidencePath
if($null-eq$manifestFull-or$null-eq$outputFull-or$null-eq$evidenceFull){Add-Reason 'PATH_INVALID';Write-ResultAndExit $false $null}
if(-not(Test-Path -LiteralPath $manifestFull -PathType Leaf)){Add-Reason 'MANIFEST_MISSING';Write-ResultAndExit $false $null}
if(Test-Path -LiteralPath $outputFull){Add-Reason 'OUTPUT_EXISTS';Write-ResultAndExit $false $null}
$manifest=$null;try{$manifest=Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'MANIFEST_INVALID_JSON';Write-ResultAndExit $false $null}
$root=Resolve-Full ([string]$manifest.project_root);if($null-eq$root){Add-Reason 'PROJECT_ROOT_INVALID';Write-ResultAndExit $false $null}
if(-not(WithinSafe $outputFull $root)){Add-Reason 'OUTPUT_OUTSIDE_PROJECT_ROOT'}
if(-not(WithinSafe $evidenceFull $root)){Add-Reason 'EVIDENCE_OUTSIDE_PROJECT_ROOT'}
if(-not(Test-Path -LiteralPath $evidenceFull -PathType Leaf)){Add-Reason 'EVIDENCE_MISSING'}
if($TaskId -notmatch '^T\d+$'){Add-Reason 'TASK_ID_INVALID'}
if([string]::IsNullOrWhiteSpace($Command)){Add-Reason 'COMMAND_MISSING'}
if($ExitCode -eq [int]::MinValue){Add-Reason 'EXIT_CODE_MISSING'}
if($reasons.Count-gt 0){Write-ResultAndExit $false $null}

$checkpointDirectory=Split-Path -Parent $outputFull;$previous=$null;$sequence=1
$existing=@(Get-ChildItem -LiteralPath $checkpointDirectory -Filter 'checkpoint-*.json' -File -ErrorAction SilentlyContinue|Sort-Object Name)
if($existing.Count-gt 0){$last=$existing[-1];try{$previous=Get-Content -LiteralPath $last.FullName -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'CHECKPOINT_CHAIN_INVALID'}}
if($null-ne$previous){$recomputed=Hash-CanonicalObject $previous;if([string]$previous.checkpoint_sha256-ne$recomputed){Add-Reason 'CHECKPOINT_CHAIN_INVALID'};if($null-eq$previous.sequence-or[int]$previous.sequence-lt 1){Add-Reason 'CHECKPOINT_CHAIN_INVALID'}else{$sequence=[int]$previous.sequence+1}}
if($reasons.Count-gt 0){Write-ResultAndExit $false $null}
$evidenceHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $evidenceFull).Hash.ToUpperInvariant()
$checkpoint=[ordered]@{schema_version=1;checkpoint_id=[guid]::NewGuid().ToString('N');run_id=[string]$manifest.run_id;sequence=$sequence;manifest_path=$manifestFull;project_root=$root;design_hash=[string]$manifest.design_hash;plan_hash=[string]$manifest.plan_hash;task_id=$TaskId;command=$Command;exit_code=$ExitCode;evidence_path=$evidenceFull;evidence_sha256=$evidenceHash;previous_checkpoint_sha256=if($null-eq$previous){$null}else{[string]$previous.checkpoint_sha256};model=[string]$manifest.model;reasoning=[string]$manifest.reasoning;git=$manifest.git;created_at_utc=[DateTime]::UtcNow.ToString('o')}
$checkpoint.checkpoint_sha256=Hash-CanonicalObject ([pscustomobject]$checkpoint);$json=$checkpoint|ConvertTo-Json -Depth 20
try{Write-CreateOnly -Path $outputFull -Content $json}catch{Add-Reason 'OUTPUT_CREATE_FAILED';Write-ResultAndExit $false $null}
Write-ResultAndExit $true $checkpoint
