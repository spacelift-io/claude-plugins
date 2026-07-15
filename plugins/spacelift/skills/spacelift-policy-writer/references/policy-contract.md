# Spacelift Policy Contract - Quick Reference

This is the authoritative reference for Spacelift policy input data and rule outputs. Use it to ensure every generated policy references valid fields and produces correct rule names.

The machine-readable source is bundled alongside this file as `policy-contract.json` (mirrors `https://app.spacelift.io/.well-known/policy-contract.json`).

> **Rego version note:** The example patterns in this file are shown in classic Rego **v0** syntax (`deny[reason] { ... }`, bare helper rules). Spacelift also has a `REGO_V1` engine (OPA 1.0 syntax) under which v0 syntax fails to parse - `if` and `contains` are mandatory there. For new policies, prefer the portable form (`import future.keywords.contains` / `import future.keywords.if` plus `deny contains reason if { ... }`), which works identically under both engines. See the "Rego v0 vs v1 (engine versions)" section in `guides/formatting.md` and the verified walkthrough at `examples/01-plan-guard-destructive.md`.

## Policy Types at a Glance

| Type         | Package     | Rule Outputs                                                                                                                                                                                    | Purpose                                                     |
| ------------ | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| ACCESS       | `spacelift` | `allow`, `deny` (bool)                                                                                                                                                                            | Control user access to stacks/modules                       |
| APPROVAL     | `spacelift` | `approve`, `reject` (bool)                                                                                                                                                                        | Auto-approve or reject runs awaiting approval               |
| GIT_PUSH     | `spacelift` | `track`, `propose`, `ignore` (bool)                                                                                                                                                              | Respond to git push/PR events                               |
| LOGIN        | `spacelift` | `allow`, `admin`, `deny` (bool); `space_read`, `space_write`, `space_admin`, `teams` (sets of strings); `roles` (map of space slug → list of role slugs)                                          | Control authentication and authorization                    |
| NOTIFICATION | `spacelift` | `send` (bool); `channels`, `message`, `subject` (strings)                                                                                                                                        | Control notification delivery                               |
| PLAN         | `spacelift` | `deny`, `warn` (sets of strings - each element is a reason)                                                                                                                                       | Evaluate terraform/OpenTofu plans before apply              |
| TASK         | `spacelift` | `deny`, `warn` (sets of strings - each element is a reason)                                                                                                                                       | Control task command execution                              |
| TRIGGER      | `spacelift` | `stacks`, `modules` (sets of stack/module IDs to trigger)                                                                                                                                        | Trigger downstream stacks/modules on run completion         |

---

## ACCESS Policy

**Input paths:**

- `input.request.remote_ip` - requester IP
- `input.request.timestamp_ns` - request timestamp (nanoseconds)
- `input.session.login` - user login identifier
- `input.session.name` - user display name
- `input.session.teams` - user's teams (array, may be null)
- `input.session.admin` - whether session has admin privileges
- `input.session.machine` - whether this is a machine session
- `input.session.creator_ip` - session creation IP
- `input.stack.*` - stack being accessed (see Stack fields below)
- `input.module.*` - module being accessed (alternative to stack)
- `input.slack.*` - Slack access info (alternative to session)

**Rules:** `allow` = true/false, `deny` = true/false

**Example patterns:**

```rego
package spacelift

# Allow access for members of the DevOps team
allow {
    input.session.teams[_] == "DevOps"
}

# Deny access to administrative stacks for non-admins
deny {
    input.stack.administrative
    not input.session.admin
}
```

---

## APPROVAL Policy

**Input paths:**

- `input.run.id` - run identifier
- `input.run.type` - run type (TRACKED, PROPOSED, etc.)
- `input.run.state` - current run state
- `input.run.branch` - git branch
- `input.run.commit.*` - commit info (author, branch, message, hash, etc.)
- `input.run.changes[]` - entity changes (phase, action, moved, entity)
- `input.run.creator_session.*` - session that created the run
- `input.run.drift_detection` - whether this is a drift detection run
- `input.run.triggered_by` - who/what triggered the run
- `input.run.runtime_config.*` - runtime configuration
- `input.run.user_provided_metadata[]` - user metadata strings
- `input.run.repository_runtime_config_changed` - whether repo runtime config changed (approval-specific)
- `input.reviews.current.approvals[]` - current approval events
- `input.reviews.current.rejections[]` - current rejection events
- `input.reviews.older.approvals[]` - previous approval events
- `input.reviews.older.rejections[]` - previous rejection events
- Each approval/rejection: `.author`, `.state`, `.state_version`, `.author_roles[]` (each role has `.id`, `.name`, `.slug`, `.ulid`)
- `input.stack.*` - stack associated with the run

**Rules:** `approve` = true/false, `reject` = true/false

**Example patterns:**

```rego
package spacelift

# Auto-approve if two unique approvers from the SRE team
approve {
    approvers := {review.author |
        review := input.reviews.current.approvals[_]
    }
    count(approvers) >= 2
}

# Reject runs that modify runtime config
reject {
    input.run.repository_runtime_config_changed
}
```

---

## GIT_PUSH Policy

**Input paths:**

- `input.push.branch` - git branch pushed to
- `input.push.hash` - commit hash
- `input.push.message` - commit message
- `input.push.author` - push author
- `input.push.tag` - git tag (if any)
- `input.push.created_at` - push timestamp
- `input.push.affected_files[]` - files changed by the push
- `input.pull_request.action` - PR action type (opened, synchronize, closed, etc.)
- `input.pull_request.author` - PR author
- `input.pull_request.title` - PR title
- `input.pull_request.labels[]` - PR labels
- `input.pull_request.draft` - whether PR is a draft
- `input.pull_request.closed` - whether PR is closed
- `input.pull_request.diff[]` - files affected by the PR
- `input.pull_request.head.*` - head commit (branch, hash, author, message)
- `input.pull_request.base.*` - base commit
- `input.pull_request.id` - PR identifier
- `input.pull_request.approved` - whether PR is approved
- `input.pull_request.mergeable` - whether PR is mergeable
- `input.pull_request.undiverged` - whether PR is undiverged
- `input.pull_request.head_owner` - owner of head repo
- `input.pull_request.comment` - PR comment (string, object, or null)
- `input.stack.*` - stack that may be affected
- `input.module.*` - module that may be affected (alternative to stack)
- `input.in_progress[]` - runs currently in progress (each has `.id`, `.state`, `.type`, `.branch`, `.commit.*`, `.triggered_by`, `.drift_detection`)
- `input.vcs_integration.*` - VCS integration info (`.id`, `.name`, `.provider`, `.is_default`, `.labels[]`, `.space.*`)

**Rules:** `track` = true/false, `propose` = true/false, `ignore` = true/false

**Critical distinction - push vs pull_request:**

- For push events: use `input.push.affected_files` for file-path matching
- For PR events: use `input.pull_request.diff` for file-path matching
- `input.push` may be null on PR events; `input.pull_request` may be null on push events
- Always guard with null checks or use the appropriate field for the event type

**Example patterns:**

```rego
package spacelift

# Track pushes to the main branch
track {
    input.push.branch == input.stack.branch
}

# Propose runs for PRs
propose {
    input.pull_request.action != ""
}

# Ignore changes outside the project root (monorepo pattern)
ignore {
    not affected_files_in_project
}

affected_files_in_project {
    some file in input.push.affected_files
    startswith(file, input.stack.project_root)
}

# Also check PR diff for PR events
affected_files_in_project {
    some file in input.pull_request.diff
    startswith(file, input.stack.project_root)
}

# Ignore draft PRs
ignore {
    input.pull_request.draft
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
- `input.session.admin` - current admin status
- `input.session.machine` - whether machine session
- `input.session.member` - whether user is a member of the account
- `input.session.creator_ip` - session creation IP
- `input.slack.*` - Slack auth info (alternative to session)
- `input.spaces[]` - available spaces (each: `.id`, `.name`, `.labels[]`)
- `input.roles[]` - available roles (each: `.id`, `.name`, `.slug`, `.ulid`)

**Rules:**

- `allow` (bool) - allow non-admin login
- `admin` (bool) - grant admin privileges
- `deny` (bool) - deny login
- `space_read` (set of space IDs) - grant read access to spaces
- `space_write` (set of space IDs) - grant write access to spaces
- `space_admin` (set of space IDs) - grant admin access to spaces
- `teams` (set of strings) - assign teams
- `roles` (map: space slug → list of role slugs) - assign roles in spaces

**Example patterns:**

```rego
package spacelift

# Allow members to log in
allow {
    input.session.member
}

# Grant admin to platform team
admin {
    input.session.teams[_] == "platform-engineering"
}

# Map GitHub teams to Spacelift spaces
space_read[space.id] {
    space := input.spaces[_]
    input.session.teams[_] == "developers"
}

space_write[space.id] {
    space := input.spaces[_]
    space.labels[_] == concat("", ["team:", input.session.teams[_]])
}

# Assign roles in spaces
roles := { space.id: ["viewer"] |
    space := input.spaces[_]
    input.session.teams[_] == "readonly-team"
}
```

---

## NOTIFICATION Policy

**Input paths:**

- `input.account.name` - account display name
- `input.webhook_endpoints[]` - available webhooks (each: `.id`, `.labels[]`)

**Event-specific (exactly one will be present):**

- `input.run_updated.run.*` - the updated run
- `input.run_updated.stack.*` - associated stack
- `input.run_updated.state` - new run state
- `input.run_updated.username` - user who triggered state change (nullable)
- `input.run_updated.note` - optional state transition note
- `input.run_updated.urls.run` - URL to the run
- `input.run_updated.timing` - run timing info
- `input.run_updated.policy_receipts[]` - policy execution receipts (each: `.type`, `.name`, `.outcome`, `.flags[]`)
- `input.run_updated.plan_policy_decision.deny[]` - plan deny reasons
- `input.run_updated.plan_policy_decision.warn[]` - plan warnings
- `input.internal_error.severity` - error severity
- `input.internal_error.message` - error message
- `input.internal_error.error` - error details
- `input.module_version.module.*` - module with new version
- `input.module_version.version.*` - the new version (`.id`, `.number`, `.state`, `.latest`, `.commit.*`)

**Rules:**

- `send` (bool) - whether to send notification
- `channels` (set of strings) - notification channels
- `message` (string) - custom message content
- `subject` (string) - custom subject/title

**Example patterns:**

```rego
package spacelift

# Notify on failed tracked runs
send {
    input.run_updated.state == "FAILED"
    input.run_updated.run.type == "TRACKED"
}

# Send to Slack
channels[channel_id] {
    send
    channel_id := "slack-channel-id"
}

# Route to webhook by label
channels[endpoint.id] {
    send
    endpoint := input.webhook_endpoints[_]
    endpoint.labels[_] == "ops-alerts"
}

# Custom message
message := sprintf("Run %s on stack %s failed", [
    input.run_updated.run.id,
    input.run_updated.stack.name,
])
```

---

## PLAN Policy

**Input paths:**

- `input.spacelift.commit.*` - git commit (author, branch, message, hash, etc.)
- `input.spacelift.request.*` - plan request details
- `input.spacelift.run.*` - run info (`.id`, `.type`, `.state`, `.branch`, `.changes[]`, `.creator_session.*`, `.drift_detection`, `.flags[]`, `.runtime_config.*`, `.user_provided_metadata[]`)
- `input.spacelift.previous_run.*` - previous run info (nullable)
- `input.spacelift.stack.*` - stack being planned (or `input.spacelift.module.*`)
- `input.terraform.resource_changes[]` - Terraform resource changes (standard Terraform JSON plan format)
- `input.terraform.resource_drift[]` - detected drift
- `input.terraform.output_changes` - output changes
- `input.terraform.terraform_version` - Terraform version
- `input.cloudformation` - CloudFormation plan data (nullable)
- `input.kubernetes` - Kubernetes plan data (nullable)
- `input.pulumi` - Pulumi plan data (nullable)
- `input.ansible` - Ansible plan data (nullable)
- `input.terragrunt` - Terragrunt plan data (nullable)
- `input.third_party_metadata` - third-party data like Infracost (nullable)

**Rules:** `deny` (set of reason strings), `warn` (set of reason strings)

**Example patterns:**

```rego
package spacelift

# Deny plans that delete more than N resources
deny[reason] {
    deletions := [rc |
        rc := input.terraform.resource_changes[_]
        rc.change.actions[_] == "delete"
    ]
    count(deletions) > 5
    reason := sprintf("Plan would delete %d resources (limit: 5)", [count(deletions)])
}

# Warn on any resource replacements
warn[reason] {
    rc := input.terraform.resource_changes[_]
    rc.change.actions[_] == "delete"
    rc.change.actions[_] == "create"
    reason := sprintf("Resource %s will be replaced (destroy+create)", [rc.address])
}

# Deny unapproved provider versions
deny[reason] {
    rc := input.terraform.resource_changes[_]
    not startswith(rc.provider_name, "registry.terraform.io/hashicorp/")
    reason := sprintf("Unapproved provider: %s", [rc.provider_name])
}
```

---

## TASK Policy

**Input paths:**

- `input.request.command` - command to be executed
- `input.request.remote_ip` - requester IP
- `input.request.timestamp_ns` - request timestamp
- `input.session.*` - user session (login, name, teams, admin, machine, etc.)
- `input.stack.*` - stack where task runs (or `input.module.*`)

**Rules:** `deny` (set of reason strings), `warn` (set of reason strings)

**Example patterns:**

```rego
package spacelift

# Only allow specific commands
deny[reason] {
    not allowed_command
    reason := sprintf("Command not allowed: %s", [input.request.command])
}

allowed_command {
    startswith(input.request.command, "terraform ")
}

allowed_command {
    startswith(input.request.command, "tofu ")
}

# Warn on state manipulation
warn[reason] {
    contains(input.request.command, "state ")
    reason := "This command manipulates Terraform state - proceed with caution"
}
```

---

## TRIGGER Policy

**Input paths (run-triggered):**

- `input.run.*` - the completed run (`.id`, `.type`, `.state` [terminal: FINISHED, FAILED, CANCELED, DISCARDED, STOPPED, SKIPPED], `.branch`, `.commit.*`, `.changes[]`, `.creator_session.*`, etc.)
- `input.stack.*` - stack associated with the completed run
- `input.stacks[]` - candidate stacks for triggering (each has all stack fields + `.queued_runs`)
- `input.workflow[]` - workflow run info (each: `.id`, `.stack_id`, `.state`, `.type`)

**Input paths (module-version-triggered):**

- `input.module.*` - the module with a new version
- `input.stacks[]` - candidate stacks for triggering

**Rules:** `stacks` (set of stack IDs to trigger), `modules` (set of module IDs to trigger)

**Example patterns:**

```rego
package spacelift

# Trigger all dependent stacks when a run finishes successfully
stacks[stack.id] {
    input.run.state == "FINISHED"
    input.run.type == "TRACKED"
    stack := input.stacks[_]
}

# Only trigger stacks with no queued runs
stacks[stack.id] {
    input.run.state == "FINISHED"
    stack := input.stacks[_]
    stack.queued_runs == 0
}

# Trigger stacks in the same space
stacks[stack.id] {
    input.run.state == "FINISHED"
    stack := input.stacks[_]
    stack.space.id == input.stack.space.id
}
```

---

## Common Stack Fields (used across many policy types)

- `input.stack.id` - stack identifier
- `input.stack.name` - display name
- `input.stack.branch` - tracked git branch
- `input.stack.repository` - repository name
- `input.stack.project_root` - project root directory
- `input.stack.namespace` - stack namespace
- `input.stack.state` - current stack state
- `input.stack.administrative` - whether administrative
- `input.stack.autodeploy` - whether autodeploy is enabled
- `input.stack.labels[]` - stack labels (may be null)
- `input.stack.contexts[]` - attached context slugs
- `input.stack.locked_by` - user who locked it (nullable)
- `input.stack.space.id` - space ID
- `input.stack.space.name` - space name
- `input.stack.space.labels[]` - space labels
- `input.stack.worker_pool.id` - worker pool ID (nullable)
- `input.stack.worker_pool.public` - whether public pool
- `input.stack.worker_pool.labels[]` - worker pool labels
- `input.stack.terraform_version` - Terraform version (nullable)
- `input.stack.terraform_workflow_tool` - workflow tool (nullable)
- `input.stack.tracked_commit.*` - currently tracked commit (nullable)
- `input.stack.additional_project_globs[]` - additional project globs

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
- `input.module.current_version` - current version string (nullable)
- `input.module.space.*` - space info
- `input.module.worker_pool.*` - worker pool info
