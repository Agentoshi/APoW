# Architecture

AgentCoin is a three-contract system deployed on Base. Each contract has a single responsibility, and once configured, the entire system is fully immutable: no admin keys, no upgradability, no governance.

---

## System Overview

```
MiningAgent (ERC-8004)             AgentCoin (ERC-20)             LPVault
Mining rigs / agent IDs      ──>   $AGENT token mining      <──   LP accumulation
10k supply                          21M supply                     Uniswap V3 + UNCX
```

---

## Contracts

### MiningAgent

The NFT contract. Every mining rig is an [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) agent identity, a standard that extends ERC-721 with agent-specific capabilities like identity URIs, key-value metadata, and cryptographically verified wallet bindings.

Minting requires solving an SMHL (String-Match Hash Lock) challenge within 20 seconds. All mint fees flow directly to LPVault.

**Key properties:**
- 10,000 max supply
- 5 rarity tiers with hashpower multipliers (1x–5x)
- Fully on-chain generative pixel art
- Mint fees forwarded to LPVault in the same transaction

### AgentCoin

The ERC-20 token with built-in proof-of-work mining. Follows [ERC-918](https://eips.ethereum.org/EIPS/eip-918) (Mineable Token) concepts with a dual-proof system: miners submit an SMHL format proof and a SHA-3 hash below the current difficulty target. The hash proof is the competitive mechanism; SMHL serves as lightweight format verification (agents prove identity once at mint time via their ERC-8004 Mining Rig).

**Key properties:**
- 21,000,000 fixed supply (18.9M mineable + 2.1M LP reserve)
- Bitcoin-style competitive mining, one winner per block
- Adaptive difficulty targeting 1 mine per 5 Base blocks (~10s)
- 10% reward decay every 500,000 mines

### LPVault

Accumulates ETH from mint fees. When the threshold is reached, it converts all ETH to USDC and deploys a full-range AGENT/USDC Uniswap V3 position, permanently locked via UNCX eternal lock.

**Key properties:**
- Automated LP deployment at 5 ETH threshold
- AGENT/USDC pair (not AGENT/WETH)
- UNCX eternal lock, liquidity can never be withdrawn
- Deployer retains trading fee collection rights only

---

## Data Flow

```
Minter                MiningAgent              LPVault              Uniswap V3
  │                       │                       │                     │
  ├── solve SMHL ────────>│                       │                     │
  ├── mint{ETH} ─────────>│                       │                     │
  │                       ├── forward ETH ───────>│                     │
  │                       ├── mint NFT            │                     │
  │                       │                       │                     │
  │                       │              (threshold reached)            │
  │                       │                       ├── wrap ETH → WETH   │
  │                       │                       ├── swap WETH → USDC  │
  │                       │                       ├── create pool ─────>│
  │                       │                       ├── add liquidity ───>│
  │                       │                       ├── lock via UNCX     │
```

```
Miner                 AgentCoin               MiningAgent
  │                       │                       │
  ├── getMiningChallenge()│                       │
  │<── challenge + target │                       │
  ├── solve SMHL          │                       │
  ├── find nonce          │                       │
  ├── mine(nonce, sol, id)│                       │
  │                       ├── verify ownerOf(id)─>│
  │                       │<── owner address ─────│
  │                       ├── verify SMHL         │
  │                       ├── verify hash < target│
  │                       ├── mint reward to miner│
  │                       ├── rotate challenge    │
  │                       ├── adjust difficulty?  │
```

---

## Immutability

After deployment and configuration, ownership is renounced on all three contracts. The system becomes fully autonomous:

| Contract | Admin Functions | Post-Renounce |
|----------|----------------|---------------|
| MiningAgent | `setAgentCoin`, `setLPVault` | One-time only, then locked |
| AgentCoin | None | Immutable from deploy |
| LPVault | `setAgentCoin` | One-time only, then locked |

No upgrades. No pauses. No parameter changes. The protocol runs exactly as deployed, forever.
