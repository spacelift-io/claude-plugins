# NOTIFICATION delivery: webhooks vs named integrations

## Rules

| Rule | Shape | Purpose |
|---|---|---|
| `send` | bool | Whether to send the notification. |
| `channels` | set of strings | Where it goes: webhook endpoint IDs or integration channel IDs. |
| `message` | string | Custom message content. |
| `subject` | string | Custom subject/title. |

## Events the policy reads (exactly one present per evaluation)

- `input.run_updated.*` - run state changes: `.run.*`, `.stack.*`, `.state`, `.username` (nullable), `.note`, `.urls.run`, `.timing`, `.policy_receipts[]`, `.plan_policy_decision.deny[]` / `.warn[]`
- `input.internal_error.*` - `.severity`, `.message`, `.error`
- `input.module_version.*` - `.module.*`, `.version.*` (`.id`, `.number`, `.state`, `.latest`, `.commit.*`)

Always available: `input.account.name` and `input.webhook_endpoints[]` (each: `.id`, `.labels[]`).

## Generic webhooks - route via `input.webhook_endpoints[]`, matched by `.id` or `.labels[]`

```rego
channels[endpoint.id] {
    send
    endpoint := input.webhook_endpoints[_]
    endpoint.labels[_] == "ops-alerts"
}
```

## Named integrations (e.g. Slack) - put the channel ID directly in `channels`

```rego
send {
    input.run_updated.state == "FAILED"
    input.run_updated.run.type == "TRACKED"
}

channels[channel_id] {
    send
    channel_id := "slack-channel-id"  # Slack channel ID, not the channel name
}
```

## Custom message

```rego
message := sprintf("Run %s on stack %s failed", [
    input.run_updated.run.id,
    input.run_updated.stack.name,
])
```
