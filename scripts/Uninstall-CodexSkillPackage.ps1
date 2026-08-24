[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstalledSkillPath,
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$installed = $null
$backup = $null
$evidence = $null

function Write-JsonFile {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
}

try {
    $installed = [IO.Path]::GetFullPath($InstalledSkillPath).TrimEnd('\')
    $backup = [IO.Path]::GetFullPath($BackupPath).TrimEnd('\')
    $evidence = [IO.Path]::GetFullPath($EvidencePath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $installed -PathType Container)) { throw "INSTALLED_SKILL_MISSING:$installed" }
    if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $evidence)) { throw 'BACKUP_OR_EVIDENCE_PATH_EXISTS' }
    $parent = Split-Path -Parent $backup
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    Move-Item -LiteralPath $installed -Destination $backup
    $result = [ordered]@{
        uninstall_status = 'PASS'
        installed_path = $installed
        backup_path = $backup
        recoverable = $true
        evidence_path = $evidence
    }
    Write-JsonFile -Path (Join-Path $evidence 'result.json') -Value $result
    $result | ConvertTo-Json -Depth 12 -Compress
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ($evidence -and (Test-Path -LiteralPath $evidence -PathType Container)) {
        Write-JsonFile -Path (Join-Path $evidence 'result.json') -Value ([ordered]@{ uninstall_status = 'BLOCKED'; error = $message })
    }
    Write-Error $message
    exit 1
}
