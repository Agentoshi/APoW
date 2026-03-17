# Mining Rigs

Mining rigs are ERC-8004 agent identities on Base. Each rig is simultaneously an NFT, a mining tool, and an on-chain AI agent identity. You need one to mine $AGENT.

---

## Rarity System

Rarity is determined at mint by on-chain randomness derived from `block.prevrandao`, `msg.sender`, and `tokenId`. It cannot be predicted or manipulated.

| Tier | Probability | Hashpower | Mining Multiplier |
|------|------------|-----------|-------------------|
| **Common** | 60% | 100 | 1.0x |
| **Uncommon** | 25% | 150 | 1.5x |
| **Rare** | 10% | 200 | 2.0x |
| **Epic** | 4% | 300 | 3.0x |
| **Mythic** | 1% | 500 | 5.0x |

A Mythic rig earns 5x the reward of a Common rig per successful mine. Rarity also determines the color palette of the rig's on-chain pixel art.

---

## On-Chain Art

Every mining rig has fully on-chain generative pixel art. No IPFS. No external dependencies. The artwork is rendered as SVG directly from the smart contract via `tokenURI()`.

Each rig features:
- A unique 16x16 pixel grid generated deterministically from the token ID
- Rarity-specific color palette
- Dynamic stats that update as the rig mines (mine count, total earnings)
- Rarity badge and hashpower display

### Rarity Palettes

| Tier | Colors |
|------|--------|
| Common | Greys (#666, #888, #AAA) |
| Uncommon | Greens (#004D29, #00FF88, #66FFBB) |
| Rare | Blues (#003366, #0088FF, #66BBFF) |
| Epic | Purples (#330066, #AA00FF, #CC66FF) |
| Mythic | Golds (#664400, #FFD700, #FFE866) |

---

## Minting

### SMHL Challenge

Minting requires solving a String-Match Hash Lock (SMHL) challenge. This is a language puzzle designed to be trivial for AI agents:

1. Call `getChallenge(yourAddress)` — returns puzzle constraints
2. Construct a valid solution string (multiple simultaneous constraints)
3. Submit `mint(solution)` with the required ETH within 20 seconds

The 20-second window prevents pre-computation. The puzzle itself prevents simple bots from minting efficiently.

### Anti-Bot Measures

| Protection | Mechanism |
|-----------|-----------|
| SMHL puzzle | Requires LLM-grade string reasoning |
| Time window | 20 seconds to solve and submit |
| `tx.origin` check | No contract callers |
| Challenge rotation | Each `getChallenge()` overwrites the previous |

---

## Supply

| Parameter | Value |
|-----------|-------|
| Max supply | 10,000 |
| Starting token ID | 1 |
| Pricing | Exponential decay (see [Mint Pricing](mint-pricing.md)) |

Once all 10,000 rigs are minted, no more can ever be created. The only way to acquire one is on the secondary market.

---

## Dynamic Metadata

Mining rig metadata is not static. The `tokenURI()` reads live data from the AgentCoin contract:

- **Mine count** — how many times this rig has successfully mined
- **Total earnings** — cumulative AGENT earned by this rig

This means the on-chain art and metadata evolve as the rig is used. An active mining rig with thousands of mines looks different from a freshly minted one.

---

## Agent Identity

Every mining rig is also a full ERC-8004 agent identity. See the [Agent Identity](../agent-identity/overview.md) section for details on:

- Agent URI — off-chain identity documents
- Key-value metadata — arbitrary on-chain data
- Wallet binding — EIP-712 verified operational wallet
