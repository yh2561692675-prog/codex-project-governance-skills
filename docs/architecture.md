# Architecture

## Purpose

The project is a collection of composable governance Skills rather than a service with a central runtime. Each Skill owns a narrow contract, keeps project identity explicit, and writes evidence to a caller-selected location.

## Layers

```text
project profile + Git identity
            |
            v
development preflight ----> design/plan readiness
            |                         |
            +------------+------------+
                         v
             lightweight governance policy
                         |
                         v
             long-running execution state
                         |
                         v
             evidence-bound closure report
```

- **Identity layer:** `x-project-development-preflight` verifies the real worktree, profile, entry/compliance checks, writer isolation, and shared-resource conflicts.
- **Planning layer:** `project-design-plan-readiness` requires a design and a dependency-ordered plan before a new stage begins.
- **Decision layer:** `lightweight-project-governance` classifies local autonomy, review, escalation, and risk triggers.
- **Execution layer:** `long-running-project-execution` keeps checkpoints, stop conditions, model-routing facts, and resume inputs bound to one candidate.
- **Closure layer:** `evidence-bound-project-closure` reports engineering, installation, real use, human acceptance, formal data, and release independently.
- **Asset layer:** `animate-tech-board` supplies an optional visual-board Skill in the same package layout.

## Installation data flow

1. Read and validate the source Skill identity and required files.
2. Create a source manifest and a source ZIP under the caller's fresh evidence path.
3. Create a short-lived staging directory beside the target installation.
4. Extract and compare the staging manifest with the source manifest.
5. Move an existing target to a recoverable backup, then move the staged directory into place.
6. Compare the installed manifest and write a success receipt.
7. On failure, move any new target aside and restore the previous target when possible.

Evidence paths are create-only. Unknown existing target content is never silently deleted or overwritten.

## Boundaries

The package does not decide whether a user may merge, publish, delete remote branches, expose formal data, or submit an application. Those are human or project-level gates. Tests prove behavior in a fixture; they do not prove human acceptance or external adoption.
