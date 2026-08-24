[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [switch]$FreshInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$candidate = [IO.Path]::GetFullPath($CandidatePath)
if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "CANDIDATE_MISSING:$candidate" }

function Read-JsonStrict {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON_MISSING:$Path" }
    return [IO.File]::ReadAllText($Path, (New-Object Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
}

function Get-Sha256 {
    param([string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { return (($hasher.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '') }
        finally { $hasher.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Invoke-Child {
    param([string]$ScriptPath, [string[]]$Arguments)
    $hostPath = (Get-Process -Id $PID).Path
    $raw = @(& $hostPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Code = $code; Output = @($raw | ForEach-Object { [string]$_ }) }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED:$Message" }
}

$manifest = Read-JsonStrict (Join-Path $candidate 'candidate-manifest.json')
Assert-True ([string]$manifest.candidate_type -eq 'release-candidate') 'candidate_type'
Assert-True ([string]$manifest.version -eq '0.1.0') 'version'
Assert-True ([string]$manifest.project_name -eq 'Project Development Governance') 'project_name'
Assert-True ([string]$manifest.source_commit -match '^[0-9a-f]{40}$') 'source_commit'
Assert-True (@($manifest.skills).Count -ge 1) 'skills'
Assert-True (@($manifest.assets).Count -ge 3) 'assets'

$checksumLines = @(Get-Content -LiteralPath (Join-Path $candidate 'checksums.sha256') -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$checksumMap = @{}
foreach ($line in $checksumLines) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "CHECKSUM_LINE_INVALID:$line" }
    $checksumMap[$Matches[2]] = $Matches[1]
}
foreach ($asset in @($manifest.assets)) {
    $relative = ([string]$asset.path).Replace('/', '\')
    $path = Join-Path $candidate $relative
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "asset_missing:$relative"
    $actual = Get-Sha256 $path
    Assert-True ($actual -eq [string]$asset.sha256) "asset_hash:$relative"
    Assert-True ($checksumMap.ContainsKey([string]$asset.path)) "checksum_missing:$($asset.path)"
    Assert-True ($checksumMap[[string]$asset.path] -eq $actual) "checksum_mismatch:$($asset.path)"
}
Write-Output 'ASSET_HASH_PARITY=PASS'

$scratch = Join-Path $candidate ('.verification-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$sourceArchiveRecord = @($manifest.assets | Where-Object { [string]$_.kind -eq 'source_archive' }) | Select-Object -First 1
Assert-True ($null -ne $sourceArchiveRecord) 'source_archive_record'
$sourceArchive = Join-Path $candidate ([string]$sourceArchiveRecord.path).Replace('/', '\')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceExtract = Join-Path $scratch 'source'
[IO.Compression.ZipFile]::ExtractToDirectory($sourceArchive, $sourceExtract)
$archiveRoot = Join-Path $sourceExtract ('project-development-governance-v' + [string]$manifest.version)
Assert-True (Test-Path -LiteralPath $archiveRoot -PathType Container) 'source_archive_root'
$archiveFiles = @(Get-ChildItem -LiteralPath $archiveRoot -File -Recurse)
Assert-True ($archiveFiles.Count -gt 20) 'source_archive_not_populated'
foreach ($file in $archiveFiles) {
    $relative = $file.FullName.Substring($archiveRoot.Length).TrimStart('\').Replace('\', '/')
    Assert-True ($relative -notmatch '(^|/)(outputs|dist|99_Temp|\.codex|\.git)(/|$)') "forbidden_archive_path:$relative"
    $textExtensions = @('.md', '.yml', '.yaml', '.json', '.ps1', '.toml')
    if ($textExtensions -contains $file.Extension.ToLowerInvariant()) {
        $text = [IO.File]::ReadAllText($file.FullName, (New-Object Text.UTF8Encoding($false, $true)))
        $textForScan = $text
        if ($relative -eq 'scripts/Install-CodexSkillPackage.Tests.ps1') {
            $fixturePrefix = ('X:' + '\Projects\01_Active')
            $textForScan = $textForScan.Replace($fixturePrefix, '<X_PROJECTS_FIXTURE_ROOT>')
        }
        $xProjectsPrefix = ('X:' + '\Projects\')
        $unsafePathPattern = '(?i)(?:C:\\Users\\|' + [regex]::Escape($xProjectsPrefix) + '|F:\\|/Users/|/home/|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,})'
        Assert-True ($textForScan -notmatch $unsafePathPattern) "unsafe_archive_text:$relative"
    }
}

$layout = Invoke-Child -ScriptPath (Join-Path $archiveRoot 'scripts\Test-SkillPackageLayout.ps1') -Arguments @()
Assert-True ($layout.Code -eq 0) ('layout:' + ($layout.Output -join ' '))
$runner = Invoke-Child -ScriptPath (Join-Path $archiveRoot 'tests\Invoke-CIMatrix.ps1') -Arguments @('-Mode', 'Runner', '-ArtifactRoot', (Join-Path $scratch 'ci-runner'))
Assert-True ($runner.Code -eq 0) ('runner:' + ($runner.Output -join ' '))
$local = Invoke-Child -ScriptPath (Join-Path $archiveRoot 'tests\Invoke-CIMatrix.ps1') -Arguments @('-Mode', 'LocalContract', '-ArtifactRoot', (Join-Path $scratch 'ci-local'))
Assert-True ($local.Code -eq 0) ('local:' + ($local.Output -join ' '))
Write-Output 'CORE_SMOKE=PASS'

$behaviorOutput = Join-Path $scratch 'behavior'
$behavior = Invoke-Child -ScriptPath (Join-Path $archiveRoot 'scripts\Invoke-GovernanceBehaviorEvaluation.ps1') -Arguments @(
    '-Baseline', (Join-Path $archiveRoot 'evaluations\baseline'),
    '-Candidate', $archiveRoot,
    '-OutputPath', $behaviorOutput
)
Assert-True ($behavior.Code -eq 0) ('behavior:' + ($behavior.Output -join ' '))
Write-Output 'BEHAVIOR_SMOKE=PASS'

if ($FreshInstall) {
    $skillName = [string]$manifest.skills[0]
    $sourceSkill = Join-Path $archiveRoot ('skills\' + $skillName)
    $installedSkill = Join-Path $scratch ('codex-home\skills\' + $skillName)
    $installEvidence = Join-Path $scratch 'install-evidence'
    $installScript = Join-Path $archiveRoot 'scripts\Install-CodexSkillPackage.ps1'
    $install = Invoke-Child -ScriptPath $installScript -Arguments @('-SourceSkillPath', $sourceSkill, '-InstalledSkillPath', $installedSkill, '-EvidencePath', $installEvidence)
    Assert-True ($install.Code -eq 0) ('install:' + ($install.Output -join ' '))
    $receipt = Read-JsonStrict (Join-Path $installEvidence 'result.json')
    Assert-True ([string]$receipt.install_status -eq 'PASS') 'install_status'
    Assert-True ([string]$receipt.source_install_parity -eq 'PASS') 'source_install_parity'
    $uninstallEvidence = Join-Path $scratch 'uninstall-evidence'
    $backupPath = Join-Path $scratch ('backup\' + $skillName)
    $uninstallScript = Join-Path $archiveRoot 'scripts\Uninstall-CodexSkillPackage.ps1'
    $uninstall = Invoke-Child -ScriptPath $uninstallScript -Arguments @('-InstalledSkillPath', $installedSkill, '-BackupPath', $backupPath, '-EvidencePath', $uninstallEvidence)
    Assert-True ($uninstall.Code -eq 0) ('uninstall:' + ($uninstall.Output -join ' '))
    Assert-True (-not (Test-Path -LiteralPath $installedSkill)) 'uninstall_target_removed'
    Write-Output 'FRESH_INSTALL=PASS'
}

$result = [ordered]@{
    schema_version = 1
    candidate_path = $candidate
    source_commit = [string]$manifest.source_commit
    asset_hash_parity = 'PASS'
    core_smoke = 'PASS'
    behavior_smoke = 'PASS'
    fresh_install = if ($FreshInstall) { 'PASS' } else { 'NOT_RUN' }
    verified_at_utc = [DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $candidate 'verification-result.json'), ($result | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Write-Output 'RELEASE_CANDIDATE=PASS'

