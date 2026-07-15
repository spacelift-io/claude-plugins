# Policy types by run lifecycle stage

All 8 types use `package spacelift`. Exact input paths per type: `../references/policy-contract.md`.

| Lifecycle stage | Type | Rule outputs | What it controls |
|---|---|---|---|
| **Who gets in** - account & resource access | `LOGIN` | `allow` / `admin` / `deny` (bool); `space_read` / `space_write` / `space_admin` / `teams` (sets); `roles` (map: space slug → role slugs) | Who can authenticate and what spaces, teams, and roles they receive. |
| | `ACCESS` | `allow` / `deny` (bool) | User access to individual stacks and modules. |
| **What becomes a run** - VCS events | `GIT_PUSH` | `track` / `propose` / `ignore` (bool) | Whether a push/PR event creates a tracked run, a proposed run, or nothing. |
| **What gates plan / apply** - inside the run | `PLAN` | `deny` / `warn` (sets of reason strings) | Evaluates the terraform/OpenTofu plan before apply - deny blocks, warn annotates. |
| | `APPROVAL` | `approve` / `reject` (bool) | Auto-approves or rejects runs awaiting approval (e.g. require N unique approvers). |
| | `TASK` | `deny` / `warn` (sets of reason strings) | Which ad-hoc task commands users may execute on a stack. |
| **What happens after** - run reaches a terminal state | `TRIGGER` | `stacks` / `modules` (sets of IDs to trigger) | Starts runs on downstream stacks/modules when a run completes (or a module version is published). |
| | `NOTIFICATION` | `send` (bool); `channels` (set of strings); `message` / `subject` (strings) | Whether, where, and how run updates, internal errors, and module versions are reported. |

## How they compose

- LOGIN gates entry to the account and assigns spaces/roles/teams; ACCESS then gates per-stack/module visibility - together they decide who can act at all.
- GIT_PUSH decides what becomes a run: `track` → tracked run, `propose` → proposed run, `ignore` → nothing. Default behavior is track+propose, so suppression requires `ignore` rules.
- PLAN gates the plan: any `deny` reason blocks the run; `warn` reasons surface in the UI without blocking.
- APPROVAL gates the apply for runs awaiting approval; TASK gates ad-hoc commands with the same deny/warn set pattern.
- TRIGGER fans out on completion: its `stacks[id]` / `modules[id]` output starts runs on downstream stacks, which are then evaluated by *their own* GIT_PUSH/PLAN/APPROVAL policies.
- NOTIFICATION reports outcomes last and can read earlier policies' receipts and the plan decision (`input.run_updated.policy_receipts[]`, `input.run_updated.plan_policy_decision`) - see `flags-and-interaction.md`.
