[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

# Keep this script encoded as UTF-8 with BOM: Windows PowerShell 5.1 must read
# the Chinese category literals below as UTF-8 so its classification agrees with PowerShell 7.

$ErrorActionPreference = 'Stop'

function Write-DiscoveryResult {
    param([Parameter(Mandatory = $true)]$Result)
    $Result | ConvertTo-Json -Depth 8
    exit 0
}

try {
    $resolvedRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}
catch {
    Write-DiscoveryResult ([ordered]@{
        schema_version = 1
        project_root = $ProjectRoot
        planning_root = $null
        planning_root_exists = $false
        reason_codes = @('PROJECT_ROOT_INVALID')
        files = @()
    })
}

if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    Write-DiscoveryResult ([ordered]@{
        schema_version = 1
        project_root = $resolvedRoot
        planning_root = $null
        planning_root_exists = $false
        reason_codes = @('PROJECT_ROOT_MISSING')
        files = @()
    })
}

$planningRoot = Join-Path $resolvedRoot 'docs\future-development'
if (-not (Test-Path -LiteralPath $planningRoot -PathType Container)) {
    Write-DiscoveryResult ([ordered]@{
        schema_version = 1
        project_root = $resolvedRoot
        planning_root = $planningRoot
        planning_root_exists = $false
        reason_codes = @('PLANNING_ROOT_MISSING')
        files = @()
    })
}

$records = foreach ($file in Get-ChildItem -LiteralPath $planningRoot -File -Recurse -Filter '*.md') {
    $name = $file.Name
    $category = if ($name -match '(?i)(逐项实施计划|实施计划|implementation[-_ ]?plan)') {
        'Plan'
    }
    elseif ($name -match '(?i)(验收.*窗口|acceptance.*window)') {
        'AcceptanceWindow'
    }
    elseif ($name -match '(?i)(路线图|roadmap)') {
        'Roadmap'
    }
    elseif ($name -match '(?i)(方向|direction)') {
        'Direction'
    }
    elseif ($name -match '(?i)(设计文档|完整设计|design)') {
        'Design'
    }
    else {
        'Other'
    }

    $version = $null
    $versionScore = -1
    if ($name -match '(?i)V(?<major>\d+)(?:\.(?<minor>\d+))?') {
        $major = [int]$Matches['major']
        $minor = if ($Matches['minor']) { [int]$Matches['minor'] } else { 0 }
        $version = "V$major.$minor"
        $versionScore = ($major * 100000) + $minor
    }

    [pscustomobject][ordered]@{
        relative_path = $file.FullName.Substring($resolvedRoot.Length).TrimStart('\')
        category = $category
        version = $version
        version_score = $versionScore
        last_write_utc = $file.LastWriteTimeUtc.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

$sorted = @($records | Sort-Object -Property @{ Expression = 'version_score'; Descending = $true }, @{ Expression = 'relative_path'; Descending = $false })

Write-DiscoveryResult ([ordered]@{
    schema_version = 1
    project_root = $resolvedRoot
    planning_root = $planningRoot
    planning_root_exists = $true
    reason_codes = @()
    files = $sorted
})

