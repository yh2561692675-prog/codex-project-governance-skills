[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$implementation=Join-Path $PSScriptRoot 'Invoke-LongRunStateTransition.ps1'
if(-not(Test-Path -LiteralPath $implementation -PathType Leaf)){Write-Error 'RED: Invoke-LongRunStateTransition.ps1 is missing.';exit 1}
function Assert-Equal{param($Actual,$Expected,[string]$Message);if($Actual -ne $Expected){throw "$Message Expected=[$Expected] Actual=[$Actual]"}}
function Assert-Contains{param([object[]]$Actual,[string]$Expected,[string]$Message);if($Actual -notcontains $Expected){throw "$Message Missing=[$Expected] Actual=[$($Actual -join ',')]"}}
function Invoke-Transition{param([string]$StatePath,[string]$Event,[string]$OutputPath);$old=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$raw=&powershell.exe -NoProfile -ExecutionPolicy Bypass -File $implementation -StatePath $StatePath -Event $Event -OutputPath $OutputPath 2>&1;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old};$lines=@($raw|ForEach-Object{[string]$_});$start=-1;$end=-1;for($i=0;$i -lt $lines.Count;$i++){if($start-lt 0-and$lines[$i].TrimStart().StartsWith('{')){$start=$i};if($lines[$i].TrimEnd().EndsWith('}')){$end=$i}};$json=if($start-ge 0-and$end-ge $start){(($lines[$start..$end]-join [Environment]::NewLine)|ConvertFrom-Json)}else{$null};[pscustomobject]@{Code=$code;Json=$json}}
function New-State{param([string]$Path,[string]$State);[ordered]@{schema_version=1;run_id='state-fixture';state=$State;task_id='T01';updated_at_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $Path -Encoding utf8}
$base=[System.IO.Path]::GetFullPath('X:\Projects\01_Active\15_项目开发治理Skills\99_Temp\long-run-v1_1\T06');$fixture=Join-Path $base ('state-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $fixture -Force|Out-Null;$state=Join-Path $fixture 'state.json'
try{
    New-State -Path $state -State 'PRECHECK';$r1=Invoke-Transition -StatePath $state -Event 'PRECHECK_PASS' -OutputPath (Join-Path $fixture 's1.json');Assert-Equal $r1.Code 0 'PRECHECK_PASS must succeed.';Assert-Equal $r1.Json.state 'PLAN_GATE' 'PRECHECK transition.'
    $r2=Invoke-Transition -StatePath (Join-Path $fixture 's1.json') -Event 'PLAN_READY' -OutputPath (Join-Path $fixture 's2.json');Assert-Equal $r2.Json.state 'RUN_INITIALIZED' 'PLAN_GATE transition.'
    $r3=Invoke-Transition -StatePath (Join-Path $fixture 's2.json') -Event 'RUN_STARTED' -OutputPath (Join-Path $fixture 's3.json');Assert-Equal $r3.Json.state 'TASK_SELECTED' 'Run initialization transition.'
    $r4=Invoke-Transition -StatePath (Join-Path $fixture 's3.json') -Event 'IMPLEMENTATION_STARTED' -OutputPath (Join-Path $fixture 's4.json');Assert-Equal $r4.Json.state 'TASK_IMPLEMENTING' 'Task implementation transition.'
    $r5=Invoke-Transition -StatePath (Join-Path $fixture 's4.json') -Event 'VERIFICATION_STARTED' -OutputPath (Join-Path $fixture 's5.json');Assert-Equal $r5.Json.state 'TASK_VERIFYING' 'Verification transition.'
    $r6=Invoke-Transition -StatePath (Join-Path $fixture 's5.json') -Event 'VERIFICATION_PASSED' -OutputPath (Join-Path $fixture 's6.json');Assert-Equal $r6.Json.state 'CHECKPOINT_WRITTEN' 'Checkpoint transition.'
    $r7=Invoke-Transition -StatePath (Join-Path $fixture 's6.json') -Event 'TASK_CHECKPOINTED' -OutputPath (Join-Path $fixture 's7.json');Assert-Equal $r7.Json.state 'TASK_SELECTED' 'Next task transition.'
    New-State -Path $state -State 'TASK_VERIFYING';$retry=Invoke-Transition -StatePath $state -Event 'RETRYABLE_FAILURE' -OutputPath (Join-Path $fixture 'retry.json');Assert-Equal $retry.Json.state 'RETRY_PENDING' 'Retry transition.'
    $blocked=Invoke-Transition -StatePath $state -Event 'MODEL_POLICY_BLOCKED' -OutputPath (Join-Path $fixture 'blocked.json');Assert-Equal $blocked.Json.state 'BLOCKED_MODEL' 'Model blocker transition.'
    $illegal=Invoke-Transition -StatePath $state -Event 'FINAL_VERIFY_PASS' -OutputPath (Join-Path $fixture 'illegal.json');Assert-Equal $illegal.Code 1 'Illegal transition must fail.';Assert-Contains @($illegal.Json.reason_codes) 'INVALID_TRANSITION' 'Illegal transition reason.'
    New-State -Path $state -State 'WAIT_HUMAN';$terminal=Invoke-Transition -StatePath $state -Event 'RUN_STARTED' -OutputPath (Join-Path $fixture 'terminal.json');Assert-Equal $terminal.Code 1 'Terminal state must not revive.';Assert-Contains @($terminal.Json.reason_codes) 'TERMINAL_STATE' 'Terminal reason.'
    New-State -Path $state -State 'CLEANUP_ROUND_1';$c1=Invoke-Transition -StatePath $state -Event 'CLEANUP_1_COMPLETE' -OutputPath (Join-Path $fixture 'c2.json');Assert-Equal $c1.Json.state 'CLEANUP_ROUND_2' 'Cleanup round one transition.'
    $c2=Invoke-Transition -StatePath (Join-Path $fixture 'c2.json') -Event 'CLEANUP_2_COMPLETE' -OutputPath (Join-Path $fixture 'final.json');Assert-Equal $c2.Json.state 'FINAL_VERIFY' 'Cleanup round two transition.'
    Write-Output 'TEST_LONG_RUN_STATE_TRANSITION=PASS';exit 0
}finally{if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}}
