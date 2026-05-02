# Build a Safe Treasury Guardian by Talking to KeeperHub

*A working tour of the KeeperHub agent surface — written from a real session, with real bumps left in.*

---

## Why this article exists

If you're an AI agent (or someone shipping one) that needs to do things onchain, the boring problems eat your week: gas estimation, nonce sequencing, retry on transient failures, key custody, RPC flakiness, idempotency on retries. KeeperHub bills itself as the *execution and reliability layer for AI agents operating onchain* — meaning it owns those boring problems so your agent only has to own intent.

This article is a builder's tour. We'll wire an agent to KeeperHub, ask it (in English) to author a workflow that watches a Safe multisig for security-critical changes, deploy it, and watch it run. Along the way we'll hit the real surprises a first-time builder hits — they're left in, because the value of this piece is honesty, not marketing.

If you want a one-liner: **KeeperHub turns "watch this onchain thing and tell me when X happens" from a weekend of code into a sentence.**

---

## The mental model in 90 seconds

Three primitives compose every workflow:

- **Triggers** — what starts the workflow. Five types: `Manual`, `Schedule` (cron), `Webhook`, `Block` (every N blocks), `Event` (a specific log topic on a specific contract).
- **Actions** — what the workflow does. ~400 of them at last count: protocol-specific (Aave, Lido, Uniswap, Safe, Chainlink, Morpho, Pendle, …), generic (`HTTP Request`, `Database Query`, `Condition`, `For Each`), and comms (Discord, Slack, Telegram, Sendgrid, Webhook).
- **Conditions** — branches on prior step output.

Steps reference each other with one syntax: `{{@nodeId:Label.field}}`. So a balance read in node `check-balance` labeled `Check Balance` is consumable downstream as `{{@check-balance:Check Balance.balance}}`. There's a `__system` namespace too — `{{@__system:System.unixTimestamp}}` is the current time at execution.

That's it. Triggers fire, actions run, conditions branch, references thread data through. The hard parts — gas, retries, custody — happen below the line.

---

## Three surfaces, one backend

KeeperHub exposes the same backend three ways:

| Surface | When to reach for it | Auth |
|---|---|---|
| **REST API** (`https://app.keeperhub.com/api`) | Server-to-server, your own backend | `Authorization: Bearer kh_…` |
| **MCP server** (`https://app.keeperhub.com/mcp`) | Any MCP-aware agent (Claude, Cursor, custom) | OAuth 2.1 (browser) **or** `kh_…` header |
| **CLI** (`kh`) | Scripts, CI, local dev | `kh auth login` or `KH_API_KEY` env |

For an AI agent, MCP is the right surface — your agent gets typed tools and stable schemas instead of curl-and-pray.

---

## The first bump: two API key shapes that look interchangeable but aren't

Open the dashboard, click "API Keys", and you see a "User" tab and an "Organisation" tab. Both produce a string starting with `kh_…` or `wfb_…`. Both copy with the same button. Both feel identical.

They are not.

- `kh_…` = **organization-scoped**. This is the one your agent needs. Works against the REST API, the MCP server, and the CLI.
- `wfb_…` = **user-scoped, webhook-only**. Fires webhook *triggers* on workflows you own. Cannot list integrations, cannot create workflows, cannot do anything an agent needs.

The trap: if you grab a `wfb_` key by accident, almost everything *appears* to work. `GET /api/workflows` returns `[]` (HTTP 200). No error. You assume your org is empty and start building. In fact you're locked out.

> **Honest aside.** I hit this exact trap in the session this article is written from. The fix is one click in the dashboard ("Organisation" tab → Create New Key) but the failure mode is silent and I lost real time to it. There's a feedback note in the repo asking the team to either error visibly or rename the prefixes.

So: **make sure your key starts with `kh_`.** Copy it once — it's shown once — and stash it.

```bash
echo 'KH_API_KEY=kh_your_key_here' >> .env
```

---

## Connecting an agent (Claude Code, here)

I'm using Claude Code. One command:

```bash
claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp
```

Then `/mcp` inside Claude Code authenticates via OAuth 2.1 — a browser tab opens, you approve, the session gets a token (1h access, 30d refresh). For headless contexts (CI, deployed agents) skip OAuth and pass the key:

```bash
claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp \
  --header "Authorization: Bearer kh_..."
```

You now have 19 MCP tools. The ones you'll use most:

- `list_action_schemas` — what's available to build with (triggers, actions, chains)
- `search_templates` — 80+ pre-built workflows you can clone
- `ai_generate_workflow` — natural language → workflow JSON
- `create_workflow`, `update_workflow`, `delete_workflow`
- `execute_workflow`, `get_execution_status`, `get_execution_logs`
- `list_integrations`, `get_wallet_integration` — credentials and wallets

---

## Checking what's already there before we build

Before generating anything, an agent should look around. Two MCP calls:

```
list_workflows()          → []
search_templates()        → 85 templates
```

Eighty-five templates is a lot. Skimming the list, the categories are:

- **Lending health & liquidation guards** — Aave V3 Health Factor Guardian, Compound V3 Liquidation Guard, Morpho Position Monitor, Spark SparkLend Reserve Position Monitor
- **Liquid staking** — Lido stETH Auto-Wrapper, Rocket Pool Auto-Stake, Ethena USDe/sUSDe Balance Monitor
- **DEX & LP** — Uniswap V3 LP Position Monitor, Curve Pool Watchers, Aerodrome veAERO Epoch Voter, CoW Swap order trackers, Pendle market expiry
- **Yield vaults** — Yearn V3 Auto-Depositor, Sky Savings Auto-Deposit, Spark sDAI tracker
- **Oracles** — Chainlink staleness monitors, Chronicle multi-oracle dashboards, stablecoin depeg alerts
- **Safe multisig watchers** — owner change, threshold change, module install, guard change, AI-assessed transaction monitor
- **Operational** — Treasury Balance Watcher, ESM (emergency shutdown module) listeners, salary distribution

> **Practical takeaway.** Before you author from scratch, run `search_templates` with a query close to your goal. There's a 30% chance someone already shipped it.

For this tour we'll author something small but real: **a Safe multisig guardian that pings Discord whenever an owner is added, the signature threshold drops, or a module is installed.** Those three events cover the most common Safe compromise vectors.

---

## Two ways to build it

### Path A — `ai_generate_workflow`

Plain English in:

```
ai_generate_workflow(
  prompt: "Watch a Safe multisig on Ethereum mainnet. Whenever an owner
           is added, the signature threshold is changed, or a module is
           enabled, send a Discord alert with the event details."
)
```

What you get back is *not* a finished workflow object. It's a **stream of operations**, newline-delimited JSON, ending in `{"type":"complete"}`:

```jsonc
{"type":"operation","operation":{"op":"setName","name":"Safe Multisig Monitor Workflow"}}
{"type":"operation","operation":{"op":"addNode","node":{"id":"trigger-monitor-events","type":"trigger","data":{"label":"Monitor Safe Events","config":{"triggerType":"Webhook"},...}}}}
{"type":"operation","operation":{"op":"addNode","node":{"id":"check-owners","type":"action","data":{"config":{"actionType":"safe/get-owners","network":"Ethereum","contractAddress":"Your safe multisig address"},...}}}}
// ... two more reads (safe/get-threshold, safe/get-modules-paginated)
// ... three discord/send-message nodes
// ... six addEdge ops fanning trigger → reads → discords
{"type":"complete"}
```

Caller has to apply these operations to build the workflow object — `create_workflow` doesn't take this stream directly. This isn't documented anywhere I could find, and it's the first place a real builder gets stuck. (The KeeperHub dashboard appears to consume the same stream when you author by chat in-app.)

**Three real problems with the generated workflow as-is.** I'm leaving these in because they're the kind of thing you'd actually catch in review:

1. **The trigger is `Webhook`, not `Event`.** The prompt asked the workflow to *watch* for owner/threshold/module changes — Safe emits events for all three (`AddedOwner`, `ChangedThreshold`, `EnabledModule`). The right primitive is the `Event` trigger watching the Safe contract. The generator picked `Webhook` instead, meaning the workflow only fires when *something else* tells it to. That's a regression from the user's intent.

2. **No state comparison.** The generated workflow polls owners, threshold, and modules in three parallel branches, then unconditionally fires three Discord messages. It would alert on *every* run, not on change. To do the job the prompt described, you need a `Database Query` to remember last-seen state and a `Condition` to compare. The generator didn't add either.

3. **`network` is set to the string `"Ethereum"`, but the action schema says it must be a chain ID** (e.g. `"1"` for mainnet). I confirmed this against `search_protocol_actions(protocol: "safe")`:

   ```
   safe/get-owners
     network: "string (chain ID)"
     contractAddress: "string (supports {{@nodeId:Label.field}} templates) - 0x..."
   ```

   The generated config wouldn't validate. `validate_plugin_config` would catch it — which is exactly why the recommended authoring order ends with that step before `create_workflow`.

So the honest pitch for `ai_generate_workflow` is: **it gives you a 70% workflow you have to fix.** That's still useful — typing out 14 nodes and 6 edges by hand is no fun — but the marketing one-liner ("describe intent, get a typed workflow") oversells it. Treat the output as a draft, not a deliverable.

### Path B — assemble by hand

For an agent that wants control, the safe order is:

1. `list_action_schemas(category: "triggers")` → confirm `Event` trigger exists
2. `search_plugins(category: "safe")` → find the Safe action namespace
3. `get_plugin("safe")` → read the parameter shape
4. `validate_plugin_config(...)` for each node before assembling
5. `create_workflow(name, nodes, edges, …)` once everything validates
6. `execute_workflow` (manual fire) → `get_execution_status` → `get_execution_logs`

Skip step 1–4 and you'll discover schema drift the slow way: `create_workflow` errors are precise but the round-trip is expensive.

---

## What goes wrong when you try this for real

Here is what actually happened during this session, written down so you can avoid the same hour.

**1. `wfb_` vs `kh_`.** Already covered. The first thing I tried — `GET /api/workflows` — returned `[]`. So did the same call with no auth header at all. Identical responses for valid-but-wrong-scope, fake, and missing keys. If you see an empty list, double-check your prefix before you double-check your code.

**2. Some documented REST endpoints don't exist.** Probing directly:

```
GET /api/executions       → 404 (HTML, not JSON)
GET /api/execute          → 404
GET /api/analytics        → 404
POST /api/workflows       → 405 Method Not Allowed
```

The MCP equivalents (`get_execution_status`, `execute_workflow`, `create_workflow`) work fine. So *the capability is there* — but the REST surface advertised in the docs has gaps. Until the REST routes are mounted, build agents on MCP, not curl.

**3. Error envelopes don't match the docs.** Public docs claim `{"error": {"code", "message"}}`. Reality on the wire:

```
401 → {"error":"Unauthorized"}            # flat string, no code
404 (resource) → {"error":"Workflow not found"}  # flat string, no code
404 (route) → <!DOCTYPE html>...           # full HTML
```

If you `JSON.parse` a route 404, you'll throw. If you switch on `response.error.code`, you'll always hit the default branch. Wrap your client accordingly.

**4. No rate-limit headers.** The docs say 100 req/min. The wire has no `X-RateLimit-*` or `Retry-After`. You can't back off proactively — only reactively, after a 429 you can't predict.

**5. The reference syntax wasn't in the public docs.** It's `{{@nodeId:Label.field}}` (with `__system` for built-ins). I only found this by introspecting `list_action_schemas`. If you've been guessing — stop, that's the format.

**6. Two MCP discovery calls overflow client tool-output buffers.** `search_templates` with no args returned 797k characters (85 templates with full node graphs). `list_action_schemas` returned 365k characters (396 actions). On Claude Code, both got auto-saved to disk and required `jq` to consume. Pass narrower filters (`category`, `query`) up front, or be ready to read from a file.

**7. The MCP server's own self-documentation is incomplete.** `tools_documentation` describes 14 tools and 3 chains. The live server actually exposes **30 tools** (`list_workflows`, `list_workflow`, `get_workflow`, `create_workflow`, `update_workflow`, `delete_workflow`, `search_workflows`, `get_workflow_listing`, `update_workflow_listing`, `unlist_workflow`, `execute_workflow`, `call_workflow`, `get_execution_status`, `get_execution_logs`, `execute_contract_call`, `execute_protocol_action`, `execute_transfer`, `execute_check_and_execute`, `get_direct_execution_status`, `ai_generate_workflow`, `list_action_schemas`, `search_plugins`, `search_protocol_actions`, `get_plugin`, `search_templates`, `get_template`, `deploy_template`, `list_integrations`, `get_wallet_integration`, `tools_documentation`) and supports 21 chains. Building from `tools_documentation` as ground truth means missing the marketplace surface, the entire direct-execution family, and the only tool that documents schema landmines (`get_plugin`).

**8. Two tools share a noun and do opposite things.** `list_workflows` enumerates the workflows in your org (read). `list_workflow` (singular) **publishes** a workflow to the marketplace catalog (write — sets `isListed=true`, assigns a public slug). An agent picking by name without reading descriptions will either silently no-op or unintentionally publish private work. Read the tool descriptions before you call.

**9. The featured "Wallet ETH Balance Watcher" template is broken.** When I called `get_template("qf8nxbxhdsqie2r3u1pb2")` on the canonical hello-world template — the one a new builder will inspect to learn the platform — it returned a workflow with four real defects:

- A node labeled "Send Discord Message" with description "Sends alert to configured Discord channel" and a `discordMessage` field has `actionType: "slack/send-message"`. Discord-on-the-tin, Slack-on-the-wire.
- `network: "sepolia"` — a name, not the chain-ID string the schema explicitly requires.
- An edge sets `targetHandle: null` despite the schema's own `tips` array saying "Do NOT use targetHandle."
- The Condition node carries both a deprecated `condition` string *and* a structured `conditionConfig` side by side. Migration drift, with no clarity on which wins at execution time.

Builders learn anti-patterns by example. Until featured templates are linted against the schema rules they advertise, this is the wrong place to start a tour.

**10. There are two reference syntaxes and only one is documented.** Step references use `{{@nodeId:Label.field}}` — covered in the public docs and in `get_plugin`'s `tips`. **Environment references use `{{env.VAR_NAME}}`** (e.g. `{{env.KH_WALLET_ADDRESS}}`, `{{env.ALERT_EMAIL}}`) — visible in featured templates, mentioned **nowhere** in the public docs, the `templateSyntax` block, the `tips` array, or `tools_documentation`. A builder who copies a template runs into `{{env.…}}`, looks for the env config UI, finds nothing obvious, and either guesses or hard-codes. This is fixable with one paragraph in the docs.

These aren't deal-breakers. They're the kind of friction every platform has at this stage. The difference is whether the maintainers want them written down — and the KeeperHub team explicitly asked for honest feedback, which is why this article exists in this form.

---

## Running the workflow

Once `create_workflow` returns an ID, you flip it on:

```
update_workflow(id: "...", enabled: true)
```

For a Safe-event-triggered workflow, that's enough — it'll fire when the contract emits one of the watched events. To smoke-test before going live:

```
execute_workflow(id: "...")          → returns execution_id
get_execution_status(execution_id)   → "running" | "completed" | "failed"
get_execution_logs(execution_id)     → step-by-step trace, including tx hashes if any
```

If a step failed, the logs name the node and the error. Fix the schema, `update_workflow`, run again. The platform handles gas estimation, retry, and sequencing — you don't.

---

## What I'd do differently for production

- **Bind a wallet integration** before any write actions. `get_wallet_integration` returns the integration ID you reference in write nodes. Until that's wired, your workflow can read but not transact.
- **Add an idempotency key on `execute_workflow`.** Currently there isn't one. If your agent retries a manual fire on transient failure, you risk double-firing. (Filed as a feature request in the repo.)
- **Wrap the MCP error path.** Until the public error envelope stabilizes, treat any non-2xx as `error.message: <raw body>` and don't lean on a `code` field that isn't there.
- **Pin the chain.** 21 chains are supported including testnets. For first runs, use Base Sepolia or Ethereum Sepolia — the read paths cost nothing.

---

## What KeeperHub is actually good at

After a session of poking, the platform's edge is clear:

- **The action library is unusually deep.** 396 typed actions across 20+ DeFi protocols means most workflows are composition, not implementation.
- **The template marketplace is a real shortcut.** 85 production-shaped workflows is a lot — most of what an org wants on day one is already there.
- **`ai_generate_workflow` is the killer feature.** Plain-English authoring against a typed schema library is exactly the right shape for agents to consume, and it's the most differentiated thing in the box.
- **Reference syntax is simple and consistent.** Once you know `{{@nodeId:Label.field}}`, every workflow looks the same.

What needs the most love is the **edges** — error envelopes, REST route parity with MCP, key-prefix UX, the public docs page on reference syntax. All addressable. None block a real build.

---

## The 30-line version of this article

```
1.  Get a kh_ key (NOT wfb_) from app.keeperhub.com (Organisation tab).
2.  claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp
3.  /mcp  → OAuth.
4.  Call get_plugin first — its `tips` array has rules that exist
    nowhere else (chain ID format, Condition operator symbols,
    Database Query templating, edge sourceHandle constraints).
5.  search_templates(query: "...")  # before authoring, look here.
    But read the JSON before deploying — featured templates ship
    with real bugs (wrong actionType, missing chain ID, etc.).
6.  ai_generate_workflow(prompt: "...") returns a stream of ops, not
    a workflow. Apply the ops; expect to fix at least the network
    field (it picks "Ethereum" instead of "1").
7.  create_workflow(nodes, edges) — server-side validation surfaces
    remaining errors. There is no validate_plugin_config tool.
8.  update_workflow(enabled: true) → execute_workflow(id) → poll
    get_execution_status → get_execution_logs on failure.
9.  Step refs: {{@nodeId:Label.field}}. Env refs: {{env.VAR_NAME}}
    (the second one is undocumented; learn it from templates).
10. ai_generate_workflow doesn't add state-comparison logic. If your
    intent is "alert on change," wire a Database Query + Condition
    yourself.
```

That's the build loop. The rest is taste.

---

*Written 2026-05-02. Repo with full session log, feedback notes, and developer documentation: [Learn-KeeperHub](https://github.com/Rashmi-278/Learn-KeeperHub).*
