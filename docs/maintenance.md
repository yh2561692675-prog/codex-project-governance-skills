# Maintenance Guide

## Issue triage

Use a reproducible title and include the affected Skill, shell version, candidate commit, command, exit code, and sanitized output. Classify the issue as layout, installation, identity/preflight, planning, governance policy, execution/resume, closure evidence, documentation, or security. Do not paste secrets or private data.

## Pull request review

Maintainers review each PR in an isolated worktree. The review checklist is:

- source and target identity are explicit;
- only one writer owns the worktree;
- no shared-resource conflict is hidden;
- changed behavior has focused tests in PowerShell 5.1 and 7 when applicable;
- failure paths preserve existing targets and write bounded evidence;
- documentation and examples match the tested contract;
- engineering status is not presented as human acceptance, formal data, release, or adoption.

## Normal release flow

1. Finish the approved implementation plan and run the two-shell contract suite.
2. Complete the first and second unfinished-item reviews; record blockers instead of bypassing them.
3. Prepare a candidate closure package with commit, hashes, tests, known failures, rollback, and evidence-layer status.
4. Obtain maintainer approval for the license, default-branch merge, version tag, and public release.
5. Publish release notes that distinguish verified facts from planned work.
6. Observe real users and external cases separately; never infer adoption from a local demo or a download.

## Rollback

For a local Skill install, use the recorded backup locator and the recoverable uninstall helper. For source changes, revert the focused commit or use a new corrective commit; do not reset, clean, stash, or overwrite an unknown worktree. For a public release, the maintainer decides whether to yank, supersede, or document it.

## Evidence retention

Keep candidate-bound evidence under the project acceptance-evidence root. Preserve prior plans and future-development windows. A later correction is an append-only ledger entry, not a rewrite of historical evidence.
