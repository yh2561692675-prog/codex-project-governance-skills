# Candidate and affected-review-scope contract

T04 defines the lightweight governance boundary between an automated candidate and the review scope that candidate can support. These files are project-level skill contracts; they do not read business data, personal content, secrets, or production systems.

## Candidate manifest

`New-LightweightCandidateManifest.ps1` accepts a JSON input and creates one new manifest only when all bindings can be rechecked. The manifest binds the project id, Git root/worktree, current branch, HEAD, dirty state, design and plan paths plus SHA-256 hashes, changed paths, test commands and exit codes, artifacts, risk tier, and rollback text. The output is create-only: an existing output path returns `OUTPUT_EXISTS` and is never overwritten.

The candidate hash is a SHA-256 of the compact JSON representation of the manifest with `candidate_sha256` excluded. Re-running the calculation must produce the same value. A stale planning hash returns `PLANNING_HASH_MISMATCH`; a changed branch, HEAD, Git root, or dirty state returns a stable identity reason code. A candidate is an automated engineering artifact, not proof of real use, human acceptance, formal data approval, or release.

## Affected review scope

`Resolve-AffectedReviewScope.ps1` requires a candidate manifest and its hash. It maps changed paths to tests and evidence references, retains evidence with no dependency intersection, and reports `affected_paths`, `affected_tests`, `invalidated_evidence`, `retained_evidence`, `expanded`, and stable `reason_codes`. Configuration, schema, and `.codex` changes expand the scope with `CONFIG_OR_SCHEMA_CHANGE`. An unmapped non-documentation change expands conservatively with `AFFECTED_PATH_UNMAPPED`; documentation-only changes with no dependency intersection retain evidence and return `NO_AFFECTED_EVIDENCE_INVALIDATION`.

Candidate or output drift is fail-closed with `CANDIDATE_HASH_MISMATCH` or `OUTPUT_EXISTS`. Unknown or unproven impact must expand the review scope; it must never silently narrow it. The generated scope is evidence for review planning only and cannot authorize production publication, protected-data access, external account actions, or formal release.
