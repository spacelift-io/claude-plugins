# NOTIFICATION Delivery: Webhooks vs Named Integrations

## Rules

- `send` (bool) — whether to send the notification.
- `channels` (set of strings) — where it goes: webhook endpoint IDs or integration channel IDs.
- `message` (string) — custom message content.
- `subject` (string) — custom subject/title.

## Events the Policy Reads (exactly one present per evaluation)

- `input.run_updated.*` — run state changes: `.run.*`, `.stack.*`, `.state`, `.username` (nullable), `.note`, `.urls.run`, `.timing`, `.policy_receipts[]`, `.plan_policy_decision.deny[]` / `.warn[]`
- `input.internal_error.*` — `.severity`, `.message`, `.error`
- `input.module_version.*` — `.module.*`, `.version.*` (`.id`, `.number`, `.state`, `.latest`, `.commit.*`)

Always available: `input.account.name` and `input.webhook_endpoints[]` (each: `.id`, `.labels[]`).

## Generic Webhooks — route via `input.webhook_endpoints[]`, matched by `.id` or `.labels[]`

```rego
channels[endpoint.id] {
    send
    endpoint := input.webhook_endpoints[_]
    endpoint.labels[_] == "ops-alerts"
}
```

## Named Integrations (e.g. Slack) — put the channel ID directly in `channels`

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

## Custom Message

```rego
message := sprintf("Run %s on stack %s failed", [
    input.run_updated.run.id,
    input.run_updated.stack.name,
])
```
