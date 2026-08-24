[CmdletBinding()]
param(
    [ValidateSet('LocalContract', 'Runner', 'Security')]
    [string]$Mode = 'LocalContract',
    [string]$ArtifactRoot,
    [string]$RunnerId = 'local',
    [string]$ShellName = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
    $ArtifactRoot = Join-Path $projectRoot ("99_Temp\ci-matrix\{0}-{1}" -f $Mode.ToLowerInvariant(), ([guid]::NewGuid().ToString('N').Substring(0, 8)))
}
$ArtifactRoot = [IO.Path]::GetFullPath($ArtifactRoot)
[IO.Directory]::CreateDirectory($ArtifactRoot) | Out-Null

$results = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet('PASS', 'FAIL', 'NOT_APPLICABLE')][string]$Status,
        [string]$Message
    )
    $results.Add([pscustomobject][ordered]@{
        name = $Name
        status = $Status
        message = $Message
    })
    if ($Status -eq 'FAIL') { $failures.Add("${Name}:$Message") }
}

function Assert-File {
    param([string]$RelativePath)
    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Result -Name "file:$RelativePath" -Status FAIL -Message 'missing'
        return $false
    }
    return $true
}

function Read-RepoText {
    param([string]$RelativePath)
    $path = Join-Path $projectRoot $RelativePath
    return [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding($false, $true)))
}

function Write-Json {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}

function Write-JUnit {
    param([string]$Path, [object[]]$Items)
    $escaped = @($Items | ForEach-Object {
        $name = [Security.SecurityElement]::Escape([string]$_.name)
        $message = [Security.SecurityElement]::Escape([string]$_.message)
        if ($_.status -eq 'PASS') {
            "    <testcase name=`"$name`"><system-out>$message</system-out></testcase>"
        }
        elseif ($_.status -eq 'NOT_APPLICABLE') {
            "    <testcase name=`"$name`"><skipped message=`"$message`" /></testcase>"
        }
        else {
            "    <testcase name=`"$name`"><failure message=`"$message`" /></testcase>"
        }
    })
    $failed = @($Items | Where-Object status -eq 'FAIL').Count
    $skipped = @($Items | Where-Object status -eq 'NOT_APPLICABLE').Count
    $xml = @(
        "<?xml version=`"1.0`" encoding=`"utf-8`"?>"
        "<testsuite name=`"codex-governance-ci`" tests=`"$(@($Items).Count)`" failures=`"$failed`" skipped=`"$skipped`">"
        $escaped
        '</testsuite>'
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $xml, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-ChildScript {
    param([string]$ScriptPath, [string[]]$Arguments)
    $hostExecutable = (Get-Process -Id $PID).Path
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = @(& $hostExecutable -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ code = $code; output = @($raw | ForEach-Object { [string]$_ }) }
}

function Test-DocumentationSafety {
    $paths = @('README.md', 'README.zh-CN.md', 'LICENSE', 'SECURITY.md', 'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md', 'CHANGELOG.md', 'docs/architecture.md', 'docs/maintenance.md')
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($relative in $paths) {
        if (-not (Assert-File -RelativePath $relative)) { continue }
        $text = Read-RepoText -RelativePath $relative
        foreach ($pattern in @('C:\', 'X:\', 'F:\', '/Users/', '{{', 'TBD', 'TODO')) {
            if ($text.Contains($pattern)) { $bad.Add("${relative}:$pattern") }
        }
    }
    if ($bad.Count -gt 0) {
        Add-Result -Name 'documentation-safety' -Status FAIL -Message ($bad -join ',')
        return
    }
    Add-Result -Name 'documentation-safety' -Status PASS -Message 'no local absolute paths or unresolved placeholders'
}

function Invoke-LocalContract {
    $workflows = @('.github/workflows/ci.yml', '.github/workflows/security.yml')
    foreach ($relative in $workflows) { [void](Assert-File -RelativePath $relative) }
    foreach ($relative in @('.github/ISSUE_TEMPLATE/bug_report.yml', '.github/ISSUE_TEMPLATE/feature_request.yml', '.github/pull_request_template.md')) {
        [void](Assert-File -RelativePath $relative)
    }

    $ci = if (Test-Path -LiteralPath (Join-Path $projectRoot '.github/workflows/ci.yml')) { Read-RepoText '.github/workflows/ci.yml' } else { '' }
    $security = if (Test-Path -LiteralPath (Join-Path $projectRoot '.github/workflows/security.yml')) { Read-RepoText '.github/workflows/security.yml' } else { '' }
    $requiredCiTokens = @(
        'windows-powershell-5.1', 'windows-pwsh-7', 'ubuntu-pwsh-7', 'macos-pwsh-7',
        'actions/checkout@v4', 'actions/upload-artifact@v4', 'permissions:', 'contents: read',
        'concurrency:', 'timeout-minutes:', 'Invoke-CIMatrix.ps1'
    )
    foreach ($token in $requiredCiTokens) {
        if (-not $ci.Contains($token)) { Add-Result -Name "ci-token:$token" -Status FAIL -Message 'missing' }
    }
    if ($security -notmatch 'permissions:\s*\r?\n\s*contents:\s*read') {
        Add-Result -Name 'security-permissions' -Status FAIL -Message 'contents read permission missing'
    }
    $templateText = ''
    foreach ($relative in @('.github/ISSUE_TEMPLATE/bug_report.yml', '.github/ISSUE_TEMPLATE/feature_request.yml', '.github/pull_request_template.md')) {
        if (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf) { $templateText += Read-RepoText $relative }
    }
    foreach ($token in @('reproduction', 'test', 'evidence', 'risk', 'rollback')) {
        if ($templateText.ToLowerInvariant().Contains($token)) { continue }
        Add-Result -Name "template-token:$token" -Status FAIL -Message 'missing'
    }
    if ($failures.Count -eq 0) { Add-Result -Name 'ci-schema' -Status PASS -Message 'four runner/shell combinations and controlled actions declared' }
    $matrixStatus = 'FAIL'
    if ($ci -match 'windows-powershell-5\.1' -and $ci -match 'windows-pwsh-7' -and $ci -match 'ubuntu-pwsh-7' -and $ci -match 'macos-pwsh-7') { $matrixStatus = 'PASS' }
    Add-Result -Name 'matrix-size' -Status $matrixStatus -Message 'expected four combinations'
    Test-DocumentationSafety
}

function Invoke-RunnerContract {
    $manifestPath = Join-Path $ArtifactRoot 'skill-manifest.json'
    $layoutScript = Join-Path $projectRoot 'scripts/Test-SkillPackageLayout.ps1'
    $layout = Invoke-ChildScript -ScriptPath $layoutScript -Arguments @('-ManifestPath', $manifestPath)
    if ($layout.code -eq 0 -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Add-Result -Name 'skill-layout' -Status PASS -Message ($layout.output -join ' ')
    }
    else { Add-Result -Name 'skill-layout' -Status FAIL -Message ($layout.output -join ' ') }
    Test-DocumentationSafety

    $fixtureRoot = Join-Path $ArtifactRoot 'fixture'
    $source = Join-Path $fixtureRoot 'source/example-skill'
    $installed = Join-Path $fixtureRoot 'installed/example-skill'
    $evidence = Join-Path $fixtureRoot 'evidence/install'
    $uninstallEvidence = Join-Path $fixtureRoot 'evidence/uninstall'
    $backup = Join-Path $fixtureRoot 'backup/example-skill'
    [IO.Directory]::CreateDirectory((Join-Path $source 'scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $source 'agents')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $source 'references')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'SKILL.md'), "---`nname: example-skill`ndescription: CI fixture`n---`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $source 'agents/openai.yaml'), "interface:`n  display_name: Example`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $source 'scripts/run.ps1'), "Write-Output 'fixture'`n", (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $source 'references/contract.md'), "# fixture`n", (New-Object Text.UTF8Encoding($false)))
    $installer = Invoke-ChildScript -ScriptPath (Join-Path $projectRoot 'scripts/Install-CodexSkillPackage.ps1') -Arguments @('-SourceSkillPath', $source, '-InstalledSkillPath', $installed, '-EvidencePath', $evidence)
    $receipt = Join-Path $evidence 'result.json'
    if ($installer.code -eq 0 -and (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        $uninstaller = Invoke-ChildScript -ScriptPath (Join-Path $projectRoot 'scripts/Uninstall-CodexSkillPackage.ps1') -Arguments @('-InstalledSkillPath', $installed, '-BackupPath', $backup, '-EvidencePath', $uninstallEvidence)
        if ($uninstaller.code -eq 0 -and (Test-Path -LiteralPath $backup -PathType Container) -and -not (Test-Path -LiteralPath $installed)) {
            Add-Result -Name 'portable-install-uninstall' -Status PASS -Message 'fixture install parity and recoverable uninstall passed'
        }
        else { Add-Result -Name 'portable-install-uninstall' -Status FAIL -Message ($uninstaller.output -join ' ') }
    }
    else { Add-Result -Name 'portable-install-uninstall' -Status FAIL -Message ($installer.output -join ' ') }

    $runningOnWindows = ($env:OS -eq 'Windows_NT')
    if ($runningOnWindows) {
        Add-Result -Name 'project-integration' -Status NOT_APPLICABLE -Message 'CI checkout is not an X-drive project worktree'
    }
    else {
        Add-Result -Name 'project-integration' -Status NOT_APPLICABLE -Message 'X-drive project integration is Windows-specific; portable package contract ran'
    }
}

function Invoke-SecurityContract {
    $paths = @('.github/workflows/ci.yml', '.github/workflows/security.yml', 'scripts', 'tests', 'README.md', 'README.zh-CN.md')
    $secretPatterns = @('sk-[A-Za-z0-9]{20,}', 'ghp_[A-Za-z0-9]{20,}', 'github_pat_[A-Za-z0-9_]{20,}', '-----BEGIN (RSA |EC )?PRIVATE KEY-----')
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($relative in $paths) {
        $path = Join-Path $projectRoot $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) { $files = @(Get-Item -LiteralPath $path) }
        elseif (Test-Path -LiteralPath $path -PathType Container) { $files = @(Get-ChildItem -LiteralPath $path -File -Recurse) }
        else { continue }
        foreach ($file in $files) {
            $text = [IO.File]::ReadAllText($file.FullName, (New-Object Text.UTF8Encoding($false, $true)))
            foreach ($pattern in $secretPatterns) { if ($text -match $pattern) { $hits.Add($file.FullName) } }
        }
    }
    if ($hits.Count -gt 0) { Add-Result -Name 'secret-pattern-scan' -Status FAIL -Message ($hits -join ',') }
    else { Add-Result -Name 'secret-pattern-scan' -Status PASS -Message 'no high-confidence secret patterns found' }
    $security = Read-RepoText '.github/workflows/security.yml'
    if ($security -match 'permissions:\s*\r?\n\s*contents:\s*read') { Add-Result -Name 'security-workflow-permissions' -Status PASS -Message 'read-only contents permission' }
    else { Add-Result -Name 'security-workflow-permissions' -Status FAIL -Message 'missing read-only permission' }
}

if ($Mode -eq 'LocalContract') { Invoke-LocalContract }
elseif ($Mode -eq 'Runner') { Invoke-RunnerContract }
else { Invoke-SecurityContract }

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$summary = [ordered]@{
    schema_version = 1
    mode = $Mode
    runner_id = $RunnerId
    shell = $ShellName
    status = $status
    reason_codes = if ($Mode -eq 'Runner' -and -not ($env:OS -eq 'Windows_NT')) { @('PROJECT_INTEGRATION_NOT_APPLICABLE') } else { @() }
    results = $results.ToArray()
}
Write-Json -Path (Join-Path $ArtifactRoot 'ci-results.json') -Value $summary
Write-JUnit -Path (Join-Path $ArtifactRoot 'ci-results.junit.xml') -Items $results.ToArray()

if ($Mode -eq 'LocalContract') {
    if ($status -eq 'PASS') {
        Write-Output 'CI_SCHEMA=PASS'
        Write-Output 'MATRIX_EXPECTED=4'
        Write-Output 'REQUIRED_CORE_ASSERTIONS=PASS'
    }
    else {
        Write-Output 'CI_SCHEMA=FAIL'
        Write-Output 'MATRIX_EXPECTED=4'
        Write-Output 'REQUIRED_CORE_ASSERTIONS=FAIL'
    }
}
elseif ($Mode -eq 'Security') { Write-Output ("SECURITY_STATIC={0}" -f $status) }
else { Write-Output ("CI_RUNNER={0}" -f $status) }
if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Error $_ }; exit 1 }
exit 0
