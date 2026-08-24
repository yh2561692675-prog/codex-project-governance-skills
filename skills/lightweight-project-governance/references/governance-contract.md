# Lightweight Governance Contract

## Governance stages

| Stage | Default behavior | Human boundary |
|---|---|---|
| `DEVELOP_AUTONOMOUS` | Continue approved code, test, documentation, and anonymous fixture work in dependency order. | No pre-development review. |
| `CANDIDATE_AUTOMATED` | Run the declared checks and bind the candidate to project/root/branch/HEAD, plan hashes, changed paths, and rollback evidence. | No formal release. |
| `OPTIONAL_REVIEW` | Offer a review package only when the user requests it. | No review request leaves a safe local candidate ready. |
| `USER_FINAL_REVIEW` | Submit one final review package with `pass`, `needs_changes`, or `reject` when the policy is required. | The user decides. |
| `ESCALATED_REVIEW` | Stop or route to the project-specific high-risk gates. | Formal data, personal/student data, secrets, recommendations, publication, production, paid actions, and external accounts require authorization. |

## Validator output

`Test-ProjectGovernanceProfile.ps1` is read-only and returns JSON with:

```json
{
  "verdict": "READY or BLOCKED",
  "reason_codes": [],
  "project_id": "registered-id-or-null",
  "project_type": "registered-type-or-null",
  "default_review": "disabled-or-null",
  "escalation_triggers": ["formal_data", "personal_or_student_data"]
}
```

`READY` requires a unique catalog project ID, matching profile and catalog identity, verified X-drive Git root, safe relative paths, schema version `1.0` or fresh-run `1.1`, matching optional design/plan/profile/catalog hashes, and `lightweight_first` defaults. V1.1 delivery intent is resolved separately by `Resolve-LocalAutonomyPolicy.ps1`; any identity, policy, evidence, conflict, or risk failure is fail-closed.

## Stable blocker codes

- `BLOCKED_IDENTITY`: `PROJECT_NOT_REGISTERED`, `PROJECT_ID_DUPLICATE`, `GIT_ROOT_MISMATCH`, hash drift, profile/catalog mismatch, or cross-project path.
- `BLOCKED_POLICY`: unsupported schema/policy version, missing protected Git path, sensitive profile flags, or a default-policy mismatch.
- `PROFILE_MISSING`, `CATALOG_MISSING`, `PROFILE_REQUIRED_FIELD_MISSING`, `PROFILE_UNKNOWN_FIELD`, `PROFILE_HASH_MISMATCH`, `CATALOG_HASH_MISMATCH`, `DESIGN_HASH_MISMATCH`, and `PLAN_HASH_MISMATCH` preserve the deterministic detail.

## Skill boundaries

`x-project-development-preflight` owns checkout identity and writer/resource isolation. `project-design-plan-readiness` owns the versioned design/plan gate. `long-running-project-execution` owns the run, model receipt, retries, checkpoints, and cleanup rounds. `evidence-bound-project-closure` owns layered closure. P14 is an optional final-review backend only; it is not a development gate.

Formal release remains `NO_GO` until the user separately authorizes it.
