[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [bool]$RequireXDrive = $true,

    [int]$ProjectedWip = -1,

    [int]$SameWorktreeWriterCount = -1,

    [int]$SharedResourceConflictCount = -1,

    [int]$EntryExitCode = [int]::MinValue,

    [int]$ComplianceExitCode = [int]::MinValue
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$hardReasons = New-Object 'System.Collections.Generic.List[string]'
$unknownReasons = New-Object 'System.Collections.Generic.List[string]'

function Add-UniqueReason {
    param(
        [Parameter(Mandatory = $true)]$List,
        [Parameter(Mandatory = $true)][string]$Code
    )
    if (-not $List.Contains($Code)) {
        $List.Add($Code)
    }
}

function Write-ResultAndExit {
    param([Parameter(Mandatory = $true)]$Result)
    $Result | ConvertTo-Json -Depth 8
    exit 0
}

function Read-Utf8TextStrict {
    param([Parameter(Mandatory = $true)][string]$Path)

    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [System.IO.File]::ReadAllText($Path, $encoding)
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties |
            Where-Object { $_.Name -ceq $name } |
            Select-Object -First 1
        if ($null -ne $property) {
            return $property.Value
        }
    }
    return $null
}

try {
    $resolvedRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
}
catch {
    $resolvedRoot = $ProjectRoot
    Add-UniqueReason $hardReasons 'PROJECT_ROOT_INVALID'
}

if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    Add-UniqueReason $hardReasons 'PROJECT_ROOT_MISSING'
    Write-ResultAndExit ([ordered]@{
        schema_version = 1
        observed_at_utc = [DateTime]::UtcNow.ToString('o')
        project_root = $resolvedRoot
        verdict = 'BLOCKED'
        reason_codes = @($hardReasons)
        evidence_transferable = $false
        git = $null
        project_contract = $null
        isolation = $null
    })
}

$pathRoot = [System.IO.Path]::GetPathRoot($resolvedRoot)
if ($RequireXDrive -and ($pathRoot -ine 'X:\')) {
    Add-UniqueReason $hardReasons 'NOT_X_DRIVE'
}

if ($resolvedRoot -match '(?i)(pre-i2-recovery-root|legacy|recovery[-_ ]?snapshot)') {
    Add-UniqueReason $hardReasons 'LEGACY_OR_RECOVERY_ROOT'
}

$gitRoot = $null
$gitCommonDir = $null
$branch = $null
$head = $null
$dirty = $null
$statusLines = @()

function Invoke-GitReadOnly {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $WorkingDirectory @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{ Output = $output; ExitCode = $exitCode }
    }
    catch {
        return [pscustomobject]@{ Output = @(); ExitCode = 1 }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

$gitRootResult = Invoke-GitReadOnly -WorkingDirectory $resolvedRoot -Arguments @('rev-parse', '--show-toplevel')
if ($gitRootResult.ExitCode -ne 0 -or -not $gitRootResult.Output) {
    Add-UniqueReason $hardReasons 'GIT_ROOT_UNRESOLVED'
}
else {
    $gitRoot = [System.IO.Path]::GetFullPath(($gitRootResult.Output | Select-Object -First 1).Trim())

    $branchResult = Invoke-GitReadOnly -WorkingDirectory $gitRoot -Arguments @('branch', '--show-current')
    if ($branchResult.ExitCode -ne 0) {
        Add-UniqueReason $hardReasons 'GIT_BRANCH_UNRESOLVED'
    }
    else {
        $branch = ($branchResult.Output | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Add-UniqueReason $hardReasons 'DETACHED_HEAD'
        }
    }

    $headResult = Invoke-GitReadOnly -WorkingDirectory $gitRoot -Arguments @('rev-parse', 'HEAD')
    if ($headResult.ExitCode -ne 0 -or -not $headResult.Output) {
        Add-UniqueReason $hardReasons 'GIT_HEAD_UNRESOLVED'
    }
    else {
        $head = ($headResult.Output | Select-Object -First 1).Trim()
    }

    $commonResult = Invoke-GitReadOnly -WorkingDirectory $gitRoot -Arguments @('rev-parse', '--git-common-dir')
    if ($commonResult.ExitCode -ne 0 -or -not $commonResult.Output) {
        Add-UniqueReason $hardReasons 'GIT_COMMON_DIR_UNRESOLVED'
    }
    else {
        $commonValue = ($commonResult.Output | Select-Object -First 1).Trim()
        if ([System.IO.Path]::IsPathRooted($commonValue)) {
            $gitCommonDir = [System.IO.Path]::GetFullPath($commonValue)
        }
        else {
            $gitCommonDir = [System.IO.Path]::GetFullPath((Join-Path $gitRoot $commonValue))
        }
        if ($RequireXDrive -and ([System.IO.Path]::GetPathRoot($gitCommonDir) -ine 'X:\')) {
            Add-UniqueReason $hardReasons 'GIT_METADATA_OUTSIDE_X_DRIVE'
        }
    }

    $statusResult = Invoke-GitReadOnly -WorkingDirectory $gitRoot -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    if ($statusResult.ExitCode -ne 0) {
        Add-UniqueReason $hardReasons 'GIT_STATUS_UNRESOLVED'
    }
    else {
        $statusLines = @($statusResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $dirty = ($statusLines.Count -gt 0)
        if ($dirty) {
            Add-UniqueReason $hardReasons 'DIRTY_WORKTREE'
        }
    }
}

$instructionPath = if ($gitRoot) { Join-Path $gitRoot 'AGENTS.md' } else { Join-Path $resolvedRoot 'AGENTS.md' }
$profilePath = if ($gitRoot) { Join-Path $gitRoot '.codex\x-drive\project-profile.json' } else { Join-Path $resolvedRoot '.codex\x-drive\project-profile.json' }
$entryPath = if ($gitRoot) { Join-Path $gitRoot 'Enter-XProject.ps1' } else { Join-Path $resolvedRoot 'Enter-XProject.ps1' }
$compliancePath = if ($gitRoot) { Join-Path $gitRoot 'Test-XProjectCompliance.ps1' } else { Join-Path $resolvedRoot 'Test-XProjectCompliance.ps1' }

$instructionsExist = Test-Path -LiteralPath $instructionPath -PathType Leaf
$profileExists = Test-Path -LiteralPath $profilePath -PathType Leaf
$entryExists = Test-Path -LiteralPath $entryPath -PathType Leaf
$complianceExists = Test-Path -LiteralPath $compliancePath -PathType Leaf
$profileValid = $false
$profileProjectRoot = $null
$profileMainRepositoryPath = $null

if (-not $profileExists) {
    Add-UniqueReason $hardReasons 'PROJECT_PROFILE_MISSING'
}
else {
    $profileText = $null
    try {
        $profileText = Read-Utf8TextStrict -Path $profilePath
    }
    catch [System.Text.DecoderFallbackException] {
        Add-UniqueReason $hardReasons 'PROJECT_PROFILE_INVALID_UTF8'
    }
    catch {
        Add-UniqueReason $hardReasons 'PROJECT_PROFILE_READ_FAILED'
    }

    if ($null -ne $profileText) {
        $profile = $null
        try {
            $profile = $profileText | ConvertFrom-Json
            if ($null -eq $profile) {
                throw 'Profile JSON did not produce an object.'
            }
        }
        catch {
            Add-UniqueReason $hardReasons 'PROJECT_PROFILE_INVALID_JSON'
        }

        if ($null -ne $profile) {
            $profileProjectRoot = Get-ObjectPropertyValue -Object $profile -Names @('project_root', 'projectRoot')
            $profileMainRepositoryPath = Get-ObjectPropertyValue -Object $profile -Names @('main_repository_path', 'mainRepositoryPath')
            if ([string]::IsNullOrWhiteSpace([string]$profileProjectRoot)) {
                Add-UniqueReason $hardReasons 'PROJECT_PROFILE_REQUIRED_FIELD_MISSING'
            }
            else {
                $profileValid = $true
            }
        }
    }
}

if (-not $entryExists) {
    Add-UniqueReason $hardReasons 'ENTRY_SCRIPT_MISSING'
}
if (-not $complianceExists) {
    Add-UniqueReason $hardReasons 'COMPLIANCE_SCRIPT_MISSING'
}

if ($SameWorktreeWriterCount -lt 0) {
    Add-UniqueReason $unknownReasons 'SAME_WORKTREE_WRITER_COUNT_UNKNOWN'
}
elseif ($SameWorktreeWriterCount -gt 0) {
    Add-UniqueReason $hardReasons 'SAME_WORKTREE_WRITER_PRESENT'
}

if ($SharedResourceConflictCount -lt 0) {
    Add-UniqueReason $unknownReasons 'SHARED_RESOURCE_CONFLICT_COUNT_UNKNOWN'
}
elseif ($SharedResourceConflictCount -gt 0) {
    Add-UniqueReason $hardReasons 'SHARED_RESOURCE_CONFLICT'
}

if ($EntryExitCode -eq [int]::MinValue) {
    Add-UniqueReason $unknownReasons 'ENTRY_EXIT_CODE_UNKNOWN'
}
elseif ($EntryExitCode -ne 0) {
    Add-UniqueReason $hardReasons 'ENTRY_CHECK_FAILED'
}

if ($ComplianceExitCode -eq [int]::MinValue) {
    Add-UniqueReason $unknownReasons 'COMPLIANCE_EXIT_CODE_UNKNOWN'
}
elseif ($ComplianceExitCode -ne 0) {
    Add-UniqueReason $hardReasons 'COMPLIANCE_CHECK_FAILED'
}

$verdict = if ($hardReasons.Count -gt 0) {
    'BLOCKED'
}
elseif ($unknownReasons.Count -gt 0) {
    'READ_ONLY_ONLY'
}
else {
    'READY'
}

$allReasons = @($hardReasons) + @($unknownReasons)

Write-ResultAndExit ([ordered]@{
    schema_version = 1
    observed_at_utc = [DateTime]::UtcNow.ToString('o')
    project_root = $resolvedRoot
    verdict = $verdict
    reason_codes = $allReasons
    hard_blockers = @($hardReasons)
    unknowns = @($unknownReasons)
    evidence_transferable = $false
    git = [ordered]@{
        root = $gitRoot
        common_dir = $gitCommonDir
        branch = $branch
        head = $head
        dirty = $dirty
        status_lines = $statusLines
    }
    project_contract = [ordered]@{
        instructions_path = $instructionPath
        instructions_exist = $instructionsExist
        profile_path = $profilePath
        profile_exists = $profileExists
        profile_valid = $profileValid
        profile_project_root = $profileProjectRoot
        profile_main_repository_path = $profileMainRepositoryPath
        entry_script_path = $entryPath
        entry_script_exists = $entryExists
        entry_exit_code = if ($EntryExitCode -eq [int]::MinValue) { $null } else { $EntryExitCode }
        compliance_script_path = $compliancePath
        compliance_script_exists = $complianceExists
        compliance_exit_code = if ($ComplianceExitCode -eq [int]::MinValue) { $null } else { $ComplianceExitCode }
    }
    isolation = [ordered]@{
        projected_wip = if ($ProjectedWip -lt 0) { $null } else { $ProjectedWip }
        global_wip_limit = $null
        project_count_limit_enforced = $false
        same_worktree_writer_count = if ($SameWorktreeWriterCount -lt 0) { $null } else { $SameWorktreeWriterCount }
        shared_resource_conflict_count = if ($SharedResourceConflictCount -lt 0) { $null } else { $SharedResourceConflictCount }
    }
})
