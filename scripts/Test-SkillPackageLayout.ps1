[CmdletBinding()]
param(
    [string]$SkillsRoot,
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($SkillsRoot)) {
    $SkillsRoot = Join-Path (Split-Path -Parent $scriptRoot) 'skills'
}
$errors = New-Object System.Collections.Generic.List[string]
$manifestSkills = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath $SkillsRoot -PathType Container)) { throw "SKILLS_ROOT_MISSING:$SkillsRoot" }
foreach ($skill in @(Get-ChildItem -LiteralPath $SkillsRoot -Directory | Sort-Object Name)) {
    $required = @(
        (Join-Path $skill.FullName 'SKILL.md'),
        (Join-Path $skill.FullName 'agents\openai.yaml'),
        (Join-Path $skill.FullName 'scripts'),
        (Join-Path $skill.FullName 'references')
    )
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path)) { $errors.Add("LAYOUT_MISSING:$path") }
    }
    $skillFile = Join-Path $skill.FullName 'SKILL.md'
    if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
        $text = [IO.File]::ReadAllText($skillFile, (New-Object Text.UTF8Encoding($false, $true)))
        if ($text -notmatch '(?m)^name:\s*[a-z0-9-]+\s*$') { $errors.Add("SKILL_NAME_MISSING:$skillFile") }
        if ($text -match '\{\{[^}]+\}\}') { $errors.Add("TEMPLATE_VARIABLE:$skillFile") }
    }
    $files = @(
        Get-ChildItem -LiteralPath $skill.FullName -File -Recurse |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    relative_path = $_.FullName.Substring($skill.FullName.Length).TrimStart('\').Replace('\', '/')
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                    length = [long]$_.Length
                }
            } |
            # Sort by UTF-8 bytes instead of the host culture so PS5.1 and PS7
            # emit the same manifest order for punctuation and versioned names.
            Sort-Object { [BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes([string]$_.relative_path)) }
    )
    $manifestSkills.Add([pscustomobject][ordered]@{
        name = $skill.Name
        relative_path = $skill.Name
        required_paths = @('SKILL.md', 'agents/openai.yaml', 'scripts', 'references')
        file_count = $files.Count
        files = $files
    })
}
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    Write-Output "SKILL_LAYOUT=FAIL"
    exit 1
}
if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
    $manifestFullPath = [IO.Path]::GetFullPath($ManifestPath)
    $manifestParent = [IO.Path]::GetDirectoryName($manifestFullPath)
    if ([string]::IsNullOrWhiteSpace($manifestParent)) { throw "MANIFEST_PARENT_INVALID:$manifestFullPath" }
    if (-not (Test-Path -LiteralPath $manifestParent -PathType Container)) {
        New-Item -ItemType Directory -Path $manifestParent -Force | Out-Null
    }
    $manifest = [ordered]@{
        schema_version = 1
        generated_at_utc = [DateTime]::UtcNow.ToString('o')
        skills_root = [IO.Path]::GetFullPath($SkillsRoot)
        skill_count = $manifestSkills.Count
        skills = $manifestSkills.ToArray()
    }
    [IO.File]::WriteAllText($manifestFullPath, ($manifest | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    Write-Output "SKILL_MANIFEST=$manifestFullPath"
}
Write-Output "SKILL_COUNT=$(@(Get-ChildItem -LiteralPath $SkillsRoot -Directory).Count)"
Write-Output 'SKILL_LAYOUT=PASS'
exit 0
