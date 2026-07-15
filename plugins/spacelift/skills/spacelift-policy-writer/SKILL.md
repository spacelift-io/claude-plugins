---
name: spacelift-policy-writer
description: Write, edit, debug, and explain Spacelift policies in Rego (OPA). Use whenever creating or troubleshooting ACCESS, APPROVAL, GIT_PUSH, LOGIN, NOTIFICATION, PLAN, TASK, or TRIGGER policies for Spacelift, or when a user asks to author/fix/explain a Spacelift policy. Bundles the authoritative policy contract — every valid input path and rule output per policy type — plus the machine-readable schema. Covers both Rego engine versions (REGO_V0 classic and REGO_V1 / OPA 1.0 syntax) and the portable future.keywords pattern that works under both.
---

# Spacelift Policy Writer

Router for writing, debugging, and testing Spacelift policies (Rego/OPA). **Read this, then open the ONE resource for your task — don't preload everything.**

## Always true

- Every policy uses `package spacelift`.
- Input paths and rule outputs differ per policy **type** — never guess a field name; the contract is authoritative.
- The 8 types: `ACCESS`, `APPROVAL`, `GIT_PUSH`, `LOGIN`, `NOTIFICATION`, `PLAN`, `TASK`, `TRIGGER`.

## Route by task

| If you need to… | Open |
|---|---|
| Pick which policy type(s) fit a goal, or see how types work together | `guides/policy-types.md` |
| Look up exact input paths / rule outputs for a type | `references/policy-contract.md` (machine-readable: `references/policy-contract.json`) |
| Get Rego right — rule shapes, null guards, Rego v0 vs v1, the portable pattern | `guides/formatting.md` |
| Use flags, or have one policy feed/interact with another | `guides/flags-and-interaction.md` |
| Send notifications — webhooks vs integrations (Slack, etc.) | `guides/delivery-webhooks-vs-integrations.md` |
| Test / simulate a policy on the fly (no deploy) | `guides/testing.md` |
| Debug a policy that errors, does nothing, or misbehaves — or explain one | `guides/debugging.md` |
| See a real, verified end-to-end example | `examples/` |

## Specialist sub-agents (`agents/`)

- `agents/capability-synthesizer.md` — map a governance goal → the policy type(s) and how they compose.
- `agents/tester.md` — synthesize a sample input, simulate via the Spacelift MCP, iterate on the decision.

## Output shape

Clean Rego in a ```rego block: `package spacelift`, a one-line purpose comment, the rules, then helper rules. No sample JSON unless asked.
