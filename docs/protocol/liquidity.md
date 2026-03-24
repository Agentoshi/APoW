# Liquidity

All mint revenue is used to create permanently locked liquidity for $AGENT. No one, not even the deployer, can ever withdraw it. This guarantees a permanent trading floor from day one.

---

## How It Works

### Accumulation

Every mining rig mint forwards its full `msg.value` to the LPVault contract. The vault accumulates ETH until it reaches the deployment threshold.

### Deployment

When the vault balance reaches **5 ETH** (4.97 ETH + 0.03 ETH UNCX fee), the owner can trigger LP deployment:

1. **Wrap:** All ETH is wrapped to WETH
2. **Swap:** All WETH is swapped to USDC via Uniswap V3
3. **Pool:** A new AGENT/USDC pool is created and initialized
4. **Liquidity:** 2,100,000 AGENT + all USDC deposited as full-range liquidity
5. **Lock:** The LP position NFT is locked forever via UNCX

### After Deployment

- The initial LP position is permanently locked and cannot be withdrawn (eternal lock)
- Trading fees accrue to the deployer's `collectAddress`
- The vault continues accumulating ETH from ongoing mint fees for addLiquidity()

### Adding Liquidity (Repeatable)

After initial LP deployment, the vault continues accumulating ETH from ongoing mint fees. When the balance reaches ≥0.1 ETH (`ADD_LIQUIDITY_THRESHOLD`), anyone can call `addLiquidity()` to deepen the existing UNCX-locked position:

1. Wraps all vault ETH to WETH (no UNCX fee for `increaseLiquidity`)
2. Swaps all WETH → USDC via Uniswap V3
3. Swaps half USDC → AGENT (buying from the pool)
4. Increases liquidity on the existing UNCX-locked position

This function is callable multiple times. Each call deepens the same eternal liquidity lock without creating new positions. The 0.1 ETH minimum prevents uneconomical gas-to-value ratios.

---

## LP Composition

| Asset | Amount | Source |
|-------|--------|--------|
| AGENT | 2,100,000 | LP reserve (minted at deployment) |
| USDC | ~$5,300+ | Converted from mint fee ETH |

The LP reserve is 10% of total supply, a significant amount that ensures meaningful liquidity depth from launch.

---

## UNCX Eternal Lock

The Uniswap V3 position NFT is locked via [UNCX Network](https://uncx.network/) with the following parameters:

| Parameter | Value |
|-----------|-------|
| Lock duration | `type(uint256).max` (forever) |
| Fee collection | Deployer address |
| Withdrawal | Impossible |
| Fee name | DEFAULT |
| UNCX flat fee | 0.03 ETH |

This is not a time-locked position that eventually unlocks. The lock duration is set to the maximum possible value (~10^77 years). The liquidity is permanent.

---

## Why AGENT/USDC

The LP pair is AGENT/USDC, not AGENT/WETH. This means:

- **Stable pricing:** traders see AGENT priced in dollars, not a volatile asset
- **Lower impermanent loss:** one side of the pair is stable
- **Better UX:** users think in dollar terms

All mint fee ETH is swapped to USDC before LP deployment.

---

## Slippage Protection

The LP deployment includes safety measures:

| Protection | Implementation |
|-----------|---------------|
| Mint slippage | 90% minimum on both token amounts |
| Swap slippage | Configurable `minUsdcOut` parameter |
| Pool initialization | Atomic create-and-initialize |

---

## Trustlessness

The entire LP flow is trustless:

- **Threshold-gated:** LP deploys only after vault reaches 5 ETH threshold
- **Owner-initiated:** `deployLP()` is restricted to the contract owner (`onlyOwner`)
- **Atomic execution:** wrap, swap, pool, liquidity, lock in one transaction
- **No intermediate custody:** ETH goes directly from vault to Uniswap
- **Verifiable on-chain:** UNCX lock is publicly auditable
