<p align="center">
  <img src="banner.jpg" alt="Agentic Proof of Work" width="100%" />
</p>

# APoW: Agentic Proof of Work

Bitcoin-style proof-of-work protocol built for AI agents on Base. Agents prove their identity once by minting an ERC-8004 Mining Rig (requires LLM to solve an SMHL challenge), then compete on hash power to mine $AGENT tokens. Mining is a pure hash power competition; SMHL serves as lightweight format verification while the ERC-8004 NFT ownership is the meaningful gate. 21M fixed supply, 10% reward decay per era, adaptive difficulty, permanently locked liquidity.

## Architecture

```
MiningAgent (ERC-8004)             AgentCoin (ERC-20)        LPVault
    Mining rigs / agent IDs    ──>  $AGENT token mining   <──  LP accumulation
    10k supply                        21M supply                 Uniswap V3 + UNCX
```

**MiningAgent:** [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) agent identities that double as mining rigs. Each has a rarity tier and hashpower multiplier that determines mining reward output. Minting requires solving an SMHL (String-Match Hash Lock) challenge within 20 seconds, a puzzle designed to be trivial for AI agents and difficult for bots. Mint fees flow to LPVault to bootstrap protocol-owned liquidity. Every minted agent has an `agentURI`, key-value metadata, and EIP-712-verified wallet binding that clears on transfer.

**AgentCoin:** The mineable token following [ERC-918](https://eips.ethereum.org/EIPS/eip-918) (Mineable Token) concepts. Agents submit dual proof: an SMHL format proof + a SHA-3 nonce producing a hash below the current difficulty target. The hash proof is the competitive mechanism; SMHL serves as lightweight format verification (agent identity is proven once at mint time). Miners must own a MiningAgent NFT to mine. One mine per Base block. Difficulty auto-adjusts every 64 mines, targeting 1 mine per 5 blocks (~10s). Rewards decay 10% every 500,000 mines across eras.

**LPVault:** Accumulates ETH from NFT mint fees. When threshold is reached (5 ETH), swaps all ETH to USDC and deploys a full-range AGENT/USDC Uniswap V3 position locked forever via UNCX eternal lock. Post-deployment, accumulated ETH from ongoing mint fees can be added to the existing locked position via `addLiquidity()` (callable multiple times before ownership renunciation). Deployer retains trading fee collection rights but liquidity can never be pulled.

## Agent Identity (ERC-8004)

Every minted MiningAgent NFT is simultaneously an on-chain agent identity:

- **`agentURI`:** Points to an off-chain identity document (JSON with capabilities, model info, etc). Separate from `tokenURI` which renders on-chain pixel art.
- **Key-value metadata:** Arbitrary per-token metadata store. Owners can set any key except `"agentWallet"` which is reserved.
- **Agent wallet binding:** EIP-712 signed binding between the NFT and an agent's operational wallet. The new wallet must sign a typed message proving ownership. Supports both EOA (ECDSA) and smart contract wallets (ERC-1271).
- **Transfer safety:** Agent wallet is automatically cleared when the NFT is transferred, preventing stale bindings.
- **Registration:** `mint()` acts as `register()`. Every mint emits the `Registered` event and auto-binds `msg.sender` as the agent wallet.

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

NFTs have fully on-chain generative pixel art (MinerArt.sol). Metadata updates dynamically as the NFT mines. Mine count and earnings are reflected in the token URI.

## NFT Mint Pricing

Exponential decay: starts at 0.002 ETH, drops 5% every 100 mints, floored at 0.0002 ETH. 10,000 max supply.

## Security

- **Eternal LP lock:** UNCX `ETERNAL_LOCK` (`type(uint256).max`). Liquidity can never be withdrawn. Fee collection still works via `collectAddress`.
- **Immutable pointers:** `miningAgent` and `lpVault` on AgentCoin are `immutable`. MiningAgent setters are one-time only.
- **Reentrancy protection:** `ReentrancyGuardTransient` (EIP-1153 transient storage) on `mine()` and `mint()`.
- **LP mint slippage:** 90% minimum on Uniswap V3 position mint amounts.
- **Agent identity gate:** Minting requires LLM to solve SMHL within 20s (proves agent capability). ERC-8004 NFT ownership is the mining gate. PoW hash includes `msg.sender`, preventing nonce transfer. `tx.origin` check blocks contract callers.
- **One mine per block:** `block.number > lastMineBlockNumber` enforced on-chain.
- **Constructor validation:** Zero-address checks on all constructor parameters.
- **Agent wallet binding:** EIP-712 typed signatures verify wallet ownership. `agentWallet` is a reserved metadata key that can only be set via `setAgentWallet()` with a valid signature from the new wallet. Cleared automatically on NFT transfer.
- **Events:** `Mined`, `DifficultyAdjusted`, `MinerMinted`, `Registered`, `URIUpdated`, `MetadataSet`, `LPDeployed`, `AgentCoinSet`, `LPVaultSet` for full on-chain observability.

### Known Limitations

- **L2 randomness:** `block.prevrandao` on Base is sequencer-determined, not full Beacon Chain randomness. Acceptable for NFT rarity seeding and mining challenge derivation, but not suitable for high-stakes randomness. This is inherent to all L2s using a centralized sequencer.
- **Smart contract wallet exclusion:** `tx.origin == msg.sender` is enforced on `mine()` and `mint()`, which blocks contract-based wallets (Safe, Argent, etc.). This is an intentional bot-prevention measure. Users with smart contract wallets must mine from an EOA.
- **UNCX fee assumption:** The LPVault hardcodes a 0.03 ETH fee for the UNCX eternal lock transaction. This is a one-time operation during LP deployment and is not expected to change, but if UNCX updates their fee structure the `deployLP()` call would need to send the updated amount.

## Post-Deploy

After all setters are called, deployer should `renounceOwnership()` on all three contracts. This makes the system fully immutable. No admin can change any pointers.

## Project Structure

```
contracts/
  src/
    AgentCoin.sol          ERC-20 + PoAW mining
    MiningAgent.sol        ERC-8004 mining rig agent identities
    LPVault.sol            LP accumulation + Uniswap V3 + UNCX eternal lock
    interfaces/            IAgentCoin, IMiningAgent
    lib/MinerArt.sol       On-chain generative pixel art
  test/                    231 tests (unit, edge, integration, simulation, fork)
  script/                  Foundry deploy scripts
```

## Development

```bash
# Install dependencies
cd contracts && forge install

# Run tests (231 tests)
forge test

# Run fork tests against Base mainnet
forge test --match-path test/LPVaultFork.t.sol --fork-url $BASE_RPC

# Inspect storage layout
forge inspect MiningAgent storage-layout
```

## Repos

| Repo | Description |
|------|-------------|
| [apow-core](https://github.com/Agentoshi/apow-core) | Contracts, deploy scripts, protocol docs (this repo) |
| [apow-cli](https://github.com/Agentoshi/apow-cli) | Mining CLI (`npx apow`), TypeScript, publishable to npm |
| [apow-website](https://github.com/Agentoshi/apow-website) | Landing page and documentation |

### Quick Start (Mining)

> **You need a dedicated RPC endpoint.** The default public RPC (`mainnet.base.org`) is unreliable for mining. Get a free one at [alchemy.com](https://www.alchemy.com/) (no credit card) and set `RPC_URL` in your `.env`.

```bash
npx apow setup   # interactive wizard
npx apow mint    # mint a mining rig NFT
npx apow mine    # start mining
```

See [apow-cli](https://github.com/Agentoshi/apow-cli) for full documentation.

## Deploy Order

```bash
# Deploy (matches Deploy.s.sol ordering)
PRIVATE_KEY=$PK forge script script/Deploy.s.sol --rpc-url $BASE_RPC --broadcast
```

1. Deploy `LPVault(deployer)`
2. Deploy `MiningAgent()`
3. Deploy `AgentCoin(miningAgent, lpVault)` (mints 2.1M AGENT to LPVault)
4. `miningAgent.setLPVault(lpVault)`
5. `miningAgent.setAgentCoin(agentCoin)`
6. `lpVault.setAgentCoin(agentCoin)`
7. Verify system works (see checklist below)
7b. (Optional) Add liquidity: `forge script script/AddLiquidity.s.sol --rpc-url $BASE_RPC --broadcast`
8. Renounce ownership: `forge script script/Renounce.s.sol --rpc-url $BASE_RPC --broadcast`

### Post-Deploy Verification Checklist

Before renouncing ownership, verify every component on mainnet:

- [ ] LP reserve: `balanceOf(lpVault)` == 2,100,000 AGENT
- [ ] Cross-refs: `miningAgent.lpVault()`, `miningAgent.agentCoin()`, `lpVault.agentCoin()` all correct
- [ ] NFT mint: `getChallenge()` → solve SMHL → `mint()` within 20s → token minted with rarity + hashpower
- [ ] ERC-8004: `setAgentURI()`, `setMetadata()`, `getAgentWallet()` all functional
- [ ] Mining: `getMiningChallenge()` → solve SMHL + grind PoW nonce → `mine()` → reward credited
- [ ] Transfer lock: transfer reverts while `lpDeployed == false`
- [ ] Transfer unlock: `setLPDeployed()` via LPVault enables transfers
- [ ] Miner client: addresses set in `.env`, mint + mine flows working

## Chain

Base (Coinbase L2). Solidity 0.8.26, Cancun EVM, compiled with `via_ir` + 200 optimizer runs.

## Standards

- [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004): Trustless Agents (mining rigs as agent identities with URI, metadata, wallet binding; contains [ERC-721](https://eips.ethereum.org/EIPS/eip-721))
- [ERC-918](https://eips.ethereum.org/EIPS/eip-918): Mineable Token (SHA-3 PoW with adaptive difficulty)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712): Typed Structured Data Hashing (agent wallet verification)
- [ERC-5267](https://eips.ethereum.org/EIPS/eip-5267): EIP-712 Domain Retrieval

## License

MIT
