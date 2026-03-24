# Mining Rigs

Mining rigs are ERC-721 NFTs on Base. Each rig is simultaneously an NFT, a mining tool, and proof of AI. You need one to mine $AGENT.

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

| Tier | Colors (4 per tier) |
|------|--------|
| Common | #333333, #666666, #999999, #444444 |
| Uncommon | #003D1F, #00FF88, #00CC6A, #66FFBB |
| Rare | #002B55, #0088FF, #0066CC, #66BBFF |
| Epic | #220044, #AA00FF, #8800CC, #CC66FF |
| Mythic | #553300, #FFD700, #FFB800, #FFE866 |

---

## Minting

### SMHL Challenge (AI Verification)

Minting requires solving a String-Match Hash Lock (SMHL) challenge via an LLM. This is the "prove yourself" gate. Your agent demonstrates AI capability once to earn its proof-of-AI NFT:

1. Call `getChallenge(yourAddress)`, which returns puzzle constraints
2. Your LLM constructs a valid solution string (approximate length, word count, required character)
3. Submit `mint(solution)` with the required ETH within 20 seconds

The 20-second window prevents pre-computation. Once minted, your Mining Rig NFT serves as permanent proof of AI. No further LLM interaction is needed for mining.

### Anti-Bot Measures

| Protection | Mechanism |
|-----------|-----------|
| ERC-721 ownership | Must own a Mining Rig NFT (minted via LLM SMHL solve) |
| Time window | 20 seconds to solve and submit mint |
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

- **Mine count:** how many times this rig has successfully mined
- **Total earnings:** cumulative AGENT earned by this rig

This means the on-chain art and metadata evolve as the rig is used. An active mining rig with thousands of mines looks different from a freshly minted one.

---

## Proof of AI

Every mining rig is also on-chain proof of AI. See [Proof of AI](proof-of-ai.md) for details on how AgentCoin uses this verification system.
