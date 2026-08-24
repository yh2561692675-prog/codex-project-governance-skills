---
name: x-project-development-preflight
description: Use when starting, continuing, resuming, or handing off local project development where the real Git root or worktree, X-drive compliance, dirty state, concurrent writers, shared-resource ownership, or evidence provenance is not yet verified.
---

# X Project Development Preflight

## Overview

Establish a fresh, checkout-bound identity before any project write. A directory name, historical PASS, clean-looking folder, or another worktree's candidate is never current evidence.

## Required Response Shape

Every preflight response fills all seven ordered slots explicitly:

1. `Current verdict`: compute `READY`, `READ_ONLY_ONLY`, or `BLOCKED` from facts already supplied or observed. A known hard blocker dominates unknown checks; a second same-worktree writer or an active shared-resource conflict is immediately `BLOCKED`.
2. `Reason codes`: list known blockers and unknowns.
3. `Observed identity`: target, Git root/worktree, branch, HEAD, common directory, X-local metadata, legacy/recovery exclusion, and tracked plus untracked state collected read-only without reset, clean, or stash.
4. `Project contract`: applicable instructions, profile path/validity, entry/compliance paths, and observed exit codes.
5. `Isolation`: same-worktree writers, shared-resource conflicts, and separated runtime/data/evidence roots. Global project count is informational only and never a blocker.
6. `Evidence boundary`: identify non-transferable historical or other-checkout evidence.
7. `Release criteria`: state the exact facts or successful checks needed for a fresh verdict.

## Workflow

1. Read the nearest project instructions. If the target is under `F:\git仓库`, refresh and use its repository registry before selecting a checkout.
2. Resolve the actual Git root/worktree, branch, HEAD, common Git directory, and tracked/untracked status. Do not reset, clean, stash, or change Git configuration.
3. Read `.codex\x-drive\project-profile.json`; reject missing/invalid profiles, Git metadata outside X, and legacy/recovery roots.
4. Determine same-worktree writers and shared-resource conflicts from current task/thread evidence. Unknown ownership is not permission to write. Do not impose a global project-count limit.
5. From the selected root, run `Enter-XProject.ps1` and `Test-XProjectCompliance.ps1` when required by project policy; preserve both exit codes.
6. Run `scripts/Test-ProjectDevelopmentPreflight.ps1` with the observed counts and exit codes. Read [references/preflight-contract.md](references/preflight-contract.md) for the output contract.
7. Re-issue the seven-slot response from fresh observations. `READY` permits authorized project-scoped development; `READ_ONLY_ONLY` permits bounded inspection, planning, and evidence collection; `BLOCKED` permits no project write.

## Quick Reference

| Verdict | Allowed action |
|---|---|
| `READY` | Authorized project-scoped development may begin |
| `READ_ONLY_ONLY` | Inspect and report; resolve unknown evidence |
| `BLOCKED` | Stop writes; report reason codes and release criteria |

Example after observing the project checks:

```powershell
& '.\scripts\Test-ProjectDevelopmentPreflight.ps1' `
  -ProjectRoot 'X:\Projects\01_Active\Example\01_Workspace\worktrees\feature' `
  -ProjectedWip 2 -SameWorktreeWriterCount 0 -SharedResourceConflictCount 0 `
  -EntryExitCode 0 -ComplianceExitCode 0
```

## Common Mistakes

- Inferring branch or readiness from a folder name.
- Treating `git status` as a substitute for root, HEAD, common-dir, profile, entry, compliance, ownership, and shared-resource checks.
- Reusing F-drive, other-worktree, historical candidate, test, or acceptance evidence.
- Calling a missing observation “probably safe.” Unknowns remain `READ_ONLY_ONLY` or `BLOCKED`.
