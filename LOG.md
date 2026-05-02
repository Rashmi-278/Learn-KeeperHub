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

### Open / next

- Verify the `[needs hands-on]` items in `FEEDBACK.md` with a real run:
  - `list_workflows` / `list_integrations` against the live org
  - Behavior of `update_workflow` with partial node arrays (merge vs replace?)
  - Whether `execute_workflow` honors `enabled` state
  - Whether `delete_workflow` with `force: true` cascades into in-flight executions
- Decide whether to install the actual Claude Code plugin (separate from the raw MCP add) so `/keeperhub:*` slash commands resolve.
- Confirm the workflow reference syntax by inspecting a real workflow via `get_workflow`.
