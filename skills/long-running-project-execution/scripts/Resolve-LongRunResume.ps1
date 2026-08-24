[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$CheckpointDirectory,
    [Parameter(Mandatory=$true)][string]$CurrentIdentityPath,
    [string]$OutputPath=''
)
$ErrorActionPreference='Stop';$reasons=New-Object 'System.Collections.Generic.List[string]'
function Add-Reason{param([string]$Code);if(-not$reasons.Contains($Code)){[void]$reasons.Add($Code)}}
function Read-Json{param([string]$Path);try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Write-Decision{param([string]$Decision,[string]$ResumeTask,$Invalidated,$LastCheckpoint);$result=[ordered]@{schema_version=1;decision=$Decision;reason_codes=@($reasons);resume_task=$ResumeTask;invalidated_evidence=@($Invalidated);last_checkpoint=$LastCheckpoint;manifest_path=$ManifestPath;identity_path=$CurrentIdentityPath;evaluated_at_utc=[DateTime]::UtcNow.ToString('o')};$json=$result|ConvertTo-Json -Depth 16;Write-Output $json;if(-not[string]::IsNullOrWhiteSpace($OutputPath)){try{$dir=Split-Path -Parent $OutputPath;if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$b=[Text.Encoding]::UTF8.GetBytes($json);$stream.Write($b,0,$b.Length)}finally{$stream.Dispose()}}catch{Add-Reason 'OUTPUT_CREATE_FAILED'}};if($Decision -eq 'RESUME_ALLOWED'){exit 0}else{exit 1}}
if(-not(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){Add-Reason 'MANIFEST_MISSING';Write-Decision 'EVIDENCE_INVALIDATED' $null @() $null}
if(-not(Test-Path -LiteralPath $CurrentIdentityPath -PathType Leaf)){Add-Reason 'IDENTITY_MISSING';Write-Decision 'READ_ONLY_ONLY' $null @() $null}
$manifest=Read-Json $ManifestPath;$identity=Read-Json $CurrentIdentityPath
if($null-eq$manifest){Add-Reason 'MANIFEST_INVALID_JSON';Write-Decision 'EVIDENCE_INVALIDATED' $null @() $null}
if($null-eq$identity){Add-Reason 'IDENTITY_INVALID_JSON';Write-Decision 'READ_ONLY_ONLY' $null @() $null}
$state=[string]$manifest.state;if($state -in @('WAIT_HUMAN','COMPLETED','LOCAL_COMMIT','REVIEW_PACKAGE')){Write-Decision 'COMPLETED_TERMINAL' $null @() $null}
if([string]$identity.active_run_id -and [string]$identity.active_run_id -ne [string]$manifest.run_id){Add-Reason 'DUPLICATE_RUN_ID';Write-Decision 'BLOCKED_CONFLICT' $null @() $null}
$files=@(Get-ChildItem -LiteralPath $CheckpointDirectory -Filter 'checkpoint-*.json' -File -ErrorAction SilentlyContinue|Sort-Object Name)
if($files.Count -eq 0){Add-Reason 'NO_CHECKPOINT';Write-Decision 'NO_CHECKPOINT' $null @() $null}
$checkpoints=@();foreach($file in $files){$cp=Read-Json $file.FullName;if($null-eq$cp){Add-Reason 'CHECKPOINT_INVALID_JSON';continue};$checkpoints+=,$cp}
if($checkpoints.Count -eq 0){Add-Reason 'NO_VALID_CHECKPOINT';Write-Decision 'EVIDENCE_INVALIDATED' $null @() $null}
$chainValid=$true;$expectedSequence=1;$previousHash=$null;foreach($cp in $checkpoints){if([int]$cp.sequence-ne$expectedSequence){$chainValid=$false};if([string]$cp.run_id-ne[string]$manifest.run_id){$chainValid=$false};if($expectedSequence-gt 1-and[string]$cp.previous_checkpoint_sha256-ne[string]$previousHash){$chainValid=$false};if([string]::IsNullOrWhiteSpace([string]$cp.checkpoint_sha256)){$chainValid=$false};$expectedSequence++;$previousHash=[string]$cp.checkpoint_sha256}
if(-not$chainValid){Add-Reason 'CHECKPOINT_CHAIN_INVALID';Write-Decision 'EVIDENCE_INVALIDATED' $null @('checkpoint-chain','downstream-task-evidence') $checkpoints[-1]}
$identityPairs=@(
    @([string]$manifest.design_hash,[string]$identity.design_hash),
    @([string]$manifest.plan_hash,[string]$identity.plan_hash),
    @([string]$manifest.model,[string]$identity.model),
    @([string]$manifest.reasoning,[string]$identity.reasoning),
    @([string]$manifest.profile_path,[string]$identity.profile_path),
    @([string]$manifest.git.head,[string]$identity.git_head)
)
$identityChanged=$false;foreach($pair in $identityPairs){if(-not[string]::IsNullOrWhiteSpace($pair[0])-and-not[string]::IsNullOrWhiteSpace($pair[1])-and$pair[0]-ne$pair[1]){$identityChanged=$true}}
if($identityChanged){Add-Reason 'IDENTITY_CHANGED';Write-Decision 'EVIDENCE_INVALIDATED' $null @('checkpoint-chain','downstream-task-evidence') $checkpoints[-1]}
$writerState=[string]$identity.writer_state;if($writerState -eq 'active'){Add-Reason 'ACTIVE_WRITER_PRESENT';Write-Decision 'BLOCKED_CONFLICT' $null @() $checkpoints[-1]};if($writerState -ne 'inactive'){Add-Reason 'WRITER_STATE_UNKNOWN';Write-Decision 'READ_ONLY_ONLY' $null @() $checkpoints[-1]}
$last=$checkpoints[-1];$resumeTask='NEXT_UNSPECIFIED';if(([string]$last.task_id)-match '^T(\d+)$'){$resumeTask='T'+(([int]$Matches[1])+1).ToString('00')}
Write-Decision 'RESUME_ALLOWED' $resumeTask @() $last
