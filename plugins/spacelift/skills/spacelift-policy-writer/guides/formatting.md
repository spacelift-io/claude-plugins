# Rego authoring & formatting

## Always

- `package spacelift` - every policy, every type.
- Reference only input paths from `references/policy-contract.md`. Never guess field names.
- Output in a fenced ` ```rego ` block with a header comment stating what the policy does.

## Rule type per policy

The rule output shape depends on the policy type - using the wrong one silently does nothing:

| Policy types | Rule shape |
|---|---|
| ACCESS, APPROVAL, GIT_PUSH | booleans (`allow`, `deny`, `approve`, `reject`, `track`, `propose`, `ignore`) |
| PLAN, TASK | sets of reason strings (`deny[reason]`, `warn[reason]`) |
| TRIGGER | sets of IDs (`stacks[id]`, `modules[id]`) |
| LOGIN | mix: `allow`/`admin`/`deny` bools; `space_read`/`space_write`/`space_admin`/`teams` sets; `roles` map (space slug → list of role slugs) |
| NOTIFICATION | `send` bool; `channels` set; `message`/`subject` strings |

## Null-guard pattern

`teams`, `labels`, `worker_pool`, `push` (on PR events), and `pull_request` (on push events) can be null. Iterating or calling `count()` on null errors.

```rego
# Safe - works even if teams is null
has_team(team) {
    input.session.teams[_] == team
}

# Unsafe - errors if teams is null
bad_check {
    count(input.session.teams) > 0
}
```

## Helper rules

Break complex logic into named helpers so intention is clear:

```rego
deny[reason] {
    is_production_stack
    has_destructive_changes
    reason := "Cannot destroy resources in production"
}

is_production_stack {
    input.spacelift.stack.labels[_] == "env:production"
}
```

## Reason strings

`deny`/`warn` reasons show up in the Spacelift UI. Use `sprintf` for dynamic context:

```rego
deny[reason] {
    rc := input.terraform.resource_changes[_]
    rc.change.actions[_] == "delete"
    reason := sprintf("Deletion of %s is blocked in production", [rc.address])
}
```

## Rego v0 vs v1 (engine versions)

Spacelift's GraphQL `PolicyEngineType` enum has exactly two values - there is no v2 engine (the "v2" in `policySimulatev2` is the mutation version, not the Rego version):

| Engine | Syntax |
|---|---|
| `REGO_V0` | Classic OPA syntax. `deny[reason] { ... }` and bare helper rules parse fine. |
| `REGO_V1` | OPA 1.0 syntax. `if` and `contains` are **mandatory** in rule heads. A v0-style policy fails to parse under this engine with one error per rule/function head, e.g. "`if` keyword is required before rule body", "`contains` keyword is required for partial set rules", "`if` keyword is required before function body". |

### Translation table (v0 → v1)

| Rule kind | Rego v0 | Rego v1 |
|---|---|---|
| Complete rule | `allow { body }` | `allow if { body }` |
| Partial set rule | `deny[x] { body }` | `deny contains x if { body }` |
| Function rule | `f(x) { body }` | `f(x) if { body }` |
| Default rule | `default allow := false` | unchanged |
| Iteration (`coll[_]`), comprehensions, `sprintf`, string builtins | unchanged | unchanged |

### Recommended default: the portable pattern

Add the `future.keywords` imports and use the v1 rule-head forms. This compiles and behaves **identically under both engines**:

```rego
package spacelift

import future.keywords.contains
import future.keywords.if

deny contains reason if {
    is_production
    rc := input.terraform.resource_changes[_]
    rc.change.actions == ["delete"]
    reason := sprintf("%s would be destroyed in a production stack", [rc.address])
}

is_production if {
    input.spacelift.stack.labels[_] == "env:production"
}
```

Verified live against Spacelift's API with a 2×2 simulation matrix: v0 syntax parses only under `REGO_V0`; the portable form parses under both and returns byte-identical decisions. See `examples/01-plan-guard-destructive.md` for the matrix and a complete verified portable PLAN policy.

**Prefer the portable pattern for all new policies.** Use bare v0 syntax only when editing an existing v0 policy where a minimal diff matters.

## Structure for complex policies

1. `package spacelift`
2. Header comment explaining the policy's purpose
3. Imports (`import future.keywords.contains` / `import future.keywords.if` when portable)
4. Main rules (`deny`, `allow`, `track`, etc.)
5. Helper rules

## Syntax reminders

- **Sets vs booleans:** `deny[reason] { ... }` builds a set; `deny { ... }` is a boolean. Portable/v1 equivalents: `deny contains reason if { ... }` and `deny if { ... }`.
- **Iteration:** `some x in collection` or `collection[_]`; prefer `some` for clarity in complex rules.
- **String matching:** `startswith(str, prefix)`, `endswith(str, suffix)`, `contains(str, substr)`, `regex.match(pattern, str)`.
- **Comprehensions:** `[x | cond]` arrays, `{x | cond}` sets, `{k: v | cond}` objects.
- **Defaults:** `default allow = false` - useful in ACCESS/LOGIN policies.
- **`:=` vs `==`:** `:=` is local assignment (preferred for locals), `==` is comparison.
- **Negation:** `not some_rule` - the rule must be defined somewhere for negation to work.
- **`with` keyword:** test-only input override - `allow with input as mock_input`.
