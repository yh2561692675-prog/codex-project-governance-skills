[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

function Read-Json {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "Missing JSON: $Path"
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false, $true))) | ConvertFrom-Json
}

$profile = Read-Json (Join-Path $root '.codex\x-drive\project-profile.json')
Assert-True ([string]$profile.projectRoot -eq $root) 'Profile root must bind the current successor worktree.'
Assert-True ([string]$profile.repositoryType -eq 'linked-worktree') 'Profile must identify a linked worktree.'

$requiredSkills = @(
    'skills\x-project-development-preflight\SKILL.md',
    'skills\project-design-plan-readiness\SKILL.md',
    'skills\lightweight-project-governance\SKILL.md',
    'skills\long-running-project-execution\SKILL.md',
    'skills\evidence-bound-project-closure\SKILL.md'
)
foreach ($relative in $requiredSkills) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "Skill is missing: $relative"
}

$projectLabel = [regex]::Unescape('\u9879\u76ee\u5f00\u53d1\u6cbb\u7406') + 'Skills'
$designLabel = [regex]::Unescape('\u8bbe\u8ba1\u6587\u6863')
$planLabel = [regex]::Unescape('\u9010\u9879\u5b9e\u65bd\u8ba1\u5212')
$requiredDocs = @(
    "docs\future-development\${projectLabel}_${designLabel}_V2.0.md",
    "docs\future-development\${projectLabel}_${planLabel}_V2.0.md",
    "docs\future-development\${projectLabel}_${designLabel}_V1.3.md",
    "docs\future-development\${projectLabel}_${planLabel}_V1.3.md",
    'docs\maintenance\source-branches.md',
    'docs\maintenance\current-state-ledger.md'
)
foreach ($relative in $requiredDocs) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "Governance document is missing: $relative"
}

$policy = Read-Json (Join-Path $root 'config\lightweight-governance\risk-policy-v2.json')
Assert-True ($null -ne $policy.hardTriggers) 'Risk policy must expose hard triggers.'
Assert-True (@($policy.hardTriggers).Count -ge 5) 'Risk policy must retain multiple hard triggers.'
$schema = Read-Json (Join-Path $root 'schemas\project-governance-profile-v1.1.schema.json')
Assert-True ([string]$schema.title -ne '') 'Profile schema must have a title.'

$preflight = Join-Path $root 'skills\x-project-development-preflight\scripts\Test-ProjectDevelopmentPreflight.ps1'
$raw = @(& $preflight -ProjectRoot $root -SameWorktreeWriterCount 0 -SharedResourceConflictCount 0 -EntryExitCode 0 -ComplianceExitCode 0)
$result = ($raw -join [Environment]::NewLine) | ConvertFrom-Json
Assert-True ([string]$result.verdict -eq 'READY') 'Current successor preflight must be READY.'
Assert-True ([bool]$result.git.dirty -eq $false) 'End-to-end candidate must be clean when verified.'

Write-Output 'GOVERNANCE_END_TO_END=PASS'
exit 0
