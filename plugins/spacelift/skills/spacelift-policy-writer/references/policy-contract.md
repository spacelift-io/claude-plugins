# Spacelift Policy Contract - Quick Reference

This is the authoritative reference for Spacelift policy input data and rule outputs. Use it to ensure every generated policy references valid fields and produces correct rule names.

The machine-readable source is bundled alongside this file as `policy-contract.json` (mirrors `https://app.spacelift.io/.well-known/policy-contract.json`).

> **Rego version note:** Every example in this file uses the portable form: `import future.keywords` and rule heads written with `if` and `contains`. It parses and decides the same under the `REGO_V0` and `REGO_V1` engines. Classic v0 heads (`deny[reason] { ... }`) fail to parse under `REGO_V1`. See the "Rego v0 vs v1 (engine versions)" section in `guides/formatting.md` and the verified walkthrough at `examples/01-plan-guard-destructive.md`.

## Policy Types at a Glance

| Type         | Package     | Rule Outputs                                                                                                                                                                                                                                 | Purpose                                                                     |
| ------------ | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| ACCESS       | `spacelift` | `read`, `write`, `deny_write`, `deny` (bool)                                                                                                                                                                                                 | Grant read or write access to a stack or module                             |
| APPROVAL     | `spacelift` | `approve`, `reject` (bool); `approve_with_note`, `reject_with_note` (sets of strings)                                                                                                                                                        | Approve or reject a run awaiting approval                                   |
| GIT_PUSH     | `spacelift` | `track`, `propose`, `ignore`, `ignore_track`, `notrigger`, `fail`, `notify`, `allow_fork`, `prioritize` (bool); `cancel`, `external_dependency`, `message` (sets of strings); `lock`, `unlock`, `module_version`, `priority` (strings)       | Decide what a push or pull request event does to a stack or module          |
| INTENT       | `spacelift` | `allow`, `deny` (sets of strings)                                                                                                                                                                                                            | Allow or deny a resource operation made through the Intent API              |
| LOGIN        | `spacelift` | `allow`, `admin`, `deny`, `deny_admin` (bool); `team`, `deny_message` (sets of strings); `roles` (map of space ID → set of role slugs)                                                                                                      | Control authentication and authorization                                    |
| NOTIFICATION | `spacelift` | `inbox`, `slack`, `webhook`, `pull_request` (sets of objects)                                                                                                                                                                                | Route notifications to the inbox, Slack, webhooks and pull request comments |
| PLAN         | `spacelift` | `deny`, `warn` (sets of strings - each element is a reason)                                                                                                                                                                                  | Evaluate a plan before it is applied                                        |
| TASK         | `spacelift` | `deny` (set of strings - each element is a reason)                                                                                                                                                                                           | Block a task command                                                        |
| TRIGGER      | `spacelift` | `trigger` (set of stack IDs); `priority` (string)                                                                                                                                                                                            | Trigger stacks after a tracked run ends or a module version is created      |

Every type also has `flag`, `reset_flag` and `sample` (see Rules on Every Type).

## Rule Shapes

Spacelift wraps each policy in a library that declares every contract rule with a default and reads back the map `data.spacelift.result`. The shape of a rule decides how to write its head:

- bool: `track if { ... }`. The library already declares `default track = false`, so a policy that writes its own `default` for a contract rule fails to compile.
- set: `deny contains reason if { ... }`. Writing a set rule as a boolean (`deny if ...`), or a boolean rule as a set, fails to compile with `conflicting rules`.
- string: `lock := value if { ... }`. The library default is `""`, which means unset.
- LOGIN `roles`: `roles[space_id] contains slug if { ... }`.

Rule outputs from every policy of a type attached to the same stack, module or account are combined. Each section says how.

## Rules on Every Type

- `flag` (set of strings) - strings attached to this evaluation. Where the policy evaluates against a run, they appear on that run's policy receipt and as `run.flags` for policies evaluated later for the same run
- `reset_flag` (set of strings) - flags to clear. A flag is cleared only once every policy that set it also requests the reset
- `sample` (bool) - store this evaluation's input and result in the policy's evaluation records, where the policy workbench can replay it. Defaults to false; LOGIN defaults to true

---

## ACCESS Policy

**Input paths:**

- `input.request.remote_ip` - IP address of the request origin
- `input.request.timestamp_ns` - request time, Unix nanoseconds
- `input.session.*` - the user's session (see Session Fields)
- `input.slack.*` - present instead of `session` when the request comes from Slack: `.command`, `.channel.id`, `.channel.name`, `.team.id`, `.team.name`, `.user.id`, `.user.real_name`, `.user.display_name`, `.user.is_admin`, `.user.is_owner`, `.user.is_restricted`, `.user.has_2fa`
- `input.stack.*` - the stack being accessed (see Common Stack Fields)
- `input.module.*` - present instead of `stack` when a module is accessed (see Common Module Fields)

**Rules:**

- `read` (bool) - grant read access
- `write` (bool) - grant write access; write implies read
- `deny_write` (bool) - cancel `write`, leaving read access if `read` grants it
- `deny` (bool) - deny all access, whatever the other rules decide

A rule true in any access policy counts. `deny` wins, then `write` unless `deny_write`, then `read`. With none of them true, the decision is deny.

**Example patterns:**

```rego
package spacelift

import future.keywords

# The DevOps team can write
write if "DevOps" in input.session.teams

# The Engineering team can read
read if "Engineering" in input.session.teams

# Only admins write to administrative stacks
deny_write if {
	input.stack.administrative
	not input.session.admin
}
```

---

## APPROVAL Policy

**Input paths:**

- `input.run.*` - the run awaiting approval (see Common Run Fields)
- `input.run.repository_runtime_config_changed` - whether the repository runtime config has changed (approval only)
- `input.stack.*` - stack the run belongs to
- `input.reviews.current.approvals[]`, `input.reviews.current.rejections[]` - reviews cast against the current state of the run
- `input.reviews.older.approvals[]`, `input.reviews.older.rejections[]` - reviews cast before the run last changed
- Each review: `.author`, `.note` (empty when none), `.state`, `.state_version`, `.author_roles[]` (roles the author had at the time, each `.id`, `.name`, `.slug`, `.ulid`; may be null), `.identity.ulid` and `.identity.federations[<provider>].id` / `.username` (present when an identity resolves), `.session.*` and `.request.*` (stored as recorded, so keys vary)

**Rules:**

- `approve` (bool) - approve the run
- `reject` (bool) - reject the run
- `approve_with_note` (set of strings) - a non-empty set approves the run; each entry is recorded against the approval
- `reject_with_note` (set of strings) - a non-empty set rejects the run; each entry is recorded against the rejection

The run is approved when every attached approval policy approves and none rejects. It is rejected when a policy rejects and not every policy approves. Otherwise the decision is undecided.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Two distinct SRE approvers on the current state approve the run,
# unless a rejection below applies
approve if {
	count(sre_approvers) >= 2
	count(input.reviews.current.rejections) == 0
	not input.run.repository_runtime_config_changed
}

# Any rejection on the current state rejects the run
reject if count(input.reviews.current.rejections) > 0

# A runtime config change in the repository is rejected with a reason
reject_with_note contains "Runtime config changed in the repository" if {
	input.run.repository_runtime_config_changed
}

sre_approvers contains review.author if {
	some review in input.reviews.current.approvals
	some role in review.author_roles
	role.slug == "sre"
}
```

---

## GIT_PUSH Policy

**Input paths:**

- `input.push.*` - the pushed commit: `.branch`, `.hash`, `.message`, `.author`, `.tag`, `.created_at`, `.affected_files[]`, `.affected_stacks_count` (stacks and modules on the repository whose project root or globs match the files, counted before any policy runs), `.commits[]` (commits batched into this push, oldest first; Commit Fields plus `.affected_files[]`)
- `input.pull_request.*` - the pull request event: `.id` (integer), `.action`, `.action_initiator`, `.author`, `.title`, `.labels[]`, `.draft`, `.closed`, `.approved`, `.mergeable`, `.undiverged`, `.head_owner`, `.diff[]` (files the pull request changes), `.affected_stacks_count`, `.head.*` and `.base.*` (Commit Fields), `.comment` (string, present only when the event carries a comment)
- `input.in_progress[]` - runs in progress for this stack: Common Run Fields except `.changes`, `.creator_session`, `.flags` and `.runtime_config`
- `input.vcs_integration.*` - `.id`, `.name`, `.description`, `.provider`, `.is_default`, `.labels[]`, `.space.*`, `.created_at`, `.updated_at`; set on push events only
- `input.stack.*` - stack that may be affected
- `input.module.*` - present instead of `stack` for a module, plus `input.module.current_version` (number of the latest version, `0.0.0` when there is none)

**Push vs pull_request:**

- On a push event, `input.pull_request` is null.
- On a pull request event, `input.push` holds the merge commit when the pull request was merged, otherwise the head commit. It is absent when the head branch is the stack's tracked branch and the pull request was not merged.
- Match files with `input.push.affected_files` for pushes and `input.pull_request.diff` for pull requests, and write one rule body per event so a missing document fails only its own body.

**Rules:**

- `track` (bool) - track the pushed commit and trigger a tracked run
- `propose` (bool) - trigger a proposed run without tracking the commit
- `ignore` (bool) - ignore the push entirely
- `ignore_track` (bool) - cancel `track`: the result is a proposed run if `propose` is true, otherwise the push is ignored
- `notrigger` (bool) - track the commit without triggering a run
- `fail` (bool) - report the push as failed against the commit; no run is triggered
- `notify` (bool) - send a commit status check for a push that is ignored; it has no effect on any other outcome
- `message` (set of strings) - commit status message in place of the default; entries from every policy are joined with `, `
- `cancel` (set of strings) - IDs of in-progress runs to cancel (`input.in_progress[].id`)
- `external_dependency` (set of strings) - external dependency markers the resulting run must wait on
- `allow_fork` (bool) - allow a run for a pull request opened from a forked repository
- `prioritize` (bool) - put the resulting run ahead of others on a private worker pool queue
- `priority` (string: `high`, `normal` or `low`) - priority of the resulting run on a private worker pool queue. An error when combined with `prioritize` or when policies disagree
- `lock` (string) - lock the stack under this identifier; every policy must give the same value
- `unlock` (string) - unlock the stack held under this identifier
- `module_version` (string) - version to publish when the push targets a module; more than one policy setting it is an error

A boolean true in any push policy counts. `ignore` wins, then `track` unless `ignore_track`, then `propose`. With none of them true, the push is ignored.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Track pushes to the stack's tracked branch
track if input.push.branch == input.stack.branch

# Propose a run for every pull request event
propose if not is_null(input.pull_request)

# Ignore events that change nothing under the project root (monorepo pattern)
ignore if not affected

# Ignore draft pull requests
ignore if input.pull_request.draft

affected if {
	some file in input.push.affected_files
	startswith(file, input.stack.project_root)
}

affected if {
	some file in input.pull_request.diff
	startswith(file, input.stack.project_root)
}
```

---

## INTENT Policy

**Input paths:**

- `input.resource.resource_id` - identifier of the resource
- `input.resource.provider` - provider name, e.g. `hashicorp/aws`
- `input.resource.provider_version` - provider version (semver)
- `input.resource.resource_type` - resource type, e.g. `aws_instance`
- `input.resource.operation` - `create`, `update`, `delete`, `refresh` or `import`
- `input.resource.current_state`, `input.resource.proposed_state` - resource state before and after the operation; keys are defined by the provider; may be null
- `input.reviews.allow[]`, `input.reviews.deny[]` - reviews approving or rejecting the operation, empty when there are none. Each: `.author`, `.session.*` and `.request.*` (stored as recorded, so keys vary)

**Rules:**

- `allow` (set of strings) - reasons to allow the operation
- `deny` (set of strings) - reasons to deny the operation; vetoes `allow`

Reasons from every intent policy add up. Any deny reason denies the operation. Otherwise any allow reason allows it. With neither, the operation is pending.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Creates and refreshes go ahead
allow contains "non-destructive operation" if input.resource.operation in {"create", "refresh"}

# Any other operation goes ahead once a reviewer approves it
allow contains sprintf("approved by %s", [review.author]) if {
	some review in input.reviews.allow
}

# A reviewer's rejection blocks the operation
deny contains sprintf("rejected by %s", [review.author]) if {
	some review in input.reviews.deny
}
```

---

## LOGIN Policy

**Input paths:**

- `input.request.remote_ip` - requester IP
- `input.request.timestamp_ns` - request timestamp
- `input.session.login` - login identifier (e.g., GitHub username)
- `input.session.name` - display name
- `input.session.teams` - teams (array, may be null)
- `input.session.machine` - always false in a login policy input
- `input.session.member` - whether the identity provider counts the user as a member: with GitHub, membership of the account's GitHub organization; with SAML or OIDC, always true; with Google, GitLab or Microsoft, false for every user a login policy sees
- `input.session.creator_ip` - session creation IP
- `input.slack.*` - Slack auth info (alternative to session)
- `input.spaces[]` - available spaces (each: `.id`, `.name`, `.labels[]`)
- `input.roles[]` - available roles (each: `.id`, `.name`, `.slug`, `.ulid`)

`input.session.admin` is absent from a login policy input.

**Rules:**

- `allow` (bool) - allow non-admin login
- `admin` (bool) - grant account admin
- `deny` (bool) - deny login, whatever any policy allows
- `deny_admin` (bool) - cancel `admin`; it does not remove a space-admin role on the root space, which also makes the user an account admin
- `deny_message` (set of strings) - messages shown when the login is denied
- `team` (set of strings) - replace the teams from the identity provider; the user gets every role bound to them
- `roles` (map: space ID → set of role slugs) - grant roles in spaces; role slugs are in `input.roles[].slug`, and the system roles are space-admin, space-writer and space-reader

Spacelift evaluates every login policy on the account and combines the results. allow, admin and deny from any one policy count, and team and roles grants from all of them add up, so a grant without a condition reaches every user that any login policy lets in.

A login policy must not let in everyone the identity provider authenticates. A condition that only checks that input.session.login is set does exactly that. With GitHub, condition allow and admin on input.session.member or input.session.teams. With Google, GitLab or Microsoft, condition them on input.session.login, such as the company email domain (GitLab also sends teams; Google and Microsoft send none). Saving refuses a login policy that lets in a sample outsider, but only for that one sample.

space_read, space_write and space_admin are deprecated. Spacelift still honours them in existing policies. Write roles instead.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Members of the account's GitHub organization log in
allow if input.session.member

# The platform team are account admins
admin if "platform-engineering" in input.session.teams

# Every member can read every space
roles[space.id] contains "space-reader" if {
	input.session.member
	some space in input.spaces
}

# Each team writes to the spaces labelled with its name
roles[space.id] contains "space-writer" if {
	input.session.member
	some space in input.spaces
	some team in input.session.teams
	concat("", ["team:", team]) in space.labels
}
```

---

## NOTIFICATION Policy

**Input paths:**

- `input.account.name` - account display name
- `input.webhook_endpoints[]` - webhook endpoints (each: `.id`, `.labels[]`)

**Event-specific (exactly one is present):**

- `input.run_updated` - a run changed state:
  - `.state` - new run state
  - `.username` - user who caused the change (nullable)
  - `.note` - note for the state transition (nullable)
  - `.run.*` - the run (see Common Run Fields), plus `.promoted`, `.states_history[]` (`.new_state`, `.note`, `.username`) and `.commit.author_identity.*`
  - `.stack.*` - stack the run belongs to
  - `.urls.run` - URL of the run
  - `.timing[]` - `.state` and `.duration` (nanoseconds) for each state the run has left; null until the run leaves its first state
  - `.policy_receipts[]` - `.type`, `.name`, `.outcome`, `.flags[]`; null when the run has none
  - `.plan_policy_decision.deny[]`, `.plan_policy_decision.warn[]` - plan policy outcome (nullable)
- `input.module_version` - a module version changed state:
  - `.module.*` - see Common Module Fields
  - `.version.*` - `.id`, `.number`, `.state`, `.latest`, `.created_at`, `.commit.*`, `.test_runs[]` (`.id`, `.title`, `.state`, `.created_at`, `.updated_at`)
- `input.internal_error` - Spacelift itself failed: `.severity`, `.message`, `.error`
- `input.worker_usage` - the account's private-worker usage is running into its contract: `.severity`, `.message`, `.contracted_limit`, `.contracted_percentile`, `.concurrency_at_contracted_percentile`, `.limit_ratio`, `.burst_budget_minutes`, `.burst_used_minutes`, `.burst_remaining_minutes`, `.burst_ratio`, `.cycle_start` and `.cycle_end` (Unix seconds). `.previous_concurrency_at_contracted_percentile`, `.previous_limit_ratio`, `.previous_burst_used_minutes` and `.previous_burst_ratio` hold the value a day earlier; compare with them to fire once when a threshold is first crossed

**Rules (sets of objects, one object per message):**

- `inbox` - Spacelift inbox: `title`, `body`, `severity` (`INFO`, `WARNING` or `ERROR`)
- `slack` - Slack: `channel_id` (required), `message` (replaces the default message), `mention_users[]`, `mention_groups[]` (mentioned in the default message), `thread_key` (the first message with a key starts a thread, later ones reply to it)
- `webhook` - webhook: `endpoint_id` (required, `input.webhook_endpoints[].id`), `payload` (custom JSON body), `method`, `headers` (map of strings appended to the request)
- `pull_request` - pull request comment: `id` (integer), `branch`, `commit` (target commit SHA), `body`, `deduplication_key` (updates an existing comment instead of adding another), `truncate_body` (bool)

Messages from every notification policy add up. With all four sets empty, nothing is sent.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Failed tracked runs go to the ops Slack channel
slack contains {"channel_id": "C0123456789", "message": msg} if {
	input.run_updated.state == "FAILED"
	input.run_updated.run.type == "TRACKED"
	msg := sprintf("Run %s on stack %s failed: %s", [
		input.run_updated.run.id,
		input.run_updated.stack.name,
		input.run_updated.urls.run,
	])
}

# Finished runs go to every webhook endpoint labelled ops-alerts
webhook contains {"endpoint_id": endpoint.id, "payload": payload} if {
	input.run_updated.state == "FINISHED"
	some endpoint in input.webhook_endpoints
	"ops-alerts" in endpoint.labels
	payload := {"run": input.run_updated.run.id, "stack": input.run_updated.stack.id}
}

# Internal errors go to the inbox
inbox contains {"title": "Spacelift internal error", "body": input.internal_error.message, "severity": "ERROR"} if {
	input.internal_error
}
```

---

## PLAN Policy

**Input paths:**

- `input.spacelift.run.*` - the run (see Common Run Fields), plus `.promoted`
- `input.spacelift.previous_run.*` - the previous run, same fields (nullable)
- `input.spacelift.commit.*` - see Commit Fields
- `input.spacelift.request.timestamp_ns` - request time, Unix nanoseconds
- `input.spacelift.stack.*` - stack being planned (or `input.spacelift.module.*`)
- `input.terraform` - Terraform plan; on OpenTofu stacks it mirrors `input.opentofu`; null for other vendors:
  - `.resource_changes[]` - `.address`, `.type`, `.name`, `.mode` (`managed` or `data`), `.module_address`, `.provider_name`, `.change.actions[]` (one or more of `no-op`, `create`, `read`, `update`, `delete`), `.change.before` (null on create), `.change.after` (null on delete), `.change.after_unknown`; attribute keys are defined by the provider
  - `.checks[]` - check block results as the plan JSON reports them
  - `.terraform_version`
- `input.opentofu` - same shape for OpenTofu stacks, with `.opentofu_version` in place of `.terraform_version`
- `input.terragrunt[<project>]` - one Terraform-shaped plan per Terragrunt project
- `input.pulumi.steps[]` - Pulumi preview steps, keys as Pulumi reports them
- `input.cloudformation.changes[]` - change set changes, keys as CloudFormation reports them
- `input.kubernetes`, `input.ansible` - plan data passed through as the vendor produced it (nullable)
- `input.third_party_metadata.infracost` - Infracost report, absent unless the run produced one; keyed by project for Terragrunt
- `input.third_party_metadata.custom[<name>]` - custom inputs: a file named `<name>.custom.spacelift.json` lands under `<name>`

**Rules:**

- `deny` (set of strings) - reasons to block the plan from being applied
- `warn` (set of strings) - warnings about the plan

Reasons from every plan policy add up. Any deny reason blocks the plan.

The library defines helper sets of `input.terraform.resource_changes[]` entries: `affected_resources` (create, update or delete), `created_resources`, `updated_resources`, `deleted_resources` and `recreated_resources` (both created and deleted). Use them directly; a policy rule with one of these names and another shape fails to compile.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Block plans that delete more than 5 resources
deny contains sprintf("Plan deletes %d resources (limit: 5)", [count(deleted_resources)]) if {
	count(deleted_resources) > 5
}

# Warn on every replaced resource
warn contains sprintf("%s will be replaced", [resource.address]) if {
	some resource in recreated_resources
}

# Block new IAM users
deny contains sprintf("Do not create IAM users: %s", [resource.address]) if {
	some resource in created_resources
	resource.type == "aws_iam_user"
}
```

---

## TASK Policy

**Input paths:**

- `input.request.command` - command to be executed
- `input.request.remote_ip` - IP address of the request origin
- `input.request.timestamp_ns` - request time, Unix nanoseconds
- `input.session.*` - the session running the task (see Session Fields)
- `input.stack.*` - stack the task runs on (or `input.module.*`)

The library defines `request`, `session` and `stack` as `input.request`, `input.session` and `input.stack`. Do not define rules with those names.

**Rules:**

- `deny` (set of strings) - reasons to block the task from executing

Reasons from every task policy add up. Any deny reason blocks the task.

**Example patterns:**

```rego
package spacelift

import future.keywords

# Only terraform and tofu commands run as tasks
deny contains sprintf("Command not allowed: %s", [input.request.command]) if {
	not allowed_command
}

# Only admins run state commands, wherever "state" appears as a word
deny contains "Only admins run state commands" if {
	"state" in command_words
	not input.session.admin
}

command_words := regex.split(`\s+`, trim_space(input.request.command))

allowed_command if startswith(input.request.command, "terraform ")

allowed_command if startswith(input.request.command, "tofu ")
```

---

## TRIGGER Policy

**Input paths (a tracked run reached a terminal state):**

- `input.run.*` - the run (see Common Run Fields), plus `.promoted`, `.states_history[]` (`.new_state`, `.note`, `.username`) and `.priority` (`high`, `normal` or `low`). `.state` is one of `FINISHED`, `FAILED`, `CANCELED`, `DISCARDED`, `STOPPED`, `SKIPPED`
- `input.stack.*` - stack the run belongs to
- `input.stacks[]` - candidate stacks (Common Stack Fields plus `.queued_runs`): only stacks in the policy's space and the spaces below it
- `input.workflow[]` - workflow runs (each: `.id`, `.stack_id`, `.state`, `.type`)

**Input paths (a module version was created):**

- `input.module.*` - the module (see Common Module Fields)
- `input.module.version.*` - the version: `.id`, `.number`, `.state`, `.latest`, `.created_at`, `.commit.*`, `.test_runs[]` (nullable)
- `input.stacks[]` - candidate stacks (Common Stack Fields plus `.queued_runs`)

**Rules:**

- `trigger` (set of strings) - IDs of stacks to trigger (`input.stacks[].id`)
- `priority` (string: `high`, `normal` or `low`) - priority of every run this policy triggers on a private worker pool queue. Policies that disagree about one stack leave its run at `normal`

**Example patterns:**

```rego
package spacelift

import future.keywords

# After a successful tracked run, trigger stacks labelled depends-on:<this stack>
trigger contains stack.id if {
	input.run.state == "FINISHED"
	input.run.type == "TRACKED"
	some stack in input.stacks
	concat("", ["depends-on:", input.stack.id]) in stack.labels
}

# After a new latest module version, trigger idle stacks labelled uses:<module>
trigger contains stack.id if {
	input.module.version.latest
	some stack in input.stacks
	stack.queued_runs == 0
	concat("", ["uses:", input.module.id]) in stack.labels
}

# Runs triggered after drift detection queue at low priority
priority := "low" if input.run.drift_detection
```

---

## Common Run Fields

Used by `input.run` (APPROVAL, TRIGGER), `input.spacelift.run` and `input.spacelift.previous_run` (PLAN), `input.run_updated.run` (NOTIFICATION) and, in part, `input.in_progress[]` (GIT_PUSH).

- `.id` - run identifier
- `.type` - `PROPOSED`, `TRACKED`, `TASK`, `TESTING`, `DESTROY` or `PARSE`
- `.state` - current run state
- `.branch` - git branch
- `.commit.*` - see Commit Fields
- `.command` - command executed for the run (nullable)
- `.created_at`, `.updated_at` - Unix nanoseconds
- `.drift_detection` - whether this is a drift detection run
- `.triggered_by` - who or what triggered the run (nullable)
- `.trigger.run.id`, `.trigger.stack.id`, `.trigger.trigger.*` - the run that triggered this one, its stack and its own trigger (nullable)
- `.creator_session.*` - session that created the run (see Session Fields), plus `.identity.ulid` and `.identity.federations[<provider>].id` / `.username`
- `.flags[]` - flags set on this run by policies evaluated earlier for it
- `.changes[]` - Spacelift's record of entity changes, not Terraform's plan format:
  - `.phase` - `plan` or `apply`
  - `.action` - `added`, `changed`, `deleted`, `no-op`, `read`, `destroy-Before-create-replaced`, `create-Before-destroy-replaced`, `import`, `forget`, `create-after-forgotten`, `ok`, `skipped`, `rescued`, `ignored`, `unreachable`, `failed`, `open`, `renew` or `close`. A replaced resource has one change
  - `.moved` - whether the entity was moved
  - `.entity.address`, `.entity.name`, `.entity.type` (as the vendor reports it), `.entity.entity_type` (`resource`, `output`, `stack` or `module`), `.entity.entity_vendor` (`terraform`, `opentofu`, `pulumi` or `cloudformation`)
  - `.entity.data.*` - vendor-specific detail, e.g. `.values` (Terraform resource attributes), `.provider`, `.module`, `.tainted`, `.urn` (Pulumi), `.logical_resource_id` (CloudFormation)
- `.runtime_config.*` (nullable) - `.project_root`, `.runner_image`, `.terraform_version`, `.environment` (map of variables), `.git_sparse_checkout_paths[]`, hook command lists `.before_init[]`, `.before_plan[]`, `.before_apply[]`, `.before_perform[]`, `.before_destroy[]`, `.after_init[]`, `.after_plan[]`, `.after_apply[]`, `.after_perform[]`, `.after_destroy[]`, `.after_run[]`
- `.user_provided_metadata[]` - user-provided metadata strings
- `.force_apply_mode` - `DISABLED`, `SINGLE` or `CASCADE`
- `.based_on_local_workspace` - whether the run is based on a local workspace

## Session Fields

Used by `input.session` (ACCESS, TASK) and `.creator_session` on runs. LOGIN differs; see its section.

- `.login` - login identifier
- `.name` - display name
- `.teams[]` - teams the user belongs to (may be null)
- `.admin` - whether the session has admin privileges; an empty string on a run whose creator was a machine
- `.machine` - whether the session belongs to a machine rather than a person
- `.creator_ip` - IP address where the session was created
- `.idp_subject` - subject (sub) claim from the identity provider; empty only for a secret-based API key
- `.stack_id` - slug of the stack whose run holds this session; present only for a session Spacelift issued to a run

## Commit Fields

- `.author`, `.branch`, `.hash`, `.message`, `.tag`, `.url`
- `.created_at` - Unix nanoseconds
- `.pull_request_id` - pull request ID if the commit is from a pull request (nullable)
- `.exist_on_tracked_branch` - whether the commit exists on the tracked branch (nullable)

## Common Stack Fields (used across many policy types)

- `input.stack.id` - stack identifier
- `input.stack.name` - display name
- `input.stack.branch` - tracked git branch
- `input.stack.repository` - repository name
- `input.stack.project_root` - project root directory
- `input.stack.additional_project_globs[]` - additional project glob patterns
- `input.stack.namespace` - stack namespace
- `input.stack.state` - current stack state
- `input.stack.administrative` - whether administrative
- `input.stack.autodeploy` - whether autodeploy is enabled
- `input.stack.labels[]` - stack labels (may be null)
- `input.stack.contexts[]` - attached context slugs
- `input.stack.locked_by` - user who locked it (nullable)
- `input.stack.roles[]` - Spacelift roles granted on the stack (each: `.id`, `.name`, `.slug`, `.ulid`)
- `input.stack.space.id`, `input.stack.space.name`, `input.stack.space.labels[]` - space the stack belongs to (`space` is nullable)
- `input.stack.worker_pool.public` - whether it is the public worker pool (`worker_pool` is nullable)
- `input.stack.worker_pool.id`, `input.stack.worker_pool.name`, `input.stack.worker_pool.labels[]` - absent for the public pool rather than null
- `input.stack.terraform_version` - Terraform version (Terraform stacks only, null for other vendors)
- `input.stack.terraform_workflow_tool` - workflow tool (Terraform stacks only, null for other vendors)
- `input.stack.tracked_commit.*` - currently tracked commit, see Commit Fields (nullable)

## Common Module Fields

- `input.module.id` - module identifier
- `input.module.name` - module name
- `input.module.namespace` - module namespace
- `input.module.branch` - tracked branch
- `input.module.repository` - repository name
- `input.module.project_root` - project root
- `input.module.administrative` - whether administrative
- `input.module.terraform_provider` - Terraform provider
- `input.module.labels[]` - labels (may be null)
- `input.module.contexts[]` - context slugs
- `input.module.space.*` - space (`.id`, `.name`, `.labels[]`; nullable)
- `input.module.worker_pool.*` - worker pool (same fields as the stack's; nullable)

`input.module.current_version` exists only in GIT_PUSH input, and `input.module.version` only in TRIGGER input.
