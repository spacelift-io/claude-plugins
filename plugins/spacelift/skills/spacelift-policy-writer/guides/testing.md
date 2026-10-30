# Testing policies on the fly (simulation)

The Spacelift MCP server evaluates a draft policy server-side and saves nothing. Use its tools in this order:

1. `policy_input_schema` with `type` - the type's input structure, the rules Spacelift reads back, and the type description. Call it before writing each type.
2. `policy_input_capture_read` - inputs captured from real events in the account. Use it when the policy depends on values in the data (resource types, changed files, team names). Captures need space admin, and login captures need admin on the root space.
3. `policy_simulate` - evaluate the body.

## `policy_simulate` arguments

| Argument | Meaning |
|---|---|
| `type`, `body` | The draft and its policy type. |
| `policy` | A stored policy's id, evaluated with its stored body, type and engine. Leave out `type`, `body`, `engineType` and `libraries` with it. |
| `input` | Your own input, as an object or a JSON string. Omit it to use the built-in sample for the type, which holds one ordinary event (e.g. a finished tracked run), so a rule can match nothing. |
| `captures` | Capture ids from `policy_input_capture_read`. One result row per capture. Cannot be combined with `input`. |
| `patch` | A JSON merge patch (object) or JSON Patch (array) applied to each input first, e.g. to change the run state of a capture or set a field to null. |
| `engineType` | `REGO_V1` (default) or `REGO_V0`. |
| `libraries` | `[{name, body}]` for libraries the body imports. |

## What comes back

- `decision` - the full result object for the type, with every rule its library declares: e.g. `deny` / `warn` / `flag` / `reset_flag` / `sample` for PLAN, `webhook` / `slack` / `inbox` / `pull_request` for NOTIFICATION, `trigger` / `priority` for TRIGGER.
- `simulated_with` - the type and engine used. Save with that `engineType`: `policyCreatev2` defaults to `REGO_V0` when it is omitted.
- `input_source` - `sample` when the built-in sample was used, `capture` with captures (then `results` holds one row per capture).
- `print_output` - output of `print()` calls in the rules Spacelift reads and the rules they use.
- `save_refusal` - LOGIN only: the error that saving the body would return. Saving refuses a login policy that lets in a sample session from outside the organization.

Compile errors come back as the tool error: v0 heads under `REGO_V1`, a wrong rule shape ("conflicting rules"), a redeclared default, or a call to `http.send`, `net.lookup_ip_addr`, `opa.runtime`, `rego.parse_module`, `time.now_ns` or `trace`.

Simulate under the engine you will save. For a portable policy, simulate under both.

## Building the `input`

Take paths from `policy_input_schema` (or `references/policy-contract.md`): only the fields the policy touches, with correct nesting (PLAN puts stack and run under `input.spacelift.*` and the plan data at the top level). A missing field and a null field are different inputs, so when a field can be null, simulate the null case too. Captures from real events beat synthesized inputs - pass their ids, do not copy them into `input`.

## Without `policy_simulate`

The GraphQL mutation `policySimulatev2(input: { body, input, type, libraries, engineType })` does the same through the Spacelift MCP `mutate` tool. Its `input` is a JSON-encoded string, and the decision comes back as a JSON string.

## The iterate loop

1. Simulate with a representative input.
2. Read the decision.
3. Tweak the policy (or the input, to cover another scenario). When a rule does not fire, add `print()` to its body.
4. Re-simulate. Repeat until both the triggering and non-triggering cases behave as intended.
