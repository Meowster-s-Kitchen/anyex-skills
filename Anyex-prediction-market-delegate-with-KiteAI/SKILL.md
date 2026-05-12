---
name: Anyex-prediction-market-delegate-with-KiteAI
description: >
  Trade Polymarket prediction markets autonomously using Kite AI gasless payments.
  This skill is part of the Kite Passport partnership — it enables any AI agent
  holding a Kite wallet (with USDC.e on Kite AI mainnet, chain ID 2368) to discover
  live prediction markets, get real-time prices, sign an EIP-3009 payment
  authorization with their own wallet key, and place orders on Polymarket's CLOB
  — all without a JWT, API key, or local tooling. The x402 payment signature is
  both the payment mechanism and the user identity: the `from` address of the
  EIP-3009 message becomes the Kite Passport user, and AnyEx provisions a
  Polymarket-compatible Gnosis Safe on Polygon on their behalf. Agents need only
  their Kite wallet private key and USDC.e balance to trade end-to-end.
---

# Anyex Prediction Market — Delegate with Kite AI

You are executing a Polymarket prediction market trade via the AnyEx Kite MCP server.

## Kite Passport Context

This skill is part of the **Kite Passport** program — a partnership between AnyEx and Kite AI that allows any agent or user with a Kite wallet to trade real-money prediction markets on Polymarket without setting up accounts, API keys, or managing gas.

**How identity works**: There is no separate JWT or session token. When you sign the EIP-3009 `TransferWithAuthorization` message with your Kite wallet, the `from` address is extracted server-side and used as your permanent identity. AnyEx automatically provisions a Gnosis Safe on Polygon for that address on first trade, and all Polymarket positions, orders, and activity are indexed under that Safe.

**What you need as an agent**:
- A Kite wallet address and its private key (or signing capability)
- A USDC.e balance on Kite AI mainnet (chain ID 2368, token `0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e`)
- Access to the Kite RPC at `https://rpc.gokite.ai` to fetch block timestamps

## Arguments

The user (or calling agent) provides: `<query> <outcome> <budget_usdc>`
- `query`: market search term (e.g. "Trump president", "MicroStrategy BTC")
- `outcome`: YES or NO
- `budget_usdc`: how much USDC to spend (e.g. 5 means $5 USDC)

Example: `/Anyex-prediction-market-delegate-with-KiteAI "MicroStrategy sells BTC" YES 5`

**IMPORTANT — Units**: `budget_usdc` is always in USDC dollars, NOT shares. If the user says "5u" or "5" or "$5", they mean $5 USDC. For FAK (market) orders, `size` passed to `polymarket_buy` equals the USDC budget directly — the CLOB converts it to shares internally (shares = budget / price).

If arguments are missing, ask the user. When asking for amount, always phrase as "How much USDC to spend?"

## Authentication Model

x402 payment = identity. No separate JWT or API session is required.

When `polymarket_buy` is called with a valid `x_payment` payload:
1. The server decodes the base64 payload and extracts the `from` address
2. The EIP-3009 signature is verified against the Kite USDC.e contract
3. The `from` address is used as the Kite Passport user's identity
4. AnyEx submits the payment to the Kite gasless relayer (`https://gasless.gokite.ai/mainnet`)
5. The relayer executes the on-chain USDC.e transfer — the agent pays no gas

This means any agent that can sign EIP-712 typed data with a Kite wallet can trade Polymarket markets through AnyEx, with no pre-registration or token issuance.

## Execution Steps

### 1. Find the market

Call the `polymarket_markets` MCP tool with the user's query to find matching markets. The tool searches by keyword against event titles. Only markets with `acceptingOrders: true` are returned.

If the MCP tool is not available (not connected as an MCP server), fall back to calling the Gamma API directly via HTTP:

```bash
curl -s "https://gamma-api.polymarket.com/events?title=<QUERY>&closed=false&active=true&limit=10" \
  -H 'User-Agent: anyex-kite-mcp/1.0.0'
```

**Important**: Do NOT use the `/markets` endpoint with `slug=` for text search — it does exact slug matching, not keyword search. Always use the `/events` endpoint with `title=` for keyword search.

Show the user the top results with:
- Question
- Current YES/NO prices
- Token IDs

If multiple markets match, ask the user to pick one. Extract the `clobTokenIds` — index 0 = YES token, index 1 = NO token.

### 2. Get the quote

Call `polymarket_buy` **without** `x_payment` and **without** `price`, passing `size` = the user's USDC budget — it will auto-fetch the best ask and return a 402 Payment Required response:

```json
{
  "payment_required": true,
  "x402_version": 2,
  "kite_gasless": true,
  "network": "eip155:2368",
  "token": "0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e",
  "pay_to": "0x33e372BFEbe00abe5a99Bb596412Ce22004BBF4D",
  "max_timeout_seconds": 30,
  "amount": "<integer_string_6_decimals>",
  "resolved_price": 0.72,
  "auto_price": true,
  "estimated_cost_usd": "5.00"
}
```

Save `amount` and `pay_to` — you will need both in Step 3.

Show the user:
> "Best ask: $X.XX/share — $Y USDC buys ~N shares (= budget / price). Proceed?"
> (N = budget / resolved_price, for display only)

Wait for user confirmation before continuing.

### 3. Sign the x402 EIP-3009 payment

**The payment signature expires in 25 seconds. Complete Steps 3 and 4 immediately after signing.**

Construct and sign an EIP-712 `TransferWithAuthorization` message using your Kite wallet. This is a pure cryptographic operation — no local scripts, no environment variables, no Node.js install required. Any agent that can sign EIP-712 typed data can complete this step.

#### 3a. Fetch the latest Kite block timestamp

Make a JSON-RPC call to the Kite mainnet RPC to get the latest block timestamp:

```
POST https://rpc.gokite.ai
Content-Type: application/json

{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}
```

Extract `result.timestamp` (a hex string). Convert to decimal — this is `latestBlockTimestamp` (seconds since epoch).

#### 3b. Construct the EIP-712 message

**Domain** (matches the Kite USDC.e token contract):
```json
{
  "name": "Bridged USDC (Kite AI)",
  "version": "2",
  "chainId": 2368,
  "verifyingContract": "0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e"
}
```

**Type definition**:
```
TransferWithAuthorization(
  address from,
  address to,
  uint256 value,
  uint256 validAfter,
  uint256 validBefore,
  bytes32 nonce
)
```

**Message values**:

| Field | Value | Notes |
|-------|-------|-------|
| `from` | Your Kite wallet address | Checksummed EIP-55 address |
| `to` | `pay_to` from Step 2 response | `0x33e372BFEbe00abe5a99Bb596412Ce22004BBF4D` |
| `value` | `amount` from Step 2 response | Integer string, 6 decimals (e.g. `"5000000"` = $5) |
| `validAfter` | `latestBlockTimestamp - 1` | Must be before current block time |
| `validBefore` | `floor(Date.now()/1000) + 25` | 25-second validity window |
| `nonce` | 32 random bytes, hex-prefixed | e.g. `"0x" + randomBytes(32).hex()` |

#### 3c. Sign with EIP-712

Sign the typed data using your Kite wallet's private key. The result is a 65-byte ECDSA signature. Split it into `v` (integer), `r` (32-byte hex), `s` (32-byte hex).

**ethers.js v6:**
```js
const sig = ethers.Signature.from(await wallet.signTypedData(domain, types, message))
// sig.v, sig.r, sig.s
```

**viem:**
```js
const sig = await signTypedData({ domain, types, primaryType: 'TransferWithAuthorization', message })
const { v, r, s } = parseSignature(sig)
```

**Python (eth_account):**
```python
from eth_account import Account
from eth_account.messages import encode_typed_data
msg = encode_typed_data(domain_data=domain, message_types=types, message_data=message)
signed = Account.sign_message(msg, private_key=key)
# signed.v, '0x' + signed.r.hex(), '0x' + signed.s.hex()
```

#### 3d. Build the x_payment payload

Construct the JSON payload:
```json
{
  "from": "<your_kite_wallet_address>",
  "to": "<pay_to_from_step2>",
  "value": "<amount_from_step2>",
  "validAfter": "<latestBlockTimestamp_minus_1_as_string>",
  "validBefore": "<unix_now_plus_25_as_string>",
  "tokenAddress": "0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e",
  "nonce": "<0x_prefixed_32_random_bytes_hex>",
  "v": <integer_recovery_id>,
  "r": "<0x_prefixed_r_component>",
  "s": "<0x_prefixed_s_component>"
}
```

Base64-encode the entire JSON string (UTF-8, no line breaks) — this is the `x_payment` value.

**Proceed immediately to Step 4.**

### 4. Place the order

Call `polymarket_buy` MCP tool with all parameters:
- `market_slug`: from step 1
- `token_id`: the correct token ID for the chosen outcome (`clobTokenIds[0]` = YES, `clobTokenIds[1]` = NO)
- `outcome`: YES or NO
- `price`: the `resolved_price` from step 2
- `size`: the USDC budget (same value used in step 2 for FAK orders)
- `order_type`: FAK (default, fills immediately or kills)
- `x_payment`: the base64 string from step 3

### 5. Report result

Show the user:
- Success/failure
- Shares bought and price paid
- Trade UUID and Order ID
- Safe address (your Polymarket-compatible Gnosis Safe on Polygon)
- Kite settlement tx: `https://kitescan.ai/tx/<settleTxHash>`
- Polygon funding tx (if first-time user): `https://polygonscan.com/tx/<fundingTxHash>`
- Any error message

If the order was killed (FAK with no match), explain that no matching sell orders were found at that price level and suggest trying GTC (limit order) or a slightly higher price.

### 6. Verify position

After a successful trade, call `polymarket_positions` with the user's `wallet_address` (their Kite wallet address) to confirm the position. Show:
- Title, outcome, size
- Avg price, current price
- PnL (cash + percent)

Note: Polymarket's data API may have a few seconds of lag after a trade. If positions appear empty immediately after a successful trade, wait 5–10 seconds and retry.

## Other Available Tools

### polymarket_positions
Query all open positions with PnL. Uses public `data-api.polymarket.com/positions`.
- Input: `wallet_address` (your Kite wallet address)
- Returns: title, size, avgPrice, curPrice, cashPnl, percentPnl, etc.

### polymarket_activity
Query trade history and activity log. Uses public `data-api.polymarket.com`.
- Input: `wallet_address`, `limit` (default 20)
- Returns: trades (side, size, price, outcome, txHash) and activity (type, usdcSize)

### polymarket_open_orders
Query and manage open GTC/GTD limit orders. Uses authenticated CLOB session.
- Input: `wallet_address`, `action` (`list` | `cancel` | `cancel_all`), `order_ids` (for cancel)
- `list`: show all live orders
- `cancel`: cancel specific orders by ID
- `cancel_all`: cancel all open orders

### polymarket_wallet
Query Safe address and USDC.e balance on Polygon. Read-only, no auth.
- Input: `wallet_address` (your Kite wallet address)

## MCP Server

Connect to the AnyEx Kite MCP server to access all `polymarket_*` tools:

```json
{
  "mcpServers": {
    "anyex-kite": {
      "type": "http",
      "url": "https://mcp.anyex.ai/anyex/v1/mcp/kite"
    }
  }
}
```

## Network Constants

| Parameter | Value |
|-----------|-------|
| Kite chain ID | `2368` |
| Kite RPC | `https://rpc.gokite.ai` |
| Gasless relayer | `https://gasless.gokite.ai/mainnet` |
| USDC.e token | `0x7aB6f3ed87C42eF0aDb67Ed95090f8bF5240149e` |
| EIP-712 token name | `Bridged USDC (Kite AI)` |
| EIP-712 token version | `2` |
| Token decimals | `6` |
| AnyEx pay_to | `0x33e372BFEbe00abe5a99Bb596412Ce22004BBF4D` |
| Signature window | 25 seconds (`validBefore = now + 25`) |
| Kite explorer | `https://kitescan.ai/tx/<txHash>` |
| Polygon explorer | `https://polygonscan.com/tx/<txHash>` |

## API Reference

- **Market search**: `https://gamma-api.polymarket.com/events?title=<QUERY>&closed=false&active=true`
- **Positions**: `https://data-api.polymarket.com/positions?user=<SAFE_ADDRESS>&sizeThreshold=0.01&limit=100&sortBy=TOKENS&sortDirection=DESC`
- **Trades**: `https://data-api.polymarket.com/trades?user=<SAFE_ADDRESS>&limit=20`
- **Activity**: `https://data-api.polymarket.com/activity?user=<SAFE_ADDRESS>&limit=20`
- **Kite RPC (block timestamp)**: `POST https://rpc.gokite.ai` — `eth_getBlockByNumber("latest", false)`
- **Do NOT use** `/markets?slug=` for text search (exact match only)
- **Do NOT use** CLOB `/data/orders` or `/data/trades` without auth (returns 401)
