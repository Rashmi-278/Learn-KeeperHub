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

### MCP tools (verified live, 2026-05-02)

The public docs say 19 tools. The live server exposes **29**. Grouped:

- **Workflows** — `list_workflows`, `list_workflow` (singular variant, behavior unclear), `get_workflow`, `create_workflow`, `update_workflow`, `delete_workflow`
- **Marketplace listing** — `get_workflow_listing`, `update_workflow_listing`, `unlist_workflow`
- **Execution** — `execute_workflow`, `call_workflow`, `get_execution_status`, `get_execution_logs`
- **Direct execution** (no workflow needed) — `execute_contract_call`, `execute_protocol_action`, `execute_transfer`, `execute_check_and_execute`, `get_direct_execution_status`
- **AI authoring** — `ai_generate_workflow`
- **Discovery** — `list_action_schemas`, `search_plugins`, `search_protocol_actions`, `get_plugin`, `get_template`
- **Templates** — `search_templates`, `deploy_template`
- **Integrations** — `list_integrations`, `get_wallet_integration`
- **Meta** — `tools_documentation`

There is **no `validate_plugin_config` tool** despite the docs claiming one. The closest substitute is reading `get_plugin` and matching field-by-field before calling `create_workflow`.

### Authoring pattern

When building a workflow programmatically, the safe order is:

1. `list_action_schemas` (or `search_protocol_actions` for DeFi) — find the right `actionType`
2. `get_plugin(pluginType)` — read the literal `requiredFields` / `optionalFields` and consume the `tips` array (it contains landmines that aren't documented anywhere else)
3. Build nodes and edges by hand; match field names exactly
4. `create_workflow` — server-side validation surfaces remaining errors
5. `execute_workflow` → poll `get_execution_status` → `get_execution_logs` on failure

### Landmines to know before authoring

These come from the live `get_plugin` response and are not in the public docs:

- **`network` is a chain ID string**, not a name. `"1"` for Ethereum mainnet, `"11155111"` for Sepolia, `"8453"` for Base. Passing `"Ethereum"` will fail validation. (`ai_generate_workflow` itself gets this wrong.)
- **`actionType` must match exactly.** `"web3/check-balance"` works; `"Get Wallet Balance"` does not.
- **Condition operators are exact symbols.** `===`, `!==`, `<`, `>`, `<=`, `>=` — not `equals`, `less_than`, etc. Each rule and group needs a unique `id` field (nanoid/UUID).
- **Condition rule fields are `leftOperand` and `rightOperand`** — not `field`/`value`.
- **Database Query inlines refs into SQL directly.** `SELECT * FROM t WHERE id = '{{@step:Step.id}}'`. Do **not** use `$1`/`$2` placeholders with a separate `dbParams` array — the UI ignores that format.
- **`tokenConfig` is a JSON-stringified object** with shape `{"mode":"custom","customToken":{"address":"0x...","symbol":"USDC"}}` — not a flat `{address, symbol, decimals}`.
- **Edges:** use `sourceHandle` only. Set it to `'true'`/`'false'` on Condition nodes and `'loop'`/`'done'` on For Each. **Never** use `targetHandle`.
- **Built-in time variables** live under the `__system` namespace: `{{@__system:System.unixTimestamp}}` (seconds, matches `block.timestamp`), `{{@__system:System.unixTimestampMs}}`, `{{@__system:System.isoTimestamp}}`.
- **Every trigger emits `triggeredAt`** as an ISO string. Reference as `{{@triggerId:Label.data.triggeredAt}}`.

### Wallets

KeeperHub wallets are **Para MPC** — non-custodial, keys split between the user and Para, neither can sign alone. `get_wallet_integration` returns the integration ID you bind to write actions.

Proxy contracts (EIP-1967, EIP-1822, Diamond/EIP-2535) are auto-detected and the implementation ABI is fetched. Verified contracts get auto-ABI from the block explorer; unverified contracts require manual ABI.

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
