[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$skillsRoot = Join-Path $root 'skills'
$installer = Join-Path $root 'scripts\Install-CodexSkillPackage.ps1'
$uninstaller = Join-Path $root 'scripts\Uninstall-CodexSkillPackage.ps1'
# Keep the bounded test root short enough for Windows PowerShell 5.1's
# legacy MAX_PATH behavior while retaining project-local isolation.
$tempBase = Join-Path $root '99_Temp\T03'
$runRoot = Join-Path $tempBase ([guid]::NewGuid().ToString('N'))

function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ASSERTION_FAILED:$Message" } }
function Get-Sha256 { param([string]$Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try { return (([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')).ToUpperInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Get-TreeHash { param([string]$Path); @(
    Get-ChildItem -LiteralPath $Path -File -Recurse | ForEach-Object {
        [pscustomobject]@{ relative_path = $_.FullName.Substring($Path.Length).TrimStart('\').Replace('\','/'); sha256 = Get-Sha256 -Path $_.FullName; length = $_.Length }
    } | Sort-Object relative_path
) }
function Invoke-ChildScript {
    param([string]$Script, [string[]]$Arguments)
    $hostExecutable = (Get-Process -Id $PID).Path
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $raw = @(& $hostExecutable -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    [pscustomobject]@{ Code = $code; Raw = @($raw | ForEach-Object { [string]$_ }) }
}

New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
try {
    foreach ($skill in @(Get-ChildItem -LiteralPath $skillsRoot -Directory | Sort-Object Name)) {
        $name = $skill.Name
        $installPath = Join-Path $runRoot "installed\$name"
        $evidencePath = Join-Path $runRoot "evidence\$name\install"
        $install = Invoke-ChildScript -Script $installer -Arguments @('-SourceSkillPath', $skill.FullName, '-InstalledSkillPath', $installPath, '-EvidencePath', $evidencePath)
        Assert-True ($install.Code -eq 0) "Install failed for ${name}: $($install.Raw -join ' | ')"
        Assert-True (Test-Path -LiteralPath (Join-Path $evidencePath 'result.json') -PathType Leaf) "Install receipt missing for ${name}"
        $sourceTree = @(Get-TreeHash -Path $skill.FullName)
        $installedTree = @(Get-TreeHash -Path $installPath)
        Assert-True (($sourceTree | ConvertTo-Json -Depth 5) -eq ($installedTree | ConvertTo-Json -Depth 5)) "SOURCE_INSTALL_PARITY failed for ${name}"
        $backupPath = Join-Path $runRoot "backup\$name"
        $uninstallEvidence = Join-Path $runRoot "evidence\$name\uninstall"
        $uninstall = Invoke-ChildScript -Script $uninstaller -Arguments @('-InstalledSkillPath', $installPath, '-BackupPath', $backupPath, '-EvidencePath', $uninstallEvidence)
        Assert-True ($uninstall.Code -eq 0) "Uninstall failed for ${name}: $($uninstall.Raw -join ' | ')"
        Assert-True (-not (Test-Path -LiteralPath $installPath)) "Installed path remains for ${name}"
        Assert-True (Test-Path -LiteralPath $backupPath -PathType Container) "Recoverable backup missing for ${name}"
    }
    Write-Output 'INSTALL_SMOKE=PASS'
    Write-Output 'SOURCE_INSTALL_PARITY=PASS'
    Write-Output 'UNINSTALL_ROLLBACK=PASS'
    exit 0
}
finally {
    if (Test-Path -LiteralPath $runRoot) {
        $resolved = [IO.Path]::GetFullPath($runRoot)
        $allowed = [IO.Path]::GetFullPath($tempBase)
        if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw "UNSAFE_CLEANUP:$resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
