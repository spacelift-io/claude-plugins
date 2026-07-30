# Example: plan guard for destructive changes

**Goal:** a PLAN policy that denies pure destroys on production stacks, warns on destroys elsewhere, and always warns (never blocks) on replacements - verified under both Rego engines without deploying anything.

This walks through portable authoring → synthesized input → `policySimulatev2` under both engines. Simulation is server-side and persists nothing.

## Step 1 - write the policy in the portable pattern

`import future.keywords.contains` / `import future.keywords.if` plus v1 rule-head forms (`deny contains reason if { ... }`, `helper if { ... }`, `f(x) if { ... }`). This compiles and behaves identically under both engines - see "Rego v0 vs v1 (engine versions)" in `guides/formatting.md`.

```rego
package spacelift

import future.keywords.contains
import future.keywords.if

# Pure destroys are denied in production stacks, warned elsewhere.
# Replacements (destroy + recreate) are always a warning, never a hard block.

deny contains reason if {
    is_production
    rc := input.terraform.resource_changes[_]
    is_pure_destroy(rc)
    reason := sprintf("%s would be destroyed in a production stack", [rc.address])
}

warn contains reason if {
    not is_production
    rc := input.terraform.resource_changes[_]
    is_pure_destroy(rc)
    reason := sprintf("%s would be destroyed", [rc.address])
}

warn contains reason if {
    rc := input.terraform.resource_changes[_]
    is_replacement(rc)
    reason := sprintf("%s will be replaced (destroy + recreate)", [rc.address])
}

is_production if {
    input.spacelift.stack.labels[_] == "env:production"
}

is_pure_destroy(rc) if {
    rc.change.actions == ["delete"]
}

is_replacement(rc) if {
    actions := {a | a := rc.change.actions[_]}
    actions == {"delete", "create"}
}
```

## Step 2 - synthesize a sample input

From `references/policy-contract.md` (PLAN): only the fields the policy touches, with the PLAN-specific nesting (`input.spacelift.*` for stack/run, `input.terraform.*` for the plan). A production stack (label `env:production`) with three resource changes: a pure destroy, a replacement, and an in-place update.

```json
{
  "spacelift": {
    "stack": {
      "labels": ["env:production"]
    }
  },
  "terraform": {
    "resource_changes": [
      {
        "address": "aws_s3_bucket.logs",
        "change": { "actions": ["delete"] }
      },
      {
        "address": "aws_db_instance.main",
        "change": { "actions": ["delete", "create"] }
      },
      {
        "address": "aws_instance.web",
        "change": { "actions": ["update"] }
      }
    ]
  }
}
```

## Step 3 - simulate under both engines

Run the `policySimulatev2` mutation via the Spacelift MCP `mutate` tool with input object `{ body, input, type: "PLAN", engineType }`, where `engineType` is the `PolicyEngineType` enum: `REGO_V0` or `REGO_V1`. Same policy logic + same input across all four cells, verified live against Spacelift's GraphQL API:

| Policy syntax | `REGO_V0` | `REGO_V1` |
|---|---|---|
| Classic v0 (`deny[reason] { ... }`, bare helpers) | Passes (1 deny + 1 warn) | Parse error - "`if` keyword is required before rule body", "`contains` keyword is required for partial set rules", "`if` keyword is required before function body" (one per rule/function head) |
| Portable (`future.keywords` + `contains ... if`) | Passes (1 deny + 1 warn) | Passes (1 deny + 1 warn) - byte-identical result to the `REGO_V0` cell |

Re-run this matrix as a regression check whenever the skill's syntax guidance changes.

## Step 4 - read the decision

Expected decision on this input (production stack):

- `deny` - 1 element: `"aws_s3_bucket.logs would be destroyed in a production stack"`
- `warn` - 1 element: `"aws_db_instance.main will be replaced (destroy + recreate)"`
- `aws_instance.web` (update) matches nothing - no output.

## Step 5 - exercise the non-production path

Remove the `env:production` label and re-simulate: the destroy moves from `deny` to `warn` (`"aws_s3_bucket.logs would be destroyed"`), replacement warning unchanged. Both the triggering and non-triggering cases now behave as intended.

## Why this shape

- **Portable by default** - one policy body runs under both engines; no per-engine forks to maintain.
- **Simulate before deploy** - `policySimulatev2` evaluates server-side and persists nothing; parse errors come back per rule head.
- **Both engines exercised** - a portable policy is only proven portable when `REGO_V0` and `REGO_V1` return identical decisions.
- **Input is minimal** - only fields the policy touches, with correct PLAN nesting; a full plan JSON adds nothing but tokens.
- **Deny vs warn split** - hard-block only what must never happen (production destroys); annotate the rest so runs keep flowing.

## Pitfall avoided

A v0-style version of this policy (`deny[reason] { ... }`, bare helper heads) parses only under `REGO_V0`. Run it on a `REGO_V1` engine and it fails to parse with one error per rule/function head. The portable form removes that failure mode entirely.
