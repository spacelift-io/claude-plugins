# Debugging & explaining policies

## Debug workflow

1. Identify the type from the rule names + input paths.
2. Verify every input path against `references/policy-contract.md` - never guess.
3. Scan for the pitfalls below.
4. Simulate it (`guides/testing.md`). Put `print()` in a rule that does not fire, and the output comes back as `print_output`.
5. Explain the fault in plain language, then show the corrected policy with comments marking what changed.

## Pitfalls

- **Wrong input path** - e.g. `input.stack` instead of `input.spacelift.stack` in a PLAN policy. PLAN puts stack (or module), run, commit and request under `input.spacelift.*`. Plan data stays top-level (`input.terraform`, `input.opentofu`, `input.pulumi`, ...).
- **Absence handled the wrong way round** - a missing or null field (`teams`, `labels`, `worker_pool`, `pull_request`) makes a rule undefined, so a deny that must catch absence needs `not` on a helper. See `guides/formatting.md`.
- **Wrong rule shape** - bool vs set vs string, e.g. `deny if` in PLAN. Fails to compile with "conflicting rules". See `guides/formatting.md`.
- **Wrong rule name** - e.g. `allow` in PLAN, `warn` in TASK, `send` in NOTIFICATION. Compiles and is ignored.
- **`input.push.affected_files` on a PR event** - there `input.push` is the head commit, or absent when the PR comes from the tracked branch. Use `input.pull_request.diff`.
- **Missing `package spacelift`**, Rego syntax slips (braces, set comprehensions), or v0-style rule heads run on a `REGO_V1` engine (see `guides/formatting.md`).

## Symptom → cause

| Symptom | Cause + fix |
|---|---|
| Monorepo proposed-run storm - GIT_PUSH proposes a run for every PR | `propose` fires without a path check. Gate it on `input.pull_request.diff` matching `input.stack.project_root` |
| Every push ignored after attaching a GIT_PUSH policy | With a push policy attached, a push is ignored unless a `track` or `propose` rule fires. The built-in default applies only with no push policy (or no entitlement to workflow policies). Add explicit `track` / `propose` rules |
| LOGIN rule for "no teams" never fires | `input.session.teams` is null, so `count()` and iteration are undefined. Use `not` on a helper rule |
| Compile error "conflicting rules data.spacelift.X" | Rule X has the wrong shape for the type (bool vs set vs string) |
| Compile error "multiple default rules" | The body declares `default` for a rule Spacelift's library already defaults |
| Policy does nothing - attached but no effect | Attached as the wrong type, rule names don't match the type (e.g. `allow` in a PLAN policy - there is none), or logic never evaluates true |
| Plan policy silently empty | `input.stack` / `input.session` instead of `input.spacelift.stack` / `input.spacelift.run.creator_session` |

## Explaining a policy

State the type + intent → walk each rule (what it checks, what happens on a match) → call out edge cases → note any problems.
