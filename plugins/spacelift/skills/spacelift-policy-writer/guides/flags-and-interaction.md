# Flags, sampling, and cross-policy interaction

## Flags

- `flag` - set-of-strings output: attaches custom labels to the run, visible in the UI and readable by later policies.
- `reset_flag` - clears previously set flags so only the current policy's `flag` values remain.

Read-back paths (from the contract):

| Policy | Read-back path |
|---|---|
| PLAN | `input.spacelift.run.flags[]` |
| NOTIFICATION | `input.run_updated.policy_receipts[].flags[]` (each receipt: `.type`, `.name`, `.outcome`, `.flags[]`) |

```rego
# GIT_PUSH: label runs whose PR touches prod paths
flag["touches-prod"] {
    some f in input.pull_request.diff
    startswith(f, "prod/")
}
```

## Sampling

Decision JSON (returned by evaluation and by `policySimulatev2`) includes a `sample` boolean. When a policy sets `sample` to true, the input + decision pair is stored as a policy sample, so real inputs can be inspected and replayed later (workbench, `get_policy_sample`).

```rego
sample { true }   # sample everything while developing; tighten later
```

## Cross-policy interaction

- **NOTIFICATION reads prior policy results** on the same run:
  - `input.run_updated.policy_receipts[]` - one receipt per policy evaluated
  - `input.run_updated.plan_policy_decision.deny[]` / `.warn[]` - the PLAN policy's reason strings

```rego
# NOTIFICATION: alert only when the plan policy denied something
send {
    count(input.run_updated.plan_policy_decision.deny) > 0
}
```

- **TRIGGER output starts new runs**: `stacks[id]` triggers runs on downstream stacks; those runs are evaluated by the downstream stacks' *own* GIT_PUSH/PLAN/APPROVAL policies - nothing is inherited from the upstream stack.
- **Flags flow down the lifecycle**: flags set early (e.g. by GIT_PUSH) are readable by PLAN via `input.spacelift.run.flags[]` and by NOTIFICATION via receipts - a lightweight signal channel between policies.

Snippets above use v0 fragment syntax to match the contract examples; for full new policies prefer the portable pattern (`import future.keywords` + `contains`/`if`) from `guides/formatting.md`.
