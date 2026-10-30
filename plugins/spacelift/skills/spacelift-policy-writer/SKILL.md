---
name: spacelift-policy-writer
description: Use when writing, editing, debugging, or explaining Spacelift policies in Rego (OPA) - ACCESS, APPROVAL, GIT_PUSH, INTENT, LOGIN, NOTIFICATION, PLAN, TASK, TRIGGER. Bundles the authoritative policy contract (every valid input path and rule output per type) plus the machine-readable .well-known schema, and covers both Rego engine versions (REGO_V0 classic, REGO_V1 / OPA 1.0) with the portable future.keywords pattern that runs under both. Trigger on terms - Spacelift policy, Rego, OPA, deny, warn, approve, track/propose/ignore, plan policy, push policy, login policy, notification policy, trigger policy, policy_simulate, policySimulate.
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
| Rego rule shapes, missing and null fields, Rego v0 vs v1, the portable pattern | `guides/formatting.md` |
| Flags, or one policy feeding / interacting with another | `guides/flags-and-interaction.md` |
| Notifications - webhooks, Slack, inbox, pull request comments | `guides/delivery-webhooks-vs-integrations.md` |
| Test / simulate a policy with no deploy | `guides/testing.md` |
| Debug a policy that errors, does nothing, or misbehaves; or explain one | `guides/debugging.md` |

End-to-end recipe: `examples/01-plan-guard-destructive.md`.

## Specialist sub-agents

Delegate when the task is bigger than a single lookup (prompts in `agents/`):

| Sub-agent | Use for |
|---|---|
| `agents/capability-synthesizer.md` | Map a governance goal to the policy type(s) and how they compose |
| `agents/tester.md` | Build inputs, simulate with the Spacelift MCP `policy_simulate` tool, iterate on the decision |

## Output shape

Clean Rego in a ```rego block - `package spacelift`, a one-line purpose comment, the rules, then helper rules. No sample JSON unless asked.

## Pitfalls catalog

Each is real and frequent. Apply the mitigation by default.

| Pitfall | Mitigation |
|---|---|
| PLAN policy references `input.stack` / `input.session` and silently matches nothing | PLAN puts stack (or module), run, commit and request under `input.spacelift.*` - use `input.spacelift.stack` / `input.spacelift.run.creator_session`. Plan data stays top-level: `input.terraform`, `input.opentofu`, `input.pulumi`, `input.terragrunt`, ... |
| v0-style heads (`deny[x] {}`) fail to parse on a REGO_V1 engine | Use the portable `import future.keywords` plus `deny contains x if {}` form (`guides/formatting.md`) |
| GIT_PUSH policy attached and now nothing runs | The built-in default (track on the tracked branch, propose elsewhere) applies only while no push policy is attached (or the account lacks workflow policies). An attached policy ignores every push for which no `track` or `propose` rule fires - write both explicitly. `ignore` beats both |
| PR events matched via `input.push.affected_files` | On a PR event `input.push` is the PR head commit, absent when the head branch is the stack's tracked branch, and the merge commit on a merge. Match PRs on `input.pull_request.diff`. `input.pull_request` is null on push events |
| A rule meant to catch users without teams never fires | `input.session.teams` can be null. `count()`, iteration and `in` over null are undefined, so the rule does not fire (it does not error). Catch the absence with `not` on a helper (`guides/formatting.md`) |
| LOGIN `allow if input.session.login` lets in anyone the identity provider authenticates | Condition on `input.session.member` or teams (GitHub) or the email domain (Google, GitLab, Microsoft); simulate an outsider and confirm the login is denied |
| LOGIN uses `space_read` / `space_write` / `space_admin` | Deprecated - write `roles` with slugs from `input.roles[].slug` |
| Rule has the right name but the wrong shape (e.g. `deny if` in PLAN, `write contains` in ACCESS) | Compile error "conflicting rules data.spacelift.<rule>" - match the shape in `guides/formatting.md` |
| Rule name the type does not read (e.g. `allow` in PLAN, `send` / `channels` in NOTIFICATION, `warn` in TASK) | Silently ignored - take rule names from the contract |
| `default allow := false` in the body | Compile error "multiple default rules" - Spacelift's library already defaults every boolean rule to false |

## Outside this skill

`references/policy-contract.md` is the field-level source of truth. Its machine-readable companion `references/policy-contract.json` is a snapshot of Spacelift's published contract at `https://app.spacelift.io/.well-known/policy-contract.json` - refresh from there if the schema changes. For platform behavior beyond policy authoring, consult `https://docs.spacelift.io`.
