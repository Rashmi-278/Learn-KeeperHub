# Learn-KeeperHub

A working journal of building agent-driven workflows on [KeeperHub](https://app.keeperhub.com/) — the execution and reliability layer for AI agents operating onchain.

This repo is the result of an end-to-end engagement: read the docs, wire up an agent, deploy real workflows against a real Safe multisig on Ethereum mainnet, and write down what worked, what broke, and what the docs got wrong. Every claim has a literal MCP call or `curl` response behind it.

## What's in here

| File | What it is |
|---|---|
| [`ARTICLE.md`](ARTICLE.md) | **Build a Safe Treasury Guardian by Talking to KeeperHub** — a builder's tour of the platform, written from a real session with the rough edges left in |
| [`AGENTS.md`](AGENTS.md) | Developer-facing reference for connecting an AI agent to KeeperHub (REST, MCP, CLI), the 30 live MCP tools, and the schema landmines |
| [`FEEDBACK.md`](FEEDBACK.md) | Honest builder feedback for the KeeperHub team — UX friction, reproducible bugs (B1–B10), doc gaps, feature requests |
| [`AUTH_TEST.md`](AUTH_TEST.md) | Reproducible curl commands for the `/api/workflows` silent-200 auth bug |
| [`LOG.md`](LOG.md) | Session-by-session log of what we did, what tripped us up, and what got resolved |

`Log.md` (lowercase `og`) is personal scratch and not authoritative.

## How to read it

- **Curious about KeeperHub?** Start with `ARTICLE.md`. It's the narrative tour.
- **Building an agent against KeeperHub?** Read `AGENTS.md`. It's the reference card.
- **You work on KeeperHub and want the bug list?** `FEEDBACK.md` and `AUTH_TEST.md`. Every bug has reproduction steps.
- **Want to follow the chronology of how we got here?** `LOG.md`.

## Quick path: a guardian in 30 minutes

```bash
# 1. Get an organization-scoped key (NOT a wfb_ key) from app.keeperhub.com
#    → avatar → API Keys → Organisation tab → Create New Key

# 2. Connect an MCP-capable agent (here: Claude Code)
claude mcp add --transport http keeperhub https://app.keeperhub.com/mcp
# Then /mcp in Claude Code → OAuth in browser

# 3. Set up a Discord webhook integration
#    → Discord channel → Edit → Integrations → New Webhook → Copy URL
#    → app.keeperhub.com → Integrations → New → Discord → paste URL

# 4. Deploy a Safe template, patch its defects, enable it
#    (deploy_template + update_workflow + execute_workflow via MCP)
```

The full walkthrough — including the four template defects you have to patch by hand — is in `ARTICLE.md`.

## What's running on this org as a result

Three live Safe-security guardians watching `0x91c32893216dE3eA0a55ABb9851f581d4503d39b` on Ethereum mainnet:

- **Threshold Guardian** — alerts on `ChangedThreshold` (the canonical compromise vector)
- **Owner Change Guardian** — alerts on `AddedOwner`
- **Module Install Guardian** — alerts on `EnabledModule` (highest-severity Safe event)

Coverage gap: `ChangedGuard` — the featured template was too structurally broken to deploy. Plan is to rebuild from scratch via `create_workflow`.

## The biggest finding

**The MCP `get_plugin` schema declares output field names that the runtime does not emit.**

| Action | Schema declares | Runtime emits |
|---|---|---|
| `safe/get-owners` | `outputFields.owners` | `output.result` |
| `safe/get-threshold` | `outputFields.threshold` | `output.result` |
| `safe/get-modules-paginated` | `outputFields.array`, `outputFields.next` | `output.result.array`, `output.result.next` |

Every featured Safe template references the schema names. Every featured Safe template would silently deliver alerts with empty data sections. The defect is invisible in dev because Event triggers don't fire under manual test — only deploying, swapping to a Manual trigger, and reading the execution log surfaces it.

Detail in `FEEDBACK.md` (B9-critical) and `ARTICLE.md`.

## License

MIT — see [`LICENSE`](LICENSE).
