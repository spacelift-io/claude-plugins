# Policy types by run lifecycle stage

All 9 types use `package spacelift`. Exact input paths per type: `../references/policy-contract.md`.

| Lifecycle stage | Type | Rule outputs | What it controls |
|---|---|---|---|
| **Who gets in** - account & resource access | `LOGIN` | `allow` / `admin` / `deny` / `deny_admin` (bool); `team` / `deny_message` (sets); `roles` (map: space ID → role slugs) | Who can authenticate and what spaces, teams, and roles they receive. Root space only. |
| | `ACCESS` | `deny` / `deny_write` / `read` / `write` (bool) | Read or write access to individual stacks and modules. Created in the legacy space only. |
| **What becomes a run** - VCS events | `GIT_PUSH` | `track` / `propose` / `ignore` / `ignore_track` / `notrigger` / `fail` / `notify` / `allow_fork` / `prioritize` (bool); `cancel` / `message` / `external_dependency` (sets of strings); `lock` / `unlock` / `module_version` / `priority` (strings) | Whether a push/PR event creates a tracked run, a proposed run, or nothing. Also run cancellation, stack locks, commit status, module versions and queue priority. |
| **What gates plan / apply** - inside the run | `PLAN` | `deny` / `warn` (sets of reason strings) | Evaluates the plan (Terraform/OpenTofu, Pulumi, CloudFormation, Terragrunt, ...) before apply - deny blocks, warn annotates. |
| | `APPROVAL` | `approve` / `reject` (bool); `approve_with_note` / `reject_with_note` (sets of notes) | Approves or rejects a run (e.g. require N unique approvers). |
| | `TASK` | `deny` (set of reason strings) | Which ad-hoc task commands (`input.request.command`) may run on a stack. Deprecated - Spacelift points to APPROVAL policies instead. |
| **What happens after** - run reaches a terminal state | `TRIGGER` | `trigger` (set of stack IDs); `priority` (`high` / `normal` / `low`) | Starts runs on other stacks when a tracked run reaches a terminal state or a module version is created. Candidates are in `input.stacks[]`. |
| | `NOTIFICATION` | `webhook` / `slack` / `inbox` / `pull_request` (sets of delivery objects) | Where run updates, module versions, internal errors, and worker usage reports are delivered. |
| **Outside runs** - Intent API | `INTENT` | `allow` / `deny` (sets of reason strings) | Resource operations made through the Intent API (`input.resource.*`). |

Every type also reads `flag` / `reset_flag` (sets) and `sample` (bool) - see `flags-and-interaction.md`.

`INITIALIZATION` also exists. It is deprecated, has no entry in the contract, and `policy_input_schema` returns no schema for it. Write an APPROVAL policy instead.

## How they compose

- LOGIN gates entry to the account and assigns teams and per-space roles. Every login policy on the account is evaluated and their results are combined. ACCESS then grants read or write on a stack or module: `deny` overrides everything, `write` implies read, `deny_write` cancels `write`.
- GIT_PUSH decides what becomes a run: `ignore` beats everything, then `track` (unless `ignore_track`), then `propose`. Booleans are OR-ed across attached push policies. When no rule fires, the push is ignored. Spacelift's built-in default (track pushes to the tracked branch, propose other branches and opened or updated PRs, skip tags and changes outside the project root) runs only when no push policy is attached or the account is not entitled to workflow policies.
- PLAN gates the plan: any `deny` reason blocks the run; `warn` reasons surface in the UI without blocking.
- APPROVAL decides a run awaiting approval: every approval policy must approve, a single `reject` rejects, and approve plus reject in one policy leaves the run undecided. TASK gates ad-hoc commands with a `deny` set.
- TRIGGER fans out on completion: each ID in `trigger` starts a run on that stack. `priority` applies to every run the policy triggers.
- NOTIFICATION reports outcomes last and can read earlier policies' receipts and the plan decision (`input.run_updated.policy_receipts[]`, `input.run_updated.plan_policy_decision`) - see `flags-and-interaction.md`.
- INTENT decides an Intent API operation: any `deny` reason denies, an `allow` reason with no `deny` allows, and neither leaves it pending.
