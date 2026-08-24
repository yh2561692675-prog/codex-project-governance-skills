[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$FailurePath,
    [Parameter(Mandatory=$true)][string]$AttemptHistoryPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop';$reasons=New-Object 'System.Collections.Generic.List[string]'
function Add-Reason{param([string]$Code);if(-not$reasons.Contains($Code)){[void]$reasons.Add($Code)}}
function Read-Json{param([string]$Path);try{return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}catch{return $null}}
function Write-Result{param([bool]$Valid,$Decision,[int]$EffectiveRetryCount,[bool]$RetryAllowed,[object]$Failure);$result=[ordered]@{schema_version=1;valid=$Valid;decision=$Decision;reason_codes=@($reasons);category=[string]$Failure.category;effective_retry_count=$EffectiveRetryCount;retry_allowed=$RetryAllowed;attempt_count=$script:attemptCount;mitigation=[string]$Failure.mitigation;impact=[string]$Failure.impact;required_input='Evidence, owner, and explicit release criteria for the classified blocker.';release_criteria='A new verified fact or mitigation matching the category; human/external/destructive gates require user decision.';recovery_entry='Resume from the last valid checkpoint after the blocker is resolved.';next_event=$script:nextEvent;cleanup_round=[int]$Failure.cleanup_round;evaluated_at_utc=[DateTime]::UtcNow.ToString('o')};$json=$result|ConvertTo-Json -Depth 16;Write-Output $json;try{$dir=Split-Path -Parent $OutputPath;if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$b=[Text.Encoding]::UTF8.GetBytes($json);$stream.Write($b,0,$b.Length)}finally{$stream.Dispose()}}catch{Add-Reason 'OUTPUT_CREATE_FAILED'};if($Valid){exit 0}else{exit 1}}
if(-not(Test-Path -LiteralPath $FailurePath -PathType Leaf)){Add-Reason 'FAILURE_MISSING';$script:attemptCount=0;$script:nextEvent='BLOCKED_WITH_EVIDENCE';Write-Result $false 'BLOCKED_WITH_EVIDENCE' 0 $false ([pscustomobject]@{category='unknown';mitigation='';impact='';cleanup_round=0})}
if(-not(Test-Path -LiteralPath $AttemptHistoryPath -PathType Leaf)){Add-Reason 'ATTEMPT_HISTORY_MISSING';$script:attemptCount=0;$script:nextEvent='BLOCKED_WITH_EVIDENCE';Write-Result $false 'BLOCKED_WITH_EVIDENCE' 0 $false ([pscustomobject]@{category='unknown';mitigation='';impact='';cleanup_round=0})}
$failure=Read-Json $FailurePath;$historyObject=Read-Json $AttemptHistoryPath
if($null-eq$failure){Add-Reason 'FAILURE_INVALID_JSON';$script:attemptCount=0;$script:nextEvent='BLOCKED_WITH_EVIDENCE';Write-Result $false 'BLOCKED_WITH_EVIDENCE' 0 $false ([pscustomobject]@{category='unknown';mitigation='';impact='';cleanup_round=0})}
$history=@($historyObject);$script:attemptCount=$history.Count;$effective=@($history|Where-Object{$_.effective -eq $true});$effectiveCount=$effective.Count
$category=([string]$failure.category).ToLowerInvariant();$round=[int]$failure.cleanup_round;$script:nextEvent='BLOCKED_WITH_EVIDENCE';$decision='BLOCKED_WITH_EVIDENCE';$retryAllowed=$false
if($category -eq 'unfinished' -and $round -gt 0){if($round -eq 1){$decision='CLEANUP_ROUND_1';$retryAllowed=$true;$script:nextEvent='CLEANUP_1_COMPLETE'}elseif($round -eq 2 -and -not[string]::IsNullOrWhiteSpace([string]$failure.mitigation)){$decision='CLEANUP_ROUND_2';$retryAllowed=$true;$script:nextEvent='CLEANUP_2_COMPLETE'}else{Add-Reason 'CLEANUP_ROUNDS_EXHAUSTED';$decision='CLEANUP_FINISHED_BLOCKED';$script:nextEvent='FINAL_VERIFY'}}
elseif($category -in @('transient','test','retryable')){if([string]::IsNullOrWhiteSpace([string]$failure.mitigation)){Add-Reason 'NO_CHANGE_RETRY_REJECTED';$decision='BLOCKED_WITH_EVIDENCE'}elseif($effectiveCount -ge 2){Add-Reason 'RETRY_LIMIT_REACHED';$decision='BLOCKED_WITH_EVIDENCE'}else{$decision='RETRYABLE';$retryAllowed=$true;$script:nextEvent='RETRY_WITH_MITIGATION';$effectiveCount++}}
elseif($category -eq 'dependency'){$decision='BLOCKED_DEPENDENCY';$script:nextEvent='DEPENDENCY_RESOLVED'}
elseif($category -in @('conflict','resource','shared-resource')){$decision='BLOCKED_CONFLICT';$script:nextEvent='RESOURCE_RELEASED'}
elseif($category -eq 'external'){$decision='BLOCKED_EXTERNAL';$script:nextEvent='EXTERNAL_RESOLVED'}
elseif($category -eq 'human'){$decision='BLOCKED_HUMAN';$script:nextEvent='HUMAN_DECISION'}
elseif($category -eq 'destructive'){$decision='BLOCKED_DESTRUCTIVE';$script:nextEvent='EXPLICIT_AUTHORIZATION'}
elseif($category -eq 'model'){$decision='MODEL_POLICY_BLOCKED';$script:nextEvent='MODEL_POLICY_RESOLVED'}
elseif($category -eq 'scope'){$decision='BLOCKED_SCOPE';$script:nextEvent='PLAN_REVISED'}
else{Add-Reason 'UNCLASSIFIED_FAILURE';$decision='BLOCKED_WITH_EVIDENCE'}
if($decision -eq 'RETRYABLE' -or $decision -like 'CLEANUP_ROUND_*'){Write-Result $true $decision $effectiveCount $retryAllowed $failure}else{if($decision -eq 'BLOCKED_WITH_EVIDENCE' -and $reasons.Count -eq 0){Add-Reason 'AUTOMATION_STOPPED'};Write-Result $false $decision $effectiveCount $retryAllowed $failure}
