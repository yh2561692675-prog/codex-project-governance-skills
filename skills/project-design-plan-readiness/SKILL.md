---
name: project-design-plan-readiness
description: Use when a new project, version, subsystem, implementation stage, future-direction revision, design document, itemized implementation plan, or plan-readiness decision is required before code changes.
---

# Project Design and Plan Readiness

## Overview

Turn an approved development direction into a versioned decision baseline and executable task contract. `PLAN_READY=PASS` authorizes code start only; it proves no delivery or release layer.

**REQUIRED SUB-SKILL:** Use `x-project-development-preflight` before selecting a project root or writing planning files.

## Required Response Shape

Fill all seven slots:

1. `Current code-start verdict`: `BLOCKED_FOR_CODE / PLAN_NOT_READY` until the new pair passes the machine gate.
2. `Baseline inventory`: current instructions, evidence, direction, roadmap, design, plan, and acceptance-window files; preserve every historical version.
3. `Direction alignment`: fill these labels explicitly — `Long-term goal`, `Scope/non-goals`, `Conflict`, `Affected/replaced items`, `Required revision`, `Dependency/WIP impact`, `Evidence gates`, `Risk`, and `Rollback`.
4. `Design output`: exact next-version path using `<项目>_设计文档_Vx.y.md` (not `_方向设计_`), at least two candidate approaches, recommendation/reasons, module dependencies, whole-project binary done criteria, validation, risks, rollback, and automatic-adoption boundary.
5. `Plan output`: exact next-version path and the complete per-task contract from [references/planning-contract.md](references/planning-contract.md).
6. `Machine gate`: use the canonical checker path `<CODEX_HOME>\scripts\Test-PlanReadiness.ps1` exactly; state the verified selected project Git root as working directory, or keep `<selected-project-git-root>` when it is unknown. Include expected exit 0 and `PLAN_READY=PASS`.
7. `Delivery boundary`: planning readiness, engineering, installation, real use, human acceptance, and formal release remain separate.

## Workflow

1. Run `scripts/Find-ProjectPlanningBaseline.ps1` read-only; inspect every returned planning file relevant to the requested direction.
2. Create the next version under `docs/future-development/`. Never overwrite, rename, or delete direction, roadmap, plan, or acceptance-window history.
3. Write two Markdown files: `<项目>_设计文档_Vx.y.md` and `<项目>_逐项实施计划_Vx.y.md`.
4. Self-review for placeholders, contradictions, dependency cycles, ambiguous completion, missing commands, and unmatched forward/reverse blockers.
5. From the selected Git root run the canonical command below with both absolute paths. Copy the checker path exactly; the current shell directory is not a substitute for an unverified project root.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File '<CODEX_HOME>\scripts\Test-PlanReadiness.ps1' `
  -DesignPath '<absolute-design-path>' `
  -PlanPath '<absolute-plan-path>'
```
6. Start authorized implementation only after exit 0 and `PLAN_READY=PASS`. Otherwise report exact failures and continue planning only.

## Quick Reference

| Observation | Code-start verdict |
|---|---|
| Pair absent, stale, or unchecked | `BLOCKED_FOR_CODE / PLAN_NOT_READY` |
| Checker fails or exits nonzero | `BLOCKED_FOR_CODE / PLAN_NOT_READY` |
| Exit 0 and `PLAN_READY=PASS` | Planning ready; engineering still pending |

## Common Mistakes

- Editing the previous version in place.
- Producing one roadmap instead of the design/plan pair.
- Writing TODO tasks without binary done criteria, commands, exit codes, evidence, failure handling, and rollback.
- Treating a ready plan as implementation, installation, acceptance, or release proof.
