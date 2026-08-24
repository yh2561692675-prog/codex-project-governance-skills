---
name: evidence-bound-project-closure
description: Build an evidence-bound closure report when a development task needs acceptance, release readiness, unfinished-item cleanup, or a final review package.
---

# Evidence-Bound Project Closure

A passing test is an engineering observation, not a release claim. Bind every closure conclusion to the current project identity and show each evidence layer separately.

Use this Skill for a project/task closure, acceptance review, candidate handoff, or release-readiness report. Do not use it to authorize a formal release, human sign-off, real data, external publication, or destructive recovery.

## Workflow

1. Confirm the actual worktree, branch, commit, candidate/installer path and hash. For local project development, run `x-project-development-preflight` first.
2. Collect the approved planning result and verification commands, exit codes, and durable evidence paths. Keep known baseline failures explicit.
3. Create a JSON manifest matching [the closure contract](references/closure-contract.md), or the fresh-run V1.1 contract in [closure-contract-v1.1.md](references/closure-contract-v1.1.md), then run:

   ```powershell
   pwsh -NoProfile -File scripts/New-EvidenceBoundClosureReport.ps1 -ManifestPath <manifest.json> -OutputPath <new-report.md>
   ```

   The output path must be new; the script refuses to overwrite a prior report.
4. Address only authorized, reversible unfinished items. Run a first cleanup round, then recheck remaining blockers once in a second round.
5. Hand over the generated report plus the final review package. V1.1 safe local engineering may end at `LOCAL_CANDIDATE_READY` with justified `NOT_APPLICABLE` layers; formal release remains `NO_GO`/`NOT_APPLICABLE` according to the declared delivery target and never becomes a PASS automatically.

## Non-negotiable distinctions

| Claim | Minimum evidence |
| --- | --- |
| Engineering complete | Current identity plus executed verification and exit code 0 |
| Installation usable | Candidate hash and source commit equal the current commit |
| Real use / human acceptance | Actual run and required manual sign-off, separately recorded |
| Formal release | All gates plus the user's explicit decision |

For V1.1, `NOT_APPLICABLE` is valid only when the resolver's delivery target excludes that layer and the report carries a non-empty applicability reason. Missing evidence, blocked preflight, risk-triggered N/A, source HEAD drift, unresolved template variables, and terminal revival remain failures.

Read [the closure contract](references/closure-contract.md) when choosing manifest fields, classifying a blocker, or preparing the final review package.

Never substitute a fixture, an old worktree, an installer from another commit, or a passing test for missing evidence.
