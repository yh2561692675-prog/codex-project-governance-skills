# Changelog

All notable changes to this project are recorded here. Until a public release is approved, entries describe repository candidates rather than a published version.

## Unreleased

### Added

- V2.0 governance integration ledger and end-to-end contract checks.
- Standard Skill layout checks for `SKILL.md`, `agents/openai.yaml`, `scripts/`, and `references/`.
- Cross-Shell Skill manifest generation with per-file SHA-256 records.
- Fresh installation, source/stage/install parity, and recoverable uninstall smoke tests.
- English and Chinese project documentation drafts.
- MIT license selected and added after maintainer confirmation.

### Fixed

- Windows PowerShell 5.1 path handling for deeply nested X-drive worktrees.
- Cross-Shell Unicode path handling in the governance end-to-end test.
- Behavior-evaluation content hashes now normalize UTF-8 line endings, so equivalent CRLF and LF JSON inputs remain reproducible across archive and runner environments.
- Skill installation manifests now compute SHA-256 through .NET instead of relying on PowerShell module auto-loading.

### Not yet a release claim

- No public repository, version tag, formal release, independent adoption, or program approval is claimed by this entry.
