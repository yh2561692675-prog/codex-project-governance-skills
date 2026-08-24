# Security Policy

## Scope

This repository contains PowerShell scripts and documentation for local project governance and Skill installation. It is not a secret store, an API proxy, or a production deployment service.

## Do not report secrets publicly

Never put API keys, access tokens, cookies, passwords, private certificates, personal data, or private repository contents in an Issue or pull request. If a secret was committed, revoke or rotate it first, then report only the minimum metadata needed to investigate.

## Reporting a vulnerability

Open a private security report through the repository's configured Git hosting security channel when available. If that channel is unavailable, open an Issue containing only a short, non-sensitive summary and request a private follow-up. Include:

- affected file and version or commit;
- reproducible steps without secrets or personal data;
- impact and the smallest safe mitigation;
- whether the issue is already exposed in a public release.

Do not test against systems that you do not own or have permission to assess.

## Safety boundaries

The installer uses create-only evidence paths, stages a complete package, preserves an existing installation in a rollback directory, and refuses unknown target conflicts. Review any path before running a script. Treat a local test result as local evidence; it is not authorization to publish, merge, delete, or access formal data.

## Maintainer response

Maintainers will acknowledge a valid report, reproduce it in an isolated fixture when possible, record the affected candidate, and publish a fix or mitigation with a regression test. Public disclosure timing is decided after the affected users can update.
