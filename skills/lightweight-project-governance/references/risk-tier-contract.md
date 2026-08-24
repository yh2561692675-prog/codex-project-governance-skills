# Project Governance Risk-Tier Contract

The resolver is a pure input/output PowerShell command. It reads one anonymous risk input and one versioned risk policy, emits deterministic JSON, and never edits the project, Git metadata, policy, or input.

## Tiers

| Tier | Use | Required gates |
|---|---|---|
| `LIGHTWEIGHT` | Ordinary code, tests, documentation, or anonymous fixtures. | `automatic_development`, `automated_candidate` |
| `CANDIDATE` | Personal content or external material kept as a draft/source reference. | Automatic development, automated candidate, one `user_final_review`. |
| `ESCALATED` | Formal facts, personal/student data, secrets, formal recommendations, publication/production, paid/external account actions, or explicit qualification conditions. | The matching hard gate and `escalated_review`. |
| `BLOCKED` | Unknown or conflicting input, invalid policy, or unsupported trigger. | `risk_resolution`, `user_decision`; no automatic release. |

## Precedence and qualification

Hard triggers are evaluated before the project default. A hard trigger cannot be downgraded by an `ordinary_*` activity. Unknown or conflicting input is fail-closed as `BLOCKED`; it is never treated as ordinary work. The resolver uses a stable trigger order and stable reason codes so equal input produces equal output.

Qualification review is `not_required` unless at least one explicit condition is present: legal approval, license approval, account permission, or a designated responsible role. When a condition is present, the tier is `ESCALATED` and `qualification_review` is required.

## Output

```json
{
  "tier": "LIGHTWEIGHT|CANDIDATE|ESCALATED|BLOCKED",
  "required_gates": [],
  "skipped_gates": [],
  "reason_codes": [],
  "affected_scope": [],
  "qualification_review": "not_required|required",
  "policy_version": "1.0",
  "policy_hash": "SHA-256"
}
```

The process exits `0` for `LIGHTWEIGHT`, `CANDIDATE`, and `ESCALATED`; unknown, conflicting, or invalid input exits `1` with `BLOCKED`. Formal release, publication, production, real data, and human acceptance remain separate user-controlled gates.
