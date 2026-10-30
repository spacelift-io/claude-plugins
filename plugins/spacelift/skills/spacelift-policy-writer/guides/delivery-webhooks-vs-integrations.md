# NOTIFICATION delivery: webhooks, Slack, inbox, pull requests

Notification policies are not attached to stacks. Every NOTIFICATION policy in the notification's space, or in a parent space it inherits from, evaluates each notification, and their deliveries add up.

## Rules

Each rule is a set of objects. One object is one delivery.

| Rule | Object fields | Delivers to |
|---|---|---|
| `webhook` | `endpoint_id` (required), `payload`, `method`, `headers` | A webhook endpoint set up in Spacelift |
| `slack` | `channel_id` (required), `message`, `mention_users`, `mention_groups`, `thread_key` | A channel of the account's Slack integration |
| `inbox` | `title`, `body`, `severity` (`INFO`, `WARNING`, `ERROR`) | The Spacelift notification inbox |
| `pull_request` | one of `id`, `branch`, `commit`; `body`, `deduplication_key`, `truncate_body` | A comment on a pull request |

Each target takes at most 10 deliveries per notification. The rest are dropped and an inbox error says so. Identical deliveries from one policy go out once.

## Events the policy reads (exactly one present per evaluation)

- `input.run_updated.*` - run state changes: `.state`, `.run.*` (incl. `.run.type`, `.run.flags[]`), `.stack.*`, `.username` (nullable), `.note`, `.urls.run`, `.timing[]`, `.policy_receipts[]`, `.plan_policy_decision.deny[]` / `.warn[]`
- `input.module_version.*` - `.module.*`, `.version.*` (`.id`, `.number`, `.state`, `.latest`, `.commit`, `.test_runs`)
- `input.internal_error.*` - `.severity`, `.message`, `.error`
- `input.worker_usage.*` - worker usage against the contracted limit: `.severity`, `.message`, `.limit_ratio`, `.burst_ratio`, ...

Always available: `input.account.name` and `input.webhook_endpoints[]` (each: `.id`, `.labels[]`).

Internal errors reach the inbox even when no policy routes them.

## Webhooks - `endpoint_id` from `input.webhook_endpoints[]`

`endpoint_id` is the endpoint's slug, the value of `input.webhook_endpoints[].id`. That list holds the endpoints in the policy's space and the spaces it inherits from. An `endpoint_id` that matches none of them is skipped with an inbox error, and a disabled endpoint is skipped. Without `payload`, Spacelift sends its default payload for the event. `method` defaults to `POST` (`PUT`, `PATCH` and `DELETE` also work), and `headers` are added to the request.

```rego
package spacelift

import future.keywords.contains
import future.keywords.if
import future.keywords.in

webhook contains {"endpoint_id": endpoint.id} if {
    input.run_updated.state == "FAILED"
    some endpoint in input.webhook_endpoints
    "ops-alerts" in endpoint.labels
}
```

## Slack - `channel_id` of the account's Slack integration

The account needs a Slack integration. Without one, `slack` deliveries are dropped and an inbox error says so. `channel_id` is the channel ID shown at the bottom of the channel's About section, not the channel name. Without `message`, Spacelift sends its default message, which `mention_users` and `mention_groups` add mentions to. Deliveries with the same `thread_key` go to one Slack thread.

```rego
package spacelift

import future.keywords.contains
import future.keywords.if

slack contains {"channel_id": "C0123456789", "message": msg} if {
    input.run_updated.state == "FAILED"
    input.run_updated.run.type == "TRACKED"
    msg := sprintf("Run %s on stack %s failed: %s", [
        input.run_updated.run.id,
        input.run_updated.stack.name,
        input.run_updated.urls.run,
    ])
}
```

## Inbox and pull request comments

```rego
package spacelift

import future.keywords.contains
import future.keywords.if

inbox contains {"title": "Module version failed", "body": input.module_version.version.number, "severity": "ERROR"} if {
    input.module_version.version.state == "FAILED"
}

pull_request contains {"id": input.run_updated.run.commit.pull_request_id, "body": "Plan finished, review it in Spacelift"} if {
    input.run_updated.state == "FINISHED"
    input.run_updated.run.type == "PROPOSED"
    input.run_updated.run.commit.pull_request_id != null
}
```

A `pull_request` delivery with none of `id`, `branch` or `commit` is skipped with an inbox error.
