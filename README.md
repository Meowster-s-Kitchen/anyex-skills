# AnyEx Claude Code Skills

Skills that let Claude (and any agent that reads `~/.claude/skills/`) trade real-money prediction markets end-to-end through the **Kite Passport** identity layer — no JWTs, API keys, or local tooling beyond a Kite wallet.

Currently shipped:

| Skill | What it does |
|---|---|
| [`Anyex-prediction-market-delegate-with-KiteAI`](./Anyex-prediction-market-delegate-with-KiteAI/SKILL.md) | Search Polymarket markets, validate they're still live, provision a Polygon DepositWallet (one-time, explicit consent), and BUY / SELL / REDEEM via x402 V2 — all from natural-language prompts. |

---

## Install

```bash
curl -fsSL https://install.anyex.ai/polymarket | bash
```

That single command:

1. Installs [`kpass`](https://docs.gokite.ai/passport) (Kite Passport CLI) if it isn't already on `PATH`.
2. Drops the skill into `~/.claude/skills/Anyex-prediction-market-delegate-with-KiteAI/`.
3. Optionally registers the AnyEx MCP server (`https://mcp.anyex.ai/anyex/v1/mcp/kite`) in your Claude Desktop config — prompted; you can decline if you only use Claude Code or another agent.

**OS support:** macOS, Linux. Windows users: install kpass via [install.kite.ai](https://install.kite.ai), then download `SKILL.md` into `%USERPROFILE%\.claude\skills\Anyex-prediction-market-delegate-with-KiteAI\` manually.

### What you get

```
~/.claude/skills/
└── Anyex-prediction-market-delegate-with-KiteAI/
    └── SKILL.md
```

Claude / Cursor / Codex / Cline / any agent that reads this directory will auto-discover the skill the next time you launch.

---

## First-run checklist

After install, three one-time setup steps:

```bash
# 1. Sign up (or log in) to Kite Passport
kpass signup init --email you@example.com
# (follow the email link, then complete the verification)

# 2. Fund the wallet — bridge ≥ $1 USDC.e to Kite mainnet (chain 2366)
kpass wallet balance         # shows your Kite wallet address + balance
# token contract: 0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e

# 3. (only on first ever trade) AnyEx provisions a Polymarket
#    DepositWallet on Polygon for you — flat $0.05 USDC fee, idempotent,
#    requires an explicit in-conversation APPROVE.
```

Then in Claude (or any agent), use natural language:

> Buy me $5 of Polymarket YES on "Will BTC close above $150k by end of 2026"

Claude orchestrates the rest — searches Polymarket, validates the market hasn't already closed, asks you to approve the DepositWallet setup (first trade only), signs the x402 payment, places the CLOB order, verifies the position.

---

## What's happening under the hood

```
┌──────────────────────────┐                  ┌────────────────────────────┐
│  Claude / Cursor / kpass │ ── x402 V2 ────► │  mcp.anyex.ai              │
│  (signs EIP-3009 with    │                  │  /anyex/v1/x402/polymarket │
│   your Kite wallet)      │ ◄── 200/402 ───  │  • /lookup • /init          │
└──────────────────────────┘                  │  • /buy   • /sell           │
                                              │  • /redeem                  │
                                              └─────────────┬──────────────┘
                                                            │
                            ┌───────────────────────────────┼───────────────────┐
                            │                               │                   │
                            ▼                               ▼                   ▼
                  Kite mainnet (USDC.e        Polymarket CLOB          Polygon DepositWallet
                  EIP-3009 settle)            (order placement)        (your custody, via
                                                                       Turnkey delegated access)
```

- **Identity = signature.** The `from` field of your signed EIP-3009 is your permanent Kite Passport user ID. No accounts to create.
- **AnyEx provisions a Polymarket-compatible DepositWallet** on Polygon for that address on first trade. You remain the sole signer (Turnkey DA).
- **kpass V2 quirks handled server-side.** The shim has an on-chain settlement fallback for the documented kpass-V2-vs-gokite-relayer `validBefore` window mismatch, so you don't need a workaround.

---

## Costs

| Action | Fee |
|---|---|
| One-time DepositWallet setup (`/init`) | ~$0.05 USDC |
| Each BUY | Order amount + Polymarket per-market maker fee |
| Each SELL | ~$0.01 USDC flat |
| Each REDEEM | ~$0.01 USDC flat |

No subscription, no minimum, no AnyEx side-fees beyond the line items above.

---

## FAQ

### Why x402 V2 + EIP-3009 instead of a JWT?

x402 is the emerging open standard for paid-API access ([spec](https://www.x402.org/)). EIP-3009 lets you authorize a USDC transfer off-chain with a single ECDSA signature — that signature is both the payment and the identity proof. No server-side session state, no replay risk (nonces are token-contract-enforced), no JWT to leak.

### What if Claude decides to buy the wrong market?

The skill enforces a **mandatory consent card** before any contract deployment (`/init`) and before any trade above your kpass session's per-tx limit. You always see the market title, fee, and outcome before the signature is requested.

### Can I use this without Claude?

Yes — the shim is plain HTTP x402 V2. Any `kpass agent:session execute` call, any `@x402/core` client, or any HTTP client that can produce a `Payment-Signature` header will work. See the `SKILL.md` "Path B" section for raw HTTP examples.

### How is this related to the AnyEx MCP server?

The MCP server (`https://mcp.anyex.ai/anyex/v1/mcp/kite`) exposes the same functionality as JSON-RPC `tools/call` for MCP-aware clients (Claude Desktop, etc.). The HTTP shim under `/anyex/v1/x402/polymarket/*` is for kpass and any standard x402 client. Same backend, two surfaces.

### Where can I see what was bought / current positions?

Public read endpoints — no signature needed:

```bash
curl "https://mcp.anyex.ai/anyex/v1/x402/polymarket/positions?safe=<your-Safe-address>"
curl "https://mcp.anyex.ai/anyex/v1/x402/polymarket/activity?safe=<your-Safe-address>"
```

Your Safe address is returned by `/lookup` and `/init`. Or use any Polymarket UI by entering the Safe address.

---

## Troubleshooting

**`kpass: command not found` after install**
The kpass installer puts the binary in `$HOME/.local/bin`. Add this to your shell rc:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**`agent:session execute` returns `internal error`**
Almost always means the merchant returned 4xx that kpass wrapped opaquely. If you control the merchant, check its server logs. If you're hitting `mcp.anyex.ai`, [open an issue](https://github.com/Meowster-s-Kitchen/anyex-skills/issues) with the timestamp — we can pull Lambda logs for the failed request.

**`HTTP 502` from a `/buy`**
Lambda timeout (30s) during a first-time deploy. The order may have placed anyway — **do not blindly retry**. Check positions first:
```bash
curl "https://mcp.anyex.ai/anyex/v1/x402/polymarket/positions?safe=<your-safe>"
```
If empty, retry. If your position is there, the buy succeeded — kpass just got the timeout response. To avoid this in the future, the skill flow runs `/init` first; only the first paid `/buy` is at risk.

**`Insufficient USDC.e balance`**
Bridge USDC.e to Kite mainnet (chain 2366), token `0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e`. Most major bridges support Polygon ↔ Kite. Min ~$1 USDC for a meaningful first trade + the $0.05 init.

**Market validation rejected my trade**
If a market's `endDate` has already passed (even if `acceptingOrders: true`), the skill refuses to buy. Polymarket leaves expired-but-unresolved markets visible with thin orderbooks; positions in those markets nearly always settle to $0. Pick a market with `endDate > today`.

---

## Contributing

PRs welcome for:
- New skills (other prediction markets, perps, etc. — same x402 V2 pattern)
- Better install scripts (Windows PowerShell, NixOS, etc.)
- Docs + examples + screenshots

For substantial changes, open an issue first.

---

## License

MIT — see [LICENSE](./LICENSE).
