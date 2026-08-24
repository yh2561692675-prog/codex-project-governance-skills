[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ASSERTION_FAILED: $Message" } }
function Assert-Equal { param($Actual, $Expected, [string]$Message); if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')" } }
function Assert-Contains { param([object[]]$Values, [string]$Expected, [string]$Message); Assert-True (@($Values | ForEach-Object { [string]$_ }) -contains $Expected) "$Message (missing '$Expected')" }
function Read-Json { param([string]$Path); Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON: $Path"; return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Invoke-Git { param([string[]]$Arguments); $o=@(& git -C $root @Arguments 2>$null); if($LASTEXITCODE -ne 0){throw "GIT_READ_FAILED: $($Arguments -join ' ')"}; return (($o | Select-Object -First 1).Trim()) }
function Write-Json { param([string]$Path, $Object); $Object | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8 }
function Invoke-Candidate { param([string]$InputPath, [string]$OutputPath); $raw=@(& $resolverPath -InputPath $InputPath -OutputPath $OutputPath 2>&1); $e=$LASTEXITCODE; $j=$null; if($raw.Count -gt 0){try{$j=(($raw|ForEach-Object{[string]$_})-join [Environment]::NewLine)|ConvertFrom-Json}catch{}}; return [pscustomobject]@{ExitCode=$e;Json=$j;Raw=$raw} }
function Hash-Canonical { param($Object); $ordered=[ordered]@{}; foreach($p in $Object.PSObject.Properties){if($p.Name -ne 'candidate_sha256'){$ordered[$p.Name]=$p.Value}}; $bytes=[Text.Encoding]::UTF8.GetBytes(($ordered|ConvertTo-Json -Depth 30 -Compress)); $sha=[Security.Cryptography.SHA256]::Create(); try{return([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToUpperInvariant()}finally{$sha.Dispose()} }

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$resolverPath = Join-Path $PSScriptRoot 'New-LightweightCandidateManifest.ps1'
$fixtureBase = Join-Path $root 'outputs\skill-packaging\lightweight-governance-v1_2\T04\test-fixtures'
$fixtureDir = Join-Path $fixtureBase ('run-' + [guid]::NewGuid().ToString('N'))
$planning = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs\future-development') -File | Where-Object {$_.Name -like '*V1.2.md'} | Sort-Object Length)

try {
    Assert-True (Test-Path -LiteralPath $resolverPath -PathType Leaf) 'candidate resolver must exist'
    Assert-True ($planning.Count -ge 2) 'V1.2 design and plan must exist'
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
    $design=$planning[0]; $plan=$planning[1]
    $branch=Invoke-Git @('branch','--show-current'); $head=Invoke-Git @('rev-parse','HEAD'); $dirtyLines=@(& git -C $root status --porcelain); $dirty=($dirtyLines.Count -gt 0)
    $policyPath=Join-Path $root 'config\lightweight-governance\risk-policy-v2.json'; $profileSchemaPath=Join-Path $root 'schemas\project-governance-profile-v1.1.schema.json'
    $dirtyFingerprint=([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes(($dirtyLines -join "`n"))) | ForEach-Object ToString x2) -join ''
    $inputPath=Join-Path $fixtureDir 'candidate-input.json'; $outputPath=Join-Path $fixtureDir 'candidate-valid.json'
    $input=[ordered]@{schema_version=1;project_id='fixture-content-media';project_root=$root;worktree=$root;branch=$branch;head=$head;dirty=$dirty;dirty_fingerprint=$dirtyFingerprint;design_path=$design.FullName;plan_path=$plan.FullName;design_hash=(Get-FileHash $design.FullName -Algorithm SHA256).Hash.ToUpperInvariant();plan_hash=(Get-FileHash $plan.FullName -Algorithm SHA256).Hash.ToUpperInvariant();policy_path=$policyPath;policy_hash=(Get-FileHash $policyPath -Algorithm SHA256).Hash.ToUpperInvariant();profile_schema_path=$profileSchemaPath;profile_schema_hash=(Get-FileHash $profileSchemaPath -Algorithm SHA256).Hash.ToUpperInvariant();delivery_target='ENGINEERING_ONLY';release_intent='NONE';review_policy='NONE';resolver_result=[ordered]@{governance_mode='LOCAL_AUTONOMOUS';terminal_state='LOCAL_CANDIDATE_READY';required_review=$false;layers=@([ordered]@{name='formal_release';status='NOT_APPLICABLE';applicability_reason='releaseIntent=NONE'})};changed_paths=@('src/example.ps1');tests=@([ordered]@{command='powershell.exe -NoProfile -File tests\example.Tests.ps1';exit_code=0});artifacts=@();risk_tier='LIGHTWEIGHT';rollback='Restore the prior candidate and re-run affected checks.'}
    Write-Json -Path $inputPath -Object $input
    $valid=Invoke-Candidate -InputPath $inputPath -OutputPath $outputPath
    Assert-Equal $valid.ExitCode 0 'valid candidate must exit 0'
    Assert-True ($null -ne $valid.Json.candidate) 'valid invocation must return candidate'
    $candidate=Read-Json -Path $outputPath
    Assert-Equal $candidate.project.project_id 'fixture-content-media' 'candidate project binding'
    Assert-Equal $candidate.identity.branch $branch 'candidate branch binding'
    Assert-Equal $candidate.identity.head $head 'candidate HEAD binding'
    Assert-Equal $candidate.identity.dirty $dirty 'candidate dirty binding'
    Assert-Equal $candidate.identity.source_head $head 'candidate source HEAD binding'
    Assert-Equal $candidate.identity.dirty_fingerprint $dirtyFingerprint 'candidate dirty fingerprint binding'
    Assert-Equal $candidate.risk_tier 'LIGHTWEIGHT' 'candidate risk tier'
    Assert-Equal $candidate.governance.terminal_state 'LOCAL_CANDIDATE_READY' 'candidate local terminal state'
    Assert-Equal $candidate.governance.required_review $false 'safe local candidate must not require review'
    Assert-Equal $candidate.governance.policy_hash $input.policy_hash 'candidate policy hash binding'
    Assert-Equal $candidate.governance.profile_schema_hash $input.profile_schema_hash 'candidate profile schema hash binding'
    Assert-Equal $candidate.governance.layers[0].status 'NOT_APPLICABLE' 'candidate layer applicability binding'
    Assert-Equal $candidate.planning.design_hash $input.design_hash 'candidate design hash'
    Assert-Equal $candidate.planning.plan_hash $input.plan_hash 'candidate plan hash'
    Assert-Equal $candidate.candidate_sha256 (Hash-Canonical -Object $candidate) 'candidate hash must be reproducible'
    Write-Output 'PASS candidate_identity_planning_tests_risk_rollback'

    $again=Invoke-Candidate -InputPath $inputPath -OutputPath $outputPath
    Assert-Equal $again.ExitCode 1 'existing candidate must not be overwritten'
    Assert-Contains @($again.Json.reason_codes) 'OUTPUT_EXISTS' 'create-only reason'
    Write-Output 'PASS candidate_create_only'

    $planningDrift=[ordered]@{}; foreach($p in $input.GetEnumerator()){$planningDrift[$p.Key]=$p.Value}; $planningDrift.design_hash=('0'*64)
    $driftInput=Join-Path $fixtureDir 'candidate-planning-drift.json'; $driftOutput=Join-Path $fixtureDir 'candidate-planning-drift.manifest.json'; Write-Json -Path $driftInput -Object $planningDrift
    $drift=Invoke-Candidate -InputPath $driftInput -OutputPath $driftOutput
    Assert-Equal $drift.ExitCode 1 'planning hash drift must exit 1'; Assert-Contains @($drift.Json.reason_codes) 'PLANNING_HASH_MISMATCH' 'planning drift reason'
    Write-Output 'PASS candidate_planning_hash_drift'

    $headDrift=[ordered]@{}; foreach($p in $input.GetEnumerator()){$headDrift[$p.Key]=$p.Value}; $headDrift.head=('0'*40)
    $headInput=Join-Path $fixtureDir 'candidate-head-drift.json'; $headOutput=Join-Path $fixtureDir 'candidate-head-drift.manifest.json'; Write-Json -Path $headInput -Object $headDrift
    $headResult=Invoke-Candidate -InputPath $headInput -OutputPath $headOutput
    Assert-Equal $headResult.ExitCode 1 'HEAD drift must exit 1'; Assert-Contains @($headResult.Json.reason_codes) 'GIT_HEAD_MISMATCH' 'HEAD drift reason'
    Write-Output 'PASS candidate_upstream_identity_drift'

    Write-Output 'CANDIDATE_MANIFEST_TESTS=PASS'
    exit 0
}
catch { Write-Error $_.Exception.Message; Write-Output 'CANDIDATE_MANIFEST_TESTS=FAIL'; exit 1 }
