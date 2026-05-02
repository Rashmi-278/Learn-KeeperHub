# KeeperHub: Builder Feedback

Honest notes from a developer working through the docs to wire an agent against KeeperHub. Organized into UX friction, bugs, doc gaps, and feature requests.

> **Scope note.** Most of what's below comes from reading the public docs end-to-end and trying to assemble a working mental model for an agent integration. Items that require actually running the platform (real UI flows, MCP server connection, on-chain execution) are flagged `[needs hands-on]` so we don't ship invented complaints.

---

## 1. Documentation gaps (the biggest blocker right now)

These are concrete URLs that should work and didn't, or content that's referenced but not findable from the obvious entry points.

- **`docs.keeperhub.com/ai-tools/mcp` → 404.** The AI Tools overview page strongly implies a dedicated MCP reference exists, but the most natural URL for it doesn't resolve. The actual page lives at `…/mcp-server`. Either alias both or fix the inbound links.
- **`docs.keeperhub.com/ai-tools/agentic-wallets` → 404.** Agentic wallets are listed as one of three first-class AI tools and four providers are named (x402, KeeperHub agentic wallet, agentcash, Coinbase) — but there's no page explaining when to pick which, how funding flows work, or what the agent has to do to use them. This is the most underdocumented part of the most differentiating feature.
- **`docs.keeperhub.com/ai-tools/claude-code` → 404.** The plugin is mentioned everywhere but there's no canonical page documenting which slash commands it adds, what `/keeperhub:login` actually does (OAuth? device code? key paste?), what skills it ships, and how it interacts with an existing MCP install.
- **API key creation steps disagree across pages.** One page says "avatar menu → API Keys → Organisation tab"; another says "Settings → API Keys → Organisation tab." Pick one; it's a 30-second fix that prevents a "wait, where?" moment on the very first step.
- **`kh_` vs `wfb_` distinction is buried.** A new builder grabs the first key they see, and `wfb_` keys silently won't work for the API or MCP. Surface this *at* the API Keys creation UI, not just in a reference table.
- **MCP authoring order isn't called out.** `create_workflow` requires the right node/edge shape; `list_action_schemas` and `validate_plugin_config` exist precisely to make that tractable. The docs list all 19 tools but never say "call these in this order." A 6-line "happy path" sequence in the MCP page would save every first-time agent author a round of trial-and-error.
- **Reference syntax for step-to-step data flow is documented inside `list_action_schemas` but not in the public docs.** The actual pattern is `{{@nodeId:Label.field}}` (e.g. `{{@check-balance:Check Balance.balance}}`, `{{@trigger:Trigger.body.amount}}`, `{{@__system:System.unixTimestamp}}`). This is load-bearing for every multi-step workflow and should have its own page in the public docs — agents and humans both have to discover it by introspecting an MCP tool today.

- **Two MCP discovery calls overflow tool-output limits.** `search_templates` with no args returned 797k chars for 85 templates; `list_action_schemas` returned 365k chars for 396 actions. Both got auto-truncated and saved to disk, forcing `jq` to consume. Default behavior should be paginated/summary; full payload on opt-in.

- **`chains` array contains a duplicate.** `Solana Devnet` appears twice in the `list_action_schemas` response.
- **Rate limits are stated (100/min authed) but error shape isn't.** What HTTP status, what body, what `Retry-After` header? Agents need to know exactly how to back off.

## 2. UX / UI friction (from the developer-onboarding flow)

- **Three surfaces, one capability — but no decision matrix on the landing page.** A builder lands on the docs and has to read four pages before realizing the API, CLI, and MCP all hit the same backend. A single table at the top of the docs ("If you're doing X, use Y") would cut time-to-first-call dramatically.
- **OAuth vs API key for MCP isn't a clear choice.** Both are documented, but it's not obvious which to pick when. Suggested rule of thumb in the docs: "Interactive Claude Code → OAuth. Headless agent or CI → `kh_` header." Right now that decision is left to the reader.
- **`[needs hands-on]` Plugin install vs. manual MCP add.** Unclear whether running `/keeperhub:login` after installing the plugin *also* registers the MCP server, or whether you need both. A one-line confirmation in the plugin docs would resolve it.
- **`[needs hands-on]` First-run onboarding for an agent.** Unverified, but worth checking: when an agent calls `create_workflow` against a brand-new org with zero integrations, does the error message actually tell it to run `list_integrations` / `get_wallet_integration` first, or does it fail opaquely?

## 3. Reproducible bugs

These were verified with `curl` against `https://app.keeperhub.com/api` on 2026-05-02. Every finding has the literal request that surfaced it.

### B1. `GET /api/workflows` returns `[]` with **no auth at all** *(severity: high — silent failure)*

```
$ curl -i https://app.keeperhub.com/api/workflows
HTTP/2 200
content-type: application/json

[]
```

Same `[]` is returned for a valid `wfb_` key, a bogus `kh_obviouslyfake` bearer, and an empty org. Four different auth states, one indistinguishable response. A developer who mistypes their key cannot tell their request was unauthenticated.

**Expected:** `401 Unauthorized` when no/invalid bearer is present, matching the behavior of `/api/integrations` and `/api/user`.

### B2. Documented response envelope is wrong

Docs say success is `{"data": {...}}` and errors are `{"error": {"code": "...", "message": "..."}}`. Real responses:

| Endpoint | Actual body | Documented body |
|---|---|---|
| `GET /workflows` (success) | `[]` | `{"data": []}` |
| `GET /chains` (success) | `[{...}, ...]` | `{"data": [{...}, ...]}` |
| `GET /integrations` (401) | `{"error":"Unauthorized"}` | `{"error":{"code":"...","message":"..."}}` |
| `GET /workflows/missing` (404) | `{"error":"Workflow not found"}` | `{"error":{"code":"...","message":"..."}}` |
| `GET /no-such-route` (404) | `<!DOCTYPE html>...` Next.js error page | JSON of any shape |

Three different error shapes (flat string, no `code` enum, raw HTML for unknown routes). Agents writing `response.error.code` will get `undefined`; agents calling `JSON.parse` on a 404 route will throw.

### B3. Documented endpoints that 404

All return HTML 404 with a `wfb_` key. (Should be retested with a `kh_` key — but route 404s shouldn't depend on auth scope.)

- `/api/executions` (the executions resource the docs name)
- `/api/runs`, `/api/workflow-runs`, `/api/v1/workflows`
- `/api/analytics`
- `/api/execute` (the "direct execution" endpoint the docs explicitly advertise)

### B4. `POST /api/workflows` → 405 Method Not Allowed

Workflow creation isn't reachable via REST at the documented path. MCP `create_workflow` works fine, so the capability exists — but the REST mount appears to be missing or moved.

### B5. No rate-limit observability

Docs state 100 req/min for authed clients. Across 21 rapid `GET /api/workflows` calls every response was 200 with no `X-RateLimit-*` or `Retry-After` header. Clients have no way to back off proactively, and (anecdotally) one request hung past a 10s timeout instead of returning 429 — possibly a soft throttle masquerading as latency.

### B6. `chains` array contains a real duplicate

The `chains` array returned by `list_action_schemas` and `get_plugin` lists "Solana Devnet" twice — with **different** chain IDs (`102` and `103`) but identical name and explorer URL. Not a casing artifact, an actual data bug:

```json
{ "chainId": 103, "name": "Solana Devnet", "explorerUrl": "https://solscan.io/?cluster=devnet" },
{ "chainId": 102, "name": "Solana Devnet", "explorerUrl": "https://solscan.io/?cluster=devnet" }
```

Pickers/UIs that key off the name will collide; agents that pass the chain ID will silently target whichever is canonical (which is undocumented).

### B7. MCP tool count drift

Public docs claim **19 tools** including `validate_plugin_config`. Live MCP server exposes **29 tools** and **does not include `validate_plugin_config`**. Concrete disagreement:

- Docs-listed but missing: `validate_plugin_config`
- Live but undocumented: `call_workflow`, `execute_check_and_execute`, `execute_contract_call`, `execute_protocol_action`, `execute_transfer`, `get_direct_execution_status`, `get_template`, `get_workflow_listing`, `update_workflow_listing`, `unlist_workflow`, `search_protocol_actions`, `tools_documentation`, `list_workflow` (a singular variant alongside `list_workflows`)

Agents that consult the public docs to decide which tools to call will pick a non-existent one and skip several useful ones.

### B8. Critical schema rules live only inside `get_plugin` responses

The `tips` array returned by `get_plugin` contains landmines that exist nowhere in the public docs:

- `network` is a chain-ID string (`"1"`), not a name (`"Ethereum"`)
- Condition operators are exact symbols (`===`, `<`); `equals`/`less_than` will fail
- Condition rules use `leftOperand`/`rightOperand`, not `field`/`value`
- Database Query must inline `{{@…}}` refs into SQL; `$1`/`$2` placeholders silently fail
- `tokenConfig` is a JSON-stringified object with a specific `mode`/`customToken` shape
- Edges use `sourceHandle` only; `targetHandle` is forbidden
- Every trigger emits `triggeredAt` (ISO timestamp)

These should be promoted to first-class public docs. Hiding them in a payload that only loads when an agent calls `get_plugin` means humans authoring through the UI never see them, and agents discover them by hitting validation errors.

### B9. `ai_generate_workflow` returns operation stream, not workflow object

Tool description implies it returns "a workflow definition ready to be created." Actual return is a newline-delimited stream of `setName`/`setDescription`/`addNode`/`addEdge`/`complete` operations. Caller has to apply them to construct the workflow object before passing to `create_workflow`. Documented behavior would be `create_workflow(generated_output)`; actual behavior requires a translation layer.

Additionally, the operations the generator emits frequently violate the schema rules in §B8 — most reliably the `network: "Ethereum"` mistake — meaning even after applying the ops you get a workflow that won't pass server validation.

## 4. Feature requests

Ranked by how much each would have helped a first-time agent build.

1. **A `dry_run` flag on `create_workflow` and `execute_workflow`.** Validate and return the would-be plan/tx without committing. Halves the cost of agent experimentation.
2. **A single `workflow_from_prompt_and_run` MCP tool** that wraps `ai_generate_workflow` → `validate` → `create` → `execute` → `await_status`. The four-step dance is fine for power users but punishing for the "hello world" path.
3. **Schema-typed errors.** Today errors are `{"error": {"code", "message"}}`. Adding a stable `code` enum (`SCHEMA_INVALID`, `WALLET_NOT_BOUND`, `RATE_LIMITED`, …) lets agents branch deterministically instead of regex-matching messages.
4. **Webhook signature verification documented inline.** If `wfb_` keys fire webhook triggers, what signs the inbound request and what header carries the signature? Without this, builders will skip verification.
5. **A `kh workflows lint` CLI command** that runs the equivalent of `validate_plugin_config` across an entire workflow file before push. Faster feedback loop than round-tripping through `create_workflow`.
6. **Per-execution cost preview.** Before `execute_workflow` runs, return the estimated gas + agentic-wallet debit. Agents budgeting their own funds need this; right now the only way to learn cost is to spend it.
7. **MCP `resources` listing for executions, not just workflows.** `keeperhub://executions/{id}` would let agents pull logs as a resource rather than a tool call, which composes better with reasoning loops.
8. **Idempotency keys on `execute_workflow`.** Agents retry. Without an idempotency key, retries can double-fire onchain actions — a real money problem.

---

## How to read this

- **Doc gaps** are the highest leverage: every one of them costs every new builder time.
- **Feature requests** 1, 3, and 8 are the ones I'd want before shipping an agent to production against KeeperHub today.
- **Bug section** is intentionally thin. We'll fill it from a real integration run, not from speculation.
