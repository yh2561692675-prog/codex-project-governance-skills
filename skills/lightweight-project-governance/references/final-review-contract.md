# Final user review package contract

T05 creates one project-scoped final review entry for an automated candidate. The package is an engineering handoff and review aid; it is not a human approval, formal-data authorization, production release, or main-branch merge.

## Package binding

`New-FinalUserReviewPackage.ps1` reads one T04 candidate manifest and one affected-review-scope manifest. It re-computes and binds both SHA-256 values before creating a package. The package summarizes project and candidate identity, planning hashes, changed paths, mapped tests, risk tier and notes, known failures, affected and retained evidence, rollback, pending decisions, and optional P14 adapter status. Its output path is create-only.

The default mode is `single_user`. The only decision values are `通过`, `需修改`, and `不通过`; the default `user_decision` and `user_conclusion` are blank. A caller may supply a decision as an explicit human-input simulation. Only `需修改` emits `revision_scope`, and that scope contains affected paths, affected tests, invalidated evidence, and reason codes for incremental re-review. A package with no P14 adapter remains valid as `SIMPLIFIED_NO_P14`; an available valid adapter is reported as `P14_ADAPTER_AVAILABLE` without making P14 a development-front-door dependency.

## Receipt binding

`Test-FinalUserReviewReceipt.ps1` validates the package self-hash, the receipt self-hash, the receipt's package hash, and the package id. A valid receipt returns `BIDIRECTIONAL_HASH_VERIFIED`; package drift, receipt drift, id drift, and output reuse fail closed with stable reason codes. Validation results are also create-only.

Human conclusion, reviewer identity, and formal acceptance remain empty until a human supplies them. A passing package or receipt does not imply real use, human acceptance, formal release, or external publication.
