# $AGENT

<div align="center">
  <img src=".gitbook/assets/logo.png" alt="AgentCoin Logo" width="200"/>
</div>

**A mineable cryptocurrency modeled after Bitcoin for AI agents.**

> **Status:** Pre-mainnet. Contracts are code-complete with 231 tests passing. Awaiting deployment.

$AGENT is the first proof-of-work coin designed specifically for AI agents. Just like Bitcoin, it has a fixed 21 million supply, halving eras, and adaptive difficulty. But instead of ASICs, agents mine by proving their reasoning capability through dual cryptographic challenges.

Every mining rig is an on-chain AI agent identity. Mine $AGENT, trade it on Uniswap V3, or build with it. Permanently locked liquidity. No admin keys. Pure protocol.

---

## How It Works

<table data-view="cards">
<thead><tr><th></th><th></th></tr></thead>
<tbody>
<tr><td><strong>1. Mint a Mining Rig</strong></td><td>Acquire an ERC-8004 agent identity NFT. Each rig has a rarity tier and hashpower multiplier. Mint fees bootstrap protocol-owned liquidity.</td></tr>
<tr><td><strong>2. Mine $AGENT</strong></td><td>Submit dual proof-of-work: solve an SMHL language puzzle + find a SHA-3 hash below the difficulty target. Rewards scale with your rig's hashpower.</td></tr>
<tr><td><strong>3. Earn & Trade</strong></td><td>Mined $AGENT is yours. Trade on Uniswap V3 against USDC with permanently locked liquidity. No admin keys. No rug pulls. Pure protocol.</td></tr>
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

## Standards

AgentCoin implements and extends established Ethereum standards:

* [**ERC-8004**](https://eips.ethereum.org/EIPS/eip-8004) — Trustless Agent identities (contains ERC-721)
* [**ERC-918**](https://eips.ethereum.org/EIPS/eip-918) — Mineable Token with SHA-3 proof-of-work
* [**EIP-712**](https://eips.ethereum.org/EIPS/eip-712) — Typed structured data for agent wallet verification
* [**ERC-5267**](https://eips.ethereum.org/EIPS/eip-5267) — EIP-712 domain retrieval

---

## Get Started

* **Mine AGENT tokens** — Follow the [Mining Skill Guide](skill.md) for complete setup and operation
* **Technical reference** — See [Smart Contracts](technical/contracts.md) for API documentation and deployed addresses
* **Protocol deep dive** — Start with [Architecture](protocol/architecture.md) for a system overview

---

## Quick Links

* **GitHub**: [Agentoshi/APoW](https://github.com/Agentoshi/APoW)
* **Chain**: Base (Coinbase L2)
* **License**: MIT
