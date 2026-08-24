[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceSkillPath,
    [Parameter(Mandatory = $true)][string]$InstalledSkillPath,
    [Parameter(Mandatory = $true)][string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
# Keep transactional directory names short enough for Windows PowerShell 5.1
# when callers use a deeply nested X-drive worktree path.
$runId = [guid]::NewGuid().ToString('N').Substring(0, 12)
$stagingPath = $null
$installedParent = $null
$sourcePackage = $null
$evidenceRoot = $null
$rollbackDirectory = $null
$failedNewDirectory = $null
$backupRunRoot = $null
$installedMoved = $false
$newInstalledMoved = $false

function Read-SkillName {
    param([Parameter(Mandatory = $true)][string]$Root)
    $skillPath = Join-Path $Root 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
        throw "SKILL_IDENTITY_MISSING:$skillPath"
    }
    try {
        $text = [System.IO.File]::ReadAllText($skillPath, $script:utf8)
    }
    catch [System.Text.DecoderFallbackException] {
        throw "SKILL_IDENTITY_INVALID_UTF8:$skillPath"
    }
    $match = [regex]::Match($text, '(?m)^name:\s*([a-z0-9-]+)\s*$')
    if (-not $match.Success) { throw "SKILL_IDENTITY_INVALID:$skillPath" }
    return $match.Groups[1].Value
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return (([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')).ToUpperInvariant()
    }
    finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}

function Get-TreeManifest {
    param([Parameter(Mandatory = $true)][string]$Root)
    return @(
        Get-ChildItem -LiteralPath $Root -File -Recurse |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    relative_path = $_.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
                    sha256 = Get-Sha256 -Path $_.FullName
                    length = $_.Length
                }
            } |
            Sort-Object relative_path
    )
}

function Test-ManifestEqual {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Left,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Right
    )
    if ($Left.Count -ne $Right.Count) { return $false }
    for ($index = 0; $index -lt $Left.Count; $index++) {
        if ($Left[$index].relative_path -cne $Right[$index].relative_path -or
            $Left[$index].sha256 -cne $Right[$index].sha256 -or
            [long]$Left[$index].length -ne [long]$Right[$index].length) {
            return $false
        }
    }
    return $true
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

try {
    if (-not (Test-Path -LiteralPath $SourceSkillPath -PathType Container)) {
        throw "SOURCE_SKILL_MISSING:$SourceSkillPath"
    }
    $sourceRoot = (Resolve-Path -LiteralPath $SourceSkillPath).Path.TrimEnd('\')
    $installedRoot = [System.IO.Path]::GetFullPath($InstalledSkillPath).TrimEnd('\')
    $evidenceRoot = [System.IO.Path]::GetFullPath($EvidencePath).TrimEnd('\')
    if (Test-Path -LiteralPath $evidenceRoot) { throw "EVIDENCE_PATH_EXISTS:$evidenceRoot" }
    if ($sourceRoot.Equals($installedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'SOURCE_AND_INSTALLED_PATH_MATCH'
    }

    $sourceName = Read-SkillName -Root $sourceRoot
    if ((Split-Path -Leaf $installedRoot) -cne $sourceName) {
        throw "INSTALLED_PATH_NAME_MISMATCH:$sourceName"
    }
    if (Test-Path -LiteralPath $installedRoot) {
        $installedName = Read-SkillName -Root $installedRoot
        if ($installedName -cne $sourceName) {
            throw "INSTALLED_SKILL_IDENTITY_MISMATCH:$installedName"
        }
    }

    # PowerShell 5.1 can return an empty Split-Path parent for some fully
    # qualified X-drive paths. Use the .NET path contract for both shells.
    $installedParent = [System.IO.Path]::GetDirectoryName($installedRoot)
    if ([string]::IsNullOrWhiteSpace($installedParent)) { throw "INSTALLED_PARENT_INVALID:$installedRoot" }
    if (-not (Test-Path -LiteralPath $installedParent -PathType Container)) {
        New-Item -ItemType Directory -Path $installedParent -Force | Out-Null
    }
    $codexHomeLikeRoot = [System.IO.Path]::GetDirectoryName($installedParent)
    if ([string]::IsNullOrWhiteSpace($codexHomeLikeRoot)) { throw "BACKUP_ROOT_INVALID:$installedParent" }
    $backupRoot = Join-Path -Path $codexHomeLikeRoot -ChildPath 'skills-backups'
    $backupRunRoot = Join-Path -Path (Join-Path -Path $backupRoot -ChildPath $sourceName) -ChildPath $runId
    $rollbackDirectory = Join-Path -Path $backupRunRoot -ChildPath 'installed-before'
    $failedNewDirectory = Join-Path -Path $backupRunRoot -ChildPath 'failed-new'
    $stagingName = '.' + $sourceName + '.staging-' + $runId
    $stagingPath = Join-Path -Path $installedParent -ChildPath $stagingName
    if (-not [System.IO.Path]::IsPathRooted($stagingPath)) { throw "STAGING_PATH_NOT_ROOTED:$stagingPath" }
    foreach ($reservedPath in @($backupRunRoot, $rollbackDirectory, $failedNewDirectory, $stagingPath)) {
        if (Test-Path -LiteralPath $reservedPath) { throw "RESERVED_PATH_EXISTS:$reservedPath" }
    }

    New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $backupRunRoot -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $sourceManifest = @(Get-TreeManifest -Root $sourceRoot)
    if ($sourceManifest.Count -eq 0) { throw 'SOURCE_SKILL_EMPTY' }
    Write-JsonFile -Path (Join-Path $evidenceRoot 'source-manifest.json') -Value $sourceManifest
    $sourcePackage = Join-Path $evidenceRoot 'source-package.zip'
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceRoot,
        $sourcePackage,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $installedBeforeManifest = @()
    if (Test-Path -LiteralPath $installedRoot -PathType Container) {
        $installedBeforeManifest = @(Get-TreeManifest -Root $installedRoot)
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $installedRoot,
            (Join-Path $evidenceRoot 'installed-before-backup.zip'),
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false
        )
    }
    else {
        [System.IO.File]::WriteAllBytes((Join-Path $evidenceRoot 'installed-before-backup.zip'), [byte[]]@())
    }
    Write-JsonFile -Path (Join-Path $evidenceRoot 'installed-before-manifest.json') -Value $installedBeforeManifest

    [System.IO.Directory]::CreateDirectory($stagingPath) | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($sourcePackage, $stagingPath)
    $stagingManifest = @(Get-TreeManifest -Root $stagingPath)
    if (-not (Test-ManifestEqual -Left $sourceManifest -Right $stagingManifest)) {
        throw 'STAGING_SOURCE_PARITY_FAILED'
    }

    if (Test-Path -LiteralPath $installedRoot -PathType Container) {
        Move-Item -LiteralPath $installedRoot -Destination $rollbackDirectory
        $installedMoved = $true
    }
    Move-Item -LiteralPath $stagingPath -Destination $installedRoot
    $newInstalledMoved = $true

    $installedAfterManifest = @(Get-TreeManifest -Root $installedRoot)
    if (-not (Test-ManifestEqual -Left $sourceManifest -Right $installedAfterManifest)) {
        throw 'SOURCE_INSTALL_PARITY_FAILED'
    }
    Write-JsonFile -Path (Join-Path $evidenceRoot 'installed-after-manifest.json') -Value $installedAfterManifest

    $result = [ordered]@{
        schema_version = 1
        install_status = 'PASS'
        source_install_parity = 'PASS'
        source_skill = $sourceRoot
        installed_skill = $installedRoot
        source_package = $sourcePackage
        rollback_directory = if ($installedMoved) { $rollbackDirectory } else { $null }
        installed_before_present = $installedMoved
        source_file_count = $sourceManifest.Count
        installed_file_count = $installedAfterManifest.Count
        completed_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-JsonFile -Path (Join-Path $evidenceRoot 'result.json') -Value $result
    Write-Output 'INSTALL_STATUS=PASS'
    Write-Output 'SOURCE_INSTALL_PARITY=PASS'
    Write-Output "ROLLBACK_DIRECTORY=$($result.rollback_directory)"
    exit 0
}
catch {
    $failure = $_.Exception.Message
    try {
        if ($newInstalledMoved -and (Test-Path -LiteralPath $installedRoot -PathType Container)) {
            Move-Item -LiteralPath $installedRoot -Destination $failedNewDirectory
        }
        if ($installedMoved -and (Test-Path -LiteralPath $rollbackDirectory -PathType Container)) {
            Move-Item -LiteralPath $rollbackDirectory -Destination $installedRoot
        }
        if ($evidenceRoot -and (Test-Path -LiteralPath $evidenceRoot -PathType Container)) {
            Write-JsonFile -Path (Join-Path $evidenceRoot 'failure.json') -Value ([ordered]@{
                schema_version = 1
                install_status = 'FAIL'
                reason = $failure
                restored_original = [bool]($installedMoved -and (Test-Path -LiteralPath $installedRoot -PathType Container))
                failed_new_directory = if (Test-Path -LiteralPath $failedNewDirectory -PathType Container) { $failedNewDirectory } else { $null }
                observed_at_utc = [DateTime]::UtcNow.ToString('o')
            })
        }
    }
    catch {
        $failure = $failure + ';ROLLBACK_FAILED:' + $_.Exception.Message
    }
    Write-Error $failure
    exit 1
}
