# Project Development Governance Skills

Reusable Codex Skills for making project work auditable, bounded, and recoverable. The package focuses on the parts of development that are easy to claim but hard to prove: selecting the real checkout, preserving evidence provenance, enforcing risk gates, resuming long work safely, and separating local engineering from human acceptance and formal release.

This is an independent open-source project. It is not an OpenAI product, does not grant Codex or API access, and does not guarantee approval for any program or repository.

## What is included

| Skill | Purpose |
|---|---|
| `x-project-development-preflight` | Bind work to the real X-drive Git root/worktree, profile, branch, writer, and evidence identity. |
| `project-design-plan-readiness` | Check that a design document and dependency-ordered implementation plan are complete before code work. |
| `lightweight-project-governance` | Resolve local-autonomy, review, escalation, and risk-tier decisions without silently widening scope. |
| `long-running-project-execution` | Execute an approved plan with checkpoints, model-routing constraints, resumable state, and fail-closed blockers. |
| `evidence-bound-project-closure` | Produce a closure report that keeps engineering, installation, real use, human acceptance, formal data, and release separate. |
| `animate-tech-board` | Optional visual-board asset used by the media workflow; kept in the same installable layout. |

## Requirements

- Windows with Windows PowerShell 5.1 or PowerShell 7.
- A Git worktree for project-governance Skills. The preflight Skill expects the project to provide its own profile and entry/compliance checks.
- A Codex Skills directory selected by the user. The installer never changes global `CODEX_HOME`, secrets, or unrelated directories.

Linux and macOS support are not claimed in this release. Contributions may add it only with a separate cross-platform test matrix.

## Install one Skill from a checkout

Run from the repository root. Replace the name with one of the Skill directories above.

```powershell
$skillName = 'x-project-development-preflight'
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$installPath = Join-Path $codexHome "skills\$skillName"
$evidencePath = Join-Path $codexHome "skill-install-evidence\$skillName"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexSkillPackage.ps1 `
  -SourceSkillPath ".\skills\$skillName" `
  -InstalledSkillPath $installPath `
  -EvidencePath $evidencePath
```

The install is staged and parity-checked before the target is switched. Existing content is moved to a recoverable backup. Evidence paths are create-only; an existing evidence directory blocks the operation.

## Verify and uninstall

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-SkillPackageLayout.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SkillInstallation.ps1
```

To remove an installed Skill without destructive deletion, provide a fresh backup and evidence path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexSkillPackage.ps1 `
  -InstalledSkillPath $installPath `
  -BackupPath (Join-Path $codexHome "skills-backups\$skillName-manual") `
  -EvidencePath (Join-Path $codexHome "skill-uninstall-evidence\$skillName-manual")
```

## Evidence model

The project reports these layers independently:

1. Engineering implementation and automated tests.
2. Fresh installation and source/install SHA-256 parity.
3. Local real-use evidence in a named project/worktree.
4. Human acceptance and review decisions.
5. Formal data or signed organizational approval.
6. Public release and independent adoption.

A passing test, fixture, candidate package, or single demonstration cannot substitute for a later layer. The Skills fail closed when identity, ownership, evidence, or a required human decision is unknown.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [docs/maintenance.md](docs/maintenance.md) before opening an issue or pull request. Every behavior change needs a focused test and a short evidence note. Do not include API keys, cookies, personal data, local absolute paths, or generated installation directories.

## License

This project is released under the [MIT License](LICENSE).

## Roadmap

- Publish a reviewed license and a versioned release after maintainer approval.
- Add independent public usage cases with reproducible manifests.
- Add cross-platform support only with native CI evidence.
- Add plugin integrations after the core install and governance contracts remain stable.

## Status

This public repository contains the V2.0 governance integration and portable installation hardening. It is a pre-release candidate: no version tag, GitHub Release, external adoption, human acceptance, or program approval is claimed.
