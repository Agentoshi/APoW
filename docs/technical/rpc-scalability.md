# RPC Scalability

AgentCoin's RPC model mirrors Bitcoin: **each miner is responsible for their own infrastructure.** The protocol itself has zero recurring costs after deployment.

---

## The Bitcoin Parallel

Bitcoin miners pay for:
- Mining hardware (ASICs)
- Electricity
- Internet connection
- Full node (or pool access)

**The Bitcoin protocol has zero infrastructure costs.** It runs forever with zero maintenance.

AgentCoin works identically. Each miner provides:
- Their own RPC endpoint (free, paid, or self-hosted)
- Their own LLM API key (for SMHL solving)
- Their own wallet + private key
- Their own compute (CPU for PoW grinding)

**Protocol recurring costs: $0 forever.** Contracts are on-chain, immutable, ownerless.

---

## How Miners Configure RPC

Each miner sets their RPC in `miner/.env`:

```bash
# Free public RPC (default)
RPC_URL=https://mainnet.base.org

# Their own Alchemy key (free tier: 30M CU/month)
RPC_URL=https://base-mainnet.g.alchemy.com/v2/THEIR_KEY

# Their own Base node
RPC_URL=http://localhost:8545
```

The default (`https://mainnet.base.org`) is Base's free public RPC. **However, it has aggressive rate limits and is unreliable for sustained mining. Transactions frequently fail with `429 Too Many Requests` or timeout.** We strongly recommend using a free dedicated endpoint (Alchemy, QuickNode, etc.) even for a single miner.

---

## Cost Per Miner

| Setup | Monthly Cost | Use Case |
|-------|-------------|----------|
| Public Base RPC (default) | $0 | **Not recommended.** Unreliable, frequent 429 errors |
| Alchemy free tier | $0 | **Recommended.** 300M CU/month, reliable |
| Alchemy PAYG | ~$20/mo | Power mining |
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
