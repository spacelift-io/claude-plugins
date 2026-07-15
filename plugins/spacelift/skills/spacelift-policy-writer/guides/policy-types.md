# Policy Types by Run Lifecycle Stage

All 8 types use `package spacelift`. Exact input paths per type: `../references/policy-contract.md`.

```
WHO GETS IN ──────────────────── account & resource access
├─ LOGIN     outputs: allow / admin / deny (bool); space_read / space_write / space_admin / teams (sets); roles (map: space slug → role slugs)
│            Controls who can authenticate and what spaces, teams, and roles they receive.
└─ ACCESS    outputs: allow / deny (bool)
             Controls user access to individual stacks and modules.

WHAT BECOMES A RUN ───────────── VCS events
└─ GIT_PUSH  outputs: track / propose / ignore (bool)
             Decides whether a push/PR event creates a tracked run, a proposed run, or nothing.

WHAT GATES PLAN / APPLY ──────── inside the run
├─ PLAN      outputs: deny / warn (sets of reason strings)
│            Evaluates the terraform/OpenTofu plan before apply — deny blocks, warn annotates.
├─ APPROVAL  outputs: approve / reject (bool)
│            Auto-approves or rejects runs awaiting approval (e.g. require N unique approvers).
└─ TASK      outputs: deny / warn (sets of reason strings)
             Controls which ad-hoc task commands users may execute on a stack.

WHAT HAPPENS AFTER ───────────── run reaches a terminal state
├─ TRIGGER       outputs: stacks / modules (sets of IDs to trigger)
│                Starts runs on downstream stacks/modules when a run completes (or a module version is published).
└─ NOTIFICATION  outputs: send (bool); channels (set of strings); message / subject (strings)
                 Controls whether, where, and how run updates, internal errors, and module versions are reported.
```

## How they compose

- LOGIN gates entry to the account and assigns spaces/roles/teams; ACCESS then gates per-stack/module visibility — together they decide who can act at all.
- GIT_PUSH decides what becomes a run: `track` → tracked run, `propose` → proposed run, `ignore` → nothing. Default behavior is track+propose, so suppression requires `ignore` rules.
- PLAN gates the plan: any `deny` reason blocks the run; `warn` reasons surface in the UI without blocking.
- APPROVAL gates the apply for runs awaiting approval; TASK gates ad-hoc commands with the same deny/warn set pattern.
- TRIGGER fans out on completion: its `stacks[id]` / `modules[id]` output starts runs on downstream stacks, which are then evaluated by *their own* GIT_PUSH/PLAN/APPROVAL policies.
- NOTIFICATION reports outcomes last and can read earlier policies' receipts and the plan decision (`input.run_updated.policy_receipts[]`, `input.run_updated.plan_policy_decision`) — see `flags-and-interaction.md`.
