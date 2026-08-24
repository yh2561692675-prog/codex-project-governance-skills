# Lightweight governance adapters

These three JSON files are reusable defaults for lightweight project governance:

- `high-impact-data.json` covers data, accepted facts, and recommendation-adjacent work.
- `content-media.json` covers content, media ingestion, and distribution.
- `infrastructure-tooling.json` covers infrastructure, automation, and developer tools.

Each adapter declares the same contract: a default final-review decision, data/media/permission triggers, executable test cases, and a reversible rollback strategy. The defaults are templates only. They intentionally contain no business-project paths, checkout paths, branch or commit identity, candidate identity, formal data, credentials, or personal/student data.

`Convert-LegacyGovernanceProfile.ps1` reads a legacy profile and emits a migration suggestion, a candidate profile, and a diff. It never edits the source profile or a business project. Existing hard gates and historical evidence references are preserved. Unknown fields are returned as `manual_mapping_required`; when the legacy shape cannot be identified, the converter returns a `legacy_fallback` result so the source governance remains the safe baseline.

The adapters are not release approval. A final review, real-data use, human acceptance, and formal release remain separate gates.
