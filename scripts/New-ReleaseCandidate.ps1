[CmdletBinding()]
param(
    [string]$RepositoryPath = (Split-Path -Parent $PSScriptRoot),
    [string]$CandidatePath = '',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.1.0',
    [string]$SourceCommit = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    $CandidatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\v0.1.0-rc'
}

$root = [IO.Path]::GetFullPath($RepositoryPath)
$candidate = [IO.Path]::GetFullPath($CandidatePath)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "REPOSITORY_MISSING:$root" }
if (-not $candidate.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "CANDIDATE_OUTSIDE_REPOSITORY:$candidate"
}

function Invoke-GitLines {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $gitArgs = @('-c', "safe.directory=$root", '-C', $root) + $Arguments
    $lines = @(& git @gitArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "GIT_FAILED:$($Arguments -join ' ')" }
    return @($lines | ForEach-Object { [string]$_ })
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { return (($hasher.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '') }
        finally { $hasher.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Write-Utf8 {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Write-Json {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value)
    Write-Utf8 -Path $Path -Text ($Value | ConvertTo-Json -Depth 30)
}

function Get-RelativeFiles {
    param([Parameter(Mandatory = $true)][string]$BasePath)
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $items = @(
        Get-ChildItem -LiteralPath $base -File -Recurse |
            ForEach-Object {
                [pscustomobject]@{
                    File = $_
                    Relative = $_.FullName.Substring($base.Length).TrimStart('\').Replace('\', '/')
                }
            } |
            Sort-Object { [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes([string]$_.Relative)) }
    )
    return $items
}

function New-DeterministicZip {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$EntryPrefix
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $parent = Split-Path -Parent $ArchivePath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $stream = [IO.File]::Open($ArchivePath, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = New-Object IO.Compression.ZipArchive($stream, ([IO.Compression.ZipArchiveMode]::Create), $false)
    try {
        $fixedTime = [DateTimeOffset]::Parse('2020-01-01T00:00:00Z')
        foreach ($item in @(Get-RelativeFiles -BasePath $SourceRoot)) {
            $entryName = (($EntryPrefix.TrimEnd('/') + '/' + $item.Relative).TrimStart('/'))
            $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedTime
            $input = [IO.File]::OpenRead($item.File.FullName)
            $output = $entry.Open()
            try { $input.CopyTo($output) }
            finally { $output.Dispose(); $input.Dispose() }
        }
    }
    finally { $archive.Dispose(); $stream.Dispose() }
}

function Add-Asset {
    param(
        [Parameter(Mandatory = $true)]$List,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Kind
    )
    $full = Join-Path $candidate $Path
    $List.Add([ordered]@{
        path = $Path.Replace('\', '/')
        kind = $Kind
        bytes = [long](Get-Item -LiteralPath $full).Length
        sha256 = Get-Sha256 -Path $full
    })
}

if (Test-Path -LiteralPath $candidate) {
    if (@(Get-ChildItem -LiteralPath $candidate -Force).Count -gt 0) { throw "CANDIDATE_PATH_NOT_EMPTY:$candidate" }
}
else { New-Item -ItemType Directory -Path $candidate -Force | Out-Null }

$head = [string](Invoke-GitLines -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1)
if ($head -notmatch '^[0-9a-f]{40}$') { throw "SOURCE_COMMIT_INVALID:$head" }
if (-not [string]::IsNullOrWhiteSpace($SourceCommit) -and $SourceCommit.ToLowerInvariant() -ne $head.ToLowerInvariant()) {
    throw "SOURCE_COMMIT_MISMATCH:expected=$SourceCommit;actual=$head"
}
$status = @(Invoke-GitLines -Arguments @('status', '--porcelain'))
if ($status.Count -gt 0) { throw "SOURCE_WORKTREE_DIRTY:$($status -join '|')" }
$remote = [string](Invoke-GitLines -Arguments @('remote', 'get-url', 'origin') | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($remote)) { throw 'ORIGIN_REMOTE_MISSING' }

$tracked = @(Invoke-GitLines -Arguments @('ls-files'))
$excluded = @('outputs/', 'dist/', '99_Temp/', '.codex/')
$packageFiles = @($tracked | Where-Object {
    $path = ([string]$_).Replace('\', '/')
    @($excluded | Where-Object { $path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
})
if ($packageFiles.Count -lt 1) { throw 'PACKAGE_FILES_EMPTY' }

$packageRoot = Join-Path $candidate 'package'
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
foreach ($relative in $packageFiles) {
    $source = Join-Path $root $relative
    $destination = Join-Path $packageRoot $relative
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$releaseNotesSource = Join-Path $root "docs\release\v$Version.md"
if (-not (Test-Path -LiteralPath $releaseNotesSource -PathType Leaf)) { throw "RELEASE_NOTES_MISSING:$releaseNotesSource" }
Copy-Item -LiteralPath $releaseNotesSource -Destination (Join-Path $candidate 'release-notes.md') -Force

$sbomSource = Join-Path $root 'sbom\cyclonedx.json'
if (-not (Test-Path -LiteralPath $sbomSource -PathType Leaf)) { throw "SBOM_MISSING:$sbomSource" }
$sbomDestination = Join-Path $candidate 'sbom\cyclonedx.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $sbomDestination) -Force | Out-Null
Copy-Item -LiteralPath $sbomSource -Destination $sbomDestination -Force

$sourceArchive = 'assets/project-development-governance-v' + $Version + '-source.zip'
New-DeterministicZip -SourceRoot $packageRoot -ArchivePath (Join-Path $candidate $sourceArchive) -EntryPrefix ('project-development-governance-v' + $Version)

$skillNames = @(
    Get-ChildItem -LiteralPath (Join-Path $packageRoot 'skills') -Directory |
        Sort-Object { [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($_.Name)) } |
        ForEach-Object { $_.Name }
)
if ($skillNames.Count -lt 1) { throw 'SKILL_LIST_EMPTY' }
$assetRecords = New-Object System.Collections.Generic.List[object]
Add-Asset -List $assetRecords -Path $sourceArchive -Kind 'source_archive'
foreach ($skillName in $skillNames) {
    $skillRelative = 'skills/' + $skillName + '-v' + $Version + '.zip'
    New-DeterministicZip -SourceRoot (Join-Path $packageRoot ('skills\' + $skillName)) -ArchivePath (Join-Path $candidate $skillRelative) -EntryPrefix $skillName
    Add-Asset -List $assetRecords -Path $skillRelative -Kind 'skill_bundle'
}
Add-Asset -List $assetRecords -Path 'release-notes.md' -Kind 'release_notes'
Add-Asset -List $assetRecords -Path 'sbom/cyclonedx.json' -Kind 'sbom'

$checksums = @($assetRecords | Sort-Object { [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes([string]$_.path)) } | ForEach-Object {
    '{0}  {1}' -f $_.sha256, $_.path
}) -join [Environment]::NewLine
Write-Utf8 -Path (Join-Path $candidate 'checksums.sha256') -Text ($checksums + [Environment]::NewLine)

$manifest = [ordered]@{
    schema_version = 1
    candidate_type = 'release-candidate'
    version = $Version
    project_name = 'Project Development Governance'
    repository = $remote
    source_commit = $head
    package_file_count = $packageFiles.Count
    skill_count = $skillNames.Count
    skills = @($skillNames)
    deterministic_archive_timestamp = '2020-01-01T00:00:00Z'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    assets = $assetRecords.ToArray()
}
Write-Json -Path (Join-Path $candidate 'candidate-manifest.json') -Value $manifest

Remove-Item -LiteralPath $packageRoot -Recurse -Force
Write-Output "RELEASE_CANDIDATE_BUILT=$candidate"
Write-Output "SOURCE_COMMIT=$head"
Write-Output "SKILL_COUNT=$($skillNames.Count)"
Write-Output "ASSET_COUNT=$($assetRecords.Count)"

