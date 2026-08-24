[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$StatePath,
    [Parameter(Mandatory=$true)][string]$Event,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop';$reasons=New-Object 'System.Collections.Generic.List[string]'
function Add-Reason{param([string]$Code);if(-not $reasons.Contains($Code)){[void]$reasons.Add($Code)}}
function Write-ResultAndExit{param([bool]$Valid,$State,$Previous,$EventName);$result=[ordered]@{schema_version=1;valid=$Valid;reason_codes=@($reasons);state=$State;previous_state=$Previous;event=$EventName;transitioned_at_utc=[DateTime]::UtcNow.ToString('o')};$result|ConvertTo-Json -Depth 12;if($Valid){exit 0}else{exit 1}}
function Write-CreateOnly{param([string]$Path,[string]$Content);$dir=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None);try{$bytes=[Text.Encoding]::UTF8.GetBytes($Content);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}
try{$stateFull=[IO.Path]::GetFullPath($StatePath);$outputFull=[IO.Path]::GetFullPath($OutputPath)}catch{Add-Reason 'PATH_INVALID';Write-ResultAndExit $false $null $null $Event}
if(-not(Test-Path -LiteralPath $stateFull -PathType Leaf)){Add-Reason 'STATE_MISSING';Write-ResultAndExit $false $null $null $Event}
if(Test-Path -LiteralPath $outputFull){Add-Reason 'OUTPUT_EXISTS';Write-ResultAndExit $false $null $null $Event}
$input=$null;try{$input=Get-Content -LiteralPath $stateFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'STATE_INVALID_JSON';Write-ResultAndExit $false $null $null $Event}
$current=[string]$input.state;if([string]::IsNullOrWhiteSpace($current)){Add-Reason 'STATE_INVALID';Write-ResultAndExit $false $current $current $Event}
$terminal=@('WAIT_HUMAN','BLOCKED_MODEL','BLOCKED_CONFLICT','BLOCKED_EXTERNAL','BLOCKED_DESTRUCTIVE','BLOCKED_HUMAN','BLOCKED_WITH_EVIDENCE','COMPLETED')
if($terminal -contains $current){Add-Reason 'TERMINAL_STATE';Write-ResultAndExit $false $current $current $Event}
$transitions=@{
 'PRECHECK'=@{'PRECHECK_PASS'='PLAN_GATE'};
 'PLAN_GATE'=@{'PLAN_READY'='RUN_INITIALIZED'};
 'RUN_INITIALIZED'=@{'RUN_STARTED'='TASK_SELECTED'};
 'TASK_SELECTED'=@{'IMPLEMENTATION_STARTED'='TASK_IMPLEMENTING';'PLAN_COMPLETE'='CLEANUP_ROUND_1'};
 'TASK_IMPLEMENTING'=@{'VERIFICATION_STARTED'='TASK_VERIFYING'};
 'TASK_VERIFYING'=@{'VERIFICATION_PASSED'='CHECKPOINT_WRITTEN';'RETRYABLE_FAILURE'='RETRY_PENDING'};
 'RETRY_PENDING'=@{'RETRY_WITH_MITIGATION'='DIAGNOSE';'RETRY_LIMIT_REACHED'='BLOCKED_WITH_EVIDENCE'};
 'DIAGNOSE'=@{'DIAGNOSIS_COMPLETE'='FIX'};
 'FIX'=@{'FIX_APPLIED'='TASK_VERIFYING'};
 'CHECKPOINT_WRITTEN'=@{'TASK_CHECKPOINTED'='TASK_SELECTED';'PLAN_COMPLETE'='CLEANUP_ROUND_1'};
 'CLEANUP_ROUND_1'=@{'CLEANUP_1_COMPLETE'='CLEANUP_ROUND_2'};
 'CLEANUP_ROUND_2'=@{'CLEANUP_2_COMPLETE'='FINAL_VERIFY'};
 'FINAL_VERIFY'=@{'FINAL_VERIFY_PASS'='LOCAL_COMMIT'};
 'LOCAL_COMMIT'=@{'LOCAL_COMMIT_DONE'='REVIEW_PACKAGE'};
 'REVIEW_PACKAGE'=@{'REVIEW_PACKAGE_DONE'='WAIT_HUMAN'}
}
$globalEvents=@{'MODEL_POLICY_BLOCKED'='BLOCKED_MODEL';'CONFLICT'='BLOCKED_CONFLICT';'RESOURCE_CONFLICT'='BLOCKED_CONFLICT';'EXTERNAL_GATE'='BLOCKED_EXTERNAL';'HUMAN_GATE'='BLOCKED_HUMAN';'DESTRUCTIVE_GATE'='BLOCKED_DESTRUCTIVE';'RETRY_LIMIT_REACHED'='BLOCKED_WITH_EVIDENCE'}
$next=$null
if($globalEvents.ContainsKey($Event)){$next=$globalEvents[$Event]}elseif($transitions.ContainsKey($current)-and $transitions[$current].ContainsKey($Event)){$next=$transitions[$current][$Event]}else{Add-Reason 'INVALID_TRANSITION';Write-ResultAndExit $false $current $current $Event}
$nextState=[ordered]@{};foreach($p in $input.PSObject.Properties){$nextState[$p.Name]=$p.Value};$nextState.state=$next;$nextState.previous_state=$current;$nextState.last_event=$Event;$nextState.updated_at_utc=[DateTime]::UtcNow.ToString('o')
$json=$nextState|ConvertTo-Json -Depth 12
try{Write-CreateOnly -Path $outputFull -Content $json}catch{Add-Reason 'OUTPUT_CREATE_FAILED';Write-ResultAndExit $false $current $current $Event}
$result=[ordered]@{schema_version=1;valid=$true;reason_codes=@();state=$next;previous_state=$current;event=$Event;state_path=$outputFull;transitioned_at_utc=[DateTime]::UtcNow.ToString('o')};$result|ConvertTo-Json -Depth 12;exit 0
