# Spacelift AI Plugins

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) maintained by [Spacelift](https://spacelift.io). It distributes skills, agents, and commands for working with the Spacelift platform and the infrastructure it manages (OpenTofu / Terraform / Terragrunt / Pulumi).

## Installing

Inside Claude Code:

```text
/plugin marketplace add spacelift-io/ai-plugins
/plugin install spacelift@spacelift
```

After installation, the bundled skills are auto-discovered by Claude Code. The `spacelift` skill activates on prompts that mention Spacelift concepts (stacks, runs, policies, spaces, intent, etc.).

## Plugins

| Plugin | Description |
|---|---|
| [`spacelift`](./plugins/spacelift) | Procedural guide and references for the [`spacelift-local`](https://github.com/spacelift-io/spacelift-mcp) MCP server - manage stacks, runs, policies, spaces, integrations, and the lifecycle of cloud resources through Intent. |

## Repository layout

```
.
├── .claude-plugin/
│   └── marketplace.json       # Marketplace manifest (lists every plugin in this repo)
├── plugins/
│   └── spacelift/
│       ├── .claude-plugin/
│       │   └── plugin.json    # Plugin manifest
│       └── skills/
│           └── spacelift/     # Auto-loaded as the `spacelift` skill
│               ├── SKILL.md
│               ├── references/
│               └── examples/
├── LICENSE
└── README.md
```

## Contributing

To add a new plugin:

1. Create a directory under `plugins/<name>/` with a `.claude-plugin/plugin.json`.
2. Add skills under `plugins/<name>/skills/<skill-name>/SKILL.md`, agents under `plugins/<name>/agents/`, commands under `plugins/<name>/commands/`, and so on.
3. Register the new plugin in `.claude-plugin/marketplace.json`.

## License

[MIT](./LICENSE)
