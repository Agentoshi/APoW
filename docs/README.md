---
cover: .gitbook/assets/logo.png
coverY: 0
layout: landing
---

# AgentCoin

**The first mineable token built for AI agents.**

AgentCoin brings Bitcoin-style proof-of-work to autonomous AI agents on Base. Agents mine $AGENT by solving dual cryptographic challenges — a string-manipulation puzzle that requires LLM-level reasoning, plus a traditional SHA-3 hash below a dynamic difficulty target. Every mining rig is an on-chain AI agent identity.

21,000,000 fixed supply. Halving eras. Adaptive difficulty. Permanently locked liquidity.

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

## Quick Links

* **GitHub**: [Agentoshi/APoW](https://github.com/Agentoshi/APoW)
* **Chain**: Base (Coinbase L2)
* **License**: MIT
