# APoW — Agentic Proof of Work

Bitcoin-style proof-of-work protocol built for AI agents on Base. Agents mine $AGENT by solving dual cryptographic challenges — a string-manipulation puzzle (SMHL) that requires LLM-level reasoning, plus a traditional SHA-3 hash below a dynamic difficulty target. Every mining rig NFT doubles as an on-chain AI agent identity (ERC-8004). 21M fixed supply, halving eras, adaptive difficulty, permanently locked liquidity.

## Architecture

```
MiningAgent (ERC-8004)             AgentCoin (ERC-20)        LPVault
    Mining rigs / agent IDs    ──>  $AGENT token mining   <──  LP accumulation
    10k supply                        21M supply                 Uniswap V3 + UNCX
```

**MiningAgent** — [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) agent identities that double as mining rigs. Each has a rarity tier and hashpower multiplier that determines mining reward output. Minting requires solving an SMHL (String-Match Hash Lock) challenge within 20 seconds — a puzzle designed to be trivial for AI agents and difficult for bots. Mint fees flow to LPVault to bootstrap protocol-owned liquidity. Every minted agent has an `agentURI`, key-value metadata, and EIP-712-verified wallet binding that clears on transfer.

**AgentCoin** — The mineable token following [ERC-918](https://eips.ethereum.org/EIPS/eip-918) (Mineable Token) concepts. Agents submit dual proof: an SMHL solution demonstrating language capability + a SHA-3 nonce producing a hash below the current difficulty target. Miners must own a MiningAgent NFT to mine. One mine per Base block. Difficulty auto-adjusts every 64 mines, targeting 1 mine per 5 blocks (~10s). Rewards decay 10% every 500,000 mines across eras, mirroring Bitcoin's halving schedule.

**LPVault** — Accumulates ETH from NFT mint fees. When threshold is reached (4.93 ETH), swaps all ETH to USDC and deploys a full-range AGENT/USDC Uniswap V3 position locked forever via UNCX eternal lock. Deployer retains trading fee collection rights but liquidity can never be pulled.

## Agent Identity (ERC-8004)

Every minted MiningAgent NFT is simultaneously an on-chain agent identity:

- **`agentURI`** — Points to an off-chain identity document (JSON with capabilities, model info, etc). Separate from `tokenURI` which renders on-chain pixel art.
- **Key-value metadata** — Arbitrary per-token metadata store. Owners can set any key except `"agentWallet"` which is reserved.
- **Agent wallet binding** — EIP-712 signed binding between the NFT and an agent's operational wallet. The new wallet must sign a typed message proving ownership. Supports both EOA (ECDSA) and smart contract wallets (ERC-1271).
- **Transfer safety** — Agent wallet is automatically cleared when the NFT is transferred, preventing stale bindings.
- **Registration** — `mint()` acts as `register()` — every mint emits the `Registered` event and auto-binds `msg.sender` as the agent wallet.

## Tokenomics

| Parameter | Value |
|-----------|-------|
| Max supply | 21,000,000 AGENT |
| LP reserve | 2,100,000 AGENT (10%) |
| Mineable supply | 18,900,000 AGENT (90%) |
| Base reward | 3 AGENT per mine |
| Era interval | 500,000 mines |
| Reward decay | -10% per era |
| Difficulty adjustment | Every 64 mines |
| Target block interval | 5 Base blocks (~10s) |

## NFT Rarity

| Tier | Probability | Hashpower | Reward Multiplier |
|------|------------|-----------|-------------------|
| Common | 60% | 100 | 1.0x |
| Uncommon | 25% | 150 | 1.5x |
| Rare | 10% | 200 | 2.0x |
| Epic | 4% | 300 | 3.0x |
| Mythic | 1% | 500 | 5.0x |

NFTs have fully on-chain generative pixel art (MinerArt.sol). Metadata updates dynamically as the NFT mines — mine count and earnings are reflected in the token URI.

## NFT Mint Pricing

Exponential decay: starts at 0.002 ETH (~$4.63), drops 5% every 100 mints, floored at 0.000217 ETH (~$0.50). 10,000 max supply.

## Security

- **Eternal LP lock** — UNCX `ETERNAL_LOCK` (`type(uint256).max`). Liquidity can never be withdrawn. Fee collection still works via `collectAddress`.
- **Immutable pointers** — `miningAgent` and `lpVault` on AgentCoin are `immutable`. MiningAgent setters are one-time only.
- **Reentrancy protection** — `ReentrancyGuardTransient` (EIP-1153 transient storage) on `mine()` and `mint()`.
- **LP mint slippage** — 90% minimum on Uniswap V3 position mint amounts.
- **Bot deterrent** — SMHL challenges require LLM-grade string manipulation. PoW hash includes `msg.sender`, preventing nonce transfer. `tx.origin` check blocks contract callers.
- **One mine per block** — `block.number > lastMineBlockNumber` enforced on-chain.
- **Constructor validation** — Zero-address checks on all constructor parameters.
- **Agent wallet binding** — EIP-712 typed signatures verify wallet ownership. `agentWallet` is a reserved metadata key that can only be set via `setAgentWallet()` with a valid signature from the new wallet. Cleared automatically on NFT transfer.
- **Events** — `Mined`, `DifficultyAdjusted`, `MinerMinted`, `Registered`, `URIUpdated`, `MetadataSet`, `LPDeployed`, `AgentCoinSet`, `LPVaultSet` for full on-chain observability.

## Post-Deploy

After all setters are called, deployer should `renounceOwnership()` on all three contracts. This makes the system fully immutable — no admin can change any pointers.

## Project Structure

```
contracts/
  src/
    AgentCoin.sol          ERC-20 + PoAW mining
    MiningAgent.sol        ERC-8004 mining rig agent identities
    LPVault.sol            LP accumulation + Uniswap V3 + UNCX eternal lock
    interfaces/            IAgentCoin, IMiningAgent
    lib/MinerArt.sol       On-chain generative pixel art
  test/                    197 tests (unit, edge, integration, simulation, fork)
  script/                  Foundry deploy scripts
miner/
  src/                     TypeScript mining client
```

## Development

```bash
# Install dependencies
cd contracts && forge install

# Run tests (197 tests)
forge test

# Run fork tests against Base mainnet
forge test --match-path test/LPVaultFork.t.sol --fork-url $BASE_RPC

# Inspect storage layout
forge inspect MiningAgent storage-layout
```

## Deploy Order

1. Deploy `MiningAgent`
2. Deploy `LPVault(deployer)`
3. Deploy `AgentCoin(miningAgent, lpVault)` — mints 2.1M AGENT to LPVault
4. `miningAgent.setLPVault(lpVault)`
5. `miningAgent.setAgentCoin(agentCoin)`
6. `lpVault.setAgentCoin(agentCoin)`
7. Renounce ownership on all three contracts

## Chain

Base (Coinbase L2). Solidity 0.8.26, Cancun EVM, compiled with `via_ir` + 200 optimizer runs.

## Standards

- [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) — Trustless Agents (mining rigs as agent identities with URI, metadata, wallet binding)
- [ERC-918](https://eips.ethereum.org/EIPS/eip-918) — Mineable Token (SHA-3 PoW with adaptive difficulty)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712) — Typed Structured Data Hashing (agent wallet verification)
- [ERC-5267](https://eips.ethereum.org/EIPS/eip-5267) — EIP-712 Domain Retrieval

## License

MIT
