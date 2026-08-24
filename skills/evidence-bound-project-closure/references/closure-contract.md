# Closure report contract

## Manifest

Provide UTF-8 JSON with the required shape below. `identity` binds conclusions to one current checkout; never borrow a commit, test result, candidate, or installer from another worktree.

```json
{
  "identity": { "project": "...", "task": "...", "worktree": "...", "branch": "...", "commit": "..." },
  "planning_status": "PASS|PENDING|FAIL",
  "engineering": { "status": "PASS|FAIL|PENDING", "command": "...", "exit_code": 0, "log_path": "..." },
  "installation_status": "PASS|PENDING|FAIL",
  "installer": { "path": "...", "source_commit": "...", "sha256": "..." },
  "real_use_status": "PASS|PENDING|FAIL",
  "human_acceptance_status": "PASS|PENDING|FAIL",
  "formal_data_status": "PASS|NO_GO|PENDING",
  "rollback_rehearsal_status": "PASS|PENDING|FAIL"
}
```

The script rejects missing identity fields and an existing output report. `engineering_status` is `PASS` only for manifest status `PASS` and exit code `0`. Installation is `BLOCKED_SOURCE_UNVERIFIED` without an installer source commit and `BLOCKED_SOURCE_MISMATCH` when that commit differs from `identity.commit`.

## Layer rules

- `planning_status=PASS` means the applicable design and itemized plan passed their readiness gate; it is not engineering completion.
- Engineering, installation, real use, human acceptance, formal data, and rollback are independent layers.
- Formal release is `NO_GO` until every layer is `PASS`. If they are all `PASS`, the report says `READY_FOR_USER_DECISION`; it never performs or claims a formal release.

## Cleanup and handoff

First address authorized unfinished plan items, rerun their verification, and emit a fresh report. Then recheck remaining blockers once after dependency changes. For lasting blockers record reason, impact, required input, and recovery entry.

The final human review package must include identity, change summary, readiness, commands/exit codes/logs, known failures, candidate paths/hashes/source binding, rollback proof, layer statuses, risks, blockers, and recovery instructions. Mainline merge, formal tag/release, formal data, human sign-off, destructive actions, and external/public changes remain user decisions.
