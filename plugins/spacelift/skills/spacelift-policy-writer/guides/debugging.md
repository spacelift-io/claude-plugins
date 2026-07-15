# Debugging & explaining policies

## Debug workflow

1. Identify the type from the rule names + input paths.
2. Verify every input path against `references/policy-contract.md` - never guess.
3. Scan for the pitfalls below.
4. Explain the fault in plain language, then show the corrected policy with comments marking what changed.

## Pitfalls

- **Wrong input path** - e.g. `input.stack` instead of `input.spacelift.stack` in a PLAN policy. PLAN nests stack/run under `input.spacelift.*`; this is the #1 plan bug.
- **Missing null guards** on nullable fields (`teams`, `labels`, `worker_pool`, `push`/`pull_request`). See `guides/formatting.md`.
- **Wrong rule output type** - bool vs set-of-reason-strings vs set-of-ids vs map. See `guides/formatting.md`.
- **`input.push.affected_files` on a PR event** - use `input.pull_request.diff` instead.
- **Missing `package spacelift`**, Rego syntax slips (braces, set comprehensions), or v0-style rule heads run on a `REGO_V1` engine (see `guides/formatting.md`).

## Symptom → cause

| Symptom | Cause + fix |
|---|---|
| Monorepo proposed-run storm - GIT_PUSH proposes a run for every PR | Matching only `input.push.affected_files`; for PR events use `input.pull_request.diff` and gate on `input.stack.project_root` |
| "Null teams" crash - LOGIN errors for some users | `input.session.teams` is null when the IdP returns no teams; iterating/counting it errors. Guard with a helper rule |
| Policy does nothing - attached but no effect | Attached as the wrong type, rule names don't match the type (e.g. `allow` in a PLAN policy - there is none), logic never evaluates true, or GIT_PUSH (default is track+propose - you need `ignore` rules to suppress, not just `track`) |
| Plan policy silently empty | `input.stack` / `input.session` instead of `input.spacelift.stack` / `input.spacelift.run.creator_session` |

## Explaining a policy

State the type + intent → walk each rule (what it checks, what happens on a match) → call out edge cases → note any problems.
