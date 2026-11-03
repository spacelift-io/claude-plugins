# Flags, sampling, and cross-policy interaction

## Flags

- `flag` - set of strings. Where the policy evaluates against a run, the flags land on that run's policy receipt and later policies for the same run read them as `run.flags`.
- `reset_flag` - set of flags to clear. A flag is cleared only once every policy that set it has requested the reset, so one policy cannot clear another's flag. Within one receipt, resets apply before that policy's own new flags.

Read-back paths (from the contract):

| Policy | Read-back path |
|---|---|
| PLAN | `input.spacelift.run.flags[]` |
| APPROVAL | `input.run.flags[]` |
| TRIGGER | `input.run.flags[]` (run-completed input only) |
| NOTIFICATION | `input.run_updated.run.flags[]`; per policy `input.run_updated.policy_receipts[].flags[]` (each receipt: `.type`, `.name`, `.outcome`, `.flags[]`) |

GIT_PUSH receipts are stored on the run the push creates, so flags set by GIT_PUSH reach every later policy for that run. A NOTIFICATION policy stores a receipt only when it delivers something, so a notification policy that only sets flags records none.

```rego
package spacelift

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# GIT_PUSH: label runs whose PR touches prod paths.
# Alone it fires no track/propose rule, so it relies on another push policy to create the run.
flag contains "touches-prod" if {
    some f in input.pull_request.diff
    startswith(f, "prod/")
}
```

## Sampling

Every decision includes a `sample` boolean. When it is true, Spacelift stores the input and the result in the policy's evaluation records, where the policy workbench can replay them. LOGIN policies sample by default, and `sample := false` opts out. Every other type defaults to false.

```rego
sample := true   # sample everything while developing; tighten later
```

## Cross-policy interaction

- **NOTIFICATION reads prior policy results** on the same run:
  - `input.run_updated.policy_receipts[]` - one receipt per policy evaluated for the run
  - `input.run_updated.plan_policy_decision.deny[]` / `.warn[]` - the PLAN policies' reason strings (`plan_policy_decision` is null when the run has no plan policy outcome)

```rego
package spacelift

import future.keywords.contains
import future.keywords.if

# NOTIFICATION: alert Slack only when a plan policy denied something
slack contains {"channel_id": "C0123456789", "message": msg} if {
    count(input.run_updated.plan_policy_decision.deny) > 0
    msg := sprintf("Plan policy blocked run %s", [input.run_updated.run.id])
}
```

- **TRIGGER output starts new runs**: each stack ID in `trigger` gets a run. Pick IDs from `input.stacks[]`, the candidate stacks.
- **Flags flow down the lifecycle**: flags set early (e.g. by GIT_PUSH) are readable by PLAN, APPROVAL, TRIGGER and NOTIFICATION through the run's flags - a lightweight signal channel between policies.
