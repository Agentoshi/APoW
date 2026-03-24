# RPC Scalability

AgentCoin's RPC model mirrors Bitcoin: **each miner is responsible for their own infrastructure.** The protocol itself has zero recurring costs after deployment.

---

## RPC Options (v0.8.0+)

As of v0.8.0, you must configure an RPC endpoint. Two options:

### Option A: Bring Your Own RPC (Recommended)

Set `RPC_URL` in `.env` with a free or paid Base RPC URL from [Alchemy](https://www.alchemy.com/) (free, 300M CU/month), [QuickNode](https://www.quicknode.com/), Infura, or any provider.

### Option B: QuickNode x402 (Zero Setup)

Set `USE_X402=true` in `.env`. Your mining wallet pays $10 USDC for ~1M RPC calls via the [x402 payment protocol](https://www.x402.org/). No API key, no account, no rate limits.

- **Cost:** $10 USDC per ~1M RPC calls (prepaid credits, one-time purchase per session)
- **Requirement:** USDC balance on Base in your mining wallet
- **No API key needed:** Payment is automatic via your wallet's USDC

---

## The Bitcoin Parallel

Bitcoin miners pay for:
- Mining hardware (ASICs)
- Electricity
- Internet connection
- Full node (or pool access)

**The Bitcoin protocol has zero infrastructure costs.** It runs forever with zero maintenance.

AgentCoin works identically. Each miner provides:
- Their own RPC endpoint (free, paid, x402, or self-hosted)
- Their own LLM API key (for SMHL solving during minting only)
- Their own wallet + private key
- Their own compute (CPU for PoW grinding)

**Protocol recurring costs: $0 forever.** Contracts are on-chain, immutable, ownerless.

---

## How Miners Configure RPC

Each miner sets their RPC in `.env`:

```bash
# Option A: Custom RPC URL (free from Alchemy, QuickNode, etc.)
# RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY

# Option B: QuickNode x402 (auto-pay $10 USDC for ~1M calls)
# USE_X402=true

# Custom Alchemy key (free tier: 300M CU/month)
RPC_URL=https://base-mainnet.g.alchemy.com/v2/THEIR_KEY

# Free public RPC (unreliable for sustained mining)
RPC_URL=https://mainnet.base.org

# Their own Base node
RPC_URL=http://localhost:8545
```

If using x402, you need USDC in your mining wallet (~$10 for ~1M RPC calls). The `apow fund` command auto-splits deposits into ETH (gas) + USDC (RPC).

---

## Cost Per Miner

| Setup | Monthly Cost | Use Case |
|-------|-------------|----------|
| Custom Alchemy (free tier) | $0 | **Recommended.** 300M CU/month, reliable |
| QuickNode x402 (zero setup) | ~$10/1M calls | Premium RPC, prepaid credits via USDC, no API key needed |
| Alchemy PAYG | ~$20/mo | Power mining |
| Public Base RPC | $0 | **Not recommended.** Unreliable, frequent 429 errors |
| Own Base node | Electricity only | Mining farm |

**At 10,000 concurrent miners:** Protocol cost = $0. Each miner's cost = $0-20/mo (their choice).

---

## MEV & Sniper Resistance

AgentCoin is sniper-resistant by design. No additional protection mechanisms needed.

### Base L2 Natural Resistance

- **No public mempool:** Coinbase's centralized sequencer processes FIFO
- **No gas auctions:** uniform base fee (~0.001 gwei), no priority bidding
- **2-second blocks:** minimal extraction window

### Protocol-Level Protection

| Mechanism | How It Helps |
|-----------|-------------|
| Transfer lock | Zero AGENT on DEXes pre-LP. No pre-positioning possible |
| No team/VC allocation | Only miners hold tokens, earned through real work |
| Atomic LP deployment | `deployLP()` creates pool + mints position in one tx |
| Eternal UNCX lock | Deployer can't rugpull. Removes #1 reason bots snipe |

### Why NOT to Add Extra Mechanisms

| Mechanism | Problem |
|-----------|---------|
| Max tx size (first N blocks) | Punishes legitimate large miners |
| Sell cooldown | Unfair to miners who earned tokens |
| Anti-snipe tax | Looks scammy, breaks DeFi composability |
| Whitelist trading period | Defeats permissionless ethos |

**Fair launch = no artificial restrictions.** Everyone mines at equal difficulty, earns equal rewards, trades freely.
