[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfilePath,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$DesignHash,
    [Parameter(Mandatory = $true)][string]$PlanHash,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$Reasoning,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$reasons = New-Object 'System.Collections.Generic.List[string]'
function Add-Reason { param([string]$Code); if(-not $reasons.Contains($Code)){[void]$reasons.Add($Code)} }
function Get-Field { param($Object,[string]$Name); if($null -eq $Object){return $null};$p=$Object.PSObject.Properties[$Name];if($null -eq $p){return $null};return $p.Value }
function Resolve-Full { param([string]$Path); try{return [System.IO.Path]::GetFullPath($Path)}catch{return $null} }
function Within { param([string]$Path,[string]$Root);if($null -eq $Path -or $null -eq $Root){return $false};$p=(Resolve-Full $Path).TrimEnd('\');$r=(Resolve-Full $Root).TrimEnd('\');return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase)-or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase) }
function Write-ResultAndExit { param([bool]$Valid,$Manifest);$result=[ordered]@{schema_version=1;valid=$Valid;reason_codes=@($reasons);manifest=$Manifest};$result|ConvertTo-Json -Depth 20;if($Valid){exit 0}else{exit 1} }

$profileFull=Resolve-Full $ProfilePath;$rootFull=Resolve-Full $ProjectRoot;$outputFull=Resolve-Full $OutputPath
if($null -eq $profileFull -or $null -eq $rootFull -or $null -eq $outputFull){Add-Reason 'PATH_INVALID';Write-ResultAndExit $false $null}
if(-not (Test-Path -LiteralPath $profileFull -PathType Leaf)){Add-Reason 'PROFILE_MISSING';Write-ResultAndExit $false $null}
if(-not (Test-Path -LiteralPath $rootFull -PathType Container)){Add-Reason 'PROJECT_ROOT_MISSING';Write-ResultAndExit $false $null}
if(-not (Within $outputFull $rootFull)){Add-Reason 'OUTPUT_OUTSIDE_PROJECT_ROOT'}
if(-not (Within $profileFull $rootFull)){Add-Reason 'PROFILE_OUTSIDE_PROJECT_ROOT'}
if(Test-Path -LiteralPath $outputFull){Add-Reason 'OUTPUT_EXISTS'}
if($DesignHash -notmatch '^[0-9A-Fa-f]{64}$' -or $PlanHash -notmatch '^[0-9A-Fa-f]{64}$'){Add-Reason 'PLANNING_HASH_INVALID'}
if($Model -ne 'gpt-5.6-luna' -or $Reasoning -ne 'xhigh'){Add-Reason 'MODEL_POLICY_BLOCKED'}

$profile=$null
try{$profile=Get-Content -LiteralPath $profileFull -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'PROFILE_INVALID_JSON'}
if($null -ne $profile){
    $profileRoot=Resolve-Full ([string](Get-Field $profile 'projectRoot'))
    if($null -ne $profileRoot -and -not $profileRoot.Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)){Add-Reason 'PROJECT_ROOT_MISMATCH'}
    $policy=Get-Field $profile 'modelPolicy';$impl=Get-Field $policy 'implementation'
    if((Get-Field $impl 'model') -ne 'gpt-5.6-luna' -or (Get-Field $impl 'reasoning') -ne 'xhigh'){Add-Reason 'MODEL_POLICY_BLOCKED'}
}

$receiptPath=Join-Path (Split-Path -Parent $profileFull) 'model-receipt.json';$receipt=$null
if(-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)){Add-Reason 'MODEL_POLICY_BLOCKED'}else{try{$receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{Add-Reason 'MODEL_POLICY_BLOCKED'}}
if($null -ne $receipt){
    if((Get-Field $receipt 'model') -ne 'gpt-5.6-luna' -or (Get-Field $receipt 'reasoning') -ne 'xhigh' -or [string]::IsNullOrWhiteSpace([string](Get-Field $receipt 'task_id'))){Add-Reason 'MODEL_POLICY_BLOCKED'}
    if((Get-Field $receipt 'project_root') -and -not ([string](Get-Field $receipt 'project_root')).Equals($rootFull,[StringComparison]::OrdinalIgnoreCase)){Add-Reason 'MODEL_RECEIPT_MISMATCH'}
    if((Get-Field $receipt 'design_hash') -and (Get-Field $receipt 'design_hash') -ne $DesignHash){Add-Reason 'MODEL_RECEIPT_MISMATCH'}
    if((Get-Field $receipt 'plan_hash') -and (Get-Field $receipt 'plan_hash') -ne $PlanHash){Add-Reason 'MODEL_RECEIPT_MISMATCH'}
}

if($reasons.Count -gt 0){Write-ResultAndExit $false $null}

$runId=[guid]::NewGuid().ToString('N');$outputDirectory=Split-Path -Parent $outputFull
if(-not (Test-Path -LiteralPath $outputDirectory -PathType Container)){New-Item -ItemType Directory -Path $outputDirectory -Force|Out-Null}
$manifest=[ordered]@{
    schema_version=1;valid=$true;run_id=$runId;created_at_utc=[DateTime]::UtcNow.ToString('o');phase='implementation';project_root=$rootFull;profile_path=$profileFull
    design_hash=$DesignHash.ToUpperInvariant();plan_hash=$PlanHash.ToUpperInvariant();model=$Model;reasoning=$Reasoning;requested_model=$Model;requested_reasoning=$Reasoning
    model_receipt_path=$receiptPath;model_receipt=$receipt;output_path=$outputFull
    git=Get-Field $profile 'gitIdentity'
    goal=[ordered]@{project_id=(Get-Field $profile 'projectId');implementation_phase='approved-itemized-plan';single_project=$true;single_phase=$true;cleanup_rounds=2;stopping_condition='All approved plan tasks, two cleanup rounds, final verification, and local review package complete; human gates remain pending.';verification_cycle='RED -> GREEN -> REFACTOR -> fresh verification';automatic_scope='Local project-scoped code, tests, docs, candidate build, checkpoints, and evidence only.';human_gates=@('real data','human acceptance','formal release','main branch merge','destructive or external action')}
    state_path=(Join-Path $outputDirectory 'state.json');checkpoints_directory=(Join-Path $outputDirectory 'checkpoints');evidence_directory=(Join-Path $outputDirectory 'task-evidence')
}
$json=$manifest|ConvertTo-Json -Depth 20
try{$stream=[System.IO.File]::Open($outputFull,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None);try{$bytes=[Text.Encoding]::UTF8.GetBytes($json);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}catch{Add-Reason 'OUTPUT_CREATE_FAILED';Write-ResultAndExit $false $null}
Write-ResultAndExit $true $manifest
