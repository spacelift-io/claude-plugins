---
name: spacelift-policy-writer
description: Use when writing, editing, debugging, or explaining Spacelift policies in Rego (OPA) - ACCESS, APPROVAL, GIT_PUSH, LOGIN, NOTIFICATION, PLAN, TASK, TRIGGER. Bundles the authoritative policy contract (every valid input path and rule output per type) plus the machine-readable .well-known schema, and covers both Rego engine versions (REGO_V0 classic, REGO_V1 / OPA 1.0) with the portable future.keywords pattern that runs under both. Trigger on terms - Spacelift policy, Rego, OPA, deny, warn, allow, approve, track/propose/ignore, plan policy, push policy, login policy, notification policy, policySimulate.
---

# Spacelift Policy Writer

Procedural guide for authoring Spacelift policies. A policy is Rego that evaluates a per-type input document into named rule outputs. Read this router, then load the one resource your task needs.

## Ground rules

1. **Every policy uses `package spacelift`.**
2. **Never guess a field.** Input paths and rule outputs differ per type - the contract in `references/` is authoritative.
3. **Prefer the portable syntax.** `import future.keywords` plus `contains ... if` rule heads run under both REGO_V0 and REGO_V1 (see `guides/formatting.md`).

## Reference selector

Load only the file that matches the task. **Do not preload references.**

| Question / task | Load |
|---|---|
| Which policy type(s) fit a goal, and how types compose | `guides/policy-types.md` |
| Exact input paths / rule outputs for a type | `references/policy-contract.md` (machine-readable: `references/policy-contract.json`) |
| Rego rule shapes, null guards, Rego v0 vs v1, the portable pattern | `guides/formatting.md` |
| Flags, or one policy feeding / interacting with another | `guides/flags-and-interaction.md` |
| Notifications - webhooks vs integrations (Slack, ...) | `guides/delivery-webhooks-vs-integrations.md` |
| Test / simulate a policy with no deploy | `guides/testing.md` |
| Debug a policy that errors, does nothing, or misbehaves; or explain one | `guides/debugging.md` |

End-to-end recipe: `examples/01-plan-guard-destructive.md`.

## Specialist sub-agents

Delegate when the task is bigger than a single lookup (prompts in `agents/`):

| Sub-agent | Use for |
|---|---|
| `agents/capability-synthesizer.md` | Map a governance goal to the policy type(s) and how they compose |
| `agents/tester.md` | Synthesize a sample input, simulate via the Spacelift MCP, iterate on the decision |

## Output shape

Clean Rego in a ```rego block - `package spacelift`, a one-line purpose comment, the rules, then helper rules. No sample JSON unless asked.

## Pitfalls catalog

Each is real and frequent. Apply the mitigation by default.

| Pitfall | Mitigation |
|---|---|
| PLAN policy references `input.stack` / `input.session` and silently matches nothing | PLAN nests everything under `input.spacelift.*` - use `input.spacelift.stack` / `input.spacelift.run.creator_session` |
| v0-style heads (`deny[x] {}`) fail to parse on a REGO_V1 engine | Use the portable `import future.keywords` plus `deny contains x if {}` form (`guides/formatting.md`) |
| GIT_PUSH policy has no effect | Default behavior is track+propose - suppress with explicit `ignore` rules, not by omitting `track` |
| PR events matched via `input.push.affected_files` | `input.push` is null on PR events - use `input.pull_request.diff`, and guard both since either can be null |
| Iterating `input.session.teams` errors for some users | It can be null when the IdP returns no teams - guard with a helper rule |
| Wrong rule output type | Match the type's contract - PLAN/TASK use `deny[reason]`/`warn[reason]` sets, ACCESS/APPROVAL use booleans, TRIGGER uses ID sets |

## Outside this skill

`references/policy-contract.md` is the field-level source of truth. Its machine-readable companion `references/policy-contract.json` is a snapshot of Spacelift's published contract at `https://app.spacelift.io/.well-known/policy-contract.json` - refresh from there if the schema changes. For platform behavior beyond policy authoring, consult `https://docs.spacelift.io`.
