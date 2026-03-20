# AgentCoin (APoW Protocol)

Agentic Proof of Work — a mineable ERC-20 token on Base L2 where AI agents prove computational work through SMHL (Show Me Human Language) challenges. 10k ERC-721 Mining Rigs with on-chain generative art. Liquidity eternally locked via UNCX. Fully immutable after ownership renunciation.

## Repo Structure

```
agentcoin/
├── contracts/          # Foundry project (Solidity 0.8.26, Cancun EVM, via_ir)
│   ├── src/
│   │   ├── AgentCoin.sol         # ERC-20 token — 21M supply, embedded PoW mining
│   │   ├── MiningAgent.sol       # ERC-721 + ERC-8004 miner NFTs — 10k supply, SMHL mint
│   │   ├── LPVault.sol           # ETH accumulator → Uniswap V3 LP → UNCX eternal lock
│   │   ├── lib/MinerArt.sol      # On-chain 16x16 pixel art SVG generation
│   │   └── interfaces/           # IAgentCoin.sol, IMiningAgent.sol
│   ├── test/                     # 231 tests across 12 suites (unit, edge, integration, simulation, security, fork)
│   │   ├── AgentCoin.t.sol
│   │   ├── AgentCoinEdge.t.sol
│   │   ├── MiningAgent.t.sol
│   │   ├── MiningAgentEdge.t.sol
│   │   ├── LPVault.t.sol
│   │   ├── LPVaultEdge.t.sol
│   │   ├── LPVaultFork.t.sol     # Fork tests (require --fork-url $BASE_RPC)
│   │   ├── LPSecurity.t.sol
│   │   ├── MinerArtEdge.t.sol
│   │   ├── Integration.t.sol
│   │   ├── RenounceImmutability.t.sol
│   │   └── Simulation.t.sol
│   ├── script/
│   │   ├── Deploy.s.sol          # Step 1: Deploy + cross-wire all 3 contracts
│   │   ├── DeployLP.s.sol        # Step 6: Quote swap + deploy LP + UNCX lock
│   │   ├── AddLiquidity.s.sol    # Step 7b: Add accumulated ETH to UNCX position
│   │   └── Renounce.s.sol        # Step 8: Renounce ownership (IRREVERSIBLE)
│   ├── foundry.toml              # solc 0.8.26, optimizer 200 runs, via_ir, cancun
│   └── lib/                      # forge-std, openzeppelin-contracts
├── miner/                        # TypeScript mining client (viem, commander, dotenv)
│   ├── src/
│   │   ├── index.ts              # CLI entry (mint, mine, stats commands)
│   │   ├── config.ts             # Env var loader + validation
│   │   ├── detect.ts             # Chain/contract auto-detection
│   │   ├── errors.ts             # Error classification and handling
│   │   ├── explorer.ts           # Block explorer URL generation
│   │   ├── miner.ts              # Mining loop (nonce grinding + SMHL solving)
│   │   ├── mint.ts               # Mint workflow (SMHL challenge → submit tx)
│   │   ├── preflight.ts          # Pre-mine validation checks
│   │   ├── smhl.ts               # SMHL solver (OpenAI/Anthropic/Ollama/Gemini)
│   │   ├── stats.ts              # On-chain stats reader
│   │   ├── ui.ts                 # Terminal UI formatting
│   │   └── wallet.ts             # Viem wallet client setup
│   └── package.json              # private:true (not yet published)
├── docs/                         # Protocol documentation
│   ├── DEPLOY_PLAN.md            # 10-step mainnet deployment runbook (self-contained)
│   ├── protocol/                 # Architecture, tokenomics, mining, difficulty, liquidity
│   └── technical/                # Contracts, security, deployment, RPC scalability
├── SPEC.md                       # Full implementation specification
└── README.md                     # Project overview
```

## Tech Stack

- **Contracts:** Solidity 0.8.26, Foundry (forge/cast/anvil), OpenZeppelin 5.x, Cancun EVM
- **Miner:** TypeScript, viem, commander, dotenv, OpenAI/Anthropic/Ollama SDKs
- **Network:** Base L2 (Chain ID: 8453)
- **External deps:** Uniswap V3 (PositionManager, SwapRouter, Factory), UNCX V3 Locker, WETH, USDC

## Running Tests

```bash
# Unit + integration tests (no network needed)
cd contracts && forge test

# Fork tests (requires Base mainnet RPC — tests real Uniswap/UNCX integration)
forge test --match-path test/LPVaultFork.t.sol --fork-url $BASE_RPC -vvv

# Build miner
cd miner && npm run build
```

## Current State

- **Contracts:** Code-complete. 231/231 tests passing. SMHL retuned to tolerant verification (length ±5, words ±2, char anywhere). Deployed to Base Sepolia — 9 on-chain mines verified across 12 LLM providers. Contracts verified on Sepolia Basescan.
- **Fork tests:** 9 tests verifying real Uniswap V3 + UNCX integration on Base mainnet.
- **Miner client:** Functional but pre-release (private:true, no unit tests, no npm publish). Tested with 12 LLM providers (OpenAI, Anthropic, Gemini, Ollama models).
- **Docs:** Comprehensive — competitive mining model, multi-wallet scaling strategies, ERC-8004 transfer semantics, full deployment runbook. All docs audited for accuracy.
- **Deployment:** NOT deployed. Mainnet-ready pending deploy command. Deploy only on explicit user command.

## Critical Safety Rules

1. **NEVER deploy without explicit user command.** Deploy scripts are irreversible. The orchestrator must confirm project name + target before executing any forge script.

2. **NEVER modify `contracts/src/` without running the full test suite.** Always run `forge test` after any contract change. All tests must pass (currently 231).

3. **Fork tests require `--fork-url`.** Without it, the `onlyFork` modifier causes tests to silently skip (returning ~3000 gas instead of real execution). Always verify gas costs are in the hundreds of thousands.

4. **Deploy is IRREVERSIBLE after Renounce (Step 8).** The Renounce script sets all owners to address(0). No admin functions can ever be called again. No upgrades. No rollback. By design.

5. **Never auto-execute deploy scripts.** `Deploy.s.sol`, `DeployLP.s.sol`, and `Renounce.s.sol` are one-shot scripts that spend real ETH and create permanent on-chain state.

6. **Secrets are sacred.** Never read or echo `.env` files, private keys, or API keys. Use `$ENV_VAR` references only.

7. **The Renounce safety check:** `Renounce.s.sol` requires `lpVault.lpDeployed() == true`. Without this, renouncing would brick `deployLP()` (which is `onlyOwner`), permanently locking the 2.1M AGENT LP reserve and any vault ETH.

## Key Contract Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Total supply | 21,000,000 AGENT | Fixed at construction |
| LP reserve | 2,100,000 AGENT | Minted to LPVault in AgentCoin constructor |
| Mineable supply | 18,900,000 AGENT | MAX_SUPPLY - LP_RESERVE |
| Base reward | 3 AGENT/mine | Decays 10% per 500k mines |
| NFT supply | 10,000 | MiningAgent cap |
| LP threshold | 4.9 ETH | Plus 0.03 ETH UNCX fee = 4.93 ETH minimum |
| Add liquidity threshold | 0.1 ETH | Minimum for addLiquidity() — below this, gas exceeds value |
| Fee tier | 0.3% (3000) | Uniswap V3 |
| UNCX lock | Eternal | type(uint256).max |
| Difficulty adjustment | Every 64 mines | Targets 1 mine per 5 Base blocks |
| SMHL challenge window | 20 seconds | For both mint and mine |
| SMHL verification | length ±5, words ±2, char anywhere | Tolerant — any LLM passes first attempt |

## Miner Client Gaps (Pre-Release)

| Gap | Priority | Description |
|-----|----------|-------------|
| No unit tests | HIGH | SMHL solver, nonce grinding, config parsing, error classification untested |
| npm publish safety | LOW | `private: true` now set — remove before npm publish, add full package metadata |
| No ABI verification | MEDIUM | miner/src/abi/ may drift from compiled contract ABIs |
| No gas config | LOW | No maxPriorityFee override for congested network |
| No CI | LOW | No GitHub Actions for `forge test` on PRs |
| No npm publish | LOW | No automated build + publish workflow |
| Default addresses | BLOCKED | Can't set DEFAULT_MINING_AGENT_ADDRESS / DEFAULT_AGENT_COIN_ADDRESS until deployed |
