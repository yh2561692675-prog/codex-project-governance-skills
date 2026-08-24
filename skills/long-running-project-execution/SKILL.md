---
name: long-running-project-execution
description: Use when an approved X-drive project must execute an itemized implementation plan continuously with model routing, checkpoints, deterministic recovery, bounded retries, two cleanup rounds, and an evidence-bound final handoff.
---

# Long-Running Project Execution

## Purpose

Run one approved implementation plan continuously inside one real Git root or worktree and one authorized writing task. This Skill coordinates evidence and stop conditions; it does not replace project design, preflight, plan readiness, human approval, or formal release.

## Required entry chain

Use these existing Skills before writing project code:

1. `$x-project-development-preflight` to bind the real root, branch, worktree, writer ownership, shared resources, X-drive profile, and current evidence.
2. `$project-design-plan-readiness` to require the approved design and itemized implementation plan with `PLAN_READY=PASS`.
3. `$superpowers:executing-plans` and `$superpowers:test-driven-development` to execute one task at a time with RED, GREEN, REFACTOR, and fresh verification.
4. `$evidence-bound-project-closure` after engineering work to produce a layered review package.

## Model routing

- Design and plan authoring: exact `gpt-5.6-sol` with `high`; revise the design or plan when architecture, scope, dependency, or done criteria must change.
- Plan implementation: exact `gpt-5.6-luna` with `xhigh`; a missing, aliased, or mismatched receipt is `MODEL_POLICY_BLOCKED`.
- Never silently substitute a model or infer a receipt from an earlier task.

## Continuous execution contract

- Bind one project, one approved plan, one implementation phase, one run ID, one worktree, one branch, and one stopping condition.
- Keep `T01` through `Tn` in dependency order. Ordinary test failures are diagnosed, fixed, and re-tested without asking for a stage confirmation.
- Write an immutable manifest, append-only checkpoints, and fresh evidence for every command. Never overwrite an existing run, checkpoint, evidence file, or identity record.
- Pause on `MODEL_POLICY_BLOCKED`, `BLOCKED_CONFLICT`, external or paid side effects, real data, destructive actions, human acceptance, formal release, or a requested scope/architecture change.
- Permit at most two effective retries for the same transient failure, and only after a recorded mitigation. No-change retries do not increase the effective retry count.
- After the main plan, run cleanup round 1 for bounded automatable unfinished items, then cleanup round 2 for only newly retryable or dependency-resolved items. Stop after round 2 and preserve unresolved blockers.
- Report engineering, installation, real use, human acceptance, and formal release separately. Engineering PASS never becomes formal release; formal release defaults to `NO_GO`.

## Script interfaces

The scripts under `scripts/` are deterministic JSON tools. They receive explicit paths, never discover an unrelated project, and fail closed on missing identity or unsafe paths:

- `Test-LongRunExecutionProfile.ps1`
- `New-LongRunManifest.ps1`
- `Invoke-LongRunStateTransition.ps1`
- `Write-LongRunCheckpoint.ps1`
- `Resolve-LongRunResume.ps1`
- `Resolve-LongRunBlocker.ps1`
- `New-LongRunClosureInput.ps1`

Read [execution-contract.md](references/execution-contract.md) and [model-routing-contract.md](references/model-routing-contract.md) before invoking them.

## Stop and handoff

At the stopping condition, create one concentrated engineering review package with commands, exit codes, hashes, known failures, blockers, evidence paths, rollback, and blank human-signoff fields. Keep T12 or an equivalent real-project trial `BLOCKED_HUMAN` until the user selects and authorizes a real project phase.
