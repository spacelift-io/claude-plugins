# Examples — Verified Portable Policies

## plan-guard-destructive.portable.rego

A PLAN policy that denies pure destroys on production stacks, warns on destroys elsewhere, and always warns (never blocks) on replacements. Written in the **portable pattern**: `import future.keywords.contains` / `import future.keywords.if` plus v1 rule-head forms (`deny contains reason if { ... }`, `helper if { ... }`, `f(x) if { ... }`). See the "Rego v0 vs v1 (Engine Versions)" section in `SKILL.md`.

## Engine Regression Matrix (verified live via `policySimulatev2`)

Verified against Spacelift's GraphQL API using the `policySimulatev2` mutation with input object `{ body, input, type: "PLAN", engineType }`, where `engineType` is the `PolicyEngineType` enum: `REGO_V0` or `REGO_V1`. Same policy logic + same input across all four cells:

| Policy syntax                                        | `REGO_V0`                | `REGO_V1`                                                                                        |
| ---------------------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------ |
| Classic v0 (`deny[reason] { ... }`, bare helpers)    | Passes (1 deny + 1 warn) | Parse error — "`if` keyword is required before rule body", "`contains` keyword is required for partial set rules", "`if` keyword is required before function body" (one per rule/function head) |
| Portable (`future.keywords` + `contains ... if`)     | Passes (1 deny + 1 warn) | Passes (1 deny + 1 warn) — byte-identical result to the `REGO_V0` cell                            |

Conclusion: the portable form is safe as a default — it compiles and behaves identically under both engines. Re-run this matrix as a regression check whenever the skill's syntax guidance changes.

## Sample Input Used

A production stack (label `env:production`) with three resource changes: a pure destroy, a replacement, and an in-place update.

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

**Expected decision on this input (production stack):**

- `deny` — 1 element: `"aws_s3_bucket.logs would be destroyed in a production stack"`
- `warn` — 1 element: `"aws_db_instance.main will be replaced (destroy + recreate)"`
- `aws_instance.web` (update) matches nothing — no output.

Remove the `env:production` label to exercise the non-production path: the destroy moves from `deny` to `warn` (`"aws_s3_bucket.logs would be destroyed"`), replacement warning unchanged.
