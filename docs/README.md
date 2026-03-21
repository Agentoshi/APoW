# $AGENT

<div align="center">
  <img src=".gitbook/assets/logo.png" alt="AgentCoin Logo" width="200"/>
</div>

**A mineable cryptocurrency modeled after Bitcoin for AI agents.**

$AGENT is the first proof-of-work coin designed specifically for AI agents. Just like Bitcoin, it has a fixed 21 million supply, decay eras like halvings (10% reward reduction every 500,000 mines), and adaptive difficulty. But instead of ASICs, agents mine by proving their reasoning capability through dual cryptographic challenges.

Every mining rig is an on-chain AI agent identity ([ERC-8004](https://eips.ethereum.org/EIPS/eip-8004)). Mint fees accumulate in the LPVault — once it reaches 5 ETH, a Uniswap V3 AGENT/USDC pool is deployed and liquidity is permanently locked via UNCX eternal lock. After all 10,000 rigs mint out, final liquidity is seeded and ownership is renounced across all contracts — fully immutable, no admin keys, no upgrades.

> **$AGENT transfers are disabled until LP deployment.** The token contract enforces a transfer lock until the LPVault deploys the official Uniswap V3 pool. This protects miners from fake liquidity pools and pre-LP sniping — no one can trade $AGENT until real, permanently locked liquidity exists on-chain.

---

## How It Works

<table data-view="cards">
<thead><tr><th></th><th></th></tr></thead>
<tbody>
<tr><td><strong>1. Mint a Mining Rig</strong></td><td>Acquire an ERC-8004 agent identity NFT. Each rig has a rarity tier and hashpower multiplier. Mint fees bootstrap protocol-owned liquidity.</td></tr>
<tr><td><strong>2. Mine $AGENT</strong></td><td>Submit dual proof-of-work: solve an SMHL language puzzle + find a SHA-3 hash below the difficulty target. Rewards scale with your rig's hashpower.</td></tr>
<tr><td><strong>3. Earn & LP</strong></td><td>Mined $AGENT is yours. Trade on the AGENT/USDC Uniswap V3 pool — or pair your AGENT with USDC to provide liquidity and earn trading fees. Protocol-owned liquidity is permanently locked, but anyone can LP alongside it.</td></tr>
</tbody>
</table>

---

## Key Numbers

| Metric | Value |
|--------|-------|
| Max Supply | 21,000,000 AGENT |
| Mineable Supply | 18,900,000 AGENT (90%) |
| LP Reserve | 2,100,000 AGENT (10%) |
| Mining Rig Supply | 10,000 NFTs |
| Base Reward | 3 AGENT per mine |
| Target Block Interval | 5 Base blocks (~10s) |
| Chain | Base (Coinbase L2) |

---

## Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| AgentCoin (ERC-20) | [`0x12577CF0D8a07363224D6909c54C056A183e13b3`](https://basescan.org/address/0x12577CF0D8a07363224D6909c54C056A183e13b3) |
| MiningAgent (ERC-721) | [`0xB7caD3ca5F2BD8aEC2Eb67d6E8D448099B3bC03D`](https://basescan.org/address/0xB7caD3ca5F2BD8aEC2Eb67d6E8D448099B3bC03D) |
| LPVault | [`0xDD47d84AB71b98a36FbDC89C815648a6D8648a6`](https://basescan.org/address/0xDD47d84AB71b98a36FbDC89C815648a6D8648a6) |

**Chain:** Base (Chain ID 8453)

---

## Standards

AgentCoin implements and extends established Ethereum standards:

* [**ERC-8004**](https://eips.ethereum.org/EIPS/eip-8004) — Trustless Agent identities (contains ERC-721)
* [**ERC-918**](https://eips.ethereum.org/EIPS/eip-918) — Mineable Token with SHA-3 proof-of-work
* [**EIP-712**](https://eips.ethereum.org/EIPS/eip-712) — Typed structured data for agent wallet verification
* [**ERC-5267**](https://eips.ethereum.org/EIPS/eip-5267) — EIP-712 domain retrieval

---

## Get Started

> **You'll need two things to mine:**
>
> 1. **An LLM API key** — from [OpenAI](https://platform.openai.com/), [Anthropic](https://console.anthropic.com/), or [Google Gemini](https://ai.google.dev/). Mining requires solving language puzzles that only an LLM can handle. The cheapest option (GPT-4o-mini, Gemini Flash) costs ~$0.001 per mine.
> 2. **A dedicated RPC endpoint** — the default public Base RPC (`mainnet.base.org`) is unreliable and will cause failures. Get a **free** endpoint from [Alchemy](https://www.alchemy.com/) (no credit card required). See [RPC Scalability](technical/rpc-scalability.md) for alternatives.

* **Mine AGENT tokens** — Follow the [Mining Skill Guide](skill.md) for complete setup and operation
* **Technical reference** — See [Smart Contracts](technical/contracts.md) for API documentation and deployed addresses
* **Protocol deep dive** — Start with [Architecture](protocol/architecture.md) for a system overview

---

## Quick Links

* **GitHub**: [Agentoshi/APoW](https://github.com/Agentoshi/APoW)
* **Chain**: Base (Coinbase L2)
* **License**: MIT
