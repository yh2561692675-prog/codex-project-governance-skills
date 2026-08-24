[CmdletBinding()]
param(
    [switch]$ScanHistory,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'outputs/oss-readiness-v2/T07'
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputPath)

if (Test-Path -LiteralPath $outputRoot) {
    $existing = @(Get-ChildItem -LiteralPath $outputRoot -Force -ErrorAction Stop)
    if ($existing.Count -gt 0) {
        throw "Output path must be fresh and empty: $outputRoot"
    }
} else {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

$gitCommand = (Get-Command git -ErrorAction Stop).Source
$safeGitPrefix = @('-c', "safe.directory=$repoRoot", '-c', 'core.quotepath=false', '-C', $repoRoot)

function Invoke-GitLines {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $lines = @(& $gitCommand @safeGitPrefix @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Lines = $lines }
}

function Test-InternalPath {
    param([string]$Path)
    return $Path -match '^(?:docs/future-development/|outputs/|99_Temp/|\.codex/|AGENTS\.md$|docs/maintenance/(?:current-state-ledger|source-branches)\.md$)'
}

function Test-TextPath {
    param([string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return $extension -notin @('.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.pdf', '.zip', '.7z', '.mp4', '.wav', '.woff', '.woff2', '.ttf', '.bin')
}

function Get-LineNumber {
    param([string]$Text, [int]$Index)
    if ($Index -le 0) { return 1 }
    return 1 + ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count
}

function Test-AllowlistedMatch {
    param(
        [string]$Category,
        [string]$Value,
        [string]$RuleId,
        [string]$Path,
        [string]$Source
    )
    if ($Category -eq 'PII') {
        if ($Value -match '(?i)example\.(?:com|org|invalid)|localhost|<CODEX_HOME>|<USER>|<selected-project-git-root>') { return $true }
        if ($RuleId -eq 'personal-path' -and $Source -ne 'working-tree' -and $Path -match '^skills/project-design-plan-readiness/(?:SKILL\.md|references/planning-contract\.md)$') { return $true }
    }
    if ($Category -eq 'SECRET') {
        if ($Value -match '(?i)REDACTED|PLACEHOLDER|YOUR[_-]?(?:KEY|TOKEN|SECRET)|CHANGE[_-]?ME|EXAMPLE|DUMMY|FIXTURE|SAMPLE') { return $true }
    }
    return $false
}

$patterns = [ordered]@{
    SECRET = @(
        [pscustomobject]@{ Id = 'private-key'; Regex = '(?:-----BEGIN\s+(?:(?:RSA|OPENSSH|EC|DSA)\s+)?PRIVATE KEY-----)' },
        [pscustomobject]@{ Id = 'openai-key'; Regex = '(?i)\bsk-[A-Za-z0-9]{20,}\b' },
        [pscustomobject]@{ Id = 'github-token'; Regex = '(?i)\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b' },
        [pscustomobject]@{ Id = 'aws-access-key'; Regex = '\bAKIA[0-9A-Z]{16}\b' },
        [pscustomobject]@{ Id = 'credential-assignment'; Regex = '(?im)\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password|cookie)\b\s*[:=]\s*[A-Za-z0-9_./+=-]{16,}' }
    )
    PII = @(
        [pscustomobject]@{ Id = 'email-address'; Regex = '(?i)\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' },
        [pscustomobject]@{ Id = 'personal-path'; Regex = '(?i)(?:[A-Z]:\\Users\\[A-Za-z0-9._-]+\\|/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/)' },
        [pscustomobject]@{ Id = 'student-identifier'; Regex = '(?im)\b(?:student[_ -]?id|学号)\b\s*[:=]\s*[A-Za-z0-9-]{6,}\b' },
        [pscustomobject]@{ Id = 'national-identifier'; Regex = '(?<!\d)\d{17}[\dXx](?!\d)' }
    )
}

$tracked = @(Invoke-GitLines -Arguments @('ls-files')).Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$internalPaths = @($tracked | Where-Object { Test-InternalPath $_ })
$publicPaths = @($tracked | Where-Object { -not (Test-InternalPath $_) -and (Test-TextPath $_) })
$findings = New-Object System.Collections.ArrayList
$envPaths = @($publicPaths | Where-Object { $_ -match '(^|/)\.env(?:\..*)?$' -and $_ -notmatch '(?i)\.env\.example$' })
foreach ($envPath in $envPaths) {
    [void]$findings.Add([pscustomobject]@{
        Key = "SECRET|env-file|$envPath|working-tree|0|$envPath"
        Category = 'SECRET'
        RuleId = 'env-file'
        Path = $envPath
        Source = 'working-tree'
        Line = 0
        Value = $envPath
    })
}

function Add-Finding {
    param(
        [string]$Category,
        [string]$RuleId,
        [string]$Path,
        [string]$Source,
        [int]$Line,
        [string]$Value
    )
    if (Test-AllowlistedMatch -Category $Category -Value $Value -RuleId $RuleId -Path $Path -Source $Source) { return }
    $key = "$Category|$RuleId|$Path|$Source|$Line|$Value"
    if (-not ($script:findings | Where-Object { $_.Key -eq $key })) {
        [void]$script:findings.Add([pscustomobject]@{
            Key = $key
            Category = $Category
            RuleId = $RuleId
            Path = $Path
            Source = $Source
            Line = $Line
            Value = $Value.Substring(0, [Math]::Min(80, $Value.Length))
        })
    }
}

foreach ($path in $publicPaths) {
    $fullPath = Join-Path $repoRoot ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $text = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
    foreach ($category in $patterns.Keys) {
        foreach ($rule in $patterns[$category]) {
            foreach ($match in [regex]::Matches($text, $rule.Regex)) {
                Add-Finding -Category $category -RuleId $rule.Id -Path $path -Source 'working-tree' -Line (Get-LineNumber -Text $text -Index $match.Index) -Value $match.Value
            }
        }
    }
}

$historyCommits = @()
if ($ScanHistory) {
    $historyCommits = @(Invoke-GitLines -Arguments @('rev-list', '--all')).Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($commit in $historyCommits) {
        foreach ($category in $patterns.Keys) {
            foreach ($rule in $patterns[$category]) {
                $grepArgs = @('grep', '--no-color', '--line-number', '-I', '-P', $rule.Regex, $commit, '--') + $publicPaths
                $grepResult = Invoke-GitLines -Arguments $grepArgs -AllowFailure
                if ($grepResult.ExitCode -ne 0) { continue }
                foreach ($line in $grepResult.Lines) {
                    $parts = [regex]::Split([string]$line, ':', 4)
                    if ($parts.Count -lt 3) { continue }
                    $pathPart = $parts[0]
                    $linePart = $parts[1]
                    $valuePart = $parts[2]
                    if ($parts.Count -ge 4 -and $parts[0] -match '^[0-9a-f]{40}$') {
                        $pathPart = $parts[1]
                        $linePart = $parts[2]
                        $valuePart = $parts[3]
                    }
                    $lineNumber = 0
                    [void][int]::TryParse($linePart, [ref]$lineNumber)
                    Add-Finding -Category $category -RuleId $rule.Id -Path $pathPart -Source $commit -Line $lineNumber -Value $valuePart
                }
            }
        }
    }
}

$licenseConflicts = New-Object System.Collections.ArrayList
$licensePath = Join-Path $repoRoot 'LICENSE'
$noticesPath = Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md'
$sbomPath = Join-Path $repoRoot 'sbom/cyclonedx.json'
if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) { [void]$licenseConflicts.Add('LICENSE missing') }
elseif (([System.IO.File]::ReadAllText($licensePath, [System.Text.Encoding]::UTF8) -notmatch '(?i)MIT License') -or ([System.IO.File]::ReadAllText($licensePath, [System.Text.Encoding]::UTF8) -notmatch '(?i)permission')) { [void]$licenseConflicts.Add('LICENSE is not recognizable MIT text') }
if (-not (Test-Path -LiteralPath $noticesPath -PathType Leaf)) { [void]$licenseConflicts.Add('THIRD_PARTY_NOTICES.md missing') }

$sbomValid = $false
if (Test-Path -LiteralPath $sbomPath -PathType Leaf) {
    try {
        $sbom = Get-Content -LiteralPath $sbomPath -Raw | ConvertFrom-Json
        $sbomValid = ($sbom.bomFormat -eq 'CycloneDX' -and [int]$sbom.specVersion -ge 1 -and @($sbom.components).Count -ge 1)
    } catch {
        $sbomValid = $false
    }
}
if (-not $sbomValid) { [void]$licenseConflicts.Add('CycloneDX SBOM missing or invalid') }

$supplyChainIssues = New-Object System.Collections.ArrayList
$workflowPaths = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot '.github/workflows') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
foreach ($workflowPath in $workflowPaths) {
    $workflow = [System.IO.File]::ReadAllText($workflowPath, [System.Text.Encoding]::UTF8)
    if ($workflow -notmatch '(?im)^permissions:\s*$') { [void]$supplyChainIssues.Add("permissions missing: $([System.IO.Path]::GetFileName($workflowPath))") }
    if ($workflow -notmatch '(?im)^\s+contents:\s+read\s*$') { [void]$supplyChainIssues.Add("contents: read missing: $([System.IO.Path]::GetFileName($workflowPath))") }
    if ($workflow -match '(?i)uses:\s+[^\s]+@(main|master|latest)\b|(?:curl|wget|Invoke-WebRequest).*https?://|releases/download') { [void]$supplyChainIssues.Add("untrusted workflow fetch or floating ref: $([System.IO.Path]::GetFileName($workflowPath))") }
}
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.gitleaks.toml') -PathType Leaf)) { [void]$supplyChainIssues.Add('.gitleaks.toml missing') }

$configHash = (Get-FileHash -LiteralPath (Join-Path $repoRoot '.gitleaks.toml') -Algorithm SHA256).Hash
$supplyChainStatus = if ($supplyChainIssues.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    SCANNER_VERSION = 'publication-safety-scanner/0.1.0'
    RUNTIME_VERSION = [string]$PSVersionTable.PSVersion
    SCAN_SCOPE = 'PUBLIC_RELEASE_SURFACE'
    HISTORY_SCANNED = [bool]$ScanHistory
    COMMITS_SCANNED = $historyCommits.Count
    PUBLIC_FILES_SCANNED = $publicPaths.Count
    INTERNAL_PATHS_EXCLUDED = $internalPaths.Count
    SECRET_FINDINGS = @($findings | Where-Object Category -eq 'SECRET').Count
    PII_FINDINGS = @($findings | Where-Object Category -eq 'PII').Count
    LICENSE_CONFLICTS = $licenseConflicts.Count
    SUPPLY_CHAIN = $supplyChainStatus
    ROTATION_EVIDENCE = if (@($findings).Count -eq 0) { 'NOT_REQUIRED_NO_SECRET_FINDINGS' } else { 'REQUIRED_REVIEW' }
    RULE_CONFIG_SHA256 = $configHash
    FINDINGS = @($findings)
    LICENSE_ISSUES = @($licenseConflicts)
    SUPPLY_CHAIN_ISSUES = @($supplyChainIssues)
}

$jsonPath = Join-Path $outputRoot 'publication-safety.json'
$markdownPath = Join-Path $outputRoot 'publication-safety.md'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$markdown = @(
    '# Public release safety verification',
    '',
    "- Scanner: $($result.SCANNER_VERSION); runtime: $($result.RUNTIME_VERSION)",
    "- Scope: $($result.SCAN_SCOPE) (internal governance records remain excluded and are listed in the release checklist).",
    "- History scanned: $($result.HISTORY_SCANNED) across $($result.COMMITS_SCANNED) commits.",
    "- Public text files scanned: $($result.PUBLIC_FILES_SCANNED); internal paths excluded: $($result.INTERNAL_PATHS_EXCLUDED).",
    "- SECRET_FINDINGS=$($result.SECRET_FINDINGS)",
    "- PII_FINDINGS=$($result.PII_FINDINGS)",
    "- LICENSE_CONFLICTS=$($result.LICENSE_CONFLICTS)",
    "- SUPPLY_CHAIN=$($result.SUPPLY_CHAIN)",
    "- Rule configuration SHA-256: $($result.RULE_CONFIG_SHA256)",
    "- Rotation evidence: $($result.ROTATION_EVIDENCE)"
)
if ($internalPaths.Count -gt 0) {
    $markdown += '', '## Excluded internal paths', '', ($internalPaths | ForEach-Object { "- $($_)" })
}
$markdown | Set-Content -LiteralPath $markdownPath -Encoding UTF8

Write-Output "SECRET_FINDINGS=$($result.SECRET_FINDINGS)"
Write-Output "PII_FINDINGS=$($result.PII_FINDINGS)"
Write-Output "LICENSE_CONFLICTS=$($result.LICENSE_CONFLICTS)"
Write-Output "SUPPLY_CHAIN=$($result.SUPPLY_CHAIN)"
if ($result.SECRET_FINDINGS -ne 0 -or $result.PII_FINDINGS -ne 0 -or $result.LICENSE_CONFLICTS -ne 0 -or $result.SUPPLY_CHAIN -ne 'PASS') {
    exit 1
}
Write-Output 'PUBLICATION_SAFETY=PASS'
exit 0
