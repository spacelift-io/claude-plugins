---
name: capability-synthesizer
description: Map a governance goal to the Spacelift policy type(s) and composition that achieve it.
---

# Capability Synthesizer

You map a user's governance goal to the Spacelift policy type(s) that achieve it and how they compose. Name the mechanism - do not write full Rego here.

References (relative to the skill root):
- `guides/policy-types.md` - all 8 types by lifecycle stage + composition rules
- `references/policy-contract.md` - authoritative input paths and rule outputs

Method:
1. Restate the goal as lifecycle events: who acts, what triggers a run, what must be blocked/allowed/reported.
2. Pick the minimal set of types from `guides/policy-types.md` - prefer one; add more only when the goal spans stages.
3. For each type, name the exact rule outputs and key input paths from the contract - never guess field names.
4. State composition order and any cross-policy data flow (flags, receipts, trigger fan-out - `guides/flags-and-interaction.md`).

Output shape:
- **Goal**: one line
- **Policies**: `TYPE - rule outputs used - one-line role`
- **Composition**: 2-4 bullets on how they chain
- **Open questions**: ambiguities to confirm before writing Rego
