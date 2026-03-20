# APoW — Mainnet Master Plan

> Strategic overview for mainnet deployment and post-deploy tasks.
> For the detailed step-by-step runbook, see `DEPLOY_PLAN.md`.

---

## Phase B — Mainnet Deploy (Steps 1-4)

Follow `DEPLOY_PLAN.md` exactly. Every step has STOP AND VERIFY checkpoints.

### B1. Deploy Contracts (Step 1)

```bash
cd ~/dev/agentcoin/contracts
source ../.env
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

**CRITICAL:** Capture the 3 contract addresses from output. Add to `.env`:
```
AGENT_COIN_ADDRESS=0x...
MINING_AGENT_ADDRESS=0x...
LP_VAULT_ADDRESS=0x...
```

**Verify:** Run all `cast call` checks from DEPLOY_PLAN.md Step 1 verification block:
- LP reserve = 2.1M AGENT in vault
- lpDeployed = false
- All 3 owners = deployer
- All 5 cross-pointers correct

### B2. Verify on Basescan (Step 2)

If `--verify` succeeded, check all 3 contracts show "Contract Source Code Verified" on Basescan.
If MiningAgent verification failed (MinerArt library), use manual verify commands from DEPLOY_PLAN.md.

### B3. Smoke Test Mint (Step 3)

```bash
cd ~/dev/agentcoin/miner
npx tsx src/index.ts mint
```

Verify: Token #1 minted, fee forwarded to vault, hashpower/rarity assigned.

### B4. Smoke Test Mine (Step 4)

```bash
npx tsx src/index.ts mine 1
```

Press Ctrl+C after 1 successful mine. Verify:
- totalMines = 1
- AGENT balance > 0 in deployer wallet
- **Transfers still locked** (critical — must revert)

**After B4:** Protocol is LIVE. People can mint NFTs and mine AGENT. Transfers remain locked until LP deploys.

---

## Phase C — LP Deploy (when vault reaches 4.93 ETH)

The vault accumulates ETH from mint fees. At starting price (0.002 ETH), ~2,465 mints fills the vault.

### C1. Monitor Vault Balance

```bash
cast balance $LP_VAULT_ADDRESS --rpc-url $BASE_RPC
```

Proceed when >= 4,930,000,000,000,000,000 wei (4.93 ETH).

### C2. Deploy LP (Step 6)

```bash
cd ~/dev/agentcoin/contracts
source ../.env
forge script script/DeployLP.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast
```

Creates Uniswap V3 AGENT/USDC pool, mints full-range LP, locks eternally in UNCX.
**Unlocks ALL AGENT transfers.**

### C3. Verify LP (Step 7)

- lpDeployed = true on both contracts
- positionTokenId > 0
- AGENT transfers work
- Uniswap pool visible, UNCX lock confirmed eternal

### C4. RENOUNCE OWNERSHIP (Step 8) — IRREVERSIBLE

```bash
forge script script/Renounce.s.sol \
  --rpc-url $BASE_RPC \
  --broadcast
```

Script enforces: all cross-pointers correct, all owners = deployer, lpDeployed = true.
After this: all owners = address(0). No admin functions. No rollback. Forever.

### C5. Verify Immutability (Step 9)

All admin function calls must revert with `OwnableUnauthorizedAccount`.

---

## Phase D — Post-Deploy Updates

### D1. Update Miner Defaults

**`miner/src/config.ts`** — set `DEFAULT_MINING_AGENT_ADDRESS` and `DEFAULT_AGENT_COIN_ADDRESS` to deployed addresses.

### D2. Update Docs

- `docs/skill.md` Section 12 — replace TBD address placeholders
- `.env.example` — add addresses as examples
- `README.md` — add deployed addresses section

### D3. npm Publish Preparation

**`miner/package.json`** changes:
- Remove `"private": true`
- Add: `"repository"`, `"author"`, `"homepage"`, `"bugs"` fields

### D4. Publish to npm

```bash
cd miner && npm run build && npm publish
```

Users can then: `npx agentcoin setup` → `npx agentcoin mint` → `npx agentcoin mine`

### D5. Update CLAUDE.md

Mark deploy as complete, update current state, remove resolved gaps.

### D6. Commit Everything

Commit all post-deploy updates, push as Agentoshi.

---

## OPSEC Checklist

| Check | Status |
|-------|--------|
| `.env` in `.gitignore` | ✓ |
| No secrets in contract code | ✓ |
| No TODO/FIXME in contracts | ✓ |
| All addresses Base mainnet 8453 | ✓ |
| Chain ID enforced in all scripts | ✓ |
| Renounce safety check (lpDeployed) | ✓ |
| Cross-pointer verification in Renounce | ✓ |
| ABIs in sync | ✓ |
| Fork tests pass | ✓ |
| Dry-run on fork succeeds | ✓ |
| Deployer wallet funded | ✓ |
| Basescan API key ready | ✓ |
| npm 2FA enabled | ✓ |
| Private key never in git/terminal output | ✓ |
| Deployer wallet has minimal funds | ✓ |
