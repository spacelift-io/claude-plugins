# Testing policies on the fly (simulation)

Spacelift's GraphQL API evaluates a policy server-side without deploying it - nothing is persisted. Run these mutations via the Spacelift MCP `mutate` tool.

## Mutations

| Mutation | Shape | Engine choice |
|---|---|---|
| `policySimulatev2` (preferred) | Single input object: `{ body, input, type, libraries, engineType }` | `engineType`: `REGO_V0` (classic syntax) or `REGO_V1` (OPA 1.0 - `if`/`contains` mandatory). For portable policies, simulate under **both**. |
| `policySimulate` (legacy) | Args `(body, input, type, libraries)` | None. |

## What comes back

The decision JSON for the policy type - e.g. `deny`/`warn` reason sets for PLAN/TASK, `allow`/`deny` booleans for ACCESS, `send`/`channels`/`message`/`subject` for NOTIFICATION, `stacks` IDs for TRIGGER. Parse errors are reported per rule head - the fastest way to spot a v0-vs-v1 syntax mismatch.

## Building the `input`

Synthesize the input JSON from `references/policy-contract.md` for the policy type: only the fields the policy touches, with correct nesting (PLAN nests under `input.spacelift.*`). When the policy is already attached with sampling enabled, real evaluation samples are better still - use one as the simulation input.

## The iterate loop

1. Simulate with a representative input.
2. Read the decision.
3. Tweak the policy (or the input, to cover another scenario).
4. Re-simulate. Repeat until both the triggering and non-triggering cases behave as intended.
