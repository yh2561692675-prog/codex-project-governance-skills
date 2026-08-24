# Execution Contract

## Identity

Every run is bound to one X-drive project root, one real Git root or worktree, one branch, one implementation phase, one design hash, one plan hash, one model receipt, one run ID, and one stopping condition. A changed upstream identity invalidates downstream evidence.

## States

The state engine accepts only explicit events. Normal progress is `READY -> RUNNING -> CHECKPOINTED -> COMPLETED`; transient failures use `RETRY_PENDING`; model, conflict, external, destructive, and human gates use `BLOCKED_*`; cleanup uses `CLEANUP_ROUND_1 -> CLEANUP_ROUND_2 -> COMPLETED` or a preserved blocked terminal state. Terminal states cannot be revived.

## Evidence

Manifest and checkpoint outputs are create-only. A checkpoint records the task ID, command, exit code, evidence locator, evidence SHA-256, prior checkpoint hash, design/plan identity, and writer identity. Evidence from another checkout, run, candidate, or stale identity is non-transferable.

## Recovery and retries

Resume starts only from the last valid checkpoint after verifying current identity and proving the old writer is inactive. Unknown ownership is read-only or conflict-blocked. A retry requires a recorded mitigation and is capped at two effective retries; an unchanged retry is rejected.

## Cleanup and review

Round 1 handles only bounded automatable unfinished items. Round 2 handles only items with a new mitigation or resolved dependency, then stops. The closure input separates engineering, installation, real use, human acceptance, and formal release; formal release is `NO_GO` until the user decides.
