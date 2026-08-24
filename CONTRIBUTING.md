# Contributing

Thanks for helping improve the project-development governance Skills.

## Before you start

1. Read `AGENTS.md` and the applicable Skill contract.
2. Work in a real, isolated Git worktree with one code writer.
3. For a new version or implementation stage, keep the design document and dependency-ordered implementation plan in `docs/future-development/`.
4. Do not include secrets, personal data, private repository material, generated installation directories, or local absolute paths.

## Pull requests

- Keep one coherent change per PR.
- Explain the problem, scope, non-goals, risk, rollback, and evidence location.
- Add or update focused tests for behavior changes.
- Run the relevant PowerShell 5.1 and PowerShell 7 checks when touching scripts.
- Distinguish engineering PASS, installation PASS, local real use, human acceptance, formal data, and release status.
- Do not claim external adoption, approval, or release until a maintainer records independent evidence.

## Review expectations

Reviewers check identity binding, path safety, clean failure behavior, cross-Shell parsing, evidence provenance, and documentation parity. A reviewer may request a smaller scope or a fresh fixture rather than accepting a historical result.

## Commit and release hygiene

Use focused commits and explicit file lists. Maintainers, not automated tests, decide merges to the default branch, version tags, public releases, license changes, and external communications.
