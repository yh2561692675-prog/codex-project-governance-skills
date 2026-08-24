# Planning Contract

Read this reference when drafting or reviewing the design/plan pair.

## Direction-alignment record

| Field | Required content |
|---|---|
| Baseline | Exact current direction/roadmap/plan paths, versions, hashes, and relevant evidence |
| Alignment | Long-term goal and the new change's contribution |
| Conflicts | Fill `Conflict`, `Affected/replaced items`, `Required revision`, and `Dependency/WIP impact` as separate labels |
| Boundaries | Scope, non-goals, formal-data and human/release gates |
| Safety | Risk, rollback, recovery entry, and evidence that cannot transfer |

## Design document

The next-version implementation design filename is `<项目>_设计文档_Vx.y.md`. Existing `_方向设计_`, roadmap, plan, and acceptance-window files remain preserved baselines; do not reuse `_方向设计_` as the required design-document filename.

The design contains:

1. deliverable goal;
2. included scope and explicit non-goals;
3. current state, project root, technology/data/compatibility constraints, and prohibited actions;
4. module dependency table with satisfaction criteria;
5. at least two candidate approaches with benefits, risks, rollback difficulty, recommendation, and reasons;
6. automatic-adoption boundary;
7. whole-project binary done criteria;
8. focused/regression/safety validation, evidence path, human gates, risks, and rollback.

## Itemized implementation task

Every task contains all of these fields:

- unique sequential ID and status;
- dependencies and blocked successors, with matching forward/reverse references;
- recommended approach;
- exact files to create, modify, and test;
- concrete implementation actions;
- binary completion checkboxes;
- executable verification command and working directory;
- expected exit code and key output;
- durable evidence path;
- known baseline failure;
- failure diagnosis, bounded retry, and blocker rule;
- rollback method.

Dependencies must exist, contain no self-reference or cycle, and place `READY` only where prerequisites are satisfied.

## Machine gate

Run from the selected project Git root. The checker path below is a canonical constant; copy it exactly. If the target Git root is not yet verified, report `<selected-project-git-root>` instead of substituting the current shell directory.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File '<CODEX_HOME>\scripts\Test-PlanReadiness.ps1' `
  -DesignPath '<absolute-design-path>' `
  -PlanPath '<absolute-plan-path>'
```

The only ready result is process exit 0 plus `PLAN_READY=PASS`. Record the output and paths. This result means planning ready; engineering, installation, real use, human acceptance, and formal release remain pending until separately proven.
