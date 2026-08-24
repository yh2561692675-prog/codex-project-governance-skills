# Preflight Contract

Read this reference when producing the preflight verdict or explaining a blocker.

## Required observations

| Area | Required evidence |
|---|---|
| Identity | Explicit target path, resolved Git root/worktree, branch, HEAD, Git common directory |
| Local state | Tracked and untracked status; no reset, clean, stash, overwrite, or global Git config change |
| Project contract | Applicable instructions, project profile validity, entry script and compliance script paths |
| X-drive binding | Project root and Git metadata on X; no legacy or recovery snapshot root |
| Isolation | Same-worktree writer count, shared-resource conflict count, and dedicated runtime/data/log/temp/export/evidence roots when project rules require them. Global project count is informational only. |
| Execution | Observed entry and compliance exit codes, not inferred results |
| Provenance | Current source/worktree/run/candidate only; historical and other-checkout evidence remains non-transferable |

## Verdict contract

The report fills all seven ordered slots and computes the first slot before describing future checks:

1. `Current verdict`: `READY`, `READ_ONLY_ONLY`, or `BLOCKED`, based on all facts already present in the request and fresh observations. Known hard blockers dominate unknowns.
2. `Reason codes`: every hard blocker and unknown.
3. `Observed identity`: target, root/worktree, branch, HEAD, common directory, X-local metadata, explicit legacy/recovery exclusion, and tracked plus untracked state gathered read-only without reset, clean, or stash.
4. `Project contract`: applicable instructions, profile path/validity, entry/compliance observations and exit codes.
5. `Isolation`: same-worktree writers, shared-resource conflicts, and separated runtime/data/evidence roots; global project count does not affect the verdict.
6. `Evidence boundary`: state that no PASS/candidate/run transfers from another source.
7. `Release criteria`: exact missing observation or successful command needed to change the verdict.

`READY` requires all required observations and successful project checks. A clean worktree alone is insufficient. `READ_ONLY_ONLY` is appropriate when identity is safe enough to inspect but same-worktree writer, shared-resource, entry, or compliance evidence is unknown. Hard identity, profile, location, dirty-state, same-worktree writer, shared-resource, entry, or compliance failures are `BLOCKED`. The number of active projects never changes the verdict.

## Safety boundary

The bundled script is read-only. It does not run project scripts, acquire ownership, create a worktree, repair a profile, change Git configuration, or authorize destructive actions. The caller supplies same-worktree writer count, shared-resource conflict count, and observed exit codes from separately authorized checks. `ProjectedWip` remains an optional informational compatibility field only.
