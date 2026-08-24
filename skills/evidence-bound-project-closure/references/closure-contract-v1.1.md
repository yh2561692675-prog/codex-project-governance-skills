# Closure Contract V1.1

V1.1 closure manifests are emitted only for a fresh resolver run and add:

```json
{
  "delivery_target": "ENGINEERING_ONLY|LOCAL_USABLE|INTERNAL_REVIEW|FORMAL_RELEASE",
  "release_intent": "NONE|INTENDED",
  "review_policy": "NONE|OPTIONAL|REQUIRED",
  "preflight_status": "READY|BLOCKED",
  "resolver": {
    "governance_mode": "LOCAL_AUTONOMOUS|USER_REVIEW|ESCALATED|BLOCKED",
    "terminal_state": "LOCAL_CANDIDATE_READY|LOCAL_USABLE_READY|OPTIONAL_REVIEW_AVAILABLE|USER_FINAL_REVIEW|ESCALATED_REVIEW|READY_FOR_USER_RELEASE_DECISION|BLOCKED",
    "required_review": false,
    "risk_codes": [],
    "layers": [{ "name": "formal_release", "status": "NOT_APPLICABLE", "applicability_reason": "releaseIntent=NONE" }]
  }
}
```

The V1.1 generator preserves the six evidence layers separately. Engineering-only may mark installation, real use, human acceptance, formal data, and formal release `NOT_APPLICABLE` when the resolver provides a reason. Local-usable requires installation and local smoke evidence. Formal-release cannot use N/A for required formal layers.

The generator fails closed for blocked preflight completion, risk-triggered N/A, missing local evidence, missing formal gates, empty applicability reasons, or an invalid resolver terminal. It is cross-shell tested under Windows PowerShell 5.1 and PowerShell 7 and writes a new report only.

`Test-ClosureArtifactIntegrity.ps1` additionally validates candidate and policy hashes, source HEAD binding, required references, template-variable absence, preflight state, terminal monotonicity, and formal-release gate completeness. It is read-only and does not create approval or release state.
