# Local Autonomy and Risk Escalation Contract

## Input contract

`Resolve-LocalAutonomyPolicy.ps1` accepts a fresh-run V1.1 intent input and the V2 policy. The input declares `delivery_target`, `release_intent`, `review_policy`, `effective_from_fresh_run`, a risk object, and layered evidence. The resolver is the only component that decides terminal state and layer applicability; tier and escalated-gate scripts remain evidence producers.

## Precedence

1. Identity or preflight failure, shared-resource conflict, destructive action, and unknown risk block local autonomy.
2. Known hard triggers produce `ESCALATED_REVIEW` with required review gates.
3. Missing evidence for the declared delivery target blocks; it cannot be hidden with `NOT_APPLICABLE`.
4. The delivery matrix then selects the local or review terminal state.

## Terminal states

| Input | Terminal state | Required review |
|---|---|---|
| `ENGINEERING_ONLY + NONE + NONE` | `LOCAL_CANDIDATE_READY` | No |
| `LOCAL_USABLE + NONE + NONE/OPTIONAL` | `LOCAL_USABLE_READY` or `OPTIONAL_REVIEW_AVAILABLE` | No |
| `INTERNAL_REVIEW + NONE + REQUIRED` | `USER_FINAL_REVIEW` | Yes |
| `FORMAL_RELEASE + INTENDED + REQUIRED` | `READY_FOR_USER_RELEASE_DECISION` | Yes |
| hard trigger | `ESCALATED_REVIEW` | Yes |
| invalid intent, missing evidence, identity/conflict/destructive/unknown risk | `BLOCKED` | Stop |

## Layer rules

Every layer has `PASS`, `BLOCKED`, or `NOT_APPLICABLE` plus `applicability_reason`. Engineering-only tasks may mark installation, real use, human acceptance, formal data, and formal release as N/A because the declared delivery excludes them. Local-usable tasks must pass installation and local smoke. Formal-release tasks may not mark required formal layers N/A.

The resolver does not create approval, formal data, release, publication, or external side effects.
