# Model Routing Contract

| Activity | Exact model | Reasoning | Failure code |
|---|---|---|---|
| Design or plan revision | `gpt-5.6-sol` | `high` | `MODEL_POLICY_BLOCKED` |
| Approved-plan implementation | `gpt-5.6-luna` | `xhigh` | `MODEL_POLICY_BLOCKED` |

The implementation receipt must come from the current task/session context and include the task ID, timestamp, project root, branch, HEAD, design hash, and plan hash. Model aliases, missing receipts, or a receipt copied from another task are invalid. The implementation Skill may stop, report the policy blocker, and request a new Luna/xhigh task; it may not silently downgrade or substitute.
