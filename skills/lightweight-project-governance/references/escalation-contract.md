# Escalated governance gates contract

`Resolve-EscalatedGovernanceGates.ps1` is the fail-closed bridge between lightweight/candidate status and high-risk project actions. It is pure input/output, does not read business data, and does not authorize a real-world action.

## Hard-trigger routing

The resolver recognizes formal data, `AcceptedFact`, formal recommendation, personal or student data, production/publication, and paid or external-account actions. Each trigger produces deterministic `required_approvals`, `owners`, `required_evidence` (also exposed as `evidence`), `release_criteria`, `recovery_entry`, and `reason_codes`. Missing any required approval or evidence returns `BLOCKED_ESCALATION`; a candidate PASS or ordinary final-review PASS cannot bypass the trigger.

The normal routes are:

- Formal data: business and compliance owners; source register, fact verification, provenance; formal-data source review, human acceptance, formal release approval; formal-data rollback.
- AcceptedFact: business and source owners; source register and fact verification; accepted-fact verification and formal release approval; accepted-fact rollback.
- Formal recommendation: business, compliance, and recommendation reviewer; source trace, criteria, human review; human recommendation review and user final approval; recommendation rollback.
- Personal/student data: data-protection and compliance owners; authorized scope, minimization, access log; protected-data approval and access review; delete/revoke recovery.
- Production/publication: release, business, and compliance owners; release checklist, rollback plan, observability; release approval and rollback readiness; release rollback.
- Paid/account action: account owner and external-action approver; account authorization and payment approval; external-action approval and reversibility; revoke/refund recovery.

## Qualification minimization

`qualification_review` is `not_required` unless the input explicitly identifies a legal basis, license, account permission, or designated role. When explicit, it adds a qualification owner, qualification basis evidence, completion criterion, and revoke recovery; missing inputs fail closed. Ordinary personal tools receive only project-developer/engineering gates and do not automatically require business leadership, compliance ownership, or a second reviewer.

Unknown triggers and conflicting signals fail closed. The output is a routing decision and evidence checklist only; it does not replace human acceptance, formal release approval, protected-data authorization, or external-action consent.
