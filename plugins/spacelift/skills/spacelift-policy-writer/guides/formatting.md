# Rego authoring & formatting

## Always

- `package spacelift` - every policy, every type.
- Reference only input paths from `references/policy-contract.md`. Never guess field names.
- Output in a fenced ` ```rego ` block with a header comment stating what the policy does.

## Rule type per policy

Spacelift wraps every policy in a per-type library that declares each rule it reads. A rule with a readable name but the wrong shape fails to compile ("conflicting rules data.spacelift.deny found"). A rule name the type does not read compiles and is silently ignored.

| Policy type | Booleans (`rule if { ... }`) | Sets (`rule contains x if { ... }`) | Other |
|---|---|---|---|
| ACCESS | `deny`, `deny_write`, `read`, `write` | | |
| APPROVAL | `approve`, `reject` | `approve_with_note`, `reject_with_note` (notes) | |
| GIT_PUSH | `track`, `propose`, `ignore`, `ignore_track`, `notrigger`, `fail`, `notify`, `allow_fork`, `prioritize` | `cancel` (run IDs), `message`, `external_dependency` | `lock`, `unlock`, `module_version`, `priority` (strings) |
| INTENT | | `allow`, `deny` (reasons) | |
| LOGIN | `allow`, `admin`, `deny`, `deny_admin` | `team`, `deny_message` | `roles` map (space ID → set of role slugs) |
| NOTIFICATION | | `webhook`, `slack`, `inbox`, `pull_request` (objects) | |
| PLAN | | `deny`, `warn` (reasons) | |
| TASK | | `deny` (reasons) | |
| TRIGGER | | `trigger` (stack IDs) | `priority` (string) |
| every type | `sample` | `flag`, `reset_flag` | |

## Missing and null fields

Only the fields the contract marks required are always present. Any other field can be missing, and several can be null: `teams`, `labels`, `worker_pool`, `pull_request` on push events, `policy_receipts`. An expression over a missing or null value is undefined, so the rule body fails and the rule does not fire. It does not error.

When not firing is the safe outcome, write no guard. When a rule must fire on absence, test it with `not` on a helper, because `count()` over null is undefined too:

```rego
package spacelift

import future.keywords.if
import future.keywords.in

# LOGIN, GitHub or GitLab only: Google and Microsoft send no teams, so this would deny everyone there

# Undefined when teams is null, so this never denies that user
deny if count(input.session.teams) == 0

# Fires for null, missing and empty teams alike
deny if not has_any_team

has_any_team if {
    some _ in input.session.teams
}
```

## Helper rules

Break complex logic into named helpers so intention is clear:

```rego
deny contains reason if {
    is_production_stack
    has_destructive_changes
    reason := "Cannot destroy resources in production"
}

is_production_stack if {
    input.spacelift.stack.labels[_] == "env:production"
}

has_destructive_changes if {
    count(deleted_resources) > 0
}
```

The PLAN library already defines `affected_resources`, `created_resources`, `deleted_resources`, `recreated_resources` and `updated_resources` over `input.terraform.resource_changes`. Use them directly, as `has_destructive_changes` does above, and do not give your own rules those names.

## Reason strings

`deny`/`warn` reasons show up in the Spacelift UI. Use `sprintf` for dynamic context:

```rego
deny contains reason if {
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
| Default rule | `default threshold := 2` | unchanged |
| Iteration (`coll[_]`), comprehensions, `sprintf`, string builtins | unchanged | unchanged |

Never declare a `default` for a rule Spacelift reads (`allow`, `deny`, `track`, ...). The library already defaults it, and a second default fails to compile ("multiple default rules").

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

v0 syntax parses only under `REGO_V0`. The portable form parses under both and returns the same decision. See `examples/01-plan-guard-destructive.md` for the 2×2 matrix and a complete portable PLAN policy.

**Prefer the portable pattern for all new policies.** Use bare v0 syntax only when editing an existing v0 policy where a minimal diff matters.

## Structure for complex policies

1. `package spacelift`
2. Header comment explaining the policy's purpose
3. Imports (`import future.keywords.contains` / `import future.keywords.if` / `import future.keywords.in` when portable, or `import future.keywords` for all of them)
4. Main rules (`deny`, `allow`, `track`, etc.)
5. Helper rules

## Syntax reminders

- **Sets vs booleans:** `deny[reason] { ... }` builds a set; `deny { ... }` is a boolean. Portable/v1 equivalents: `deny contains reason if { ... }` and `deny if { ... }`.
- **Iteration:** `some x in collection` or `collection[_]`; prefer `some` for clarity in complex rules. Under `REGO_V0`, `in` needs `import future.keywords.in`.
- **String matching:** `startswith(str, prefix)`, `endswith(str, suffix)`, `contains(str, substr)`, `regex.match(pattern, str)`.
- **Comprehensions:** `[x | cond]` arrays, `{x | cond}` sets, `{k: v | cond}` objects.
- **Defaults:** only for your own helper rules - never for a rule Spacelift reads (see above).
- **`:=` vs `==`:** `:=` is local assignment (preferred for locals), `==` is comparison.
- **Negation:** `not some_rule` is true when `some_rule` is undefined, including when the input field it reads is missing or null. The rule must be defined in the policy or the body does not compile.
- **Unavailable builtins:** `http.send`, `net.lookup_ip_addr`, `opa.runtime`, `rego.parse_module`, `time.now_ns` and `trace` do not compile in a Spacelift policy.
- **`with` keyword:** input override - `allow with input as mock_input`.
