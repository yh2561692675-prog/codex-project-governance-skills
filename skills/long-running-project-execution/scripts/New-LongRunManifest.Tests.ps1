[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$implementation = Join-Path $PSScriptRoot 'New-LongRunManifest.ps1'
if (-not (Test-Path -LiteralPath $implementation -PathType Leaf)) {
    Write-Error 'RED: New-LongRunManifest.ps1 is missing.'
    exit 1
}

function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -ne $Expected){throw "$Message Expected=[$Expected] Actual=[$Actual]"} }
function Assert-Contains { param([object[]]$Actual,[string]$Expected,[string]$Message); if($Actual -notcontains $Expected){throw "$Message Missing=[$Expected] Actual=[$($Actual -join ',')]"} }
function Invoke-Manifest {
    param([hashtable]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $implementation @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    $lines = @($raw | ForEach-Object { [string]$_ }); $start=-1; $end=-1
    for($i=0;$i -lt $lines.Count;$i++){if($start -lt 0 -and $lines[$i].TrimStart().StartsWith('{')){$start=$i};if($lines[$i].TrimEnd().EndsWith('}')){$end=$i}}
    $json = if($start -ge 0 -and $end -ge $start){(($lines[$start..$end] -join [Environment]::NewLine)|ConvertFrom-Json)}else{$null}
    [pscustomobject]@{Code=$code;Json=$json;Raw=$raw}
}
function New-Fixture {
    param([string]$Root,[string]$ReceiptModel='gpt-5.6-luna',[string]$ReceiptReasoning='xhigh')
    $longRun=Join-Path $Root '.codex\long-run';New-Item -ItemType Directory -Path $longRun -Force|Out-Null
    $profile=[ordered]@{
        schemaVersion='1.0';projectId='manifest-fixture';projectRoot=$Root
        designPath='docs\future-development\design.md';planPath='docs\future-development\plan.md'
        allowedWritePaths=@('src');protectedPaths=@('.git');runtimeRoot=(Join-Path $Root 'runtime');evidenceRoot=(Join-Path $Root 'evidence')
        sharedResources=@('port');defaultVerificationCommands=@('pwsh -File tests.ps1');humanGates=@('release')
        modelPolicy=[ordered]@{design=[ordered]@{model='gpt-5.6-sol';reasoning='high'};implementation=[ordered]@{model='gpt-5.6-luna';reasoning='xhigh'}}
        maxEffectiveRetries=2;unfinishedCleanupRounds=2;gitIdentity=[ordered]@{root=$Root;worktree=$Root;branch='codex/fixture';head=('1'*40)}
    }
    $profile|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $longRun 'execution-profile.json') -Encoding utf8
    [ordered]@{task_id='manifest-fixture-task';model=$ReceiptModel;reasoning=$ReceiptReasoning;project_root=$Root;branch='codex/fixture';head=('1'*40);design_hash=('A'*64);plan_hash=('B'*64)}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $longRun 'model-receipt.json') -Encoding utf8
}

$base=[System.IO.Path]::GetFullPath('X:\Projects\01_Active\15_项目开发治理Skills\99_Temp\long-run-v1_1\T05');$fixture=Join-Path $base ('manifest-'+[guid]::NewGuid().ToString('N'));New-Fixture -Root $fixture
$profilePath=Join-Path $fixture '.codex\long-run\execution-profile.json';$output=Join-Path $fixture 'run\run-manifest.json';$design=('A'*64);$plan=('B'*64)
try {
    $valid=Invoke-Manifest -Arguments @{ProfilePath=$profilePath;ProjectRoot=$fixture;DesignHash=$design;PlanHash=$plan;Model='gpt-5.6-luna';Reasoning='xhigh';OutputPath=$output}
    Assert-Equal $valid.Code 0 'Valid manifest must exit zero.';Assert-Equal $valid.Json.valid $true 'Valid manifest must be accepted.'
    Assert-Equal $valid.Json.manifest.model 'gpt-5.6-luna' 'Manifest model identity.';Assert-Equal $valid.Json.manifest.reasoning 'xhigh' 'Manifest reasoning identity.'
    Assert-Equal $valid.Json.manifest.goal.project_id 'manifest-fixture' 'Goal must bind one project.';Assert-Equal $valid.Json.manifest.goal.cleanup_rounds 2 'Goal cleanup bound.'
    Assert-Equal (Test-Path -LiteralPath $output -PathType Leaf) $true 'Manifest file must be created.'

    $existing=Invoke-Manifest -Arguments @{ProfilePath=$profilePath;ProjectRoot=$fixture;DesignHash=$design;PlanHash=$plan;Model='gpt-5.6-luna';Reasoning='xhigh';OutputPath=$output}
    Assert-Equal $existing.Code 1 'Existing output must be create-only blocked.';Assert-Contains @($existing.Json.reason_codes) 'OUTPUT_EXISTS' 'Create-only reason.'

    $wrongModel=Invoke-Manifest -Arguments @{ProfilePath=$profilePath;ProjectRoot=$fixture;DesignHash=$design;PlanHash=$plan;Model='gpt-5.6-sol';Reasoning='high';OutputPath=(Join-Path $fixture 'run\wrong-model.json')}
    Assert-Equal $wrongModel.Code 1 'Wrong implementation model must fail.';Assert-Contains @($wrongModel.Json.reason_codes) 'MODEL_POLICY_BLOCKED' 'Model blocker.'

    Remove-Item -LiteralPath (Join-Path $fixture '.codex\long-run\model-receipt.json') -Force
    $missingReceipt=Invoke-Manifest -Arguments @{ProfilePath=$profilePath;ProjectRoot=$fixture;DesignHash=$design;PlanHash=$plan;Model='gpt-5.6-luna';Reasoning='xhigh';OutputPath=(Join-Path $fixture 'run\missing-receipt.json')}
    Assert-Equal $missingReceipt.Code 1 'Missing receipt must fail.';Assert-Contains @($missingReceipt.Json.reason_codes) 'MODEL_POLICY_BLOCKED' 'Missing receipt blocker.'

    $emptyHash=Invoke-Manifest -Arguments @{ProfilePath=$profilePath;ProjectRoot=$fixture;DesignHash=('A'*63);PlanHash=$plan;Model='gpt-5.6-luna';Reasoning='xhigh';OutputPath=(Join-Path $fixture 'run\empty-hash.json')}
    Assert-Equal $emptyHash.Code 1 'Invalid design hash must fail.';Assert-Contains @($emptyHash.Json.reason_codes) 'PLANNING_HASH_INVALID' 'Planning hash reason.'

    Write-Output 'TEST_LONG_RUN_MANIFEST=PASS';exit 0
}
finally { if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force} }
