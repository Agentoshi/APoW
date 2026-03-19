# APoW Protocol — Mainnet Deployment Runbook

**Operator:** Agentoshi (deployer wallet)
**Network:** Base Mainnet (Chain ID: 8453)
**One-time use. Irreversible after Step 8.**

This document is self-contained. If all other context is lost, reading this file alone is sufficient to execute deployment correctly.

---

## Prerequisites

- [ ] **Foundry** installed (`forge`, `cast`, `anvil` available in PATH)
- [ ] **Node.js** 18+ via nvm, with the miner CLI built (`cd miner && npm run build`)
- [ ] **Deployer wallet** funded with sufficient ETH on Base:
  - ~0.01 ETH for contract deployments (3 contracts + cross-wiring)
  - ~0.002 ETH for smoke-test mint
  - Gas for DeployLP and Renounce scripts
  - **Total: ~0.05 ETH minimum in deployer wallet (excludes LP funding)**
- [ ] **Basescan API key** for contract verification (https://basescan.org/myapikey)
- [ ] **LLM API key** for miner SMHL challenges (OpenAI, Anthropic, or local Ollama)
- [ ] All contracts compiled and tests passing: `cd contracts && forge build && forge test`
- [ ] Fork tests passing: `forge test --match-path test/LPVaultFork.t.sol --fork-url $BASE_RPC -vvv`

---

## Environment Setup

Create `.env` in the **project root** (`~/dev/agentcoin/.env`). **Never commit this file.**

```bash
# ──────────────────────────────────────────────
# REQUIRED BEFORE STEP 1 (Contract Deployment)
# ──────────────────────────────────────────────

# Base Mainnet RPC (Alchemy/Infura recommended for reliability)
BASE_RPC=https://mainnet.base.org

# Deployer wallet private key (0x-prefixed, 64 hex chars)
PRIVATE_KEY=0x<deployer-private-key>

# Basescan API key for contract verification
BASESCAN_API_KEY=<basescan-api-key>

# ──────────────────────────────────────────────
# SET AFTER STEP 1 (from deployment output)
# ──────────────────────────────────────────────

# Deployed contract addresses (0x-prefixed, 40 hex chars)
AGENT_COIN_ADDRESS=
MINING_AGENT_ADDRESS=
LP_VAULT_ADDRESS=

# ──────────────────────────────────────────────
# REQUIRED FOR STEPS 3-4 (Smoke Tests via Miner CLI)
# ──────────────────────────────────────────────

# Miner client uses different env var names
MINER_PRIVATE_KEY=<same-as-PRIVATE_KEY-for-smoke-test>
MINER_RPC_URL=https://mainnet.base.org

# LLM for SMHL challenge solving
LLM_PROVIDER=openai
LLM_MODEL=gpt-4o-mini
LLM_API_KEY=<openai-api-key>
# Alternative providers:
# LLM_PROVIDER=anthropic  LLM_API_KEY=<anthropic-key>
# LLM_PROVIDER=ollama     (no key needed, requires local Ollama)

# ──────────────────────────────────────────────
# OPTIONAL
# ──────────────────────────────────────────────

# Explicit chain override (auto-detected from RPC URL if omitted)
# CHAIN=base

# Base Sepolia (testnet only, not used in production)
# BASE_SEPOLIA_RPC=https://sepolia.base.org
```

**Source the env before every forge command:**
```bash
source .env
```

---

## Contract Architecture

```
LPVault (receives ETH from mints, deploys Uniswap V3 LP)
  ↕ setAgentCoin()
AgentCoin (ERC-20, 21M supply, embedded PoW mining)
  ↕ constructor(miningAgent, lpVault)
MiningAgent (ERC-721 + ERC-8004 miner NFTs, 10k supply)
  ↕ setLPVault(), setAgentCoin()
```

**Key constants (hardcoded in contracts, not configurable):**

| Constant | Value | Contract |
|----------|-------|----------|
| MAX_SUPPLY | 21,000,000 AGENT | AgentCoin |
| LP_RESERVE | 2,100,000 AGENT | AgentCoin |
| MINEABLE_SUPPLY | 18,900,000 AGENT | AgentCoin |
| BASE_REWARD | 3 AGENT per mine | AgentCoin |
| LP_DEPLOY_THRESHOLD | 4.9 ETH | LPVault |
| UNCX_FLAT_FEE | 0.03 ETH | LPVault |
| FEE_TIER | 3000 (0.3%) | LPVault |
| ETERNAL_LOCK | type(uint256).max | LPVault |
| WETH | 0x4200000000000000000000000000000000000006 | LPVault |
| USDC | 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 | LPVault |
| SWAP_ROUTER | 0x2626664c2603336E57B271c5C0b26F421741e481 | LPVault |
| POSITION_MANAGER | 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1 | LPVault |
| UNCX_V3_LOCKER | 0x231278eDd38B00B07fBd52120CEf685B9BaEBCC1 | LPVault |
| UNISWAP_V3_FACTORY | 0x33128a8fC17869897dcE68Ed026d694621f6FDfD | LPVault |

---

## Deployment Steps Overview

| Step | Action | Verification | Reversible? |
|------|--------|--------------|-------------|
| 1 | Deploy contracts | All 3 deployed, cross-wired, 2.1M AGENT in vault | Yes (redeploy) |
| 2 | Verify on Basescan | All contracts verified, source readable | N/A |
| 3 | Smoke test: mint 1 NFT | Token #1 minted, fee forwarded to vault | Yes |
| 4 | Smoke test: mine 1 block | 1 mine confirmed, AGENT earned, transfers locked | Yes |
| 5 | Fund LP vault | Vault balance >= 4.93 ETH | No (ETH locked) |
| 6 | Deploy liquidity pool | LP created, UNCX locked, transfers unlocked | No |
| 7 | Verify LP deployment | Uniswap pool visible, UNCX eternal lock confirmed | N/A |
| **8** | **RENOUNCE OWNERSHIP** | **All owners == address(0). POINT OF NO RETURN.** | **NO** |
| 9 | Verify immutability | All admin functions permanently revert | N/A |
| 10 | Publish and announce | Addresses discoverable, miner defaults updated | N/A |

---

### Step 1 — Deploy Contracts

```bash
cd contracts
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

**What this does:**
1. Deploys **LPVault** (constructor arg: deployer address)
2. Deploys **MiningAgent** (no constructor args)
3. Deploys **AgentCoin** (constructor args: miningAgent address, lpVault address — mints 2.1M AGENT to LPVault)
4. Cross-wires:
   - `miningAgent.setLPVault(lpVault)` — one-shot, cannot be changed
   - `miningAgent.setAgentCoin(agentCoin)` — one-shot, cannot be changed
   - `lpVault.setAgentCoin(agentCoin)` — one-shot, cannot be changed
5. Runs post-deploy assertions (all must pass or script reverts)

**The script requires:** `PRIVATE_KEY` env var. Chain ID must be 8453 (Base mainnet).

**Capture deployed addresses from script output:**
```bash
# The script prints: "AgentCoin: 0x...", "MiningAgent: 0x...", "LPVault: 0x..."
# Export them immediately:
export AGENT_COIN_ADDRESS=<from-output>
export MINING_AGENT_ADDRESS=<from-output>
export LP_VAULT_ADDRESS=<from-output>

# Also update .env file with these addresses (needed for later steps)
```

---

### ══════ STOP AND VERIFY ══════

Before proceeding, verify all three contracts deployed correctly:

```bash
# Verify LP reserve (must return 2100000000000000000000000 = 2.1M * 1e18)
cast call $AGENT_COIN_ADDRESS "balanceOf(address)(uint256)" $LP_VAULT_ADDRESS --rpc-url $BASE_RPC

# Verify lpDeployed is false (must return 0x...0 = false)
cast call $AGENT_COIN_ADDRESS "lpDeployed()(bool)" --rpc-url $BASE_RPC
cast call $LP_VAULT_ADDRESS "lpDeployed()(bool)" --rpc-url $BASE_RPC

# Verify ownership (must return deployer address)
cast call $AGENT_COIN_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
cast call $MINING_AGENT_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
cast call $LP_VAULT_ADDRESS "owner()(address)" --rpc-url $BASE_RPC

# Verify cross-pointers
cast call $MINING_AGENT_ADDRESS "lpVault()(address)" --rpc-url $BASE_RPC
# Expected: $LP_VAULT_ADDRESS

cast call $MINING_AGENT_ADDRESS "agentCoin()(address)" --rpc-url $BASE_RPC
# Expected: $AGENT_COIN_ADDRESS

cast call $LP_VAULT_ADDRESS "agentCoin()(address)" --rpc-url $BASE_RPC
# Expected: $AGENT_COIN_ADDRESS

cast call $AGENT_COIN_ADDRESS "miningAgent()(address)" --rpc-url $BASE_RPC
# Expected: $MINING_AGENT_ADDRESS

cast call $AGENT_COIN_ADDRESS "lpVault()(address)" --rpc-url $BASE_RPC
# Expected: $LP_VAULT_ADDRESS
```

**If ANY value is wrong:** STOP. Cross-pointers are one-shot (`require(x == address(0), "Already set")`). If a pointer is wrong, you must redeploy ALL contracts from scratch. See [Rollback Procedures](#rollback-procedures).

---

### Step 2 — Verify on Basescan

If `--verify` succeeded in Step 1, check each contract:
- `https://basescan.org/address/$AGENT_COIN_ADDRESS#code`
- `https://basescan.org/address/$MINING_AGENT_ADDRESS#code`
- `https://basescan.org/address/$LP_VAULT_ADDRESS#code`

**MiningAgent** uses the `MinerArt` library via `via_ir` compilation. If auto-verify failed:

```bash
# Get library address from deployment artifacts
MINER_ART_ADDRESS=$(jq -r '.libraries[0]' contracts/broadcast/Deploy.s.sol/8453/run-latest.json 2>/dev/null || echo "<check broadcast artifacts>")

forge verify-contract $MINING_AGENT_ADDRESS MiningAgent \
  --rpc-url $BASE_RPC \
  --etherscan-api-key $BASESCAN_API_KEY \
  --libraries src/lib/MinerArt.sol:MinerArt:$MINER_ART_ADDRESS \
  --root /Users/aklo/dev/agentcoin/contracts

# For AgentCoin and LPVault (if auto-verify also failed):
forge verify-contract $AGENT_COIN_ADDRESS AgentCoin \
  --rpc-url $BASE_RPC \
  --etherscan-api-key $BASESCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address,address)" $MINING_AGENT_ADDRESS $LP_VAULT_ADDRESS) \
  --root /Users/aklo/dev/agentcoin/contracts

forge verify-contract $LP_VAULT_ADDRESS LPVault \
  --rpc-url $BASE_RPC \
  --etherscan-api-key $BASESCAN_API_KEY \
  --constructor-args $(cast abi-encode "constructor(address)" $(cast call $LP_VAULT_ADDRESS "deployer()(address)" --rpc-url $BASE_RPC)) \
  --root /Users/aklo/dev/agentcoin/contracts
```

**Verification:**
- [ ] All 3 contracts show "Contract Source Code Verified" on Basescan
- [ ] Read/Write tabs functional on each contract

---

### Step 3 — Smoke Test: Mint 1 NFT

```bash
cd miner
npx ts-node src/index.ts mint
# OR if built: node dist/index.js mint
```

This requests an SMHL challenge from MiningAgent, solves it via LLM, and submits `mint()` with the required ETH fee (starts at 0.002 ETH for token #1).

**Verification:**
```bash
# Token #1 exists and is owned by deployer
cast call $MINING_AGENT_ADDRESS "ownerOf(uint256)(address)" 1 --rpc-url $BASE_RPC
# Expected: deployer address

# Mint fee forwarded to vault (non-zero balance)
cast balance $LP_VAULT_ADDRESS --rpc-url $BASE_RPC
# Expected: > 0 (fee amount in wei)

# Next token ID incremented
cast call $MINING_AGENT_ADDRESS "nextTokenId()(uint256)" --rpc-url $BASE_RPC
# Expected: 2

# Check token #1 hashpower and rarity
cast call $MINING_AGENT_ADDRESS "hashpower(uint256)(uint16)" 1 --rpc-url $BASE_RPC
# Expected: 100 (Common), 150 (Uncommon), 200 (Rare), 300 (Epic), or 500 (Mythic)
```

---

### ══════ STOP AND VERIFY ══════

Mint must succeed before proceeding. If it fails:
- Check LLM API key is valid (`LLM_API_KEY` env var)
- Check deployer has ETH for gas + mint fee
- Check SMHL challenge timeout (20-second window — `CHALLENGE_DURATION` in AgentCoin.sol)

---

### Step 4 — Smoke Test: Mine 1 Block

```bash
cd miner
npx ts-node src/index.ts mine 1
# OR: node dist/index.js mine 1
```

Press Ctrl+C after 1 successful mine.

**Verification:**
```bash
# Total mines incremented
cast call $AGENT_COIN_ADDRESS "totalMines()(uint256)" --rpc-url $BASE_RPC
# Expected: 1

# AGENT minted to deployer (3 AGENT * hashpower/100)
# For a Common miner (hashpower=100): 3000000000000000000 (3e18 = 3 AGENT)
cast call $AGENT_COIN_ADDRESS "balanceOf(address)(uint256)" $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $BASE_RPC
# Expected: > 0

# Token #1 mine count
cast call $AGENT_COIN_ADDRESS "tokenMineCount(uint256)(uint256)" 1 --rpc-url $BASE_RPC
# Expected: 1

# Transfers still locked (this MUST revert)
cast send $AGENT_COIN_ADDRESS "transfer(address,uint256)" 0x000000000000000000000000000000000000dEaD 1 \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "locked"
# Expected: revert with "Transfers locked until LP deployed"
```

---

### ══════ STOP AND VERIFY ══════

Mining must succeed AND transfers must still be locked. If transfers are NOT locked, something is critically wrong — STOP and investigate.

---

### Step 5 — Fund LP Vault

The vault needs **>= 4.93 ETH** (4.9 ETH `LP_DEPLOY_THRESHOLD` + 0.03 ETH `UNCX_FLAT_FEE`).

**Option A: Direct funding (recommended for launch):**
```bash
cast send $LP_VAULT_ADDRESS \
  --value 4.93ether \
  --rpc-url $BASE_RPC \
  --private-key $PRIVATE_KEY
```

**Option B: Wait for organic mint fees to accumulate.** (Slow — each mint sends ~0.002 ETH, so ~2,465 mints needed.)

**Verification:**
```bash
cast balance $LP_VAULT_ADDRESS --rpc-url $BASE_RPC
# Must be >= 4930000000000000000 (4.93 ETH in wei)
# If mint fees already accumulated, add the difference:
# cast send $LP_VAULT_ADDRESS --value <remaining-wei>ether --rpc-url $BASE_RPC --private-key $PRIVATE_KEY
```

---

### ══════ STOP AND VERIFY ══════

Vault balance must be >= 4.93 ETH before proceeding. The DeployLP script will revert if below threshold.

**WARNING:** After this point, ETH sent to the vault has no withdrawal function. It can only exit via `deployLP()`. Ensure the amount is correct before sending.

---

### Step 6 — Deploy Liquidity Pool

```bash
cd contracts
source ../.env  # Re-source to pick up LP_VAULT_ADDRESS
forge script script/DeployLP.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast
```

**What this script does:**
1. Pre-flight checks: chain ID, vault ownership, sufficient balance
2. Quotes WETH→USDC swap via Uniswap V3 QuoterV2 (fee tier: 3000 = 0.3%)
3. Applies **3% slippage tolerance** (`minUsdcOut = quotedAmount * 97 / 100`)
4. Calls `lpVault.deployLP(minUsdcOut)` which:
   a. Wraps vault ETH to WETH (minus 0.03 ETH UNCX fee reserve)
   b. Swaps ALL WETH → USDC via Uniswap V3 SwapRouter
   c. Verifies no existing AGENT/USDC pool (prevents griefing)
   d. Creates AGENT/USDC Uniswap V3 pool at computed sqrt price
   e. Mints full-range LP position (tick -887220 to 887220)
   f. Sets `lpDeployed = true` on LPVault
   g. Calls `agentCoin.setLPDeployed()` — **unlocks ALL AGENT transfers**
   h. Approves UNCX locker, locks LP NFT with `unlockDate = type(uint256).max` (eternal)
   i. UNCX lock params: `owner = deployer`, `collectAddress = deployer`

**Required env vars:** `PRIVATE_KEY`, `LP_VAULT_ADDRESS`

**The script prints:** vault balance, WETH swap amount, quoted USDC out, slippage minimum, position token ID.

---

### Step 7 — Verify LP Deployment

```bash
# LP deployed flag (both contracts)
cast call $LP_VAULT_ADDRESS "lpDeployed()(bool)" --rpc-url $BASE_RPC
# Expected: true

cast call $AGENT_COIN_ADDRESS "lpDeployed()(bool)" --rpc-url $BASE_RPC
# Expected: true

# LP position token ID (must be > 0)
cast call $LP_VAULT_ADDRESS "positionTokenId()(uint256)" --rpc-url $BASE_RPC
# Expected: non-zero (e.g., 123456)

# AGENT transfers now work (should succeed)
cast send $AGENT_COIN_ADDRESS "transfer(address,uint256)" $LP_VAULT_ADDRESS 1 \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY
# Expected: success (no revert)

# Vault should have no remaining ETH/WETH (all consumed by deployLP)
cast balance $LP_VAULT_ADDRESS --rpc-url $BASE_RPC
# Expected: 0 or dust
```

**External verification:**
- [ ] Uniswap pool visible: `https://app.uniswap.org/explore/pools/base/<pool-address>`
- [ ] UNCX lock visible: `https://app.uncx.network/lockers/v3/base/lock/<lock-id>`
- [ ] Lock shows eternal unlock date (`type(uint256).max`)
- [ ] AGENT is tradeable on Uniswap
- [ ] Deployer can collect fees via UNCX dashboard

---

### ══════ STOP AND VERIFY ══════

**This is the last checkpoint before the point of no return.**

Confirm ALL of the following before Step 8:
- [ ] `lpDeployed() == true` on BOTH AgentCoin and LPVault
- [ ] LP position token ID > 0
- [ ] AGENT transfers work (test transfer succeeded)
- [ ] Uniswap pool visible and has liquidity
- [ ] UNCX lock confirmed with eternal unlock date
- [ ] Mining still works (optional re-test)
- [ ] Minting still works (optional re-test)

**If anything is wrong:** STOP. You still have admin access. See [Emergency Procedures](#emergency-procedures-before-step-8-only).

---

### Step 8 — RENOUNCE OWNERSHIP (POINT OF NO RETURN)

```
##############################################################
#                                                            #
#   ⚠ WARNING: THIS STEP IS IRREVERSIBLE.                   #
#                                                            #
#   After execution, no admin functions can ever be called.  #
#   No rollback. No upgrades. No recovery. By design.        #
#                                                            #
#   The Renounce script has a built-in safety check:         #
#   require(lpVault.lpDeployed(), "LP not deployed -         #
#           renouncing would brick the protocol")            #
#                                                            #
#   WHY: deployLP() requires onlyOwner. If you renounce     #
#   before LP deployment, owner = address(0) and deployLP()  #
#   becomes permanently uncallable. The 2.1M AGENT and any   #
#   ETH in the vault are bricked forever. The safety check   #
#   prevents this.                                           #
#                                                            #
##############################################################
```

**Pre-renounce checklist (enforced by script + manual):**
- [ ] `lpVault.lpDeployed() == true` (script enforces — will revert if false)
- [ ] All 3 contracts have correct cross-pointers (script verifies all 5)
- [ ] All 3 contracts owned by deployer (script verifies)
- [ ] LP position is locked in UNCX (manual check above)
- [ ] AGENT transfers work (verified in Step 7)
- [ ] Mining works (verified in Step 4)
- [ ] Minting works (verified in Step 3)

```bash
cd contracts
source ../.env  # Ensure all 3 contract addresses are set
forge script script/Renounce.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast
```

**Required env vars:** `PRIVATE_KEY`, `MINING_AGENT_ADDRESS`, `AGENT_COIN_ADDRESS`, `LP_VAULT_ADDRESS`

**What the script does:**
1. Verifies chain ID is 8453
2. Verifies all 5 cross-pointers are correct
3. Verifies all 3 contracts owned by deployer
4. **Safety check:** `require(lpVault.lpDeployed())` — prevents bricking
5. Calls `renounceOwnership()` on MiningAgent, AgentCoin, LPVault
6. Verifies all owners are now `address(0)`

**Verification (immediate, from script output):**
```bash
cast call $MINING_AGENT_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
# Expected: 0x0000000000000000000000000000000000000000

cast call $AGENT_COIN_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
# Expected: 0x0000000000000000000000000000000000000000

cast call $LP_VAULT_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
# Expected: 0x0000000000000000000000000000000000000000
```

---

### Step 9 — Verify Immutability

Attempt every admin function — **all must revert with `OwnableUnauthorizedAccount`:**

```bash
# MiningAgent admin functions
cast send $MINING_AGENT_ADDRESS "setLPVault(address)" 0x0000000000000000000000000000000000000001 \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "revert\|error"
# Expected: OwnableUnauthorizedAccount revert

cast send $MINING_AGENT_ADDRESS "setAgentCoin(address)" 0x0000000000000000000000000000000000000001 \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "revert\|error"
# Expected: OwnableUnauthorizedAccount revert

# LPVault admin functions
cast send $LP_VAULT_ADDRESS "setAgentCoin(address)" 0x0000000000000000000000000000000000000001 \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "revert\|error"
# Expected: OwnableUnauthorizedAccount revert

cast send $LP_VAULT_ADDRESS "emergencyUnwrapWeth()" \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "revert\|error"
# Expected: OwnableUnauthorizedAccount revert

cast send $LP_VAULT_ADDRESS "deployLP(uint256)" 0 \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "revert\|error"
# Expected: OwnableUnauthorizedAccount revert

# AgentCoin — owner functions
cast send $AGENT_COIN_ADDRESS "renounceOwnership()" \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY 2>&1 | grep -i "revert\|error"
# Expected: OwnableUnauthorizedAccount revert
```

**Verification:**
- [ ] Every call above reverts with `OwnableUnauthorizedAccount`
- [ ] Protocol is fully immutable — no human can change any parameter

---

### Step 10 — Publish and Announce

**10a. Update miner client defaults:**

Edit `miner/src/config.ts` — set the `DEFAULT_*_ADDRESS` constants:
```typescript
const DEFAULT_MINING_AGENT_ADDRESS = "0x<actual-address>";
const DEFAULT_AGENT_COIN_ADDRESS = "0x<actual-address>";
```

Rebuild miner: `cd miner && npm run build`

**10b. Update project documentation:**
- Update README.md with deployed contract addresses
- Update `.env.example` with placeholder addresses
- Commit all documentation changes

**10c. Publish addresses to discovery channels:**
- Basescan contract pages (already verified in Step 2)
- Project website
- Social media announcement

---

## Post-Deploy Full Verification Script

Run this sweep after all 10 steps are complete:

```bash
echo "=== Contract State ==="

echo "--- AgentCoin ---"
echo -n "owner: "; cast call $AGENT_COIN_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
echo -n "lpDeployed: "; cast call $AGENT_COIN_ADDRESS "lpDeployed()(bool)" --rpc-url $BASE_RPC
echo -n "totalMines: "; cast call $AGENT_COIN_ADDRESS "totalMines()(uint256)" --rpc-url $BASE_RPC
echo -n "totalSupply: "; cast call $AGENT_COIN_ADDRESS "totalSupply()(uint256)" --rpc-url $BASE_RPC
echo -n "miningAgent: "; cast call $AGENT_COIN_ADDRESS "miningAgent()(address)" --rpc-url $BASE_RPC
echo -n "lpVault: "; cast call $AGENT_COIN_ADDRESS "lpVault()(address)" --rpc-url $BASE_RPC

echo "--- MiningAgent ---"
echo -n "owner: "; cast call $MINING_AGENT_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
echo -n "nextTokenId: "; cast call $MINING_AGENT_ADDRESS "nextTokenId()(uint256)" --rpc-url $BASE_RPC
echo -n "lpVault: "; cast call $MINING_AGENT_ADDRESS "lpVault()(address)" --rpc-url $BASE_RPC
echo -n "agentCoin: "; cast call $MINING_AGENT_ADDRESS "agentCoin()(address)" --rpc-url $BASE_RPC

echo "--- LPVault ---"
echo -n "owner: "; cast call $LP_VAULT_ADDRESS "owner()(address)" --rpc-url $BASE_RPC
echo -n "lpDeployed: "; cast call $LP_VAULT_ADDRESS "lpDeployed()(bool)" --rpc-url $BASE_RPC
echo -n "positionTokenId: "; cast call $LP_VAULT_ADDRESS "positionTokenId()(uint256)" --rpc-url $BASE_RPC
echo -n "deployer: "; cast call $LP_VAULT_ADDRESS "deployer()(address)" --rpc-url $BASE_RPC
echo -n "agentCoin: "; cast call $LP_VAULT_ADDRESS "agentCoin()(address)" --rpc-url $BASE_RPC
```

**Expected final state:**
- All `owner()` = `0x0000000000000000000000000000000000000000`
- `lpDeployed == true` on both AgentCoin and LPVault
- All cross-pointers match deployed addresses
- `positionTokenId > 0`
- `totalMines >= 1` (from smoke test)
- Minting, mining, and AGENT transfers all functional

---

## Emergency Procedures (Before Step 8 ONLY)

> After Step 8, there are no emergency procedures. The protocol is immutable by design.

### Stuck WETH in LPVault (DeployLP partial failure)

If `deployLP()` fails after wrapping ETH→WETH but before completing:

```bash
cast send $LP_VAULT_ADDRESS "emergencyUnwrapWeth()" \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY
```

This unwraps WETH back to ETH in the vault. Only callable by owner before LP is deployed.

**Verify recovery:**
```bash
# WETH balance should be 0
cast call 0x4200000000000000000000000000000000000006 "balanceOf(address)(uint256)" $LP_VAULT_ADDRESS --rpc-url $BASE_RPC
# Expected: 0

# ETH balance should be restored
cast balance $LP_VAULT_ADDRESS --rpc-url $BASE_RPC
# Expected: ~4.9 ETH
```

### Wrong cross-pointer detected

Cross-pointers are one-shot (`require(x == address(0), "Already set")`). **If any pointer is wrong, you cannot fix it.** You must redeploy ALL contracts from scratch.

### LP vault funded but need to abort

ETH sent to the vault has **no withdrawal function**. It can only exit through `deployLP()`. If you funded the vault but need to abort:
- The owner can call `emergencyUnwrapWeth()` to recover wrapped WETH only
- Raw ETH has no escape path — it is consumed by `deployLP()` or stays in the contract forever
- **Plan carefully before funding the vault**

---

## Rollback Procedures

### Before Step 5 (vault not yet funded)

**Full rollback — redeploy from scratch:**
```bash
# Previous contracts become dead (no funds at risk)
# Start over from Step 1 with a clean .env
```

Cost: ~0.01 ETH in gas (deployment cost only).

### Between Step 5 and Step 6 (vault funded, LP not deployed)

**Partial recovery possible:**
```bash
# 1. If WETH is stuck (partial deployLP failure):
cast send $LP_VAULT_ADDRESS "emergencyUnwrapWeth()" \
  --rpc-url $BASE_RPC --private-key $PRIVATE_KEY

# 2. Raw ETH in vault cannot be withdrawn. It can only exit via deployLP().
#    If deployment is fundamentally broken, this ETH is lost.
#    You can still deploy LP to recover it into the Uniswap pool.
```

### Between Step 6 and Step 8 (LP deployed, not yet renounced)

**No rollback needed** — the protocol is functional. You still have admin access. Assess what's wrong:
- If LP parameters look wrong: cannot undo. But the LP is locked eternally anyway.
- If you want to pause: don't proceed to Step 8. Admin functions still available.

### After Step 8

**No rollback possible.** This is intentional. The protocol is trustless precisely because nobody — including Agentoshi — can change it.

---

## Important Notes

- **Agentoshi wallet is NOT destroyed.** It retains UNCX fee collection rights only. The wallet collects trading fees from the LP position via the UNCX dashboard.

- **Fee collection procedure:** UNCX dashboard → connect deployer wallet → "Collect Fees". Lock params set `owner = deployer` and `collectAddress = deployer`, granting permanent fee collection rights even after ownership renunciation.

- **Token #1 + ~3 AGENT remain in Agentoshi's wallet** from the smoke tests (Steps 3-4). Negligible amount, no special handling needed.

- **Agentoshi never mines again after Step 4.** The smoke test is the only time the deployer mines. All subsequent mining is by public participants.

- **Why the Renounce safety check exists:** `deployLP()` is an `onlyOwner` function. If ownership is renounced before LP deployment, `deployLP()` becomes permanently uncallable. The 2.1M AGENT LP reserve and any vault ETH would be bricked forever. The `require(lpVault.lpDeployed())` check in Renounce.s.sol prevents this catastrophic scenario.

- **Why transfers lock before LP:** AgentCoin's `_update()` blocks all non-mint, non-LPVault transfers when `lpDeployed == false`. This prevents token dumps before liquidity exists. The lock lifts automatically when `deployLP()` calls `agentCoin.setLPDeployed()`.

- **SMHL challenges prevent bot minting:** The "Show Me Human Language" challenge requires LLM-level text generation — approximate length (±5), approximate word count (±2), and a required letter. The tolerant verification ensures any LLM can solve it trivially while bots cannot generate natural language. The 20-second window (`CHALLENGE_DURATION`) prevents pre-computation.

- **`tx.origin == msg.sender` check in mining:** This is intentional bot prevention. Smart contract wallets are excluded by design. Only EOAs can mine.

- **Post-deploy miner config injection:** After Step 10a, the miner CLI will work with default addresses. Until then, users must set `MINING_AGENT_ADDRESS` and `AGENT_COIN_ADDRESS` env vars manually.
