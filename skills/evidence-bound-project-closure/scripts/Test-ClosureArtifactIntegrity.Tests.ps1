[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$validator = Join-Path $PSScriptRoot 'Test-ClosureArtifactIntegrity.ps1'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    Write-Error 'RED: Test-ClosureArtifactIntegrity.ps1 is missing.'
    exit 1
}

function Assert-Equal { param($Actual, $Expected, [string]$Message); if ($Actual -ne $Expected) { throw "ASSERTION_FAILED: $Message (expected '$Expected', got '$Actual')" } }
function Assert-Contains { param([object[]]$Values, [string]$Expected, [string]$Message); if (@($Values | ForEach-Object { [string]$_ }) -notcontains $Expected) { throw "ASSERTION_FAILED: $Message (missing '$Expected')" } }
function Write-Json { param([string]$Path, $Value); [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false))) }
function Hash-File { param([string]$Path); return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Invoke-Integrity { param([string]$Path); $raw=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator -ManifestPath $Path 2>&1); $exit=$LASTEXITCODE; $json=(($raw|ForEach-Object{[string]$_})-join [Environment]::NewLine)|ConvertFrom-Json; return [pscustomobject]@{ExitCode=$exit;Json=$json} }

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$tempRoot = Join-Path 'X:\Projects\01_Active\15_项目开发治理Skills\99_Temp\closure-integrity-v1_3' ('run-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $candidatePath = Join-Path $tempRoot 'candidate.json'
    $candidate = [ordered]@{ identity = [ordered]@{ head = ('A' * 40); source_head = ('A' * 40) } }
    Write-Json -Path $candidatePath -Value $candidate
    $candidateHash = Hash-File -Path $candidatePath
    $policyPath = Join-Path $root 'config\lightweight-governance\risk-policy-v2.json'
    $integrityPath = Join-Path $tempRoot 'integrity-valid.json'
    $validInput = [ordered]@{
        schema_version = 1
        preflight_status = 'READY'
        terminal_state = 'LOCAL_CANDIDATE_READY'
        delivery_target = 'ENGINEERING_ONLY'
        formal_release_status = 'NOT_APPLICABLE'
        candidate = [ordered]@{ path = $candidatePath; sha256 = $candidateHash; source_head = ('A' * 40) }
        policy = [ordered]@{ path = $policyPath; sha256 = (Hash-File -Path $policyPath) }
        required_references = @($policyPath)
        previous_terminal_state = ''
    }
    Write-Json -Path $integrityPath -Value $validInput
    $valid = Invoke-Integrity -Path $integrityPath
    Assert-Equal $valid.ExitCode 0 'Valid closure artifact must exit 0'
    Assert-Equal $valid.Json.valid $true 'Valid closure artifact must be valid'
    Write-Output 'PASS closure_integrity_valid'

    $template = [ordered]@{}; foreach($p in $validInput.GetEnumerator()){$template[$p.Key]=$p.Value}; $template.template_note='{{UNRESOLVED}}'
    $templatePath=Join-Path $tempRoot 'integrity-template.json'; Write-Json -Path $templatePath -Value $template
    $templateResult=Invoke-Integrity -Path $templatePath
    Assert-Equal $templateResult.ExitCode 1 'Template variable must fail'; Assert-Contains @($templateResult.Json.reason_codes) 'TEMPLATE_VARIABLE_REMAINS' 'Template reason'
    Write-Output 'PASS template_variable_blocked'

    $blocked=[ordered]@{}; foreach($p in $validInput.GetEnumerator()){$blocked[$p.Key]=$p.Value}; $blocked.preflight_status='BLOCKED'; $blockedPath=Join-Path $tempRoot 'integrity-blocked.json'; Write-Json -Path $blockedPath -Value $blocked
    $blockedResult=Invoke-Integrity -Path $blockedPath
    Assert-Equal $blockedResult.ExitCode 1 'Blocked preflight completion must fail'; Assert-Contains @($blockedResult.Json.reason_codes) 'BLOCKED_PREFLIGHT_COMPLETION' 'Blocked preflight reason'
    Write-Output 'PASS blocked_preflight_blocked'

    $drift=[ordered]@{}; foreach($p in $validInput.GetEnumerator()){$drift[$p.Key]=$p.Value}; $drift.candidate.source_head=('B'*40); $driftPath=Join-Path $tempRoot 'integrity-head-drift.json'; Write-Json -Path $driftPath -Value $drift
    $driftResult=Invoke-Integrity -Path $driftPath
    Assert-Equal $driftResult.ExitCode 1 'Source HEAD drift must fail'; Assert-Contains @($driftResult.Json.reason_codes) 'SOURCE_HEAD_DRIFT' 'Source head reason'
    Write-Output 'PASS source_head_drift_blocked'

    $formal=[ordered]@{}; foreach($p in $validInput.GetEnumerator()){$formal[$p.Key]=$p.Value}; $formal.delivery_target='FORMAL_RELEASE'; $formal.formal_release_status='NO_GO'; $formalPath=Join-Path $tempRoot 'integrity-formal.json'; Write-Json -Path $formalPath -Value $formal
    $formalResult=Invoke-Integrity -Path $formalPath
    Assert-Equal $formalResult.ExitCode 1 'Formal release missing gates must fail'; Assert-Contains @($formalResult.Json.reason_codes) 'FORMAL_RELEASE_GATE_MISSING' 'Formal gate reason'
    Write-Output 'PASS formal_release_gate_blocked'

    $revival=[ordered]@{}; foreach($p in $validInput.GetEnumerator()){$revival[$p.Key]=$p.Value}; $revival.previous_terminal_state='BLOCKED'; $revivalPath=Join-Path $tempRoot 'integrity-revival.json'; Write-Json -Path $revivalPath -Value $revival
    $revivalResult=Invoke-Integrity -Path $revivalPath
    Assert-Equal $revivalResult.ExitCode 1 'Blocked terminal revival must fail'; Assert-Contains @($revivalResult.Json.reason_codes) 'TERMINAL_REVIVAL_BLOCKED' 'Terminal revival reason'
    Write-Output 'PASS terminal_revival_blocked'

    Write-Output 'CLOSURE_ARTIFACT_INTEGRITY_TESTS=PASS'
    exit 0
}
catch { Write-Error $_.Exception.Message; Write-Output 'CLOSURE_ARTIFACT_INTEGRITY_TESTS=FAIL'; exit 1 }
finally { if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force } }
