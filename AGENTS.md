# Building Agents on KeeperHub

KeeperHub is the **execution and reliability layer for AI agents operating onchain**. It runs visual workflows that watch chain state, send transactions, and dispatch alerts — handling gas, retries, sequencing, and wallet security so an agent doesn't have to.

This guide is for developers wiring an AI agent (Claude, custom, or otherwise) to KeeperHub.

## Mental model

Three primitives compose every workflow:

- **Triggers** — manual, scheduled, webhook, blockchain event, block interval
- **Actions** — Web3 call, HTTP, notification, conditional branch, math/aggregation
- **Conditions** — branching nodes that gate on prior step output

Steps reference upstream output via a built-in reference syntax, so a chain event can route into a Discord ping or a contract call without glue code.

## Three surfaces, one platform

| Surface | When to use | Auth |
|---|---|---|
| REST API (`https://app.keeperhub.com/api`) | Custom backends, server-to-server | `Authorization: Bearer kh_…` |
| MCP server (`https://app.keeperhub.com/mcp`) | Any MCP-aware agent (Claude, Cursor, custom) | OAuth 2.1 or `kh_…` header |
| CLI (`kh`) | Scripts, CI/CD, local dev | `kh auth login` or `KH_API_KEY` env |

All three hit the same backend. Pick by transport, not capability.

## API keys

Agents need an **organization-scoped** key (prefix `kh_`). User keys (`wfb_`) only fire webhook triggers and won't work for the API or MCP.

1. Open [app.keeperhub.com](https://app.keeperhub.com/) → avatar → **API Keys**
2. **Organisation** tab → **Create New Key**
3. Copy immediately — shown once

Header on every request:

```
Authorization: Bearer kh_your_key
```

**What `kh_` keys can't do:** mutate user profiles, provision/delete/export wallets, mint new API keys, or cross human-approval boundaries. Those require a session.

Rate limits: 100 req/min authed, 10 req/min anon.

Response shape: `{"data": {...}}` on success, `{"error": {"code", "message"}}` on failure.

## Connecting an agent via MCP (recommended)

The MCP server exposes 19 tools covering full workflow CRUD, execution, discovery, and templates.

### Claude Code

```
claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp
```

Browser-based OAuth 2.1 handles auth (1-hour access token, 30-day refresh). For headless use, pass the key directly:

```
claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp \
  --header "Authorization: Bearer kh_your_key"
```

Or use the **Claude Code plugin**, which installs the MCP server and runs `/keeperhub:login` for you.

### MCP tools at a glance

- **Workflows** — `list_workflows`, `get_workflow`, `create_workflow`, `update_workflow`, `delete_workflow`
- **Execution** — `execute_workflow`, `get_execution_status`
- **Logs** — `get_execution_logs` (includes tx hashes)
- **AI authoring** — `ai_generate_workflow` (natural-language → workflow)
- **Discovery** — `list_action_schemas`, `search_plugins`, `get_plugin`, `validate_plugin_config`
- **Templates** — `search_templates`, `deploy_template`
- **Integrations** — `list_integrations`, `get_wallet_integration`
- **Meta** — `tools_documentation`, `resources` (`keeperhub://workflows[/{id}]`)

### Authoring pattern

When building a workflow programmatically, the safe order is:

1. `list_action_schemas` — find the action types you need
2. `get_plugin` for any non-trivial action — read its parameter shape
3. `validate_plugin_config` on each action before assembling
4. `create_workflow` with nodes and edges
5. `execute_workflow` → poll `get_execution_status` → `get_execution_logs` on failure

Skipping schema discovery is the fastest way to ship an invalid workflow.

## REST API surface

Major resources (all under `/api`):

- `/workflows`, `/executions`, `/execute` (direct execution without a workflow)
- `/integrations`, `/projects`, `/tags`, `/chains`
- `/analytics`, `/organizations`, `/api-keys`
- `/user` (mostly session-only)

For any agent-facing automation, you'll live in `workflows`, `executions`, and `execute`.

## CLI

```
brew install keeperhub/tap/kh    # or: go install github.com/keeperhub/cli/cmd/kh@latest
kh auth login                    # interactive
export KH_API_KEY=kh_...         # CI/CD
```

Useful command groups: `workflows` (create/list/run/pause/go-live), `execute` (contract calls, transfers), `runs` (logs, status, cancel), `wallet`, `org`, `project`.

## Agentic wallets

KeeperHub supports four funding models so an agent can pay for its own runs:

- **x402** — HTTP 402 payment protocol
- **KeeperHub agentic wallet** — managed wallet provisioned per agent
- **agentcash**
- **Coinbase**

Use `get_wallet_integration` (MCP) or `/integrations` (API) to fetch the wallet ID needed for any write action.

## Building blocks for a real agent

A minimal "agent that runs onchain" loop:

1. **Authoring** — agent calls `ai_generate_workflow` *or* assembles nodes via `create_workflow`
2. **Funding** — bind a wallet integration via `get_wallet_integration`
3. **Activation** — `update_workflow` with `enabled: true` (or `kh workflows go-live`)
4. **Trigger** — schedule, webhook, or onchain event fires it; or call `execute_workflow` directly
5. **Observation** — `get_execution_status` + `get_execution_logs` feed back into the agent's next decision

The platform owns gas estimation, retry, sequencing, and key custody. The agent owns intent.

## References

- MCP / AI tools — https://docs.keeperhub.com/ai-tools
- API — https://docs.keeperhub.com/api
- CLI — https://docs.keeperhub.com/cli
- Platform — https://app.keeperhub.com/
