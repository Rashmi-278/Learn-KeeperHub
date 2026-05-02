# KeeperHub Learning Log

Running log of what we did, what worked, and what tripped us up while wiring up KeeperHub. Newest entries at the bottom.

---

## Session 1 — 2026-05-02

### Goal
Genuinely understand KeeperHub well enough to (a) write developer docs for agents and (b) capture honest builder feedback.

### What we did

1. **Read the public docs end-to-end.** Pulled the four entry points the user shared:
   - `docs.keeperhub.com/ai-tools` (MCP / AI tools)
   - `docs.keeperhub.com/api`
   - `docs.keeperhub.com/cli`
   - `app.keeperhub.com` (platform — not fetched, just referenced)

2. **Built a mental model.** KeeperHub = execution + reliability layer for onchain AI agents. Three primitives: triggers, actions, conditions. Three surfaces: REST API, MCP server, `kh` CLI — all hitting the same backend. Auth: org-scoped `kh_` keys for agents; `wfb_` user keys only fire webhooks.

3. **Wrote `AGENTS.md`** — developer-facing doc covering the mental model, the three surfaces, API key creation, MCP connection commands, all 19 MCP tools grouped by purpose, the safe authoring order (`list_action_schemas` → `get_plugin` → `validate_plugin_config` → `create_workflow` → `execute_workflow` → poll), agentic wallet options, and a minimal end-to-end agent loop.

4. **Wrote `FEEDBACK.md`** — honest builder feedback in the four requested categories (UX friction, repro bugs, doc gaps, feature requests). Bug section deliberately marked `[needs hands-on]` rather than fabricated.

5. **Connected the MCP server.**
   ```
   claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp
   ```
   Wrote to `/home/torch/.claude.json`. Then `/mcp` in Claude Code → "Authentication successful. Connected to keeperhub." OAuth 2.1 path; no API key needed for this interactive session.

### Bumps & blockers

- **404: `docs.keeperhub.com/ai-tools/mcp`.** The natural URL for the MCP reference doesn't resolve. Real page lives at `…/mcp-server`. Inbound links in the AI Tools overview are misleading.
- **404: `docs.keeperhub.com/ai-tools/agentic-wallets`.** Four wallet providers are named (x402, KeeperHub agentic wallet, agentcash, Coinbase) with no page explaining when to pick which.
- **404: `docs.keeperhub.com/ai-tools/claude-code`.** No canonical doc for the plugin's slash commands or what `/keeperhub:login` actually does.
- **`/keeperhub:login` ran in the shell, not Claude Code.** User typed it at the bash prompt → `bash: /keeperhub:login: No such file or directory`. It's a Claude Code slash command, not a CLI binary. Easy to misread from the docs given they don't show the surrounding context.
- **`/keeperhub:login` also reported "Unknown command" inside Claude Code.** Likely because the Claude Code plugin wasn't installed — only the raw MCP server was added via `claude mcp add`. The plugin and the MCP server are separate installs; the docs conflate them.
- **`kh_` vs `wfb_` ambiguity.** Reference table buried; new builder grabbing the first key they see could end up with a `wfb_` key that silently won't work for the API or MCP.
- **API key creation steps disagree across pages.** One says "avatar → API Keys", another says "Settings → API Keys". Trivial fix; real friction.
- **Step-to-step reference syntax not specified anywhere obvious.** Workflows pass data between nodes "through built-in reference syntax" but the literal shape (`{{steps.foo.output}}`? JSONPath?) isn't shown.
- **Rate limits stated (100/min) but error shape isn't.** No HTTP status, no `Retry-After` semantics documented.

### Resolved this session

- **"Do I need an API key?"** No — OAuth covers this interactive Claude Code session. API key is needed for headless/CI, direct REST calls outside MCP, or shared deployed agents.

### Session 1.5 — live MCP exploration

Connected via `/mcp` (OAuth) and ran four discovery calls.

**Org state.**
- `list_workflows` → `[]` (empty org)
- `list_integrations` → `[]` (no creds wired)

**Marketplace.** `search_templates` → **85 templates**, heavily DeFi-flavored. Coverage:
- Lending health / liquidation guards: Aave v3 (multiple flavors incl. cross-chain ETH+Base), Compound V3, Ajna, Morpho, Spark
- Liquid staking: Lido (stETH/wstETH), Rocket Pool, Ethena (USDe/sUSDe)
- DEX / LP: Uniswap V3, Curve, Aerodrome, CoW Swap, Pendle
- Yield vaults: Yearn V3, Sky savings, Spark sDAI
- Oracles: Chainlink, Chronicle (freshness, depeg, multi-asset dashboards)
- Safe multisig watchers: owner change, threshold change, module install, guard change, transaction monitor with AI risk assessment
- Onchain operational: ESM (emergency shutdown module) listeners, salary distribution, contract interaction tester
- Canonical "hello world" candidates: **Wallet ETH Balance Watcher** (Sepolia, threshold notification), **Wallet ETH Filler** (Sepolia, auto-topup), **Treasury Balance Watcher** (Safe ETH+USDC + Discord)

**Action surface.** `list_action_schemas` → **396 actions** across 33 categories.
- 5 generic primitives: `Collect`, `Condition`, `Database Query`, `For Each`, `HTTP Request`
- Protocol kits (per-namespace): aave-v3, aave-v4, aerodrome, ajna, chainlink, chronicle, compound, cowswap, curve, ethena, lido, morpho, pendle, rocket-pool, safe, sky, spark, uniswap, yearn, wrapped
- Comms: discord, slack, telegram, sendgrid, webhook
- Dev/escape hatches: code, math, web3

**Triggers.** 5 types: `Block`, `Event`, `Manual`, `Schedule`, `Webhook`.

**Chains.** 21: Ethereum (mainnet/Sepolia), Base (mainnet/Sepolia), Arbitrum One/Sepolia, Polygon/Amoy, BNB Chain (mainnet/testnet), Avalanche/Fuji, Solana (mainnet/Devnet — listed twice in the response, minor bug), 0G + 0G Galileo, Plasma + Plasma Testnet, Tempo + Tempo Testnet.

**Reference syntax — confirmed.** Pattern: `{{@nodeId:Label.field}}`. Examples: `{{@check-balance:Check Balance.balance}}`, `{{@trigger:Trigger.body.amount}}`, `{{@__system:System.unixTimestamp}}`. Resolved at runtime before each step. **This was the #1 doc gap in FEEDBACK.md — now resolved (for us; should still ship to public docs).**

### Bumps this round

- **Two MCP responses overflowed Claude Code's tool-output cap.** `search_templates` (no args) returned **797k chars** for 85 templates; `list_action_schemas` returned **365k chars**. Both got auto-saved to disk and required `jq` to consume. This is a real DX problem for any agent building against this MCP server — burning context just to enumerate what's available.
- **`Solana Devnet` appears twice** in the chains list (once with capital D, once apparently identical). Minor, but a dedupe bug in the schema response.

### Session 2 — REST probe (real evidence, not speculation)

Sourced `KH_API_KEY` from `.env` and curl'd the REST API directly. The key turned out to be `wfb_` prefix (user-scope), not `kh_` — which is itself the most teachable bug here. We probed anyway because some surprises are scope-independent.

**Auth + ambiguity (the worst finding).** `GET /workflows` returns HTTP 200 `[]` for:
- valid `wfb_` key
- bogus `kh_obviouslyfake` bearer
- **no `Authorization` header at all**

Three different "auth" states, identical empty success response. A new builder mistypes their key, sees no errors, and concludes their org is empty. This is silent failure of the worst kind.

**Documented response envelope is wrong.** Docs claim `{"data": {...}}` / `{"error": {"code", "message"}}`. Reality:
- Success: bare array (`[]` from `/workflows`, `[{...}, ...]` from `/chains`) — no `data` wrapper
- 401: `{"error":"Unauthorized"}` (flat string)
- 404 (resource): `{"error":"Workflow not found"}` (flat string)
- 404 (route): `<!DOCTYPE html>...` Next.js error page

Agents parsing JSON will crash on route 404s. Error `code` enums don't exist.

**Documented endpoints that don't exist.** All return HTML 404:
- `/api/executions` — the documented executions resource
- `/api/runs`, `/api/workflow-runs` — common alternates
- `/api/v1/workflows`
- `/api/analytics`
- `/api/execute` — the documented "direct execution" endpoint

**`POST /api/workflows` → 405 Method Not Allowed.** REST does not expose workflow creation at the documented path. Creation appears to be MCP-only (or via an undocumented internal route the dashboard uses).

**No rate-limit headers anywhere.** 21+ rapid requests in a tight loop, every one HTTP 200, zero `X-RateLimit-*` or `Retry-After`. The documented "100 req/min" limit may exist but is unobservable to clients — they have to guess when to back off.

**Scope wall confirmed for `wfb_`:** `/integrations`, `/projects`, `/tags`, `/api-keys`, `/organizations`, `/user` all return 401. `/workflows`, `/workflows/{id}`, `/chains` are reachable.

**`/chains` works for any scope** and returns full metadata (chainId, RPC type, explorer URLs, testnet flag).

### Bumps this round

- The `.env` had `wfb_` not `kh_`. The platform sells this as a documented restriction, but the *cost* of getting it wrong is a silent empty list, not an error — that's the bug, not the user's typo.
- Hung curl loop on rapid-fire `/workflows` requests (21st req hung past 10s timeout). Could be coincidence; could be a soft throttle that hangs instead of returning 429. Worth re-testing.
- `pkill` was needed to unstick the hung curl before the second probe batch.

### Session 3 — get_plugin / get_template / tools_documentation deep-dive

Used the OAuth-MCP path (no kh_ key needed for MCP) to introspect three meta tools and the canonical hello-world template. The most important findings of the entire engagement.

**Live MCP tool count: 30 (not 19).** Public docs claim 19 tools including `validate_plugin_config`. Live server has 30 (after also catching `search_workflows` which I missed earlier) and **does not include `validate_plugin_config`**. The "safe authoring order" in AGENTS.md was wrong — corrected to drop the validate step and add `get_plugin` as the canonical schema source.

**`get_plugin` is the single most important tool, and it's not in the official authoring guide.** Its `tips` array contains schema rules that exist nowhere else: chain-ID format, Condition operator symbols, `leftOperand`/`rightOperand` field names, Database Query templating, `tokenConfig` shape, edge `sourceHandle`-only rule, the `__system` namespace, the `triggeredAt` field. Every one of these is a landmine that fails validation if you guess.

**`tools_documentation` advertises a 14-tool surface; the live server has 30.** The MCP server's own self-doc misses the marketplace tools, the direct-execution family, `get_plugin` itself, and 18 of 21 chains. Bootstrapping from `tools_documentation` gives an agent less than half the platform.

**`list_workflow` and `list_workflows` are semantic opposites, not variants.** Plural enumerates org workflows (read). Singular publishes to the marketplace (write). Naming-collision footgun.

**`get_template("qf8nxbxhdsqie2r3u1pb2")` — the canonical "Wallet ETH Balance Watcher" — is broken in four ways:**
- Discord-labeled node with `actionType: "slack/send-message"`
- `network: "sepolia"` instead of the chain-ID string
- Edge with `targetHandle: null` (forbidden by tips)
- Condition node with both legacy `condition` string and structured `conditionConfig`

**A second reference dialect exists and is fully undocumented.** `{{env.VAR_NAME}}` (e.g. `{{env.KH_WALLET_ADDRESS}}`) is in featured templates but absent from public docs, `templateSyntax`, `tips`, and `tools_documentation`. Discoverable only by reading templates.

### Bumps this round

- The KeeperHub MCP server **disconnected** mid-session (system reminder confirms `mcp__keeperhub__*` tools are no longer available). Cause unknown — could be an OAuth token TTL hit (1h access token), could be a server-side restart. Affects nothing already captured but blocks further live MCP work in this session until reconnected via `/mcp`.

### Open / next

- Verify the `[needs hands-on]` items in `FEEDBACK.md` with a real run:
  - `list_workflows` / `list_integrations` against the live org
  - Behavior of `update_workflow` with partial node arrays (merge vs replace?)
  - Whether `execute_workflow` honors `enabled` state
  - Whether `delete_workflow` with `force: true` cascades into in-flight executions
- Decide whether to install the actual Claude Code plugin (separate from the raw MCP add) so `/keeperhub:*` slash commands resolve.
- Confirm the workflow reference syntax by inspecting a real workflow via `get_workflow`.
