---
name: lightweight-project-governance
description: Govern an approved project run with lightweight-first development, automatic candidate checks, one final user review, and fail-closed escalation for high-risk work.
---

# Lightweight Project Governance

Use this Skill after the project has passed the X-drive preflight and the design/implementation plan gate. It reads a project governance profile and the P15 catalog, then selects a deterministic governance policy for one isolated project identity. Fresh V1.1 profiles may additionally use `Resolve-LocalAutonomyPolicy.ps1` to select a delivery-bound local terminal state and escalate only when risk or the declared delivery target requires it.

## Workflow

1. Resolve the current Git root, worktree, branch, HEAD, dirty state, profile, and writer/resource ownership with `x-project-development-preflight`.
2. Require the versioned design and itemized implementation plan to pass `project-design-plan-readiness`.
3. Validate the profile and catalog with `Test-ProjectGovernanceProfile.ps1`; a missing, unknown, stale, or cross-project identity is blocked.
4. For a valid `lightweight_first` project, continue the approved plan through autonomous development and automated candidate verification.
5. For a fresh V1.1 profile, resolve `deliveryTarget`, `releaseIntent`, `reviewPolicy`, evidence applicability, and risk precedence in one resolver. `ENGINEERING_ONLY` can end at `LOCAL_CANDIDATE_READY`; `LOCAL_USABLE` requires installation and local smoke evidence; optional review is offered without becoming a required gate.
6. Produce one final user review only when the resolver returns `USER_FINAL_REVIEW`, `ESCALATED_REVIEW`, or the declared review policy is `REQUIRED`. A `needs_changes` decision returns only the affected scope to development and review.
7. Route formal data, personal or student data, secrets, formal recommendations, production/publication, paid actions, external accounts, unknown risk, identity/preflight failures, shared-resource conflicts, and destructive actions to escalation or blocking.
8. Hand the evidence to `evidence-bound-project-closure`. Installation, real use, human acceptance, and formal release remain separate layers; `NOT_APPLICABLE` requires a delivery-target reason and never counts as `PASS`.

## Boundaries

- This Skill is project-scoped and read-only during profile validation. It does not modify project profiles, Git configuration, formal data, personal data, secrets, or external systems.
- P14 human-review acceleration is an optional final-review backend. It is never a prerequisite for ordinary development and must not create human approval automatically.
- Existing preflight, plan-readiness, long-run execution, and evidence-closure Skills retain their responsibilities; this Skill only orchestrates their boundaries.
- It may prepare a candidate and review package but does not publish, merge, tag, upload, pay, or perform formal release. Such actions require an explicit user decision.
- Unknown project identity, path traversal, hash drift, schema drift, duplicate project IDs, and unknown risk fail closed with stable reason codes.
